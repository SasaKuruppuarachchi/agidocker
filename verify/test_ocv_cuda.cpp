#include <iostream>
#include <opencv2/opencv.hpp>
#include <opencv2/core/cuda.hpp>
#include <opencv2/cudafilters.hpp>

int main() {
    std::cout << "OpenCV version: " << CV_VERSION << std::endl;

    // Check CUDA availability
    int num_devices = cv::cuda::getCudaEnabledDeviceCount();
    std::cout << "CUDA-enabled devices: " << num_devices << std::endl;

    if (num_devices == 0) {
        std::cout << "❌ No CUDA devices detected by OpenCV." << std::endl;
        return -1;
    }

    // Print device info
    cv::cuda::DeviceInfo dev_info(0);
    std::cout << "Using GPU: " << dev_info.name() << std::endl;
    std::cout << "Compute Capability: " << dev_info.majorVersion() 
              << "." << dev_info.minorVersion() << std::endl;

    // Create a random image
    cv::Mat img = cv::Mat::ones(512, 512, CV_8UC3) * 120;

    // Upload to GPU
    cv::cuda::GpuMat d_img, d_blur;
    d_img.upload(img);

    // Perform Gaussian blur on GPU
    cv::Ptr<cv::cuda::Filter> gauss = cv::cuda::createGaussianFilter(
        d_img.type(), d_img.type(), cv::Size(15, 15), 2);
    
    gauss->apply(d_img, d_blur);

    // Download back
    cv::Mat blurred;
    d_blur.download(blurred);

    std::cout << "CUDA Gaussian blur completed successfully!" << std::endl;

    return 0;
}

/*
# Point to your build pkgconfig dir
export PKG_CONFIG_PATH=/workspaces/ocv/build/install/lib/pkgconfig:$PKG_CONFIG_PATH
export LD_LIBRARY_PATH=/workspaces/ocv/build/install/lib:$LD_LIBRARY_PATH

# Verify you see 4.11.0 via the correct .pc file
pkg-config --modversion opencv    # expect 4.11.0
pkg-config --cflags opencv | head
pkg-config --libs opencv | head

# Build with the correct .pc name
g++ -std=c++17 /workspaces/isaac_ros-dev/src/isaac_ros_common/verify/test_ocv_cuda.cpp \
    -o test_ocv_cuda \
    $(pkg-config --cflags --libs opencv)

For x86_64 architecture, replace 'aarch64-linux' with 'x86_64-linux'.
*/