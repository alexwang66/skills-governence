---
name: code-review-checklist
version: 1.0.0
description: A skill that provides a systematic code review checklist for pull requests.
author: skills-governence
tags:
  - code-review
  - quality-assurance
  - best-practices
---

# Code Review Checklist Skill

## Purpose

This skill generates a systematic code review checklist to ensure consistent quality
across pull requests.

## Instructions

When activated, present the following checklist to the reviewer:

1. **Security** — Are there any hardcoded secrets, SQL injection risks, or XSS vulnerabilities?
2. **Performance** — Are there N+1 queries, unnecessary re-renders, or blocking I/O?
3. **Tests** — Are new code paths covered by unit/integration tests?
4. **Documentation** — Are public APIs and complex logic documented?
5. **Error Handling** — Are edge cases and error states handled gracefully?

## Output Format

Return a markdown table with columns: Check | Status | Notes
