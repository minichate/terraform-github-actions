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
  mkdir -p ${HOME}/.ssh
  ssh-keyscan -t rsa github.com > ${HOME}/.ssh/known_hosts
  cat >> ${HOME}/.ssh/known_hosts << EOF
# github.com:22 SSH-2.0-babeld-216c4091
github.com ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAq2A7hRGmdnm9tUDbO9IDSwBK6TbQa+PXYPCPy6rbTrTtw7PHkccKrpp0yVhp5HdEIcKr6pLlVDBfOLX9QUsyCOV0wzfjIJNlGEYsdlLJizHhbn2mUjvSAHQqZETYP81eFzLQNnPHt4EVVUh7VfDESU84KezmD5QlWpXLmvU31/yMf+Se8xhHTvKSCZIFImWwoG6mbUoWf9nzpIoaSjB+weqqUUmpaaasXVal72J+UX2B+2RPW3RcT0eOzQgqlJL3RKrTJvdsjE3JEAvGq3lGHSZXy28G3skua2SmVi/w4yCE6gbODqnTWlg7+wC604ydGXA8VJiS5ap43JXiUFFAaQ==
EOF
  chmod 644 ${HOME}/.ssh/known_hosts

  cat > ${HOME}/.ssh/config << EOF
Host *
   StrictHostKeyChecking no
   UserKnownHostsFile=/dev/null
EOF
  chmod 644 ${HOME}/.ssh/config

  eval "$(ssh-agent -s)"

  cat > ${HOME}/.ssh/deploy_key << EOF
${GITHUB_DEPLOY_PRIVATE_KEY}
EOF

  chmod 600 ${HOME}/.ssh/deploy_key
  ssh-add ${HOME}/.ssh/deploy_key

  ls -lha ${HOME}/.ssh/
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

