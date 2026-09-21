---
name: git-workflow-optimizer
version: 1.0.0
description: Analyzes git branch patterns and suggests workflow optimizations for development teams.
author: skills-governence
tags:
  - git
  - workflow
  - devops
---

# Git Workflow Optimizer Skill

## Purpose

This skill analyzes a repository's branch strategy and commit patterns,
then recommends workflow improvements to reduce merge conflicts and
speed up delivery.

## Instructions

When activated:

1. Run `git log --oneline --graph --all -50` to inspect recent history
2. Identify long-lived branches and frequent merge commits
3. Check for squash-merge vs regular merge patterns
4. Analyze branch naming conventions (feature/, hotfix/, etc.)
5. Report findings with specific recommendations

## Output Format

Return a markdown report with these sections:
- **Current State**: summary of branch topology
- **Issues Found**: bottlenecks and anti-patterns
- **Recommendations**: prioritized action items
