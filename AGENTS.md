# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

jetson-containers is a modular container build system for NVIDIA Jetson devices. It discovers packages, resolves their dependencies, chains their Dockerfiles together, and runs `docker build` to produce multi-stage images optimized for specific L4T/JetPack/CUDA versions.

## Commands

### Build & Run
```bash
# Build one or more packages (chains Dockerfiles in dependency order)
jetson-containers build <package> [<package2> ...]
# or equivalently:
./build.sh <package> [<package2> ...]

# Find and run a compatible container image
jetson-containers run $(autotag <package>) [command]
# or equivalently:
./run.sh $(autotag <package>) [command]

# Find the best matching image tag (local → DockerHub → build)
autotag <package>

# Useful build flags
jetson-containers build --simulate <package>              # dry-run: print commands without building
jetson-containers build --multiple pytorch tensorflow     # build each package as a separate image
jetson-containers build --list-packages                   # list all discovered packages
jetson-containers build --show-packages <package>         # show resolved metadata for a package
jetson-containers build --base=xyz:latest <package>       # start the build chain from an existing image
jetson-containers build --push=myuser <package>           # push to a registry after building

# Check for upstream version upgrades (--apply to write changes)
jetson-containers upgrade [<package> ...] [--apply]
```

### Code Style
```bash
# Install pre-commit hooks (one-time setup)
pip install -r requirements.txt
pre-commit install

# Run linting/formatting checks manually
pre-commit run --all-files
```

Pre-commit runs **Black** (formatter, line-length=88) and **Flake8** (linter) only on `jetson_containers/` and `test_precommit.py`. `packages/` Dockerfiles and `config.py` files are **not** linted by pre-commit. Note: `skip-string-normalization = true` in `pyproject.toml`.

### Tests
```bash
# Run a package config unit test directly (uses stdlib unittest, no pytest needed)
python3 tests/verify_triton_config.py
```

### Installation
```bash
bash install.sh   # sets up venv, installs deps, symlinks CLI tools to /usr/local/bin
```

## Architecture

### Package System

Every buildable unit is a **package**. Packages live under `packages/<category>/<name>/` and define metadata via one of (in priority order):

1. **YAML header in Dockerfile** — metadata between `#---` markers at the top
2. **`config.yaml` / `config.yml`** — static YAML config file
3. **`config.json`** — meta-container (no Dockerfile, just dependency composition)
4. **`config.py`** — dynamic config, returns a list of package dicts at build time

Key metadata fields: `name`, `alias`, `depends` (build-order deps), `requires` (version constraints on L4T/CUDA/Python), `test`, `build_args`, `dockerfile`.

### Build Pipeline

1. **`jetson_containers/packages.py`** — scans `packages/` recursively, runs `config.py` scripts, resolves the dependency graph, filters by L4T version compatibility, and exposes a custom Python meta path finder so packages can `from packages.ml.pytorch.version import ...`
2. **`jetson_containers/build.py`** — CLI entry point; parses args and dispatches
3. **`jetson_containers/container.py`** — core build logic: stitches multiple package Dockerfiles into one combined `Dockerfile`, invokes `docker build`, optionally runs per-package tests, and optionally pushes to a registry
4. **`jetson_containers/l4t_version.py`** — detects architecture (tegra-aarch64, aarch64, x86_64) and reads L4T/JetPack/CUDA/GPU-arch info from `/etc/nv_tegra_release`; all version variables (e.g. `CUDA_VERSION`, `PYTORCH_VERSION`) flow from here into build args

### Dynamic Package Generation

`config.py` files execute at build time and can return multiple package dicts to produce version variants. For example, PyTorch's `config.py` generates `pytorch:2.8`, `pytorch:2.8-all`, `pytorch:2.8-builder`, etc. Aliases (`torch` → `pytorch:2.8`) are resolved during package discovery.

When a package's version selection logic is complex, put it in a separate `version.py` alongside `config.py`. This lets other packages cross-import it:
```python
from packages.ml.pytorch.version import PYTORCH_VERSION
```
The `_PackagesFinder` meta path finder in `packages.py` resolves these imports against the `packages/` tree without requiring `__init__.py` files.

### Dockerfile Conventions

Use `uv pip install` (not plain `pip install`) inside Dockerfiles — `uv` is pre-installed in the base images and is significantly faster. Every Dockerfile must start with:
```dockerfile
ARG BASE_IMAGE
FROM ${BASE_IMAGE}
```

### Version Overrides

Copy `.env.default` → `.env` to override `L4T_VERSION`, `CUDA_VERSION`, `LSB_RELEASE`, `CUDA_ARCH`, local PyPI/APT mirror URLs, and SCP/webhook credentials without modifying tracked files.

### Creating a New Package

