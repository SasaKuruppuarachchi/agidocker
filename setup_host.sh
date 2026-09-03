#!/bin/bash
set -e

BASHRC_FILE="${1:-$HOME/.bashrc}"

if [[ ! -f "$BASHRC_FILE" ]]; then
    touch "$BASHRC_FILE"
fi

# Function to add a line or update an existing matching line in-place without duplicating
set_or_update() {
    local pat="$1"
    local rep="$2"
    local file="$3"
    local tmp="${file}.tmp"

    awk -v pat="$pat" -v rep="$rep" '
    BEGIN { found = 0 }
    $0 ~ pat {
        if (!found) {
            print rep
            found = 1
        }
        next
    }
    { print }
    END {
        if (!found) {
            print rep
        }
    }
    ' "$file" > "$tmp" && mv "$tmp" "$file"
}

echo "Configuring environment in $BASHRC_FILE..."

# Aliases
set_or_update "^[[:space:]]*alias[[:space:]]+ebash=" "alias ebash='gedit ~/.bashrc'" "$BASHRC_FILE"
set_or_update "^[[:space:]]*alias[[:space:]]+sbash=" "alias sbash='source ~/.bashrc'" "$BASHRC_FILE"
set_or_update "^[[:space:]]*alias[[:space:]]+agidocker=" "alias agidocker='cd ~/workspace/docker/agidocker/scripts/ && ./run_dev.sh --skip-registry-check'" "$BASHRC_FILE"
set_or_update "^[[:space:]]*alias[[:space:]]+killagidocker=" "alias killagidocker='docker container kill agipix_ros_dev-aarch64-container'" "$BASHRC_FILE"

# CUDA exports
set_or_update "^[[:space:]]*export[[:space:]]+CUDA=" "export CUDA=12.6" "$BASHRC_FILE"
set_or_update "^[[:space:]]*export[[:space:]]+PATH=.*cuda.*" 'export PATH=/usr/local/cuda-$CUDA/bin${PATH:+:${PATH}}' "$BASHRC_FILE"
set_or_update "^[[:space:]]*export[[:space:]]+CUDA_PATH=" 'export CUDA_PATH=/usr/local/cuda-$CUDA' "$BASHRC_FILE"
set_or_update "^[[:space:]]*export[[:space:]]+CUDA_HOME=" 'export CUDA_HOME=/usr/local/cuda-$CUDA' "$BASHRC_FILE"
set_or_update "^[[:space:]]*export[[:space:]]+LIBRARY_PATH=" 'export LIBRARY_PATH=$CUDA_HOME/lib64:$LIBRARY_PATH' "$BASHRC_FILE"
set_or_update "^[[:space:]]*export[[:space:]]+LD_LIBRARY_PATH=.*cuda[^/]*/lib64.*" 'export LD_LIBRARY_PATH=/usr/local/cuda-$CUDA/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}' "$BASHRC_FILE"
set_or_update "^[[:space:]]*export[[:space:]]+LD_LIBRARY_PATH=.*CUPTI.*" 'export LD_LIBRARY_PATH=/usr/local/cuda/extras/CUPTI/lib64:$LD_LIBRARY_PATH' "$BASHRC_FILE"
set_or_update "^[[:space:]]*export[[:space:]]+NVCC=" 'export NVCC=/usr/local/cuda-$CUDA/bin/nvcc' "$BASHRC_FILE"
set_or_update "^[[:space:]]*export[[:space:]]+CFLAGS=" 'export CFLAGS="-I$CUDA_HOME/include $CFLAGS"' "$BASHRC_FILE"
set_or_update "^[[:space:]]*export[[:space:]]+LD_LIBRARY_PATH=.*targets/aarch64-linux/lib.*" 'export LD_LIBRARY_PATH=/usr/local/cuda-$CUDA/targets/aarch64-linux/lib:$LD_LIBRARY_PATH' "$BASHRC_FILE"
set_or_update "^[[:space:]]*export[[:space:]]+CPATH=" 'export CPATH=/usr/local/cuda-$CUDA/targets/aarch64-linux/include:$CPATH' "$BASHRC_FILE"

# Workspace exports
set_or_update "^[[:space:]]*export[[:space:]]+WORKSPACES_DIR=" "export WORKSPACES_DIR='~/workspace'" "$BASHRC_FILE"
set_or_update "^[[:space:]]*export[[:space:]]+ISAAC_ROS_WS=" "export ISAAC_ROS_WS='~/workspace/raicam-ros'" "$BASHRC_FILE"

echo "Done! Run 'source $BASHRC_FILE' or 'sbash' to reload your environment."
source "$BASHRC_FILE"