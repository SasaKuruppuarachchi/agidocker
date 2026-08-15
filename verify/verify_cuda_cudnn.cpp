#include <cuda_runtime.h>
#include <cudnn.h>
#include <iostream>
int main() {
    int cudaVersion;
    cudaRuntimeGetVersion(&cudaVersion);
    std::cout << "CUDA runtime version: " << cudaVersion/1000 << "." << (cudaVersion%1000)/10 << std::endl;
    std::cout << "cuDNN version: " << CUDNN_MAJOR << "." << CUDNN_MINOR << "." << CUDNN_PATCHLEVEL << std::endl;
    return 0;
}

/*
g++ verify_cuda_cudnn.cpp \
    -I/usr/local/cuda-12.6/targets/aarch64-linux/include \
    -L/usr/local/cuda-12.6/targets/aarch64-linux/lib \
    -lcudart -lcudnn -o verify_cuda_cudnn

For x86_64 architecture, replace 'aarch64-linux' with 'x86_64-linux'.
g++ verify_cuda_cudnn.cpp \
    -I/usr/local/cuda-12.6/targets/x86_64-linux/include \
    -L/usr/local/cuda-12.6/targets/x86_64-linux/lib \
    -lcudart -lcudnn -o verify_cuda_cudnn
*/