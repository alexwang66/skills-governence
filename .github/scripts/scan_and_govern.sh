#!/usr/bin/env bash
# =============================================================
#  scan_and_govern.sh
#
#  Reads changed skill files from /tmp/changed_skills.txt,
#  uploads each to JFrog Artifactory, polls Xray for scan
#  results, and copies passing files to skills-authorized/.
#
#  Exit codes:
#    0  all files scanned and passed
#    1  at least one file failed scanning
# =============================================================
set -euo pipefail

# ─── Configuration ──────────────────────────────────────────
JFROG_URL="${JFROG_URL:?JFROG_URL is required}"
JFROG_ACCESS_TOKEN="${JFROG_ACCESS_TOKEN:?JFROG_ACCESS_TOKEN is required}"
ARTIFACTORY_REPO="${ARTIFACTORY_REPO:-skills-staging}"
MAX_SCAN_WAIT="${MAX_SCAN_WAIT:-300}"
SCAN_INTERVAL="${SCAN_INTERVAL:-10}"

# Strip trailing slash from URL
JFROG_URL="${JFROG_URL%/}"

AUTHORIZED_DIR="skills-authorized"
CHANGED_FILE="/tmp/changed_skills.txt"

# ─── Helpers ─────────────────────────────────────────────────
log()  { echo "  $*"; }
step() { echo ""; echo "━━━  $*  ━━━"; echo ""; }

# ─── Banner ───────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║   JFrog Skill Scan & Govern Pipeline              ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""
echo "  JFrog URL        : ${JFROG_URL}"
echo "  Artifactory Repo : ${ARTIFACTORY_REPO}"
echo "  Max Scan Wait    : ${MAX_SCAN_WAIT}s"
echo "  Poll Interval    : ${SCAN_INTERVAL}s"
echo ""

