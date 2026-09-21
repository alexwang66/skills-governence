---
name: release-health-check
version: 1.0.1
description: Verifies that a release pipeline completed end-to-end and produces a health report.
author: skills-governence
tags:
  - ci-cd
  - release
  - devops
---

# Release Health Check Skill

## Purpose

This skill validates that a CI/CD release pipeline (build, scan, publish)
completed end-to-end, and generates a concise health report for the team.

## Instructions

When activated:

1. Identify the latest pipeline run for the target repository
2. Check each stage: build, security scan, artifact publish, deploy
3. For failed stages, extract the first error message and owning step
4. Verify artifacts produced by the run are present and versioned
5. Report overall status with a pass/fail verdict per stage

## Output Format

Return a markdown report with these sections:

- **Run Summary**: run ID, trigger, duration
- **Stage Status**: table with Stage | Status | Details
- **Failures**: root-cause notes for any failed stage
- **Verdict**: overall PASS or FAIL with recommended next action
