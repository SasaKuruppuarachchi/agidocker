# Isaac ROS Dev Build Scripts

For Jetson or x86_64:
  `run_dev.sh` builds and launches the development container with ROS 2 and project workspace mounts configured under `$WORKSPACES_DIR`.
  Shell configurations and aliases are automatically loaded from `scripts/bashrc`.

Usage:
  `./run_dev.sh [--skip-registry-check]`
