# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Marker API is a FastAPI-based service that converts PDF documents to Markdown format. It supports both simple synchronous processing and distributed asynchronous processing using Celery workers.

**Core Technology**: Built on top of [marker-pdf](https://github.com/VikParuchuri/marker), a deep learning pipeline that extracts text, detects page layout, and formats content from PDFs.

## Architecture

### Two Server Modes

1. **Simple Server** (`server.py`):
   - Single-server synchronous processing
   - Models loaded at startup into memory
   - Best for: testing, small-scale deployments, local development
   - Endpoints: `/convert`, `/batch_convert`

2. **Distributed Server** (`distributed_server.py`):
   - Celery + Redis for task queue management
   - Multiple worker nodes for parallel processing
   - Flower monitoring on port 5556
   - Best for: production environments, high-volume processing
   - Endpoints: `/convert`, `/celery/convert`, `/celery/result/{task_id}`, `/batch_convert`

### Key Components

- **`marker_api/`**: Main application package
  - `routes.py`: Simple server route handlers
  - `celery_routes.py`: Distributed server route handlers
  - `celery_worker.py`: Celery app initialization
  - `celery_tasks.py`: Background task definitions (PDF conversion)
  - `model/schema.py`: Pydantic models for API request/response
  - `utils.py`: Helper functions (image processing, etc.)
  - `demo.py`: Gradio UI demo interface

- **ML Models**: Loaded via `marker.models.load_all_models()`
  - Models are loaded once per worker process at startup
  - Uses `worker_process_init` signal in Celery workers
  - Stored in global `model_list` variable

## Common Development Commands

### Environment Setup

```bash
# Copy environment template
cp .env.example .env

# Install dependencies (choose one)
poetry install
# OR
pip install -e .
```

### Running Simple Server

```bash
# Local development
python server.py --host 0.0.0.0 --port 8080

# Docker (CPU)
docker build -f docker/Dockerfile.cpu.server -t marker-api-cpu .
docker run -p 8080:8080 marker-api-cpu

# Docker (GPU)
docker build -f docker/Dockerfile.gpu.server -t marker-api-gpu .
docker run --gpus all -p 8080:8080 marker-api-gpu
```

### Running Distributed Server

**Local Setup (requires 3 terminals)**:

```bash
# Terminal 1: Start Redis
docker run -d -p 6379:6379 redis

# Terminal 2: Start Celery worker
celery -A marker_api.celery_worker.celery_app worker --pool=solo --loglevel=info

# Terminal 3: Start Flower monitoring (optional)
celery -A marker_api.celery_worker.celery_app flower --port=5555

# Terminal 4: Start FastAPI server
python distributed_server.py --host 0.0.0.0 --port 8080
```

**Docker Compose (recommended)**:

```bash
# CPU version
docker-compose -f docker-compose.cpu.yml up --build

# GPU version
docker-compose -f docker-compose.gpu.yml up --build

# Scale workers
docker-compose -f docker-compose.gpu.yml up --build --scale celery_worker=3
```

Services:
- FastAPI: http://localhost:8080
- Flower monitoring: http://localhost:5556
- Redis: localhost:6379

### Testing

```bash
# Load testing with Locust
cd tests/
locust -f test.py
```

Then open http://localhost:8089 for Locust web UI.

## Environment Variables

Configure in `.env` file:

- `REDIS_HOST`: Redis connection URL (default: `redis://localhost:6379/0`)
- `TORCH_DEVICE`: Force torch device (`cuda`, `cpu`, `mps`)
- `INFERENCE_RAM`: GPU VRAM in GB (e.g., `16`)
- `VRAM_PER_TASK`: Memory per task (adjust if OOM errors)
- `OCR_ENGINE`: OCR backend (`surya`, `ocrmypdf`, `None`)
- `OCR_ALL_PAGES`: Force OCR all pages (`true`/`false`)
- `DEFAULT_LANG`: Default document language for OCR
- `DEBUG`: Show ray logs for debugging

## API Endpoints

### Simple Server

- `GET /health`: Check server status
- `POST /convert`: Convert single PDF (returns result immediately)
- `POST /batch_convert`: Convert multiple PDFs (processes concurrently)

### Distributed Server

- `GET /health`: Server status + worker count
- `POST /convert`: Convert single PDF (blocks until complete)
- `POST /celery/convert`: Submit PDF conversion task (returns task_id)
- `GET /celery/result/{task_id}`: Get task result by ID
- `POST /batch_convert`: Submit batch conversion (returns task_id)
- `GET /batch_convert/result/{task_id}`: Get batch results with progress

All servers also mount Gradio demo UI at root path `/`.

## Code Patterns

### Adding New Celery Tasks

1. Define task in `marker_api/celery_tasks.py`:
```python
@celery_app.task(ignore_result=False, bind=True, base=PDFConversionTask, name="task_name")
def my_task(self, arg1, arg2):
    # Use global model_list (loaded at worker startup)
    # Return dict with results
    return {"status": "ok", "data": ...}
```

2. Create route handler in `marker_api/celery_routes.py`
3. Add endpoint in `distributed_server.py` within `setup_routes()`

### Model Loading

Models are expensive to load. The architecture ensures they're loaded once per worker:

- **Simple server**: Loaded in `lifespan` startup event
- **Distributed server**: Loaded in `worker_process_init` signal handler
- Stored in module-level `model_list` variable
- Reused across all tasks in that worker process

### Image Processing

Images extracted from PDFs are converted to base64 for JSON serialization:
- See `marker_api/utils.py::process_image_to_base64()`
- Handles both PIL images and numpy arrays
- Returns data URL format: `data:image/png;base64,...`

## Deployment Notes

### GPU Support

- Requires NVIDIA GPU with CUDA support
- Use `docker-compose.gpu.yml` with `--gpus all` flag
- Deploy resources defined with `capabilities: [gpu]`
- Default batch sizes use ~4GB VRAM per task

### Scaling

- Horizontal scaling: Add more Celery workers
- Adjust worker pool size with `--scale celery_worker=N`
- Task distribution handled automatically by Celery/Redis
- Monitor with Flower to identify bottlenecks

### Performance Tuning

- `VRAM_PER_TASK`: Lower if getting OOM errors
- `--batch_multiplier`: Increase if you have extra VRAM (default: 2)
- Worker pool type: `--pool=solo` for multiprocessing isolation
- Consider task timeouts for very large PDFs

## Licensing & Commercial Use

**Important**: This project wraps the marker-pdf library which has commercial usage restrictions.

- Model weights: Licensed under `cc-by-nc-sa-4.0`
- Free for: Research, personal use, orgs <$5M revenue AND <$5M VC funding
- Commercial use beyond limits requires licensing from [datalab.to](https://www.datalab.to)
- Marker API code: GPL-3.0 (see LICENSE file)

## Troubleshooting

**Server won't start**:
- Check Redis is running on port 6379
- Verify `.env` has correct `REDIS_HOST`

**Out of memory errors**:
- Lower `VRAM_PER_TASK` in settings
- Reduce number of workers
- Use CPU mode instead of GPU

**Poor quality output**:
- Set `OCR_ALL_PAGES=true` to force OCR
- Verify correct language set via `DEFAULT_LANG` or metadata
- Some PDFs have malformed text/bboxes and need OCR

**Celery tasks not processing**:
- Check Celery worker is running and connected to Redis
- Verify in Flower monitoring UI (port 5556)
- Check logs with `--loglevel=debug`