# ─── Read changed files ─────────────────────────────────────
mapfile -t FILES < "$CHANGED_FILE"
TOTAL=${#FILES[@]}

echo "  Files to scan: ${TOTAL}"
echo ""

# Counters
PASSED=0
FAILED=0

for FILE in "${FILES[@]}"; do
    step "Processing: ${FILE}"

    # Skip deleted files
    if [ ! -f "$FILE" ]; then
        log "⚠  Skipped (file deleted or not found)"
        FAILED=$((FAILED + 1))
        continue
    fi

    # Relative path from skills-upload/ onward (e.g. "category1/SKILL.md")
    RELATIVE_PATH="${FILE#skills-upload/}"
    AUTHORIZED_PATH="${AUTHORIZED_DIR}/${RELATIVE_PATH}"
    REMOTE_PATH="${RELATIVE_PATH}"

    # SHA256 checksum
    SHA256=$(sha256sum "$FILE" | awk '{print $1}')
    log "SHA256: ${SHA256}"

    # ─── Step 1: Upload to Artifactory ────────────────────
    log "📤 Uploading to Artifactory  →  ${ARTIFACTORY_REPO}/${REMOTE_PATH}"

    if ! jf rt u "$FILE" "${ARTIFACTORY_REPO}/${REMOTE_PATH}" 2>&1; then
        log "❌ Upload failed for ${FILE}"
        FAILED=$((FAILED + 1))
        continue
    fi
    log "✅ Uploaded successfully"

    # ─── Step 2: Trigger Xray scan ────────────────────────
    log "🔍 Triggering Xray scan..."
    TRIGGER_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
        -H "Authorization: Bearer ${JFROG_ACCESS_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{\"repo\":\"${ARTIFACTORY_REPO}\",\"path\":\"${REMOTE_PATH}\"}" \
        "${JFROG_URL}/xray/api/v1/scanArtifact" 2>/dev/null || true)

    HTTP_CODE=$(echo "$TRIGGER_RESPONSE" | tail -1)
    TRIGGER_BODY=$(echo "$TRIGGER_RESPONSE" | sed '$d')
    log "Scan trigger HTTP status: ${HTTP_CODE}"

    if [ "$HTTP_CODE" != "200" ] && [ "$HTTP_CODE" != "202" ]; then
        log "⚠  Scan trigger returned non-OK status (${HTTP_CODE})"
        log "  Response: ${TRIGGER_BODY}"
    fi

    # ─── Step 3: Poll for scan completion ─────────────────
    log "⏳ Waiting for scan to complete (max ${MAX_SCAN_WAIT}s)..."
    ELAPSED=0
    SCAN_STATUS="PENDING"
    STATUS_RESPONSE=""

    while [ "$ELAPSED" -lt "$MAX_SCAN_WAIT" ]; do
        sleep "$SCAN_INTERVAL"
        ELAPSED=$((ELAPSED + SCAN_INTERVAL))

        STATUS_RESPONSE=$(curl -s -X POST \
            -H "Authorization: Bearer ${JFROG_ACCESS_TOKEN}" \
            -H "Content-Type: application/json" \
            -d "{\"sha256\":[\"${SHA256}\"]}" \
            "${JFROG_URL}/xray/api/v1/summary/artifact" 2>/dev/null || true)

        SCAN_STATUS=$(echo "$STATUS_RESPONSE" \
            | jq -r '.artifacts[0].scan_status // "PENDING"' 2>/dev/null \
            || echo "PENDING")

        log "⏱  ${ELAPSED}s elapsed — scan status: ${SCAN_STATUS}"

        if [ "$SCAN_STATUS" = "DONE" ] || [ "$SCAN_STATUS" = "FINISHED" ]; then
            break
        fi
    done

    # ─── Step 4: Evaluate scan results ───────────────────
    SCAN_PASSED=false

    if [ "$SCAN_STATUS" = "DONE" ] || [ "$SCAN_STATUS" = "FINISHED" ]; then
        # Check severity from Xray response
        SEVERITY=$(echo "$STATUS_RESPONSE" \
            | jq -r '.artifacts[0].issues.severity // "None"' 2>/dev/null \
            || echo "Unknown")

        VIOLATION_COUNT=$(echo "$STATUS_RESPONSE" \
            | jq -r '.artifacts[0].issues.violations | length' 2>/dev/null \
            || echo "0")

        log "Scan severity : ${SEVERITY}"
        log "Violations    : ${VIOLATION_COUNT}"

        if [ "$SEVERITY" = "None" ] || [ "$SEVERITY" = "null" ] || [ -z "$SEVERITY" ]; then
            log "✅ Scan passed — no issues found"
            SCAN_PASSED=true
        else
            log "❌ Scan failed — issues found with severity: ${SEVERITY}"
            echo "$STATUS_RESPONSE" | jq '.' 2>/dev/null || echo "$STATUS_RESPONSE"
        fi
    else
        log "⚠  Xray scan did not complete within ${MAX_SCAN_WAIT}s"
        log "   Falling back to local binary scan (jf scan)..."

        if jf scan "$FILE" --format=json > /tmp/scan_fallback.json 2>/dev/null; then
            log "✅ Local scan passed — no issues found"
            SCAN_PASSED=true
        else
            log "❌ Local scan found issues:"
            jf scan "$FILE" 2>&1 | tail -20 || true
        fi
    fi

    # ─── Step 5: Copy to authorized if passed ────────────
    if [ "$SCAN_PASSED" = true ]; then
        mkdir -p "$(dirname "$AUTHORIZED_PATH")"
        cp "$FILE" "$AUTHORIZED_PATH"
        log "📋 Copied to ${AUTHORIZED_PATH}"
        PASSED=$((PASSED + 1))
    else
        log "🚫 Skill NOT authorized: ${FILE}"
        FAILED=$((FAILED + 1))
    fi
done

# ─── Summary ─────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║              S C A N   S U M M A R Y              ║"
echo "╠══════════════════════════════════════════════════╣"
echo "║  Total Scanned :  ${TOTAL}                              ║"
echo "║  Passed        :  ${PASSED}                              ║"
echo "║  Failed        :  ${FAILED}                              ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

if [ "$FAILED" -gt 0 ]; then
    echo "⚠  ${FAILED} skill(s) failed scanning and were NOT authorized."
    exit 1
fi

echo "✅ All skills passed scanning and were authorized!"
exit 0
