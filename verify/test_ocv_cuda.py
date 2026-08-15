import cv2

print("OpenCV version:", cv2.__version__)

# Check CUDA availability
cuda_enabled = cv2.cuda.getCudaEnabledDeviceCount()
print("CUDA-enabled devices:", cuda_enabled)

if cuda_enabled == 0:
    print("❌ No CUDA device detected by OpenCV!")
    exit(1)

# Device info
dev = cv2.cuda.getDevice()
print("Active GPU device ID:", dev)

try:
    info = cv2.cuda.DeviceInfo(dev)
    # Prefer global device-name helper; fall back to various DeviceInfo accessors
    gpu_name = "<unavailable>"

    # Attempt module-level helper
    try:
        candidate = cv2.cuda.getDeviceName(dev)
        if candidate:
            gpu_name = candidate
    except Exception:
        pass

    # Fallbacks: try multiple attribute/method names exposed by different OpenCV builds
    if gpu_name == "<unavailable>":
        for attr in ("name", "deviceName", "getName", "getDeviceName"):
            try:
                val = getattr(info, attr, None)
                if val is None:
                    continue
                gpu_name = val() if callable(val) else val
                if gpu_name:
                    break
            except Exception:
                continue

    # Last resort: other libraries or system query
    if gpu_name == "<unavailable>":
        try:
            import torch  # noqa: WPS433
            print("Fallback: Querying torch for GPU name...")
            if torch.cuda.is_available():
                gpu_name = torch.cuda.get_device_name(dev)
        except Exception:
            pass

    if gpu_name == "<unavailable>":
        import subprocess

        try:
            print("Fallback: Querying nvidia-smi for GPU name...")
            output = subprocess.check_output(
                ["nvidia-smi", "--query-gpu=name", "--format=csv,noheader", "-i", str(dev)],
                stderr=subprocess.DEVNULL,
                text=True,
            ).strip()
            if output:
                gpu_name = output
        except Exception:
            pass
    print("GPU Name:", gpu_name)

    major = info.majorVersion() if hasattr(info, "majorVersion") else None
    minor = info.minorVersion() if hasattr(info, "minorVersion") else None
    cc_str = None
    if major is not None and minor is not None:
        cc_str = f"{major}.{minor}"
        print("Compute Capability:", major, ".", minor)
    else:
        print("Compute Capability: <unavailable>")
except Exception as e:
    print("Warning: Could not read device info:", e)
    cc_str = None

# Create CPU image
import numpy as np
img = (np.ones((512, 512, 3), dtype=np.uint8) * 120)

# Upload to GPU
gpu = cv2.cuda_GpuMat()
gpu.upload(img)

# CUDA Gaussian blur
gauss = cv2.cuda.createGaussianFilter(gpu.type(), gpu.type(), (15,15), 2)

try:
    blur_gpu = gauss.apply(gpu)
    blur_img = blur_gpu.download()
    print("CUDA Gaussian blur completed successfully!")
except cv2.error as err:
    err_msg = str(err).lower()
    print("CUDA Gaussian blur failed:", err)
    if "no kernel image is available" in err_msg:
        cc_note = f"compute capability {cc_str}" if cc_str else "this GPU"
        print(
            "Likely cause: the OpenCV CUDA build lacks binaries/PTX for",
            cc_note,
            "— rebuild OpenCV with an appropriate CUDA_ARCH_BIN/PTX target (e.g., -D CUDA_ARCH_BIN=8.9).",
        )
    print("Falling back to CPU GaussianBlur for verification...")
    blur_img = cv2.GaussianBlur(img, (15, 15), 2)
    print("CPU Gaussian blur completed; CUDA path skipped.")
