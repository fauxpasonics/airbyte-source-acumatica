#!/usr/bin/env bash
# Check if a newer airbyte/python-connector-base image is available on Docker Hub.
# Compares the pinned version in metadata.yaml against the latest stable tag.
# Exit 0 = up to date, Exit 1 = newer image available (non-blocking warning).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
METADATA="$SCRIPT_DIR/metadata.yaml"

IMAGE_NAME="airbyte/python-connector-base"
PINNED=$(grep 'baseImage:' "$METADATA" | sed 's/.*baseImage: *//')
PINNED_TAG=$(echo "$PINNED" | sed 's/@sha256:.*//' | sed 's/.*://')

echo "Checking for updates to $IMAGE_NAME..."
echo "  Pinned version: $PINNED_TAG"

# Query Docker Hub API for the latest stable tags (exclude rc, dev, test)
LATEST_STABLE=$(curl -sf "https://registry.hub.docker.com/v2/namespaces/airbyte/repositories/python-connector-base/tags?page_size=25&ordering=last_updated" \
  | python3 -c "
import sys, json, re
data = json.load(sys.stdin)
# Filter to stable semver tags only (no rc, dev, test suffixes)
stable = [r['name'] for r in data.get('results', [])
          if re.match(r'^\d+\.\d+\.\d+$', r['name'])]
if stable:
    # Sort by semver
    stable.sort(key=lambda v: tuple(int(x) for x in v.split('.')), reverse=True)
    print(stable[0])
" 2>/dev/null || echo "")

if [ -z "$LATEST_STABLE" ]; then
  echo "  WARNING: Could not determine latest version from Docker Hub. Skipping check."
  exit 0
fi

echo "  Latest stable:   $LATEST_STABLE"

# Compare versions using Python for proper semver comparison
RESULT=$(python3 -c "
pinned = tuple(int(x) for x in '$PINNED_TAG'.split('.'))
latest = tuple(int(x) for x in '$LATEST_STABLE'.split('.'))
print('outdated' if latest > pinned else 'current')
" 2>/dev/null || echo "current")

if [ "$RESULT" = "current" ]; then
  echo "  Base image is up to date."
  exit 0
else
  echo ""
  echo "  *** NEWER BASE IMAGE AVAILABLE: $LATEST_STABLE (you have $PINNED_TAG) ***"
  echo ""
  echo "  To update:"
  echo "    docker pull docker.io/$IMAGE_NAME:$LATEST_STABLE"
  echo "    docker inspect --format='{{index .RepoDigests 0}}' $IMAGE_NAME:$LATEST_STABLE"
  echo "    # Then replace the baseImage line in metadata.yaml with the new tag@digest"
  echo ""
  exit 1
fi
