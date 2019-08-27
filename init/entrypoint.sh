#!/bin/sh

# stripcolors takes some output and removes ANSI color codes.
stripcolors() {
  echo "$1" | sed 's/\x1b\[[0-9;]*m//g'
}

set -e
cd "${TF_ACTION_WORKING_DIR:-.}"

if [[ ! -z "$TF_ACTION_TFE_TOKEN" ]]; then
  cat > ~/.terraformrc << EOF
credentials "${TF_ACTION_TFE_HOSTNAME:-app.terraform.io}" {
  token = "$TF_ACTION_TFE_TOKEN"
}
EOF
fi

if [[ ! -z "$GITHUB_DEPLOY_PRIVATE_KEY" ]]; then
  mkdir -p ~/.ssh
  ssh-keyscan -t rsa github.com > ~/.ssh/known_hosts
  chmod 644 ~/.ssh/known_hosts

  cat > ~/.ssh/config << EOF
Host *
   StrictHostKeyChecking no
   UserKnownHostsFile=/dev/null
EOF
  chmod 644 ~/.ssh/config

  eval "$(ssh-agent -s)"

  cat > ~/.ssh/deploy_key << EOF
${GITHUB_DEPLOY_PRIVATE_KEY}
EOF

  chmod 600 ~/.ssh/deploy_key
  ssh-add ~/.ssh/deploy_key

  ls -lha ~/.ssh/
fi

if [[ ! -z "$GOOGLE_CLOUD_KEYFILE_JSON" ]]; then
  cat > /tmp/GOOGLE_CLOUD_KEYFILE_JSON << EOF
${GOOGLE_CLOUD_KEYFILE_JSON}
EOF
  export GOOGLE_CREDENTIALS=/tmp/GOOGLE_CLOUD_KEYFILE_JSON
fi

set +e
export TF_APPEND_USER_AGENT="terraform-github-actions/1.0"
OUTPUT=$(sh -c "terraform init -input=false $*" 2>&1)
SUCCESS=$?
echo "$OUTPUT"
set -e

if [ $SUCCESS -eq 0 ]; then
    exit 0
fi

if [[ "$GITHUB_EVENT_NAME" == 'pull_request' ]]; then
    if [ "$TF_ACTION_COMMENT" = "1" ] || [ "$TF_ACTION_COMMENT" = "false" ]; then
        exit $SUCCESS
    fi

    OUTPUT=$(stripcolors "$OUTPUT")
    COMMENT="#### \`terraform init\` Failed
\`\`\`
$OUTPUT
\`\`\`
*Workflow: \`$GITHUB_WORKFLOW\`, Action: \`$GITHUB_ACTION\`*"
    PAYLOAD=$(echo '{}' | jq --arg body "$COMMENT" '.body = $body')
    COMMENTS_URL=$(cat $GITHUB_EVENT_PATH | jq -r .pull_request.comments_url)
    curl -s -S -H "Authorization: token $GITHUB_TOKEN" --header "Content-Type: application/json" --data "$PAYLOAD" "$COMMENTS_URL" > /dev/null
fi

exit $SUCCESS

