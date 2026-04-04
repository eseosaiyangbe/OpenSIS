# Production-Grade CI/CD Blueprint

This guide defines the target CI/CD operating model for this repository now that the application, GitOps, Vault, Cloudflare, and session architecture are stable enough to support a more deliberate delivery pipeline.

It is intentionally separate from the bootstrap guide. The bootstrap guide explains how the platform was brought up. This document explains how changes should move safely from source code to production.

See also:

- [Kubernetes Base](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/README.md)
- [GitOps Layer](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/gitops/README.md)
- [Overlays](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/overlays/README.md)
- [From-Scratch Local Bootstrap](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/FROM_SCRATCH_LOCAL_BOOTSTRAP.md)

## Why This Phase Exists Now

This phase is being added now because the platform has crossed an important maturity threshold:

- `dev` and `prod` are both running under GitOps
- Vault-backed secret delivery is in place
- Cloudflare public access is stable
- `prod` session handling is durable and validated at `2` replicas
- `dev` and `prod` are much closer in runtime behavior than before

That makes this the right time to design a true production-grade pipeline.

If CI/CD is added too early, it just automates drift, instability, and manual rescue work. At this stage, the platform is stable enough that automation can reinforce good behavior instead of amplifying bad behavior.

## Design Goals

The target pipeline should be:

- reproducible
- security-first
- GitOps-driven
- promotion-based
- auditable
- reversible

For this project, production-grade means:

- every deployable artifact is traceable back to a Git revision
- `prod` only runs tested immutable artifacts
- secrets do not live in GitHub Actions logs, plaintext repo files, or long-lived CI credentials
- delivery to Kubernetes happens through Argo CD reconciliation, not direct cluster mutation from CI
- failed quality gates stop promotion before `prod`
- rollback is a documented operational action, not an improvisation

## Core Approach

The recommended approach is to build the delivery model in layers.

### 1. Separate CI from CD

CI should answer:

- does the code build
- does it pass validation and tests
- is the image safe enough to promote
- is the artifact signed and traceable

CD should answer:

- which already-approved artifact should run in each environment
- has Git been updated to declare that desired state
- has Argo CD reconciled the cluster to that state

This separation keeps responsibilities clear and reduces the blast radius of automation mistakes.

### 2. Use Promotion Instead of Rebuilding Per Environment

The same built artifact should move through the path:

- build once
- validate once
- promote by reference

For this repository, that means:

- `dev` may track a mutable integration stream such as `main`
- `prod` should be promoted only by an immutable image reference such as `git-<sha>`
- later, the strongest version of this model is to pin `prod` by image digest

### 3. Keep GitOps as the Deployment Authority

GitHub Actions should not be the actor that applies production manifests directly.

Instead:

- CI builds and verifies artifacts
- a promotion step updates Git
- Argo CD reconciles the cluster from Git

This keeps production delivery auditable and aligned with the current platform design.

### 4. Make Security Controls Default

Security should not be a final polishing step. It needs to be present in the first production-grade version of the pipeline:

- least-privilege workflow permissions
- pinned GitHub Actions by commit SHA where practical
- secret scanning
- dependency scanning
- image scanning
- SBOM generation
- signed images
- provenance or attestation where possible
- protected environments for production approvals

## Implementation Status

Current blueprint progress:

- Phase A: complete
  - separate CI/CD blueprint documented in this file
  - promotion model, GitOps authority, and security-first direction defined
- Phase B: complete
  - dedicated repository validation workflow implemented and passing
  - shell and YAML validation scope tuned to repo-owned infrastructure and helper scripts
  - Kustomize render validation now covers base, dev, prod, cloudflare, and argocd
  - workflow permissions explicitly reviewed and kept at least privilege (`contents: read`)
  - pull-request validation now follows the same scoped trigger model as push validation
- Phase C: started
  - UI image workflow now resolves an immutable `git-<sha>` tag for scanning
  - Trivy image scanning added in report mode to establish a vulnerability baseline before enforcing a hard gate
- Phase D: not started
- Phase E: not started

Recently completed milestone:

- `Validate Repository` is now an active CI gate and verifies:
  - GitHub Actions workflow linting with `actionlint`
  - shell script linting with `shellcheck`
  - infrastructure YAML linting with `yamllint`
  - Kustomize render checks for the repo's core deployment layers

Why this matters:

