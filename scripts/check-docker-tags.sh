#!/bin/bash
# Check available tags for a Docker Hub image
# Usage: ./scripts/check-docker-tags.sh <user/image> [page_size]
#
# Examples:
#   ./scripts/check-docker-tags.sh corentinth/it-tools
#   ./scripts/check-docker-tags.sh grafana/grafana 20

IMAGE=${1:?"Usage: $0 <user/image> [page_size]"}
PAGE_SIZE=${2:-10}

curl -s "https://hub.docker.com/v2/repositories/${IMAGE}/tags/?page_size=${PAGE_SIZE}" \
  | python3 -m json.tool \
  | grep '"name"'
