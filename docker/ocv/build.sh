#!/usr/bin/env bash

# OpenCV + CUDA build script for Docker build stages. Mirrors build_ocv_cuda.sh
# but avoids sudo and writes artifacts to a relocatable prefix for later copy.
set -euo pipefail

OPENCV_VERSION=${OPENCV_VERSION:-4.11.0}
PYTHON_VERSION=${PYTHON_VERSION:-3.10.12}
CUDA_ARCH_BIN=${CUDA_ARCH_BIN:-${CUDA_DOCKER_ARCH:-8.7}}
NUMPY_VERSION_SPEC=${NUMPY_VERSION_SPEC:-<2}
WORKSPACE_ROOT=${WORKSPACE_ROOT:-/opt/ocv}
SRC_DIR=${SRC_DIR:-${WORKSPACE_ROOT}/opencv}
CONTRIB_DIR=${CONTRIB_DIR:-${WORKSPACE_ROOT}/opencv_contrib}
BUILD_DIR=${BUILD_DIR:-${WORKSPACE_ROOT}/build}
VENV_DIR=${VENV_DIR:-${WORKSPACE_ROOT}/.venv}
INSTALL_PREFIX=${INSTALL_PREFIX:-${BUILD_DIR}/install}
WHEEL_DIR=${WHEEL_DIR:-${BUILD_DIR}/wheelhouse}
WHEEL_EXPORT_DIR=${WHEEL_EXPORT_DIR:-${WORKSPACE_ROOT}/wheelhouse}
USE_VENV=${USE_VENV:-0}
CLEAN_BUILD=${CLEAN_BUILD:-1}

if [[ -t 1 ]]; then
	COLOR_YELLOW="\033[33m"
	COLOR_RESET="\033[0m"
else
	COLOR_YELLOW=""
	COLOR_RESET=""
fi

info() { printf "%b[INFO]%b %s\n" "${COLOR_YELLOW}" "${COLOR_RESET}" "$*"; }
err() { printf "%b[ERROR]%b %s\n" "${COLOR_YELLOW}" "${COLOR_RESET}" "$*" >&2; exit 1; }

# Resolve Python executable
PY_SHORT="${PYTHON_VERSION%.*}"
PY_BIN="$(command -v "python${PY_SHORT}" 2>/dev/null || true)"
if [[ -z "${PY_BIN}" ]]; then
	PY_BIN="$(command -v python3 2>/dev/null || true)"
fi
[[ -z "${PY_BIN}" ]] && err "Python ${PY_SHORT} not found"

# Optional virtualenv
if [[ "${USE_VENV}" == "1" ]]; then
	info "Creating venv at ${VENV_DIR}"
	"${PY_BIN}" -m venv "${VENV_DIR}"
	# shellcheck disable=SC1091
	source "${VENV_DIR}/bin/activate"
	python -m pip install --upgrade pip
	python -m pip install "numpy${NUMPY_VERSION_SPEC}"
	PY_BIN="${VENV_DIR}/bin/python"
else
	info "Ensuring numpy${NUMPY_VERSION_SPEC} available for build"
	"${PY_BIN}" -m pip install --upgrade pip
	"${PY_BIN}" -m pip install --upgrade --force-reinstall "numpy${NUMPY_VERSION_SPEC}"
fi

# Resolve numpy include dir for CMake
NUMPY_INCLUDE_DIR="$(${PY_BIN} - <<'PY'
import numpy as np
print(np.get_include())
PY
)"
[[ -z "${NUMPY_INCLUDE_DIR}" ]] && err "Could not determine numpy include directory"

