#!/bin/bash
#
# Copyright (c) 2021-2024, NVIDIA CORPORATION.  All rights reserved.
#
# NVIDIA CORPORATION and its licensors retain all intellectual property
# and proprietary rights in and to this software, related documentation
# and any modifications thereto.  Any use, reproduction, disclosure or
# distribution of this software and related documentation without an express
# license agreement from NVIDIA CORPORATION is strictly prohibited.

set -e

ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source $ROOT/utils/print_color.sh

function usage() {
    print_info "Usage: run_dev.sh"
    print_info "       [--progress plain|auto|tty]"
    print_info "Copyright (c) 2021-2024, NVIDIA CORPORATION."
}

DOCKER_ARGS=()

# Read and parse config file if exists
#
# CONFIG_IMAGE_KEY (string, can be empty)

if [[ -f "${ROOT}/.agipix_ros_common-config" ]]; then
    . "${ROOT}/.agipix_ros_common-config"
fi

# Override with config from user home directory if exists
if [[ -f ~/.agipix_ros_common-config ]]; then
    . ~/.agipix_ros_common-config
fi

# Parse command-line args
IMAGE_KEY=ros2_humble

# Pick up config image key if specified
if [[ ! -z "${CONFIG_IMAGE_KEY}" ]]; then
    IMAGE_KEY=$CONFIG_IMAGE_KEY
fi

SKIP_IMAGE_BUILD=0
SKIP_REGISTRY_CHECK=0
BUILD_PROGRESS=
VERBOSE=0
VALID_ARGS=$(getopt -o hvd:i:ba: --long help,verbose,isaac_ros_dev_dir:,image_key:,skip_image_build,skip-registry-check,progress:,docker_arg: -- "$@")
eval set -- "$VALID_ARGS"
while [ : ]; do
  case "$1" in
    -d | --isaac_ros_dev_dir)
        print_warning "Warning: -d / --isaac_ros_dev_dir is deprecated and no longer used."
        shift 2
        ;;
    -i | --image_key)
        IMAGE_KEY="$2"
        shift 2
        ;;
    -b | --skip_image_build)
        SKIP_IMAGE_BUILD=1
        shift
        ;;
    --skip-registry-check)
        SKIP_REGISTRY_CHECK=1
        shift
        ;;
    --progress)
        BUILD_PROGRESS="$2"
        shift 2
        ;;
    -a | --docker_arg)
        DOCKER_ARGS+=("$2")
        shift 2
        ;;
    -v | --verbose)
        VERBOSE=1
        shift
        ;;
    -h | --help)
        usage
        exit 0
        ;;
    --) shift;
        break
        ;;
  esac
done

# Setup on-exit traps
ON_EXIT=()
function cleanup {
    for command in "${ON_EXIT[@]}"
    do
        $command
    done
}
trap cleanup EXIT

pushd . >/dev/null
cd $ROOT
ON_EXIT+=("popd")


# Prevent running as root.
if [[ $(id -u) -eq 0 ]]; then
    print_error "This script cannot be executed with root privileges."
    print_error "Please re-run without sudo and follow instructions to configure docker for non-root user if needed."
    exit 1
fi

# Default and normalize WORKSPACES_DIR if not set
if [[ -z "$WORKSPACES_DIR" ]]; then
    WORKSPACES_DIR="$HOME/workspace"
fi
WORKSPACES_DIR="${WORKSPACES_DIR/#\~/$HOME}"

# Ensure host directories for Docker volume mounts exist
MOUNTED_DIRS=(
    "$WORKSPACES_DIR/dds"
    "$WORKSPACES_DIR/agipix_control"
    "$WORKSPACES_DIR/lidar_ws"
    "$WORKSPACES_DIR/logging"
    "$WORKSPACES_DIR/ui"
    "$WORKSPACES_DIR/docker/agidocker/.ide-session-data/sessions/ros2/.gemini"
)

for dir in "${MOUNTED_DIRS[@]}"; do
    if [[ ! -d "$dir" ]]; then
        print_info "Creating missing workspace directory: $dir"
        mkdir -p "$dir"
    fi
done

# Ensure single-file mounts exist so Docker does not create them as directories
if [[ ! -f "$HOME/.profile" ]]; then
    touch "$HOME/.profile"
fi
if [[ ! -f "$HOME/.Xauthority" ]]; then
    touch "$HOME/.Xauthority"
fi

# Check if user can run docker without root.
RE="\<docker\>"
if [[ ! $(groups $USER) =~ $RE ]]; then
    print_error "User |$USER| is not a member of the 'docker' group and cannot run docker commands without sudo."
    print_error "Run 'sudo usermod -aG docker \$USER && newgrp docker' to add user to 'docker' group, then re-run this script."
    print_error "See: https://docs.docker.com/engine/install/linux-postinstall/"
    exit 1
