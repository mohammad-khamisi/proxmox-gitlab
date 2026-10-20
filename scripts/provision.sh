#!/usr/bin/env bash
# Used when cloud-init snippets are not available (use_snippets = false):
# Terraform uploads this directory to the VM over SSH and runs it with sudo.
# Usage: provision.sh <timezone> <role>...   (roles: gitlab, runner)
set -euo pipefail

src=$(cd "$(dirname "$0")" && pwd)
timezone=$1
shift

export DEBIAN_FRONTEND=noninteractive
apt_get() { apt-get -o DPkg::Lock::Timeout=900 "$@"; }

# Let the built-in Proxmox cloud-init (user, network, package upgrade) finish.
cloud-init status --wait >/dev/null 2>&1 || true
timedatectl set-timezone "$timezone" || true

packages="qemu-guest-agent curl ca-certificates"
for role in "$@"; do
  case "$role" in
    gitlab) packages="$packages openssh-server tzdata perl" ;;
    runner) packages="$packages jq docker.io" ;;
    *) echo "unknown role: $role" >&2; exit 1 ;;
  esac
done

apt_get update
# shellcheck disable=SC2086
apt_get install -y $packages
systemctl enable --now qemu-guest-agent || true

for role in "$@"; do
  case "$role" in
    gitlab)
      install -m 0600 "$src/gitlab.env" /etc/gitlab-bootstrap.env
      install -m 0755 "$src/install-gitlab.sh" /usr/local/sbin/install-gitlab.sh
      install -D -m 0600 "$src/gitlab-bootstrap.rb" /usr/local/share/gitlab-bootstrap.rb
      /usr/local/sbin/install-gitlab.sh 2>&1 | tee /var/log/install-gitlab.log
      ;;
    runner)
      systemctl enable --now docker
      install -m 0600 "$src/runner.env" /etc/gitlab-runner-bootstrap.env
      install -m 0755 "$src/install-runner.sh" /usr/local/sbin/install-runner.sh
      /usr/local/sbin/install-runner.sh 2>&1 | tee /var/log/install-runner.log
      ;;
  esac
done

rm -rf "$src"
