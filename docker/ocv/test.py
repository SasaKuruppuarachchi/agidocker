import cv2, sys
print("file:", cv2.__file__)
print("version:", cv2.__version__)
print("cuda devices:", cv2.cuda.getCudaEnabledDeviceCount())