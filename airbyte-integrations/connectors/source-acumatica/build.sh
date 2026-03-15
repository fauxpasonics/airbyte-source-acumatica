#!/usr/bin/env bash
# Build the connector image, reading the base image from metadata.yaml
# Usage: ./build.sh [IMAGE_TAG]
#   IMAGE_TAG defaults to the dockerImageTag in metadata.yaml

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BASE_IMAGE=$(grep 'baseImage:' "$SCRIPT_DIR/metadata.yaml" | sed 's/.*baseImage: *//')
VERSION=${1:-$(grep 'dockerImageTag:' "$SCRIPT_DIR/metadata.yaml" | sed 's/.*dockerImageTag: *//')}
REPO=$(grep 'dockerRepository:' "$SCRIPT_DIR/metadata.yaml" | sed 's/.*dockerRepository: *//')

echo "Base image: $BASE_IMAGE"
echo "Building:   $REPO:$VERSION"

docker build \
  --build-arg BASE_IMAGE="$BASE_IMAGE" \
  --build-arg CONNECTOR_VERSION="$VERSION" \
  --build-arg CONNECTOR_REPO="$REPO" \
  -t "$REPO:$VERSION" \
  -t "$REPO:dev" \
  "$SCRIPT_DIR"
