#!/bin/sh

# stripcolors takes some output and removes ANSI color codes.
stripcolors() {
  echo "$1" | sed 's/\x1b\[[0-9;]*m//g'
}

# wrap takes some output and wraps it in a collapsible markdown section if
# it's over $TF_ACTION_WRAP_LINES long.
wrap() {
  if [[ $(echo "$1" | wc -l) -gt ${TF_ACTION_WRAP_LINES:-20} ]]; then
    echo "
<details><summary>Show Output</summary>

\`\`\`
$1
\`\`\`

</details>
"
else
    echo "
\`\`\`
$1
\`\`\`
"
fi
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

if [[ ! -z "$GOOGLE_CLOUD_KEYFILE_JSON" ]]; then
  cat > /tmp/GOOGLE_CLOUD_KEYFILE_JSON << EOF
${GOOGLE_CLOUD_KEYFILE_JSON}
EOF
  export GOOGLE_CREDENTIALS=/tmp/GOOGLE_CLOUD_KEYFILE_JSON
fi


if [[ ! -z "$TF_ACTION_WORKSPACE" ]] && [[ "$TF_ACTION_WORKSPACE" != "default" ]]; then
  terraform workspace select "$TF_ACTION_WORKSPACE"
fi

set +e
OUTPUT=$(sh -c "TF_IN_AUTOMATION=true terraform apply -auto-approve -input=false $*" 2>&1)
SUCCESS=$?
echo "$OUTPUT"
set -e

# If PR_DATA is null, then this is not a pull request event and so there's
# no where to comment.
PR_DATA=$(cat $GITHUB_EVENT_PATH | jq -r .pull_request)
if [ "$TF_ACTION_COMMENT" = "1" ] || [ "$TF_ACTION_COMMENT" = "false" ] || [ "$PR_DATA" = "null" ]; then
    exit $SUCCESS
fi

if [[ "$GITHUB_EVENT_NAME" == 'pull_request' ]]; then
    # Build the comment we'll post to the PR.
    OUTPUT=$(stripcolors "$OUTPUT")
    COMMENT=""
    if [ $SUCCESS -ne 0 ]; then
        OUTPUT=$(wrap "$OUTPUT")
        COMMENT="#### \`terraform apply\` Failed
$OUTPUT

*Workflow: \`$GITHUB_WORKFLOW\`, Action: \`$GITHUB_ACTION\`*"
    else
        # Call wrap to optionally wrap our output in a collapsible markdown section.
        OUTPUT=$(wrap "$OUTPUT")
        COMMENT="#### \`terraform apply\` Success
$OUTPUT

*Workflow: \`$GITHUB_WORKFLOW\`, Action: \`$GITHUB_ACTION\`*"
    fi

    # Post the comment.
    PAYLOAD=$(echo '{}' | jq --arg body "$COMMENT" '.body = $body')
    COMMENTS_URL=$(cat $GITHUB_EVENT_PATH | jq -r .pull_request.comments_url)

    curl -s -S -H "Authorization: token $GITHUB_TOKEN" --header "Content-Type: application/json" --data "$PAYLOAD" "$COMMENTS_URL" > /dev/null
fi

exit $SUCCESS
