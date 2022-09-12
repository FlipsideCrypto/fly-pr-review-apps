#!/bin/sh -l

set -ex

PR_NUMBER=$(jq -r .number /github/workflow/event.json)
if [ -z "$PR_NUMBER" ]; then
  echo "This action only supports pull_request actions."
  exit 1
fi

USER=$(jq -r .pull_request.user.login /github/workflow/event.json)
REPO_NAME=$(jq -r .repository.name /github/workflow/event.json)
PR_TITLE=$(jq -r .pull_request.head.ref /github/workflow/event.json)
EVENT_TYPE=$(jq -r .action /github/workflow/event.json)

# Default the Fly app name to pr-{repo}-{title}-{number}-{user}
app="${INPUT_NAME:-pr-$REPO_NAME-$PR_TITLE-$PR_NUMBER-$USER}"
app=$(echo $app | tr '[:upper:]' '[:lower:]')
region="${INPUT_REGION:-${FLY_REGION:-iad}}"
org="${INPUT_ORG:-${FLY_ORG:-personal}}"
image="$INPUT_IMAGE"

if ! echo "$app" | grep "$PR_NUMBER"; then
  echo "For safety, this action requires the app's name to contain the PR number."
  exit 1
fi

# PR was closed - remove the Fly app if one exists and exit.
if [ "$EVENT_TYPE" = "closed" ]; then
  echo "PR was closed - removing the Fly app."
  flyctl apps destroy "$app" -y || true
  exit 0
fi

# Create the app 
if ! flyctl status --app "$app"; then
  echo "Creating the Fly app."
  flyctl apps create --name "$app" --org "$org"
  flyctl scale memory 1024 --app "$app"
fi

# Attach postgres cluster to the app if specified.
if [ -n "$INPUT_POSTGRES" ]; then
  echo "Attaching postgres cluster."
  flyctl postgres attach "$INPUT_POSTGRES" --app "$app" --database-name "$app"-db || true
fi

# Set up secrets
if [ -n "$INPUT_SECRETS" ]; then
  echo "Setting secrets."
  echo $INPUT_SECRETS | tr " " "\n" | flyctl secrets import --app "$app"
fi

# Deploy the app
if [ "$INPUT_UPDATE" != "false" ]; then
  echo "Deploying the app."
  flyctl deploy --config "$INPUT_CONFIG" --app "$app" --region "$region" --strategy immediate --image "$image" --remote-only
fi

# Make some info available to the GitHub workflow.
fly status --app "$app" --json >status.json
hostname=$(jq -r .Hostname status.json)
appid=$(jq -r .ID status.json)
echo "::set-output name=hostname::$hostname"
echo "::set-output name=url::https://$hostname"
echo "::set-output name=id::$appid"
