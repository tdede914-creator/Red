FROM python:3.12-slim

# System deps
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libssl-dev \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install Python deps first (better cache)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy source
COPY bot/ ./bot/
COPY scripts/ ./scripts/

# Non-root user
RUN useradd -m -u 1000 kobong && \
    mkdir -p /app/data && \
    chown -R kobong:kobong /app
USER kobong

# Data + webhook
VOLUME ["/app/data"]
EXPOSE 8080

CMD ["python", "-m", "bot"]