1. Create `packages/<category>/<name>/Dockerfile` with a `#---` YAML header (or a `config.yaml`/`config.py`).
2. Declare `depends` on upstream packages (e.g., `pytorch`, `cuda`).
3. Optionally add `test.py` or `test.sh` for post-build validation.
4. Build: `jetson-containers build <name>`

## Security Features

### Multi-Stage Builds

The build system is multi-stage aware. Packages can use `FROM ... AS <alias>` for intermediate stages (e.g. a compiler/builder stage) without those stages polluting the final image. The build system tracks stage boundaries and only injects BuildKit features (ccache env vars, `--device` mounts, ccache `--mount` flags) into the **final** stage (the `FROM ${BASE_IMAGE}` stage). Intermediate stages are left untouched.

Declare multi-stage packages in config metadata:
```yaml
#---
# name: mypackage
# multistage: true
# depends: [cuda]
#---
ARG BASE_IMAGE
FROM gcc:12 AS builder
RUN make install

FROM ${BASE_IMAGE}
COPY --from=builder /usr/local /usr/local
RUN ldconfig
```

The final stage **must** use `ARG BASE_IMAGE` / `FROM ${BASE_IMAGE}` so it chains correctly in the dependency build pipeline.

### Non-Root User

**At build time** — pass identity via env vars; packages can create and switch to the declared user:
```bash
export CONTAINER_USER=jetson
export CONTAINER_UID=1000
export CONTAINER_GID=1000
jetson-containers build mypackage
```

`CONTAINER_USER`, `CONTAINER_UID`, `CONTAINER_GID` are forwarded as `--build-arg` automatically. Packages consume them like:
```dockerfile
ARG CONTAINER_USER=root
ARG CONTAINER_UID=0
ARG CONTAINER_GID=0
RUN if [ "$CONTAINER_UID" != "0" ]; then \
        groupadd -g $CONTAINER_GID $CONTAINER_USER && \
        useradd -u $CONTAINER_UID -g $CONTAINER_GID -m $CONTAINER_USER; \
    fi
USER $CONTAINER_USER
```

Declare the supported user in package metadata (`run_user` is informational for tooling):
```yaml
# run_user: jetson
```

**At runtime** — set `DOCKER_USER` to run the container as a non-root identity:
```bash
DOCKER_USER=1000:1000 ./run.sh myimage
# or by name (the user must exist in the image):
DOCKER_USER=jetson ./run.sh myimage
```
X11 forwarding (`xhost`) is automatically updated to grant the declared user display access.

For GPU access, `run.sh` also discovers the numeric GIDs that own the NVIDIA/Tegra device nodes (`/dev/nvhost*`, `/dev/nvmap`, `/dev/nvgpu/*`, `/dev/dri/render*`) and adds them via `--group-add <gid>`. Without this, a non-root process can't open the GPU nodes and CUDA fails with error 801 (`cudaGetDeviceCount` "operation not supported"). Numeric GIDs are used because the host's `render` GID usually doesn't match the container's. See [`docs/run.md`](/docs/run.md#gpu-access-as-non-root-cuda-error-801).

### Secrets

**Build-time secrets** (never baked into image layers) — declare secrets in package metadata:
```yaml
#---
# name: mypackage
# secrets: [huggingface_token]
#---
```

Point each secret at a file on the host via `JETSON_SECRET_<NAME>`:
```bash
export JETSON_SECRET_HUGGINGFACE_TOKEN=~/.hf_token
jetson-containers build mypackage
```

Secrets are mounted as `/run/secrets/<name>` inside `RUN` steps only (BuildKit `--secret`). Use them in the Dockerfile:
```dockerfile
RUN --mount=type=secret,id=huggingface_token \
    HF_TOKEN=$(cat /run/secrets/huggingface_token) \
    python3 download_model.py
```

If the env var is missing, a warning is printed and the build continues without that secret.

**Runtime secrets** — prefer file-backed tokens over env vars (values in env vars are visible in `docker inspect`):
```bash
# Preferred: mount token file into /run/secrets/
HUGGINGFACE_TOKEN_FILE=~/.hf_token ./run.sh myimage

# Fallback (token visible in docker inspect):
HUGGINGFACE_TOKEN=hf_xxx ./run.sh myimage
```

`HUGGINGFACE_TOKEN_FILE` mounts the file read-only at `/run/secrets/huggingface_token` and sets `HF_TOKEN_FILE` inside the container.

### Key Supporting Modules

- `jetson_containers/tag.py` — image tagging conventions
- `jetson_containers/docs.py` — auto-generates per-package docs from metadata
- `jetson_containers/ci.py` — CI/CD helpers
- `jetson_containers/network.py` / `webhook.py` — GitHub API integration and build notifications
- `jetson_containers/logging.py` — colored terminal output used throughout
- `jetson_containers/upgrade.py` — checks packages against upstream (PyPI/GitHub) for newer versions; powers `jetson-containers upgrade`
- `jetson_containers/db.py` — syncs DockerHub/GitHub metadata for registry introspection
