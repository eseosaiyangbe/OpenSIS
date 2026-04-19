# 01: Prerequisites

This guide helps you prepare your machine before you run the project.

The repo supports two main paths:

- local Docker Compose
- Kubernetes with Vault and Argo CD

If you are new to the stack, start with Docker Compose first.

## 1. What You Should Know First

You do not need to be an expert, but these basics will help:

- how to open and use a terminal
- how to edit files in a code editor
- how to run commands and read error messages
- the difference between a local setup and a cluster setup

If Kubernetes is new to you, that is completely fine. Start with the local Compose path, then move to Kubernetes later.

## 2. Machine Requirements

Recommended minimum for local learning:

- 4 CPU cores
- 8 GB RAM
- 30 GB free disk

Recommended for Kubernetes and observability work:

- 8 CPU cores
- 16 GB RAM
- 50 GB free disk

## 3. Operating System

This repo is easiest to follow on Linux, but macOS is supported too.

This guide covers two first-day setups:

- Ubuntu 22.04 or 24.04
- macOS with Homebrew

If you are using another Linux distribution, the overall flow is the same, but some package manager commands will be different.

## 4. Install The Base Tools

Start by installing the basic utilities used throughout the project.

### Ubuntu

```bash
sudo apt update
sudo apt install -y \
  ca-certificates \
  curl \
  git \
  gnupg \
  jq \
  lsb-release \
  python3 \
  python3-pip \
  ripgrep \
  shellcheck \
  unzip \
  wget \
  yamllint
```

### macOS

If Homebrew is not installed yet, install it first:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Then install the base tools:

```bash
brew install \
  curl \
  git \
  jq \
  python \
  ripgrep \
  shellcheck \
  wget \
  yamllint
```

What these are used for:

- `git` for cloning and updating the repository
- `curl` and `wget` for downloads and health checks
- `jq` for reading JSON output
- `ripgrep` for searching files quickly
- `shellcheck` for shell script linting
- `yamllint` for YAML validation

## 5. Install Docker And Docker Compose

Docker Compose is the easiest way to run the project locally.

### Ubuntu

If Docker was installed before on your machine, remove older distro-packaged versions first.

Why this helps:

- Ubuntu sometimes ships older Docker-related packages
- mixing those packages with Docker's official packages can cause confusing conflicts
- if the packages are not installed, the command will simply do nothing harmful

Optional cleanup:

```bash
sudo apt remove -y docker docker-engine docker.io containerd runc || true
```

Add Docker's official repository:

```bash
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo \"$VERSION_CODENAME\") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
```

Install Docker Engine and Compose:

```bash
sudo apt update
sudo apt install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin
```

Allow your user to run Docker without `sudo`:

```bash
sudo usermod -aG docker "$USER"
newgrp docker
```

### macOS

Install Docker Desktop:

```bash
brew install --cask docker
```

Then start Docker Desktop from Launchpad or Spotlight and wait until Docker shows as running.

### Verify Docker

```bash
docker --version
docker compose version
docker run --rm hello-world
```

## 6. Install kubectl

You only need this if you plan to use the Kubernetes path.

### Ubuntu

```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/kubectl
```

### macOS

```bash
brew install kubectl
```

### Verify kubectl

```bash
kubectl version --client
```

## 7. Install Helm

Helm is used for platform components such as Vault.

### Ubuntu

```bash
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

### macOS

```bash
brew install helm
```

### Verify Helm

```bash
helm version
```

## 8. Install Argo CD CLI

The Argo CD CLI is optional, but it is useful for GitOps operations.

### Ubuntu

```bash
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
rm -f argocd-linux-amd64
```

### macOS

```bash
brew install argocd
```

### Verify Argo CD CLI

```bash
argocd version --client
```

## 9. Optional Quality Tools

These are not required to run the stack, but they help you contribute cleanly.

### actionlint

#### Ubuntu

```bash
curl -s https://raw.githubusercontent.com/rhysd/actionlint/main/scripts/download-actionlint.bash | bash
sudo mv ./actionlint /usr/local/bin/actionlint
```

#### macOS

```bash
brew install actionlint
```

#### Verify

```bash
actionlint -version
```

### kustomize

You do not need a separate `kustomize` binary for this repo because `kubectl kustomize` is enough.

Verify:

```bash
kubectl kustomize k8s/base >/dev/null
```

## 10. Accounts And External Services

### Required for the local path

- no cloud account is required

### Required for the full Kubernetes production-style path

- GitHub repository access
- Docker Hub repository access
- Cloudflare account if you want the public edge path

## 11. Repo Preparation

Clone the repository:

```bash
git clone <your-fork-or-repo-url>
cd Dev_test2
```

If you plan to push changes:

```bash
git remote -v
git checkout main
```

## 12. Kubernetes Access Notes

If you are using `k3s`, tools like K9s may not work until you create a standard kubeconfig at `~/.kube/config`.

Use:

```bash
mkdir -p ~/.kube
cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
chmod 600 ~/.kube/config
```

Optional cleanup for a friendlier context name:

```bash
kubectl config rename-context default k3s-devbox
```

Verify:

```bash
kubectl config get-contexts
kubectl config current-context
kubectl top nodes
```

## 13. Environment File

This repo expects a local `.env` file for Compose values.

Check the current file:

```bash
cat .env
```

Make sure it includes the values needed by the local Vault seed flow:

- `APP_ENV`
- `MYSQL_ROOT_PASSWORD`
- `MYSQL_DATABASE`
- `MYSQL_USER`
- `MYSQL_PASSWORD`

## 14. Verify Your Tooling

Run these before starting:

```bash
git --version
curl --version
jq --version
rg --version
shellcheck --version
yamllint --version
docker --version
docker compose version
kubectl version --client
helm version
argocd version --client
```

If you are only using Compose, `kubectl`, `helm`, and `argocd` can wait until later.

## 15. Local Ports Used By This Repo

Important local ports:

- `8088` for local openSIS UI
- `8200` for local Vault
- `80` for local Traefik if you enable the `edge` profile

Make sure those ports are free before you start.

Useful checks:

### Ubuntu

```bash
ss -ltnp | rg ':8088|:8200|:80'
```

### macOS

```bash
lsof -nP -iTCP -sTCP:LISTEN | rg ':(8088|8200|80)\\b'
```

## 16. Recommended Start Path

For most beginners, this order works best:

1. local Compose
2. local troubleshooting
3. Kubernetes bootstrap
4. GitOps and operations

That gives you a simpler mental model before you move into the cluster version.

## 17. Where To Go Next

- local setup: [02-local-compose-guide.md](02-local-compose-guide.md)
- Kubernetes path: [03-kubernetes-bootstrap-guide.md](03-kubernetes-bootstrap-guide.md)