- broken manifests and scripts are now caught before image publication or GitOps reconciliation
- validation scope is strict enough to protect the platform, but narrow enough to avoid failing on vendored or unrelated app content
- this is the first real production-grade delivery control implemented from the blueprint

## Current State

The repo already has the beginnings of a pipeline:

- GitHub Actions builds and pushes the UI image
- Docker Hub is the registry
- `dev` tracks the mutable CI-backed `main` image stream
- `prod` is promoted by changing an immutable `git-<sha>` image tag
- Argo CD reconciles `dev`, `prod`, and `cloudflare`

This is a strong foundation, but it is not yet a complete production-grade CI/CD system.

Current gaps:

- repository validation workflow now exists, but broader test coverage is still missing
- no formal promotion workflow with explicit gates
- image scanning exists in report mode, but it is not yet an enforcement gate
- no signed artifacts
- no SBOM/provenance publication
- no post-deploy smoke-test workflow
- no codified rollback workflow

## Target Delivery Model

### Branch and Environment Shape

Recommended model:

- `main` is the integration branch
- `dev` auto-reconciles from Git and can track the mutable `main` image stream
- `prod` remains promotion-based and should only move through explicit Git change

Recommended artifact policy:

- `main` branch pushes publish:
  - `main`
  - `dev`
  - `git-<sha>`
- production promotion uses only:
  - `git-<sha>`
  - later optionally pinned digest references

### Workflow Separation

Recommended workflows:

1. `validate.yml`
- runs on pull requests and protected branches
- lint and validate only

2. `build-ui-image.yml`
- builds the UI image
- pushes immutable and branch-channel tags
- generates SBOM
- scans image
- signs image

3. `promote-prod.yml`
- manual or approval-gated
- updates [k8s/overlays/prod/kustomization.yaml](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/overlays/prod/kustomization.yaml)
- opens or merges a promotion PR
- Argo CD reconciles from Git

4. `post-deploy-smoke.yml`
- validates `dev` after auto-sync
- validates `prod` after promotion

5. `security-review.yml`
- scheduled scans
- dependency review
- secret scanning
- stale image vulnerability review

## Recommended CI Stages

### Stage 1: Repository and Manifest Validation

Purpose:

- catch obvious breakage before image build or promotion

Recommended checks:

- YAML validation
- Kustomize render checks for:
  - `k8s/overlays/dev`
  - `k8s/overlays/prod`
  - `k8s/platform/cloudflare`
- shell syntax validation for `scripts/*.sh`
- workflow linting for `.github/workflows/*.yml`

Recommended tools:

- `kubectl kustomize`
- `yamllint`
- `shellcheck`
- `actionlint`

### Stage 2: Application Build Validation

Purpose:

- prove the UI image still builds cleanly

Recommended checks:

- Docker build
- container startup smoke check
- PHP extension verification for critical runtime dependencies like `redis`

### Stage 3: Security and Supply Chain Checks

Purpose:

- prevent low-quality or unsafe artifacts from becoming production candidates

Recommended checks:

- image vulnerability scan with Trivy or Grype
- SBOM generation with Syft or BuildKit-native support
- secret scanning with Gitleaks
- dependency review on pull requests

Recommended artifact outputs:

- image tags
- SBOM
- scan report
- signed image
- provenance attestation if supported

### Stage 4: Environment Verification

Purpose:

- confirm the deployed environment is actually usable, not just “deployed”

Recommended `dev` smoke checks:

- `kubectl get applications.argoproj.io -n argocd`
- `kubectl get deploy,pods,svc,ingress -n opensis-dev`
- HTTP `200` on `https://opensis.dev.local`
- installer-route expectation documented clearly for `dev`
- PHP session settings check in the live pod

Recommended `prod` smoke checks:

- Argo CD app status for `opensis-prod` and `opensis-cloudflare`
- `curl -k -I https://opensis.raysosglobal.com`
- verify `/install/` redirects away from installer
- verify `opensis-ui` replica count and Redis session configuration

## Recommended CD and Promotion Model

### Dev

`dev` should remain the fast feedback environment.

Recommended behavior:

- auto-sync in Argo CD
- mutable CI-backed image stream allowed
- post-deploy smoke tests required
- drift tolerated only briefly and corrected quickly

Important dev rule:

