#!/usr/bin/env bash
# 1) Creates the S3 bucket (if needed) and uploads the UNCOMPRESSED game folder.
# 2) Creates the GameLift Streams application and waits until it is READY.
set -euo pipefail
cd "$(dirname "$0")"
source ./config.env

if [ -n "${PREBUILT_SOURCE_URI:-}" ]; then
  # The build is already in S3; nothing to create or upload.
  SOURCE_URI="$PREBUILT_SOURCE_URI"
  echo ">> Using pre-uploaded build at $SOURCE_URI"

  # GameLift Streams requires the source bucket to be in the application's
  # region, and a wrong region only surfaces as an opaque failure later.
  SRC_BUCKET="$(echo "$SOURCE_URI" | sed -E 's|^s3://([^/]+).*|\1|')"
  SRC_REGION=$(aws s3api get-bucket-location --bucket "$SRC_BUCKET" \
                 --query 'LocationConstraint' --output text)
  [ "$SRC_REGION" = "None" ] && SRC_REGION="us-east-1"
  if [ "$SRC_REGION" != "$AWS_REGION" ]; then
    echo "ERROR: bucket $SRC_BUCKET is in $SRC_REGION but AWS_REGION is $AWS_REGION."
    exit 1
  fi
  echo "   Bucket region $SRC_REGION matches."
else
  # --- create bucket (S3 Standard, same region as the application) ----------
  echo ">> Ensuring S3 bucket s3://$BUILD_BUCKET exists in $AWS_REGION ..."
  if aws s3api head-bucket --bucket "$BUILD_BUCKET" 2>/dev/null; then
    echo "   Bucket already exists."
  else
    if [ "$AWS_REGION" = "us-east-1" ]; then
      aws s3api create-bucket --bucket "$BUILD_BUCKET" --region "$AWS_REGION"
    else
      aws s3api create-bucket --bucket "$BUILD_BUCKET" --region "$AWS_REGION" \
        --create-bucket-configuration LocationConstraint="$AWS_REGION"
    fi
  fi

  # --- upload the build folder (must stay uncompressed / preserve structure)
  echo ">> Uploading build to s3://$BUILD_BUCKET/build ..."
  aws s3 sync "$BUILD_DIR" "s3://$BUILD_BUCKET/build" --delete --region "$AWS_REGION"

  SOURCE_URI="s3://$BUILD_BUCKET/build"
fi

# --- create the application --------------------------------------------------
echo ">> Creating GameLift Streams application ($RUNTIME_TYPE/$RUNTIME_VERSION, exe=$EXECUTABLE_PATH) ..."
APP_JSON=$(aws gameliftstreams create-application \
  --region "$AWS_REGION" \
  --description "$APP_DESCRIPTION" \
  --runtime-environment Type="$RUNTIME_TYPE",Version="$RUNTIME_VERSION" \
  --executable-path "$EXECUTABLE_PATH" \
  --application-source-uri "$SOURCE_URI" \
  --output json)

APP_ID=$(echo "$APP_JSON" | python3 -c 'import sys,json;print(json.load(sys.stdin)["Id"])')
APP_ARN=$(echo "$APP_JSON" | python3 -c 'import sys,json;print(json.load(sys.stdin)["Arn"])')
echo "   Application Id: $APP_ID"

# --- wait for READY ----------------------------------------------------------
echo ">> Waiting for application to become READY (this can take several minutes) ..."
while true; do
  STATUS=$(aws gameliftstreams get-application --region "$AWS_REGION" \
            --identifier "$APP_ID" \
            --query Status --output text)
  echo "   status=$STATUS"
  case "$STATUS" in
    READY) break ;;
    ERROR|*ERROR*) echo "ERROR: application entered $STATUS"; exit 1 ;;
  esac
  sleep 15
done

# --- persist state (upsert keys into state.env) ------------------------------
touch "$STATE_FILE"
grep -vE '^export (APPLICATION_ID|APPLICATION_ARN|SOURCE_URI)=' "$STATE_FILE" > "$STATE_FILE.new" || true
{
  echo "export APPLICATION_ID=\"$APP_ID\""
  echo "export APPLICATION_ARN=\"$APP_ARN\""
  echo "export SOURCE_URI=\"$SOURCE_URI\""
} >> "$STATE_FILE.new"
mv "$STATE_FILE.new" "$STATE_FILE"

echo ">> Application is READY. Id saved to $STATE_FILE"
