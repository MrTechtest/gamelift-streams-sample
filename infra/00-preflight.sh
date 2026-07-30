#!/usr/bin/env bash
# Checks prerequisites before provisioning.
set -euo pipefail
cd "$(dirname "$0")"
source ./config.env

echo ">> Checking AWS CLI ..."
command -v aws >/dev/null || { echo "ERROR: aws CLI not found. Install AWS CLI v2."; exit 1; }
aws --version

echo ">> Checking that GameLift Streams is available in this CLI version ..."
if ! aws gameliftstreams help >/dev/null 2>&1; then
  echo "ERROR: your AWS CLI does not know the 'gameliftstreams' service."
  echo "       Upgrade to the latest AWS CLI v2."
  exit 1
fi

echo ">> Checking credentials / identity ..."
aws sts get-caller-identity --output table

echo ">> Checking the built game folder exists ..."
if [ ! -f "$BUILD_DIR/$EXECUTABLE_PATH" ]; then
  echo "ERROR: $BUILD_DIR/$EXECUTABLE_PATH not found."
  echo "       Run ../game/build.sh first to produce the game build."
  exit 1
fi
echo "   Found build: $BUILD_DIR/$EXECUTABLE_PATH"

cat <<'NOTE'

--------------------------------------------------------------------------
 IMPORTANT — service quota
 New AWS accounts often have a GameLift Streams stream-capacity quota of 0.
 If 20-create-stream-group.sh fails to reach capacity, open the AWS console:
   Service Quotas -> Amazon GameLift Streams
 and request an increase for the relevant stream class (e.g. gen6n),
 then retry. Quota increases can take from minutes to a day.
--------------------------------------------------------------------------
NOTE
echo ">> Preflight OK."
