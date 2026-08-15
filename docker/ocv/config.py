import os, sys
BINARIES_PATHS = [
    "/workspaces/ocv/build/install/lib/python3.10/dist-packages/cv2/python-3.10",
    os.path.join(os.path.dirname(__file__), "python-3.10"),
]
for p in BINARIES_PATHS:
    if os.path.isdir(p) and p not in sys.path:
        sys.path.insert(0, p)