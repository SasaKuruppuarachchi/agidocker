#!/usr/bin/env bash

# Install the OpenCV wheel built by build.sh and configure loader paths.
set -euo pipefail

OPENCV_VERSION=${OPENCV_VERSION:-4.11.0}
PYTHON_VERSION=${PYTHON_VERSION:-3.10.12}
NUMPY_VERSION_SPEC=${NUMPY_VERSION_SPEC:-<2}
WORKSPACE_ROOT=${WORKSPACE_ROOT:-/opt/ocv}
INSTALL_PREFIX=${INSTALL_PREFIX:-${WORKSPACE_ROOT}/build/install}
WHEEL_DIR=${WHEEL_DIR:-${WORKSPACE_ROOT}/build/wheelhouse}

info() { printf "[INFO] %s\n" "$*"; }
err() { printf "[ERROR] %s\n" "$*" >&2; exit 1; }

PY_SHORT="${PYTHON_VERSION%.*}"
PY_BIN="$(command -v "python${PY_SHORT}" 2>/dev/null || true)"
if [[ -z "${PY_BIN}" ]]; then
  PY_BIN="$(command -v python3 2>/dev/null || true)"
fi
[[ -z "${PY_BIN}" ]] && err "Python ${PY_SHORT} not found"

wheel_path="$(ls "${WHEEL_DIR}"/opencv*.whl 2>/dev/null | head -n1)"
[[ -z "${wheel_path}" ]] && err "Wheel not found in ${WHEEL_DIR}"

info "Installing numpy${NUMPY_VERSION_SPEC} for OpenCV runtime compatibility"
"${PY_BIN}" -m pip install --upgrade --force-reinstall "numpy${NUMPY_VERSION_SPEC}"

info "Installing wheel ${wheel_path}"
"${PY_BIN}" -m pip install --force-reinstall --no-deps "${wheel_path}"

SITE_PACKAGES="$(${PY_BIN} - <<'PY'
import site, sysconfig
for path in site.getsitepackages():
	if 'site-packages' in path or 'dist-packages' in path:
		print(path)
		break
else:
	print(sysconfig.get_paths()['purelib'])
PY
)"

CONFIG_PATH="${SITE_PACKAGES}/cv2/config.py"
info "Writing loader config to ${CONFIG_PATH}"
mkdir -p "${SITE_PACKAGES}/cv2"
cat > "${CONFIG_PATH}" <<PY
import os, sys
BINARIES_PATHS = [
	"${INSTALL_PREFIX}/lib/python${PY_SHORT}/dist-packages/cv2/python-${PY_SHORT}",
	os.path.join(os.path.dirname(__file__), "python-${PY_SHORT}"),
]
for p in BINARIES_PATHS:
	if os.path.isdir(p) and p not in sys.path:
		sys.path.insert(0, p)
PY
cp "${CONFIG_PATH}" "${SITE_PACKAGES}/cv2/config-${PY_SHORT}.py"
cp "${CONFIG_PATH}" "${SITE_PACKAGES}/cv2/config-${PY_SHORT%.*}.py"

SO_SOURCE="$(find "${INSTALL_PREFIX}/lib/python${PY_SHORT}/dist-packages/cv2/python-${PY_SHORT}" -name 'cv2*.so' | head -n1 || true)"
[[ -z "${SO_SOURCE}" ]] && err "cv2 shared library not found under ${INSTALL_PREFIX}"

SO_TARGET_DIR="${SITE_PACKAGES}/cv2/python-${PY_SHORT}"
mkdir -p "${SO_TARGET_DIR}"
ln -sf "${SO_SOURCE}" "${SO_TARGET_DIR}/$(basename "${SO_SOURCE}")"

ldconfig "${INSTALL_PREFIX}/lib"

info "Verifying OpenCV ${OPENCV_VERSION} load"
"${PY_BIN}" - <<'PY'
import cv2
print("file:", cv2.__file__)
print("version:", cv2.__version__)
print("cuda devices:", cv2.cuda.getCudaEnabledDeviceCount())
PY

info "OpenCV installed"
