#!/usr/bin/env bash
# =============================================================
#  scan_and_govern.sh
#
#  Reads changed skill files from /tmp/changed_skills.txt,
#  publishes each to a JFrog Artifactory skills repository using
#  the native `jf skills publish` command (which uploads the skill
#  and triggers an Xray security scan), and copies skills that
#  pass the scan to skills-authorized/.
#
#  Auth: JF_URL + JF_ACCESS_TOKEN (or JF_USER/JF_PASSWORD) env vars,
#        or a pre-configured server via JF_SERVER_ID.
#
#  Exit codes:
#    0  all files scanned and passed
#    1  at least one file failed scanning
# =============================================================
set -euo pipefail

# ─── Configuration ──────────────────────────────────────────
ARTIFACTORY_REPO="${ARTIFACTORY_REPO:-alex-skills-local}"
SERVER_ID="${JF_SERVER_ID:-}"

AUTHORIZED_DIR="skills-authorized"
CHANGED_FILE="/tmp/changed_skills.txt"
UPLOAD_DIR="skills-upload"

# ─── Helpers ─────────────────────────────────────────────────
log()  { echo "  $*"; }
step() { echo ""; echo "━━━  $*  ━━━"; echo ""; }

# Extract a value from YAML frontmatter, e.g. frontmatter "name"
frontmatter() {
    local key="$1" file="$2"
    awk -v key="$key" '
        NR == 1 && $0 ~ /^---[[:space:]]*$/ { in_fm = 1; next }
        in_fm && $0 ~ /^---[[:space:]]*$/      { exit }
        in_fm && $0 ~ "^" key ":[[:space:]]*"  {
            sub("^" key ":[[:space:]]*", ""); gsub(/^["'"'"']|["'"'"']$/, ""); print; exit
        }
    ' "$file" | tr -d '\r'
}

# ─── Banner ──────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║   JFrog Skill Scan & Govern Pipeline              ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""
echo "  Artifactory Repo : ${ARTIFACTORY_REPO}"
echo "  Server ID        : ${SERVER_ID:-<from JF_URL env>}"
echo ""

# ─── CLI auth flags ─────────────────────────────────────────
AUTH_FLAGS=()
if [ -n "$SERVER_ID" ]; then
    AUTH_FLAGS+=(--server-id "$SERVER_ID")
fi

# ─── Read changed files ─────────────────────────────────────
if [ ! -f "$CHANGED_FILE" ]; then
    echo "  No changed-files list at ${CHANGED_FILE} — nothing to do."
    exit 0
fi

FILES=()
while IFS= read -r line; do
    [ -n "$line" ] && FILES+=("$line")
done < "$CHANGED_FILE"

TOTAL=${#FILES[@]}
echo "  Files to scan: ${TOTAL}"
echo ""

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

    # Skill name: frontmatter `name`, else file name without extension
    SKILL_NAME="$(frontmatter name "$FILE")"
    if [ -z "$SKILL_NAME" ]; then
        SKILL_NAME="$(basename "$FILE" .md)"
    fi
    log "Skill name: ${SKILL_NAME}"

    # `jf skills publish` requires a folder containing SKILL.md
    WORK_DIR="$(mktemp -d)"
    SKILL_DIR="${WORK_DIR}/${SKILL_NAME}"
    mkdir -p "$SKILL_DIR"
    cp "$FILE" "${SKILL_DIR}/SKILL.md"

    # Relative path inside skills-upload/ (e.g. "release-health-check/SKILL.md")
    RELATIVE_PATH="${FILE#${UPLOAD_DIR}/}"
    AUTHORIZED_PATH="${AUTHORIZED_DIR}/${RELATIVE_PATH}"

    SHA256=$(sha256sum "$FILE" | awk '{print $1}')
    log "SHA256: ${SHA256}"

    # ─── Publish + Xray scan (single native command) ───────
    log "📤 Publishing to ${ARTIFACTORY_REPO} and triggering Xray scan..."

    if jf skills publish "$SKILL_DIR" \
        --repo "$ARTIFACTORY_REPO" \
        --auto-delete-on-failure \
        --quiet \
        ${AUTH_FLAGS[@]+"${AUTH_FLAGS[@]}"}; then
        log "✅ Published and passed Xray security scan"
        mkdir -p "$(dirname "$AUTHORIZED_PATH")"
        cp "$FILE" "$AUTHORIZED_PATH"
        log "📋 Copied to ${AUTHORIZED_PATH}"
        PASSED=$((PASSED + 1))
    else
        log "❌ Publish/scan failed — skill NOT authorized: ${FILE}"
        FAILED=$((FAILED + 1))
    fi

    rm -rf "$WORK_DIR"
done

# ─── Summary ─────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║              S C A N   S U M M A R Y              ║"
echo "╠══════════════════════════════════════════════════╣"
echo "║  Total Scanned :  ${TOTAL}"
echo "║  Passed        :  ${PASSED}"
echo "║  Failed        :  ${FAILED}"
echo "╚══════════════════════════════════════════════════╝"
echo ""

if [ "$FAILED" -gt 0 ]; then
    echo "⚠  ${FAILED} skill(s) failed scanning and were NOT authorized."
    exit 1
fi

echo "✅ All skills passed scanning and were authorized!"
exit 0
