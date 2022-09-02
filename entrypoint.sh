#!/bin/sh -l

set -ex

if [ -n "$INPUT_PATH" ]; then
  # Allow user to change directories in which to run Fly commands.
  cd "$INPUT_PATH" || exit
fi

PR_NUMBER=$(jq -r .number /github/workflow/event.json)
if [ -z "$PR_NUMBER" ]; then
  echo "This action only supports pull_request actions."
  exit 1
fi

KEYS=$(jq 'keys' /github/workflow/event.json)
SENDER=$(jq -r .sender.name /github/workflow/event.json)
REPO_NAME=$(jq -r .repository.name /github/workflow/event.json)
EVENT_TYPE=$(jq -r .action /github/workflow/event.json)
FILES=$(ls -la /github/workflow)

echo "FILES: $FILES"
echo "KEYS: $KEYS"
echo "PR_NUMBER: $PR_NUMBER"
echo "REPO_OWNER: $REPO_OWNER"
echo "REPO_NAME: $SENDER"
echo "EVENT_TYPE: $EVENT_TYPE"

EVENT_JSON=$(jq -r . /github/workflow/event.json)

# Default the Fly app name to pr-{number}-{repo_owner}-{repo_name}
app="${INPUT_NAME:-pr-$PR_NUMBER-$REPO_OWNER-$REPO_NAME}"
region="${INPUT_REGION:-${FLY_REGION:-iad}}"
org="${INPUT_ORG:-${FLY_ORG:-personal}}"
image="$INPUT_IMAGE"

echo "$app"
echo "$region"
echo "$org"
echo "$image"

if ! echo "$app" | grep "$PR_NUMBER"; then
  echo "For safety, this action requires the app's name to contain the PR number."
  exit 1
fi

# PR was closed - remove the Fly app if one exists and exit.
if [ "$EVENT_TYPE" = "closed" ]; then
  flyctl apps destroy "$app" -y || true
  exit 0
fi

exit 0

# Deploy the Fly app, creating it first if needed.
if ! flyctl status --app "$app"; then
  flyctl launch --now --copy-config --name "$app" --image "$image" --region "$region" --org "$org"
elif [ "$INPUT_UPDATE" != "false" ]; then
  flyctl deploy --app "$app" --region "$region" --image "$image" --region "$region" --strategy immediate
fi

# Attach postgres cluster to the app if specified.
if [ -n "$INPUT_POSTGRES" ]; then
  flyctl postgres attach --postgres-app "$INPUT_POSTGRES" || true
fi

# Make some info available to the GitHub workflow.
fly status --app "$app" --json >status.json
hostname=$(jq -r .Hostname status.json)
appid=$(jq -r .ID status.json)
echo "::set-output name=hostname::$hostname"
echo "::set-output name=url::https://$hostname"
echo "::set-output name=id::$appid"
