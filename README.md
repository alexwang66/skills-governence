# skills-governence

Automated governance pipeline for agent skills: upload a skill, let JFrog Xray scan it,
and only authorized skills land in `skills-authorized/`.

## Layout

| Path | Purpose |
| --- | --- |
| `skills-upload/` | Drop new or changed skill `.md` files here |
| `skills-authorized/` | Skills that passed the Xray security scan (written by CI) |
| `.github/workflows/scan-skill.yml` | CI: runs on push to `main` touching `skills-upload/**` |
| `.github/scripts/scan_and_govern.sh` | Publishes each skill and evaluates the scan result |

## How it works

1. Push a skill `.md` file to `skills-upload/` on `main`.
2. The workflow detects the changed files (`git diff HEAD~1 HEAD -- skills-upload/`).
3. For each file, `jf skills publish` uploads it to the Artifactory skills repository
   (`alex-skills-local`) — this also **triggers an Xray security scan** and waits for it.
4. Passed skills are copied to `skills-authorized/` and committed back to `main`.
   Failed skills are not authorized, and the job fails.

The skill name comes from the `name:` field in the file's YAML frontmatter
(falling back to the file name), and the published version comes from `version:`.

## Configuration

Repository secrets:

| Secret | Value |
| --- | --- |
| `JFROG_URL` | `https://solenglatest.jfrog.io` |
| `ARTIFACTORY_ACCESS_TOKEN` | JFrog access token with upload + scan permissions |

The target repository key is set by `ARTIFACTORY_REPO` in the workflow
(`alex-skills-local`).

## Skill file format

```markdown
---
name: my-skill
version: 1.0.0
description: One-line description of what the skill does.
author: skills-governence
tags:
  - example
---

# My Skill

## Purpose
...
```

Bump `version` on every change — `jf skills publish` refuses to overwrite an
existing version.
