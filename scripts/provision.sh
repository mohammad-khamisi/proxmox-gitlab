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

packages="qemu-guest-agent curl ca-certificates cloud-guest-utils"
for role in "$@"; do
  case "$role" in
    gitlab) packages="$packages openssh-server tzdata perl" ;;
    runner) packages="$packages jq docker.io" ;;
    *) echo "unknown role: $role" >&2; exit 1 ;;
  esac
done

# Grow the root filesystem to the disk size set by Terraform (cloud images do
# this themselves; templates installed from the ISO usually use LVM).
grow_root() {
  local root_dev pv disk part
  root_dev=$(findmnt -n -o SOURCE /)
  if [[ "$root_dev" == /dev/mapper/* ]]; then
    pv=$(pvs --noheadings -o pv_name 2>/dev/null | head -n1 | tr -d ' ')
    [ -n "$pv" ] || return 0
    disk="/dev/$(lsblk -no pkname "$pv")"
    part="${pv##*[!0-9]}"
    growpart "$disk" "$part" || true
    pvresize "$pv"
    lvextend -r -l +100%FREE "$root_dev" || true
  else
    disk="/dev/$(lsblk -no pkname "$root_dev")"
    part="${root_dev##*[!0-9]}"
    growpart "$disk" "$part" || true
    resize2fs "$root_dev" || true
  fi
}

apt_get update
# shellcheck disable=SC2086
apt_get install -y $packages
systemctl enable --now qemu-guest-agent || true

grow_root || echo "warning: could not grow the root filesystem" >&2
df -h /

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
