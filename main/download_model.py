#!/usr/bin/env python
"""
This script pre-downloads Whisper models during the Docker build process.
It leverages the Whisper library's built-in caching mechanism.
"""

import os
import whisper
import torch

# Model to download - can be changed to any model in the Whisper model list
MODEL_NAME = "tiny.en"

# Print available CUDA devices for debugging
print(f"CUDA available: {torch.cuda.is_available()}")
if torch.cuda.is_available():
    print(f"CUDA device count: {torch.cuda.device_count()}")
    print(f"CUDA device name: {torch.cuda.get_device_name(0)}")

# Print the default cache location for debugging
default_cache = os.path.join(os.path.expanduser("~"), ".cache")
download_root = os.path.join(os.getenv("XDG_CACHE_HOME", default_cache), "whisper")
print(f"Download root: {download_root}")

# Ensure the cache directory exists
os.makedirs(download_root, exist_ok=True)

# Download the model
print(f"Downloading Whisper model: {MODEL_NAME}")
model = whisper.load_model(MODEL_NAME)
print(f"Model {MODEL_NAME} loaded successfully")

# Print all available models for reference
print("Available models:", whisper.available_models())

# Verify the model was downloaded correctly
model_size = os.path.getsize(os.path.join(download_root, f"{MODEL_NAME}.pt"))
print(f"Model file size: {model_size / 1024 / 1024:.2f} MB")