- because `main` is mutable, the dev UI Deployment must use pull behavior that actually refreshes the image when CI updates the tag

### Prod

`prod` should remain the controlled environment.

Recommended behavior:

- manual or approval-gated promotion
- immutable image references only
- promotion by Git change to the overlay
- Argo CD as reconciler
- post-deploy smoke validation required

Recommended promotion path:

1. merge code to `main`
2. CI builds `git-<sha>`
3. CI validates and scans the image
4. reviewer approves promotion
5. promotion updates prod overlay image tag
6. Argo CD syncs `prod`
7. smoke tests verify public behavior

## Security Baseline

### GitHub Actions

Recommended controls:

- declare explicit `permissions:` for each workflow
- default to read-only where possible
- use environment protection rules for production-facing jobs
- avoid long-lived static credentials

### Registry and Artifact Security

Recommended controls:

- use immutable tags for production
- add image signing with Cosign
- publish SBOMs
- retain scan reports with workflow artifacts

### Kubernetes and GitOps

Recommended controls:

- keep Argo CD as the only routine production deploy actor
- keep Vault as the secret source of truth
- do not inject repo secrets into manifests
- do not store kubeconfig in GitHub Secrets for direct prod deploys if GitOps can avoid it

## Recommended Future Workflows

### `validate.yml`

Suggested responsibilities:

- `yamllint`
- `shellcheck`
- `actionlint`
- render all overlays with `kubectl kustomize`
- fail fast on manifest breakage

### `build-ui-image.yml`

Suggested responsibilities:

- build image
- publish `main`, `dev`, and `git-<sha>`
- scan image
- generate SBOM
- sign image

### `promote-prod.yml`

Suggested responsibilities:

- accept an approved immutable tag or digest
- update prod overlay
- create or merge promotion change
- trigger Argo CD refresh if needed

### `smoke-dev.yml`

Suggested responsibilities:

- verify Argo CD sync health
- verify `opensis.dev.local`
- verify PHP Redis session configuration in pod

### `smoke-prod.yml`

Suggested responsibilities:

- verify Argo CD sync health
- verify public URL and installer redirect behavior
- verify `opensis-ui` replica health
- verify Redis-backed sessions are live

## Rollback Strategy

Production-grade delivery requires a rollback story that is simple and fast.

Recommended rollback action:

- revert the prod overlay image tag to the previously known-good immutable tag
- push the revert
- let Argo CD reconcile

Why this fits the current architecture:

- Git remains the source of truth
- no emergency direct mutation is required
- rollback is auditable

Recommended documentation to keep current:

- current known-good prod image tag
- last successful prod promotion
- smoke-test evidence for each promotion

## Phased Implementation Plan

### Phase A: Pipeline Architecture Lock-In

Deliverables:

- this blueprint
- documented promotion rules
- agreed workflow split between validate, build, promote, and smoke-test

### Phase B: CI Hardening

Deliverables:

- `validate.yml`
- stronger workflow permissions
- lint and render gates on pull requests

Current status:

- complete
- `validate.yml` implemented
- lint and render gates implemented and passing
- workflow permissions explicitly reviewed and kept at least privilege for the current workflow set

### Phase C: Artifact Security

Deliverables:

- image scanning
- SBOM generation
- image signing
- artifact retention policy

Current status:

- image scanning added to the UI workflow in report mode
- SBOM, signing, and retention policy work still remain

### Phase D: Promotion Workflow

Deliverables:

- explicit prod promotion workflow
- immutable image-only prod changes
- protected approval flow

### Phase E: Post-Deploy Verification

Deliverables:

- repeatable smoke tests for `dev`
- repeatable smoke tests for `prod`
- failure reporting and quick rollback guidance

## Definition Of Done

This project should consider the CI/CD platform production-grade when:

- pull requests must pass validation before merge
- image builds are reproducible and scanned
- artifacts are signed and traceable to Git commits
- `dev` updates quickly but safely
- `prod` promotions are explicit, immutable, and reviewable
- Argo CD remains the deployment authority
- rollback is a normal documented operation
- docs explain not just the commands, but the operating model

## Immediate Next Recommendation

Start with the smallest high-value implementation slice:

1. add a dedicated `validate.yml`
2. harden workflow permissions
3. add image scanning to the UI build workflow
4. then design the prod promotion workflow

That order gives strong risk reduction without destabilizing the current working platform.
