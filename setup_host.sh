echo "alias ebash='gedit ~/.bashrc'" >> ~/.bashrc
echo "alias sbash='source ~/.bashrc'" >> ~/.bashrc
echo "alias agidocker="cd ~/workspace/raicam-ros/src/agidocker/scripts/ && ./run_dev.sh --skip-registry-check"" >> ~/.bashrc

echo "export CUDA=12.6" >> ~/.bashrc
echo "export PATH=/usr/local/cuda-$CUDA/bin${PATH:+:${PATH}}" >> ~/.bashrc
echo "export CUDA_PATH=/usr/local/cuda-$CUDA" >> ~/.bashrc
echo "export CUDA_HOME=/usr/local/cuda-$CUDA" >> ~/.bashrc
echo "export LIBRARY_PATH=$CUDA_HOME/lib64:$LIBRARY_PATH" >> ~/.bashrc
echo "export LD_LIBRARY_PATH=/usr/local/cuda-$CUDA/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}" >> ~/.bashrc
echo "export LD_LIBRARY_PATH=/usr/local/cuda/extras/CUPTI/lib64:$LD_LIBRARY_PATH" >> ~/.bashrc
echo "export NVCC=/usr/local/cuda-$CUDA/bin/nvcc" >> ~/.bashrc
echo "export CFLAGS="-I$CUDA_HOME/include $CFLAGS"" >> ~/.bashrc
echo "export LD_LIBRARY_PATH=/usr/local/cuda-$CUDA/targets/aarch64-linux/lib:$LD_LIBRARY_PATH" >> ~/.bashrc
echo "export CPATH=/usr/local/cuda-$CUDA/targets/aarch64-linux/include:$CPATH" >> ~/.bashrc

echo "export WORKSPACES_DIR='~/workspace'" >> ~/.bashrc
echo "export ISAAC_ROS_WS='~/workspace/raicam-ros'" >> ~/.bashrc