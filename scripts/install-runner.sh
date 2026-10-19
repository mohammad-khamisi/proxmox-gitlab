#!/usr/bin/env bash
# Installs GitLab Runner, waits for the GitLab VM, creates an instance runner
# through the API and registers it with the docker executor.
set -euo pipefail

set -a
# shellcheck disable=SC1091
source /etc/gitlab-runner-bootstrap.env
set +a

export DEBIAN_FRONTEND=noninteractive

if ! command -v gitlab-runner >/dev/null 2>&1; then
  curl -fsSL https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh | bash
  apt-get install -y gitlab-runner
fi
usermod -aG docker gitlab-runner

if grep -q '^\s*token\s*=' /etc/gitlab-runner/config.toml 2>/dev/null; then
  echo "Runner already registered, nothing to do."
  exit 0
fi

# GitLab can take 10-20 minutes on first boot. Retry for up to 60 minutes;
# the API call also fails until the bootstrap token exists.
runner_token=""
for attempt in $(seq 1 120); do
  if response=$(curl -fsS --request POST \
      --header "PRIVATE-TOKEN: ${GITLAB_AUTOMATION_TOKEN}" \
      --data "runner_type=instance_type" \
      --data-urlencode "description=${RUNNER_NAME}" \
      --data-urlencode "tag_list=${RUNNER_TAGS}" \
      --data "run_untagged=true" \
      "${GITLAB_URL}/api/v4/user/runners" 2>/dev/null); then
    runner_token=$(echo "$response" | jq -r '.token')
    break
  fi
  echo "GitLab not ready yet (attempt ${attempt}), retrying in 30s..."
  sleep 30
done

if [ -z "$runner_token" ] || [ "$runner_token" = "null" ]; then
  echo "Could not create runner in GitLab at ${GITLAB_URL}" >&2
  exit 1
fi

gitlab-runner register \
  --non-interactive \
  --url "$GITLAB_URL" \
  --token "$runner_token" \
  --name "$RUNNER_NAME" \
  --executor docker \
  --docker-image "$RUNNER_DOCKER_IMAGE" \
  --docker-privileged="$RUNNER_DOCKER_PRIVILEGED" \
  --docker-volumes /cache

sed -i "s/^concurrent = .*/concurrent = ${RUNNER_CONCURRENT}/" /etc/gitlab-runner/config.toml

systemctl enable gitlab-runner
systemctl restart gitlab-runner

# The bootstrap token is no longer needed on this VM.
sed -i '/^GITLAB_AUTOMATION_TOKEN=/d' /etc/gitlab-runner-bootstrap.env

echo "Runner '${RUNNER_NAME}' registered against ${GITLAB_URL}"
