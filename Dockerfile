FROM python:3.12-slim

WORKDIR /app

# Install dependencies first for layer caching
COPY pyproject.toml .
RUN pip install --no-cache-dir hatchling && \
    pip install --no-cache-dir click httpx pyyaml rich

# Copy source
COPY README.md .
COPY src/ src/

# Install shai
RUN pip install --no-cache-dir --no-deps .

# Run as non-root user
RUN useradd -m shai
USER shai

ENTRYPOINT ["shai"]
