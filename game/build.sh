#!/usr/bin/env bash
# Convenience wrapper: builds the sample game inside Docker (Ubuntu 22.04) and
# copies the finished, ready-to-upload folder to ./dist on your machine.
#
# Requirements: Docker installed and running.
# Usage: ./build.sh
set -euo pipefail
cd "$(dirname "$0")"

IMAGE="glstreams-sample-game"

echo ">> Building Docker image (Ubuntu 22.04 + SDL2) ..."
docker build -t "$IMAGE" .

echo ">> Extracting dist/ from the built image ..."
rm -rf dist
CID="$(docker create "$IMAGE")"
docker cp "$CID:/build/dist" ./dist
docker rm "$CID" >/dev/null

echo
echo "==================================================================="
echo " Sample game built. Upload the ./dist folder to S3 (see infra/)."
echo " Executable launch path for create-application:  run-game.sh"
echo "==================================================================="
ls -la dist
