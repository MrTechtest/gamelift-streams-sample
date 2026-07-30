#!/usr/bin/env bash
# Creates the stream group, links the application as the default, provisions
# always-on capacity in the chosen region, and waits until it is ACTIVE.
set -euo pipefail
cd "$(dirname "$0")"
source ./config.env

if [ -z "${APPLICATION_ID:-}" ]; then
  echo "ERROR: APPLICATION_ID not set. Run 10-upload-and-create-app.sh first."
  exit 1
fi

echo ">> Creating stream group (class=$STREAM_CLASS, always-on=$ALWAYS_ON_CAPACITY, on-demand=$ON_DEMAND_CAPACITY, loc=$AWS_REGION) ..."
SG_JSON=$(aws gameliftstreams create-stream-group \
  --region "$AWS_REGION" \
  --description "$SG_DESCRIPTION" \
  --stream-class "$STREAM_CLASS" \
  --default-application-identifier "$APPLICATION_ID" \
  --location-configurations LocationName="$AWS_REGION",AlwaysOnCapacity="$ALWAYS_ON_CAPACITY",OnDemandCapacity="$ON_DEMAND_CAPACITY" \
  --output json)

SG_ID=$(echo "$SG_JSON" | python3 -c 'import sys,json;print(json.load(sys.stdin)["Id"])')
echo "   Stream group Id: $SG_ID"

echo ">> Waiting for stream group to become ACTIVE (provisioning GPU capacity; can take 10-20 min) ..."
while true; do
  STATUS=$(aws gameliftstreams get-stream-group --region "$AWS_REGION" \
            --identifier "$SG_ID" \
            --query Status --output text)
  echo "   status=$STATUS"
  case "$STATUS" in
    ACTIVE) break ;;
    ERROR|*ERROR*) echo "ERROR: stream group entered $STATUS. Check Service Quotas for capacity."; exit 1 ;;
  esac
  sleep 20
done

# persist (upsert STREAM_GROUP_ID into state.env)
touch "$STATE_FILE"
grep -vE '^export STREAM_GROUP_ID=' "$STATE_FILE" > "$STATE_FILE.new" || true
echo "export STREAM_GROUP_ID=\"$SG_ID\"" >> "$STATE_FILE.new"
mv "$STATE_FILE.new" "$STATE_FILE"

echo
echo "==================================================================="
echo " Stream group ACTIVE."
echo "   STREAM_GROUP_ID = $SG_ID"
echo "   APPLICATION_ID  = $APPLICATION_ID"
echo " Copy these into web/.env (see ../web/.env.example), then start the"
echo " web app.  Run 90-cleanup.sh when finished to stop GPU charges."
echo "==================================================================="
