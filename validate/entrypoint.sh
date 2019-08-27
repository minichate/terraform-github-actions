#!/bin/sh

# stripcolors takes some output and removes ANSI color codes.
stripcolors() {
  echo "$1" | sed 's/\x1b\[[0-9;]*m//g'
}

set -e
cd "${TF_ACTION_WORKING_DIR:-.}"

if [[ ! -z "$TF_ACTION_WORKSPACE" ]] && [[ "$TF_ACTION_WORKSPACE" != "default" ]]; then
  terraform workspace select "$TF_ACTION_WORKSPACE"
fi

if [[ ! -z "$GITHUB_DEPLOY_PRIVATE_KEY" ]]; then
  mkdir -p ${HOME}/.ssh
  ssh-keyscan -t rsa github.com >> /etc/ssh/ssh_known_hosts
  chmod 644 /etc/ssh/ssh_known_hosts

  cat > /etc/ssh/ssh_config << EOF
Host *
   StrictHostKeyChecking no
   UserKnownHostsFile=/dev/null
EOF
  chmod 644 /etc/ssh/ssh_config

  eval "$(ssh-agent -s)"

  cat > ${HOME}/.ssh/deploy_key << EOF
${GITHUB_DEPLOY_PRIVATE_KEY}
EOF

  chmod 600 ${HOME}/.ssh/deploy_key
  ssh-add ${HOME}/.ssh/deploy_key
fi

set +e
OUTPUT=$(sh -c "terraform validate $*" 2>&1)
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
    COMMENT="#### \`terraform validate\` Failed
\`\`\`
$OUTPUT
\`\`\`
*Workflow: \`$GITHUB_WORKFLOW\`, Action: \`$GITHUB_ACTION\`*"
    PAYLOAD=$(echo '{}' | jq --arg body "$COMMENT" '.body = $body')
    COMMENTS_URL=$(cat $GITHUB_EVENT_PATH | jq -r .pull_request.comments_url)
    curl -s -S -H "Authorization: token $GITHUB_TOKEN" --header "Content-Type: application/json" --data "$PAYLOAD" "$COMMENTS_URL" > /dev/null
fi

exit $SUCCESS