fi

# Check if able to run docker commands.
if [[ -z "$(docker ps)" ]] ;  then
    print_error "Unable to run docker commands. If you have recently added |$USER| to 'docker' group, you may need to log out and log back in for it to take effect."
    print_error "Otherwise, please check your Docker installation."
    exit 1
fi

# Check if git-lfs is installed (safe under set -e).
if ! git lfs version &>/dev/null ; then
    print_error "git-lfs is not installed. Please make sure git-lfs is installed before you clone the repo."
    exit 1
fi

# Check if all LFS files are in place in the repository where this script is running from.
cd $ROOT
if git rev-parse &>/dev/null; then
    LFS_FILES_STATUS=$(cd "$ROOT/.." && git lfs ls-files | cut -d ' ' -f2)
    for (( i=0; i<${#LFS_FILES_STATUS}; i++ )); do
        f="${LFS_FILES_STATUS:$i:1}"
        if [[ "$f" == "-" ]]; then
            print_error "LFS files are missing. Please re-clone repos after installing git-lfs."
            git lfs ls-files
            exit 1
        fi
    done
fi

# Determine base image key
PLATFORM="$(uname -m)"
BASE_IMAGE_KEY=$PLATFORM
if [[ ! -z "${IMAGE_KEY}" ]]; then
    BASE_IMAGE_KEY=$BASE_IMAGE_KEY.$IMAGE_KEY
fi

# Check skip image build from env
if [[ ! -z $SKIP_DOCKER_BUILD ]]; then
    SKIP_IMAGE_BUILD=1
fi

# Check skip image build from config
if [[ ! -z $CONFIG_SKIP_IMAGE_BUILD ]]; then
    SKIP_IMAGE_BUILD=1
fi

BASE_NAME="agipix_ros_dev-$PLATFORM"
if [[ ! -z "$CONFIG_CONTAINER_NAME_SUFFIX" ]] ; then
    BASE_NAME="$BASE_NAME-$CONFIG_CONTAINER_NAME_SUFFIX"
fi
CONTAINER_NAME="$BASE_NAME-container"

# Remove any exited containers.
if [ "$(docker ps -a --quiet --filter status=exited --filter name=$CONTAINER_NAME)" ]; then
    docker rm $CONTAINER_NAME > /dev/null
fi

# Re-use existing container.
if [ "$(docker ps -a --quiet --filter status=running --filter name=$CONTAINER_NAME)" ]; then
    print_info "Attaching to running container: $CONTAINER_NAME"
    ISAAC_ROS_WS=$(docker exec $CONTAINER_NAME printenv ISAAC_ROS_WS)
    print_info "Docker workspace: $ISAAC_ROS_WS"
    docker exec -i -t -u admin --workdir $ISAAC_ROS_WS $CONTAINER_NAME /bin/bash $@
    exit 0
fi

# Summarize launch
print_info "Launching Agipix ROS Dev container with image key ${BASE_IMAGE_KEY}"

# Build image to launch
if [[ $SKIP_IMAGE_BUILD -ne 1 ]]; then
    print_info "Building $BASE_IMAGE_KEY base as image: $BASE_NAME"
    # Forward optional flags to the build helper
    BUILD_HELPER_ARGS=()
    if [[ $SKIP_REGISTRY_CHECK -eq 1 ]]; then
        BUILD_HELPER_ARGS+=("--skip_registry_check")
    fi
    if [[ -n "$BUILD_PROGRESS" ]]; then
        BUILD_HELPER_ARGS+=("--progress" "$BUILD_PROGRESS")
    fi

    $ROOT/build_image_layers.sh --image_key "$BASE_IMAGE_KEY" --image_name "$BASE_NAME" "${BUILD_HELPER_ARGS[@]}"

    # Check result
    if [ $? -ne 0 ]; then
        if [[ -z $(docker image ls --quiet $BASE_NAME) ]]; then
            print_error "Building image failed and no cached image found for $BASE_NAME, aborting."
            exit 1
        else
            print_warning "Unable to build image, but cached image found."
        fi
    fi
fi

# Check image is available
if [[ -z $(docker image ls --quiet $BASE_NAME) ]]; then
    print_error "No built image found for $BASE_NAME, aborting."
    exit 1
fi

# Map host's display socket to docker
DOCKER_ARGS+=("-v /tmp/.X11-unix:/tmp/.X11-unix")
DOCKER_ARGS+=("-v $HOME/.Xauthority:/home/admin/.Xauthority:rw")
DOCKER_ARGS+=("-e DISPLAY")
DOCKER_ARGS+=("-e NVIDIA_VISIBLE_DEVICES=all")
DOCKER_ARGS+=("-e NVIDIA_DRIVER_CAPABILITIES=all")
DOCKER_ARGS+=("-e ROS_DOMAIN_ID")
DOCKER_ARGS+=("-e USER")
DOCKER_ARGS+=("-e ISAAC_ROS_WS=/workspaces/agipix_control")
DOCKER_ARGS+=("-e HOST_USER_UID=`id -u`")
DOCKER_ARGS+=("-e HOST_USER_GID=`id -g`")
DOCKER_ARGS+=("-v /dev/bus/usb:/dev/bus/usb")
DOCKER_ARGS+=("-e TERM=xterm-256color")
DOCKER_ARGS+=("-v /dev/input:/dev/input")

# Forward SSH Agent to container if the ssh agent is active.
if [[ -n $SSH_AUTH_SOCK ]]; then
    DOCKER_ARGS+=("-v $SSH_AUTH_SOCK:/ssh-agent")
    DOCKER_ARGS+=("-e SSH_AUTH_SOCK=/ssh-agent")
fi

if [[ $PLATFORM == "aarch64" ]]; then
    DOCKER_ARGS+=("-e NVIDIA_VISIBLE_DEVICES=nvidia.com/gpu=all,nvidia.com/pva=all")
    DOCKER_ARGS+=("-v /usr/bin/tegrastats:/usr/bin/tegrastats")
    DOCKER_ARGS+=("-v /tmp/:/tmp/")
    DOCKER_ARGS+=("-e DISPLAY")
    DOCKER_ARGS+=("-v /usr/lib/aarch64-linux-gnu/tegra:/usr/lib/aarch64-linux-gnu/tegra")
    DOCKER_ARGS+=("-v /usr/src/jetson_multimedia_api:/usr/src/jetson_multimedia_api")
    DOCKER_ARGS+=("--pid=host")
    DOCKER_ARGS+=("-v /usr/share/vpi3:/usr/share/vpi3")
    DOCKER_ARGS+=("-v /dev/i2c-1:/dev/i2c-1")
    #DOCKER_ARGS+=("--group-add i2c")

    # If jtop present, give the container access
    if [[ $(getent group jtop) ]]; then
        DOCKER_ARGS+=("-v /run/jtop.sock:/run/jtop.sock:ro")
    fi
else
    DOCKER_ARGS+=("-e NVIDIA_VISIBLE_DEVICES=nvidia.com/gpu=all")
fi

# Optionally load custom docker arguments from file
if [[ -z "${DOCKER_ARGS_FILE}" ]]; then
    DOCKER_ARGS_FILE=".isaac_ros_dev-dockerargs"
fi

# Check for dockerargs file in home directory, then locally in root
if [[ -f ~/${DOCKER_ARGS_FILE} ]]; then
    DOCKER_ARGS_FILEPATH=`realpath ~/${DOCKER_ARGS_FILE}`
elif [[ -f "${ROOT}/${DOCKER_ARGS_FILE}" ]]; then
    DOCKER_ARGS_FILEPATH="${ROOT}/${DOCKER_ARGS_FILE}"
fi

if [[ -f "${DOCKER_ARGS_FILEPATH}" ]]; then
    print_info "Using additional Docker run arguments from $DOCKER_ARGS_FILEPATH"
    readarray -t DOCKER_ARGS_FILE_LINES < $DOCKER_ARGS_FILEPATH
    for arg in "${DOCKER_ARGS_FILE_LINES[@]}"; do
        DOCKER_ARGS+=($(eval "echo $arg | envsubst"))
    done
fi

# Run container from image
print_info "Running $CONTAINER_NAME"
if [[ $VERBOSE -eq 1 ]]; then
    set -x
fi
docker run -d -it --rm \
    --privileged \
    --network host \
    --ipc=host \
    ${DOCKER_ARGS[@]} \
    -v "$ROOT/bashrc:/usr/local/bin/scripts/bashrc:ro" \
    -v $WORKSPACES_DIR/dds:/workspaces/dds \
    -v $WORKSPACES_DIR/agipix_control:/workspaces/agipix_control \
    -v $WORKSPACES_DIR/lidar_ws:/workspaces/lidar_ws \
    -v $WORKSPACES_DIR/logging:/workspaces/logging \
    -v $WORKSPACES_DIR/ui:/workspaces/ui \
    -v $HOME/.profile:/home/admin/.profile \
    --volume $WORKSPACES_DIR/docker/agidocker/.ide-session-data/sessions/ros2/.gemini:/root/.gemini \
    -v /etc/localtime:/etc/localtime:ro \
    --name "$CONTAINER_NAME" \
    --runtime nvidia \
    --gpus all \
    --entrypoint /usr/local/bin/scripts/workspace-entrypoint.sh \
    --workdir /workspaces/agipix_control \
    $BASE_NAME \
    /bin/bash
