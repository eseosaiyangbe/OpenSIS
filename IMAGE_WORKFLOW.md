# Image Workflow

This repo uses a Docker Hub-oriented image workflow for `opensis-ui`.

## Why

The local `docker build` plus `k3s ctr images import` path is useful for learning, but it is not a repeatable deployment workflow.

The registry-backed workflow gives us:

- one source of truth for images
- reproducible tags
- a clean path from local learning to production
- a better fit for the Kustomize overlays

## Registry Choice

This project is set up for Docker Hub.

The GitHub Actions workflow lives at:

- [.github/workflows/dockerhub-opensis-ui.yml](/home/theinventor/Desktop/devops/devopseasylearning/Dev_test2/.github/workflows/dockerhub-opensis-ui.yml)

## GitHub Settings Required

Set these in the GitHub repository settings.

### Repository Variables

- `DOCKERHUB_USERNAME`
- `DOCKERHUB_REPOSITORY`
  - optional
  - defaults logically to `opensis-ui` in the workflow if omitted

### Repository Secret

- `DOCKERHUB_TOKEN`
  - use a Docker Hub access token, not your password

## Tagging Strategy

The workflow currently publishes:

- branch tags
- git SHA tags with the `git-` prefix
- release tags like `v1.0.0`

Examples:

- `docker.io/<your-user>/opensis-ui:develop`
- `docker.io/<your-user>/opensis-ui:git-abc1234`
- `docker.io/<your-user>/opensis-ui:v1.0.0`

For this repo, the Docker Hub username is:

- `eseosaiyangbe`

So practical examples become:

- `docker.io/eseosaiyangbe/opensis-ui:develop`
- `docker.io/eseosaiyangbe/opensis-ui:git-abc1234`
- `docker.io/eseosaiyangbe/opensis-ui:v1.0.0`

The workflow intentionally does not rely on `latest`.

## Environment Strategy

### dev

The `dev` overlay still uses `opensis-ui:dev` today because that is what we used to validate the local `k3s` lab flow.

Once Docker Hub publishing is active, you can switch the `dev` overlay to something like:

- `docker.io/<your-user>/opensis-ui:develop`

### prod

The `prod` overlay should use a pinned Docker Hub image tag.

Examples:

- `docker.io/<your-user>/opensis-ui:git-abc1234`
- `docker.io/<your-user>/opensis-ui:v1.0.0`

For this repo, that means production tags should look like:

- `docker.io/eseosaiyangbe/opensis-ui:git-abc1234`
- `docker.io/eseosaiyangbe/opensis-ui:v1.0.0`

## Recommended Next Step

After the workflow is connected to your GitHub repo and Docker Hub account:

1. push the repo to GitHub
2. add the required variables and secret
3. trigger the workflow
4. confirm the image exists in Docker Hub
5. update the overlays to use your real Docker Hub image path
