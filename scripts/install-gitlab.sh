#!/usr/bin/env bash
# Installs GitLab Omnibus and creates the automation token the runner VM uses.
set -euo pipefail

set -a
# shellcheck disable=SC1091
source /etc/gitlab-bootstrap.env
set +a

export DEBIAN_FRONTEND=noninteractive

if ! dpkg -s "$GITLAB_EDITION" >/dev/null 2>&1; then
  curl -fsSL "https://packages.gitlab.com/install/repositories/gitlab/${GITLAB_EDITION}/script.deb.sh" | bash
  # EXTERNAL_URL and GITLAB_ROOT_PASSWORD are read by the package on install.
  apt-get install -y "$GITLAB_EDITION"
fi

gitlab-ctl reconfigure

# Wait for Rails to be ready before touching the database.
for _ in $(seq 1 60); do
  if curl -fsS http://127.0.0.1/-/readiness >/dev/null 2>&1; then
    break
  fi
  sleep 10
done

gitlab-rails runner /usr/local/share/gitlab-bootstrap.rb

# Secrets are no longer needed on disk.
rm -f /usr/local/share/gitlab-bootstrap.rb
sed -i '/^GITLAB_ROOT_PASSWORD=/d;/^GITLAB_AUTOMATION_TOKEN=/d' /etc/gitlab-bootstrap.env
rm -f /etc/gitlab/initial_root_password

echo "GitLab is ready at ${EXTERNAL_URL}"