# Optional clean to avoid stale CMake cache pulling cudss
if [[ "${CLEAN_BUILD}" == "1" ]]; then
	rm -rf "${BUILD_DIR:?}"/*
fi

# Ensure required directories exist after any clean
mkdir -p "${BUILD_DIR}" "${INSTALL_PREFIX}" "${WHEEL_DIR}" "${WHEEL_EXPORT_DIR}"

# Clone sources if missing
if [[ ! -d "${SRC_DIR}" ]]; then
	info "Cloning OpenCV ${OPENCV_VERSION} into ${SRC_DIR}"
	git clone --branch "${OPENCV_VERSION}" --depth 1 https://github.com/opencv/opencv.git "${SRC_DIR}"
fi

if [[ ! -d "${CONTRIB_DIR}" ]]; then
	info "Cloning OpenCV contrib ${OPENCV_VERSION} into ${CONTRIB_DIR}"
	git clone --branch "${OPENCV_VERSION}" --depth 1 https://github.com/opencv/opencv_contrib.git "${CONTRIB_DIR}"
fi

# Configure
info "Configuring OpenCV with CUDA (arch=${CUDA_ARCH_BIN})"
cmake -S "${SRC_DIR}" -B "${BUILD_DIR}" \
	-D CMAKE_BUILD_TYPE=Release \
	-D CMAKE_INSTALL_PREFIX="${INSTALL_PREFIX}" \
	-D OPENCV_EXTRA_MODULES_PATH="${CONTRIB_DIR}/modules" \
	-D OPENCV_GENERATE_PKGCONFIG=ON \
	-D OPENCV_PC_FILE_NAME=opencv.pc \
	-D BUILD_TESTS=OFF \
	-D BUILD_PERF_TESTS=OFF \
	-D BUILD_EXAMPLES=OFF \
	-D CMAKE_DISABLE_FIND_PACKAGE_cudss=ON \
	-D CMAKE_DISABLE_FIND_PACKAGE_CUDSS=ON \
	-D WITH_CUDA=ON \
	-D WITH_CUDNN=ON \
	-D OPENCV_DNN_CUDA=ON \
	-D CUDA_ARCH_BIN="${CUDA_ARCH_BIN}" \
	-D ENABLE_FAST_MATH=ON \
	-D CUDA_FAST_MATH=ON \
	-D WITH_CUFFT=ON \
	-D WITH_CUBLAS=ON \
	-D WITH_V4L=ON \
	-D WITH_OPENCL=ON \
	-D WITH_OPENGL=ON \
	-D WITH_GSTREAMER=ON \
	-D WITH_TBB=ON \
	-D BUILD_opencv_python3=ON \
	-D PYTHON3_EXECUTABLE="${PY_BIN}" \
	-D PYTHON3_NUMPY_INCLUDE_DIRS="${NUMPY_INCLUDE_DIR}"

# Build and install
info "Building OpenCV"
cmake --build "${BUILD_DIR}" -- -j"$(nproc)"

info "Installing OpenCV to ${INSTALL_PREFIX}"
cmake --install "${BUILD_DIR}"

# Provide opencv4.pc alias for tooling expecting the opencv4 pkg-config name
if [[ -f "${INSTALL_PREFIX}/lib/pkgconfig/opencv.pc" ]]; then
	ln -sf "${INSTALL_PREFIX}/lib/pkgconfig/opencv.pc" \
		"${INSTALL_PREFIX}/lib/pkgconfig/opencv4.pc"
fi

# Ensure Python bindings target is built (produces cv2 binary and config.py)
info "Building Python bindings target (opencv_python3)"
cmake --build "${BUILD_DIR}" --target opencv_python3 -- -j"$(nproc)"

# Build and store Python wheel for reuse using OpenCV's python package setup
info "Building OpenCV Python wheel (output -> ${WHEEL_DIR})"
pushd "${SRC_DIR}/modules/python/package" >/dev/null
export CMAKE_BUILD_PARALLEL_LEVEL="${CMAKE_BUILD_PARALLEL_LEVEL:-$(nproc)}"
export CMAKE_ARGS="\
	-DCMAKE_BUILD_TYPE=Release \
	-DOPENCV_EXTRA_MODULES_PATH=${CONTRIB_DIR}/modules \
	-DBUILD_TESTS=OFF \
	-DBUILD_PERF_TESTS=OFF \
	-DBUILD_EXAMPLES=OFF \
	-DCMAKE_DISABLE_FIND_PACKAGE_cudss=ON \
	-DCMAKE_DISABLE_FIND_PACKAGE_CUDSS=ON \
	-DWITH_CUDA=ON \
	-DWITH_CUDNN=ON \
	-DOPENCV_DNN_CUDA=ON \
	-DCUDA_ARCH_BIN=${CUDA_ARCH_BIN} \
	-DENABLE_FAST_MATH=ON \
	-DCUDA_FAST_MATH=ON \
	-DWITH_CUFFT=ON \
	-DWITH_CUBLAS=ON \
	-DWITH_V4L=ON \
	-DWITH_OPENCL=ON \
	-DWITH_OPENGL=ON \
	-DWITH_GSTREAMER=ON \
	-DWITH_TBB=ON \
	-DPYTHON3_EXECUTABLE=${PY_BIN} \
	-DPYTHON3_NUMPY_INCLUDE_DIRS=${NUMPY_INCLUDE_DIR}"
"${PY_BIN}" setup.py bdist_wheel
mv dist/opencv*.whl "${WHEEL_DIR}/" 2>/dev/null || true
cp -n "${WHEEL_DIR}"/opencv*.whl "${WHEEL_EXPORT_DIR}/" 2>/dev/null || true
popd >/dev/null

info "Build completed; artifacts available under ${INSTALL_PREFIX} and ${WHEEL_DIR}"
