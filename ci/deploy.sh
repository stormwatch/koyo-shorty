#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "usage: ci/deploy.sh PRODUCTION|STAGING"
    exit 1
fi

BASEPATH="$(dirname "$0")"
IMAGE_NAME="ghcr.io/stormwatch/shorty:$GITHUB_SHA"
TARGET_HOST="deepploy@$DEPLOY_HOST"

case "$1" in
    PRODUCTION)
        CONTAINER_NAME="shorty-production"
        CONTAINER_PORT="8000"
        ENVIRONMENT_PATH="$BASEPATH/production.env"
        RUN_PATH="/opt/shorty/production"
    ;;
    STAGING)
        CONTAINER_NAME="shorty-staging"
        CONTAINER_PORT="9000"
        ENVIRONMENT_PATH="$BASEPATH/staging.env"
        RUN_PATH="/opt/shorty/staging"
    ;;
    *)
        echo "error: expected $1 to be either PRODUCTION or STAGING"
        exit 1
    ;;
esac

log() {
    printf "[%s] %s\n" "$(date)" "$@"
}

log "Loading the key..."
echo "$DEPLOY_KEY" > /tmp/deploy-key
chmod 0600 /tmp/deploy-key

log "Adding GIT SHA and VERSION to environment file..."
echo "SHORTY_GIT_SHA=$GITHUB_SHA" >> "$ENVIRONMENT_PATH"
echo "VERSION=$GITHUB_SHA" >> "$ENVIRONMENT_PATH"

log "Adding POSTMARK_TOKEN to environment file..."
echo "SHORTY_POSTMARK_TOKEN=$POSTMARK_TOKEN" >> "$ENVIRONMENT_PATH"

log "Adding SENTRY_DSN to environment file..."
echo "SHORTY_SENTRY_DSN=$SENTRY_DSN" >> "$ENVIRONMENT_PATH"

log "Pulling image from GHCR..."
ssh -o "StrictHostKeyChecking off" -i /tmp/deploy-key "$TARGET_HOST" <<EOF
  echo "$PAT" | docker login ghcr.io -u stormwatch --password-stdin
  docker pull "$IMAGE_NAME"
EOF

log "Restarting the container..."
ssh -o "StrictHostKeyChecking off" -i /tmp/deploy-key "$TARGET_HOST" <<EOF
  mkdir -p "$RUN_PATH"
EOF

scp -o "StrictHostKeyChecking off" -i /tmp/deploy-key "$ENVIRONMENT_PATH" "$TARGET_HOST:$RUN_PATH/env"
ssh -o "StrictHostKeyChecking off" -i /tmp/deploy-key "$TARGET_HOST" <<EOF
  docker stop "$CONTAINER_NAME" || true
  docker rm "$CONTAINER_NAME" || true
  docker run \
    --name "$CONTAINER_NAME" \
    --env-file "$RUN_PATH/env" \
    --link "postgres-13" \
    -v "$RUN_PATH":"$RUN_PATH" \
    -p "$CONTAINER_PORT":"$CONTAINER_PORT" \
    -d \
    "$IMAGE_NAME"
EOF
