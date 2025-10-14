FROM python:3.11-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    HF_HOME=/models/hf \
    MPLCONFIGDIR=/tmp/mpl \
    TRANSFORMERS_ATTN_IMPLEMENTATION=eager

# Install system dependencies including build tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgl1-mesa-glx \
    libglib2.0-0 \
    git \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Create models directory with proper permissions
RUN mkdir -p /models/hf && chmod -R 777 /models

# Copy dependency files first for better caching
COPY pyproject.toml requirements.txt* ./

# Install Python dependencies
RUN python -m pip install --upgrade pip setuptools wheel && \
    pip install --no-cache-dir -r requirements.txt || true && \
    pip install --no-cache-dir marker-pdf fastapi uvicorn pydantic pillow && \
    echo "Dependencies installed successfully"

# Copy application code
COPY . .

# Install the package in editable mode
RUN pip install --no-cache-dir -e .

# Copy patch script and apply it AFTER all packages are installed
COPY patch_surya.py /tmp/patch_surya.py
RUN python /tmp/patch_surya.py && rm /tmp/patch_surya.py

# Preload models at build time for faster startup
RUN python -c "from marker.models import load_all_models; load_all_models()" || \
    echo "Warning: Model preloading failed, will load at runtime"

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD python -c "import requests; requests.get('http://localhost:8080/health', timeout=5)" || exit 1

CMD ["python", "server.py", "--host", "0.0.0.0", "--port", "8080"]
