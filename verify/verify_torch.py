#!/usr/bin/env python3
import torch
import torch.backends.cudnn as cudnn
import subprocess
import shutil
import torchvision

def header(title):
    print("\n" + "="*60)
    print(title)
    print("="*60)

# ---------------------------------------------------------
# 1. PyTorch CUDA Status
# ---------------------------------------------------------
header("PyTorch CUDA Status")

print("PyTorch version:", torch.__version__)
print("CUDA available:", torch.cuda.is_available())
print("CUDA version (PyTorch):", torch.version.cuda)
print("cuDNN enabled:", cudnn.enabled)
print("cuDNN version:", cudnn.version())

if not torch.cuda.is_available():
    print("\n❌ CUDA is NOT available in PyTorch. Stop here.")
    exit(1)

# ---------------------------------------------------------
# 2. GPU Information
# ---------------------------------------------------------
header("GPU Information")

gpu_name = torch.cuda.get_device_name(0)
capability = torch.cuda.get_device_capability(0)
props = torch.cuda.get_device_properties(0)

print("GPU:", gpu_name)
print("Compute Capability:", capability)
print("Total Memory (GB):", round(props.total_memory / 1024**3, 2))
print("Multiprocessors:", props.multi_processor_count)

# ---------------------------------------------------------
# 3. Basic CUDA Tensor Test
# ---------------------------------------------------------
header("CUDA Tensor Test")

try:
    a = torch.rand(1024, 1024, device="cuda")
    b = torch.rand(1024, 1024, device="cuda")
    c = torch.mm(a, b)
    print("Matrix multiply successful. Mean:", float(c.mean()))
except Exception as e:
    print("❌ CUDA tensor operation FAILED:", e)

# ---------------------------------------------------------
# 4. TorchVision CUDA Test
# ---------------------------------------------------------
header("TorchVision CUDA Status")

print("TorchVision version:", torchvision.__version__)

try:
    import torchvision.ops as ops
    x = torch.rand(1, 3, 64, 64, device="cuda")
    rois = torch.tensor([[0., 0., 32., 32.]], device="cuda")
    ops.roi_align(x, [rois], output_size=(16, 16))
    print("TorchVision CUDA ops: OK")
except Exception as e:
    print("❌ TorchVision CUDA ops FAILED:", e)

# ---------------------------------------------------------
# 5. Check NVCC in system PATH
# ---------------------------------------------------------
header("NVCC Compiler Check")

nvcc_path = shutil.which("nvcc")
print("NVCC path:", nvcc_path)

if nvcc_path:
    try:
        out = subprocess.check_output(["nvcc", "--version"]).decode()
        print(out)
    except Exception as e:
        print("❌ NVCC error:", e)
else:
    print("⚠️ NVCC not found. PyTorch can still work, but compilation is unavailable.")

# ---------------------------------------------------------
# 6. CUDA Toolkit version from nvidia-smi
# ---------------------------------------------------------
header("CUDA Toolkit Version")

try:
    smi = subprocess.check_output(["nvidia-smi"]).decode()
    print(smi)
except Exception:
    print("nvidia-smi not available (expected on Jetson).")
    # Jetson alternative
    try:
        out = subprocess.check_output(["cat", "/usr/local/cuda/version.txt"]).decode()
        print(out)
    except:
        print("Cannot read CUDA version.")

# ---------------------------------------------------------
# 7. Final Summary
# ---------------------------------------------------------
header("SUMMARY")

ok = True

if not torch.cuda.is_available():
    ok = False
    print("❌ PyTorch does NOT see a CUDA device.")

if not cudnn.enabled:
    ok = False
    print("❌ cuDNN is NOT enabled.")

try:
    import torchvision.ops as ops
except:
    ok = False
    print("❌ TorchVision is NOT installed or incompatible.")

if ok:
    print("✅ All CUDA components appear to be working correctly!")
else:
    print("⚠️ Issues detected — check above for errors.")
