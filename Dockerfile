FROM python:3.10-slim

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /app

# Install system compilation utilities for scikit-learn / numpy math engines
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Hardened Security Policy: Create a dedicated isolated system runner group
RUN groupadd -g 10001 appgroup && \
    useradd -u 10001 -g appgroup -m -s /bin/bash appuser

COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt

# Copy all source assets (app.py, utils.py, locations.py, templates, static, and indian_cities.csv)
COPY . .

# Enforce secure permission changes over all copied workspace assets
RUN chown -R appuser:appgroup /app

USER appuser

EXPOSE 5000

# Execute using Gunicorn to handle multi-threaded production load safely
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "app:app"]
