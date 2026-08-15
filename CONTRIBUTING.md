# Contributing to jetson-containers

## Adding a Package

1. Create `packages/<category>/<name>/` and add a `Dockerfile` with a `#---` YAML header:

   ```dockerfile
   #---
   # name: mypackage
   # group: ml
   # depends: [pytorch, cuda]
   # requires: '>=36'
   # test: test.py
   #---
   ARG BASE_IMAGE
   FROM ${BASE_IMAGE}

   RUN uv pip install mypackage
   ```

2. **Every Dockerfile must start with `ARG BASE_IMAGE` / `FROM ${BASE_IMAGE}`** so it chains correctly in the dependency build pipeline.

3. **Use `uv pip install`** (not plain `pip install`) — `uv` is pre-installed in base images and is significantly faster.

4. Run a local build to verify: `jetson-containers build mypackage`

5. Add a `test.py` or `test.sh` that imports or exercises the package — it runs automatically after build unless `--skip-tests` is passed.

Full metadata reference: [`docs/packages.md`](/docs/packages.md)

## Multi-Stage Packages

If your Dockerfile uses intermediate build stages, declare `multistage: true` in the header so tooling knows:

```dockerfile
#---
# name: mypackage
# multistage: true
# depends: [cuda]
#---
ARG BASE_IMAGE
FROM gcc:12 AS builder
RUN make -j$(nproc) && make install DESTDIR=/out

FROM ${BASE_IMAGE}
COPY --from=builder /out /usr/local
RUN ldconfig
```

The build system only injects ccache and GPU device mounts into the **final** `FROM ${BASE_IMAGE}` stage. Intermediate stages are left untouched.

## Non-Root Support

If your package is designed to run as a non-root user, accept the standard identity build args and declare `run_user` in metadata:

```dockerfile
#---
# name: mypackage
# run_user: jetson
#---
ARG BASE_IMAGE
FROM ${BASE_IMAGE}

ARG CONTAINER_USER=root
ARG CONTAINER_UID=0
ARG CONTAINER_GID=0

RUN if [ "$CONTAINER_UID" != "0" ]; then \
        groupadd -g $CONTAINER_GID $CONTAINER_USER && \
        useradd -u $CONTAINER_UID -g $CONTAINER_GID -m $CONTAINER_USER; \
    fi

USER $CONTAINER_USER
```

Build with: `CONTAINER_USER=jetson CONTAINER_UID=1000 CONTAINER_GID=1000 jetson-containers build mypackage`

> **Note:** Packages that use CSI cameras via `nvargus-daemon` cannot support non-root — the daemon socket is root-owned by design.

## Secrets

If your package needs credentials at build time (model weights, private registries), declare them in metadata and consume via BuildKit `--mount=type=secret`:

```dockerfile
#---
# name: mypackage
# secrets: [huggingface_token]
#---
ARG BASE_IMAGE
FROM ${BASE_IMAGE}

RUN --mount=type=secret,id=huggingface_token \
    HF_TOKEN=$(cat /run/secrets/huggingface_token) \
    python3 download_weights.py
```

The caller sets `JETSON_SECRET_HUGGINGFACE_TOKEN=/path/to/token/file` before building. The secret is never baked into an image layer.

## Dynamic Version Configs

Use `config.py` when package variants or build args depend on the L4T/CUDA/Python version. Put version-selection logic in a separate `version.py` so other packages can import it:

```python
# packages/ml/mypackage/version.py
from jetson_containers import L4T_VERSION, CUDA_VERSION
from packaging.version import Version

MYPACKAGE_VERSION = Version('2.0') if L4T_VERSION.major >= 36 else Version('1.8')
```

Other packages can then do: `from packages.ml.mypackage.version import MYPACKAGE_VERSION`

## Code Style

Changes to `jetson_containers/` Python files must pass Black and Flake8:

```bash
pip install -r requirements.txt
pre-commit install          # one-time setup
pre-commit run --all-files  # check before committing
```

- **Black** line length: 88 (`skip-string-normalization = true` — single quotes are fine)
- **Flake8** covers `jetson_containers/` only; `packages/` Dockerfiles and `config.py` files are not linted

## Testing

Run unit tests with stdlib `unittest` (no pytest needed):

```bash
python3 tests/verify_triton_config.py
```

For new packages, a `test.py` that does a minimal import + sanity check is sufficient. The build system runs it automatically after the package builds.

## Pull Request Guidelines

- **One logical change per PR** — new package, security feature, bug fix, or doc update.
- **All changes to `jetson_containers/`** require updating the relevant `docs/` page and `AGENTS.md`.
- **New package metadata fields** require updating the table in `docs/packages.md` and `jetson_containers/packages.py` (`_PACKAGE_KEYS`).
- **`run.sh` changes** require updating `docs/run.md`.
- PRs are reviewed by `@dusty-nv` and `@johnnynunez` (see `CODEOWNERS`).
