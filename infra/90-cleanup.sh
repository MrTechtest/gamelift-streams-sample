#!/usr/bin/env bash
# Tears everything down so you stop paying for GPU capacity.
# Deletes: stream group, application, and (optionally) the S3 build bucket.
set -euo pipefail
cd "$(dirname "$0")"
source ./config.env

echo ">> This will DELETE the stream group and application."
read -r -p "   Continue? [y/N] " ok
[ "$ok" = "y" ] || { echo "aborted"; exit 0; }

if [ -n "${STREAM_GROUP_ID:-}" ]; then
  echo ">> Deleting stream group $STREAM_GROUP_ID ..."
  aws gameliftstreams delete-stream-group --region "$AWS_REGION" \
      --identifier "$STREAM_GROUP_ID" || true
  # wait for it to disappear before deleting the app it references
  echo "   waiting for stream group deletion ..."
  for _ in $(seq 1 60); do
    if ! aws gameliftstreams get-stream-group --region "$AWS_REGION" \
         --identifier "$STREAM_GROUP_ID" >/dev/null 2>&1; then
      echo "   deleted."; break
    fi
    sleep 10
  done
fi

if [ -n "${APPLICATION_ID:-}" ]; then
  echo ">> Deleting application $APPLICATION_ID ..."
  aws gameliftstreams delete-application --region "$AWS_REGION" \
      --identifier "$APPLICATION_ID" || true
fi

read -r -p ">> Also delete S3 bucket s3://$BUILD_BUCKET ? [y/N] " db
if [ "$db" = "y" ]; then
  aws s3 rb "s3://$BUILD_BUCKET" --force --region "$AWS_REGION" || true
fi

rm -f "$STATE_FILE"
echo ">> Cleanup complete."
