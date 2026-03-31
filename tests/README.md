# Tests And Verification

This directory is the shared home for repo-level test helpers, smoke checks, and verification commands.

## Purpose

Use this folder for:

- repeatable verification scripts
- one-off smoke-test commands that became useful enough to keep
- environment-specific validation helpers
- future restore, observability, and production-readiness checks

## Structure

- `tests/k8s/`
  - Kubernetes-specific verification helpers
- `tests/docker/`
  - reserved for future Docker or Compose verification helpers
- `tests/docs/`
  - reserved for future checklists or runbooks if needed

## Current Helpers

- [tests/k8s/backup-inspect.sh](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/tests/k8s/backup-inspect.sh)
  - mounts the backup PVC in a temporary pod and lists the backup files
- [tests/k8s/backup-delete.sh](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/tests/k8s/backup-delete.sh)
  - deletes one backup file or all backup dump files from the backup PVC
- [tests/k8s/backup-run.sh](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/tests/k8s/backup-run.sh)
  - creates a one-off backup job from the backup `CronJob`, waits for completion, and prints the logs

## Usage Style

Keep helpers:

- small
- readable
- environment-aware through flags or env vars when useful
- safe to re-run

When a command becomes part of the learning flow more than once, move it here instead of leaving it in scratch files.
