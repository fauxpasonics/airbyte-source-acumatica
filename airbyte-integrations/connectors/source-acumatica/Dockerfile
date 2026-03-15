ARG BASE_IMAGE=docker.io/airbyte/python-connector-base:4.0.2@sha256:9fdb1888c4264cf6fee473649ecb593f56f58e5d0096a87ee0b231777e2e3e73
FROM ${BASE_IMAGE} AS builder

WORKDIR /airbyte/integration_code

# Install dependencies first (layer caching)
COPY pyproject.toml poetry.lock README.md ./
RUN poetry install --only main --no-root

# Copy source and install the root package
COPY source_acumatica ./source_acumatica
COPY main.py ./
RUN poetry install --only main

ARG BASE_IMAGE=docker.io/airbyte/python-connector-base:4.0.2@sha256:9fdb1888c4264cf6fee473649ecb593f56f58e5d0096a87ee0b231777e2e3e73
FROM ${BASE_IMAGE}

WORKDIR /airbyte/integration_code

COPY --from=builder /usr/local /usr/local
COPY source_acumatica ./source_acumatica
COPY main.py ./

ENV AIRBYTE_ENTRYPOINT="python /airbyte/integration_code/main.py"
ENTRYPOINT ["python", "/airbyte/integration_code/main.py"]

ARG CONNECTOR_VERSION
ARG CONNECTOR_REPO
LABEL io.airbyte.version=${CONNECTOR_VERSION}
LABEL io.airbyte.name=${CONNECTOR_REPO}
