#!/bin/sh
# Installs a release tarball already uploaded to the EC2 host, atomically
# repoints the `current` symlink, restarts the systemd unit, and rolls
# back to the previous release if the post-restart health check fails.
#
# Run on the EC2 host itself (via ssh from .github/workflows/deploy.yml),
# not on the CI runner. Requires passwordless sudo for exactly
# `systemctl restart <service>` (see ops/README.md for the sudoers entry)
# since the release runs as an unprivileged system user that cannot
# restart its own unit.
#
# Usage:
#   deploy-release.sh <app_name> <service_name> <deploy_root> \
#     <release_id> <tarball_path> <health_check_url>
#
# Example:
#   deploy-release.sh yokerhood yokerhood /opt/yokerhood \
#     a1b2c3d /tmp/yokerhood-release.tar.gz http://127.0.0.1:3050/

set -eu

app_name=$1
service_name=$2
deploy_root=$3
release_id=$4
tarball_path=$5
health_check_url=$6

releases_dir="$deploy_root/releases"
release_dir="$releases_dir/$release_id"
current_link="$deploy_root/current"

echo "==> Installing $app_name release $release_id into $release_dir"
mkdir -p "$release_dir"
tar -xzf "$tarball_path" -C "$release_dir"
rm -f "$tarball_path"

previous_target=""
if [ -L "$current_link" ]; then
  previous_target=$(readlink -f "$current_link")
fi

echo "==> Switching $current_link -> $release_dir"
ln -sfn "$release_dir" "$current_link.tmp"
mv -Tf "$current_link.tmp" "$current_link"

echo "==> Restarting $service_name"
# Tolerate a failed restart here (e.g. a bad release, or a failed
# ExecStartPre migration) instead of hard-exiting via `set -e`: falling
# through into the health-check loop below means curl will simply keep
# failing (connection refused) until max_attempts, which then triggers
# the same rollback-to-previous-release path as any other unhealthy
# restart, rather than leaving the bad release symlinked with no recovery.
sudo /usr/bin/systemctl restart "$service_name" || true

echo "==> Health-checking $health_check_url"
attempt=0
max_attempts=10
until curl -fsS -o /dev/null "$health_check_url"; do
  attempt=$((attempt + 1))
  if [ "$attempt" -ge "$max_attempts" ]; then
    echo "==> Health check failed after $max_attempts attempts, rolling back"
    if [ -n "$previous_target" ]; then
      ln -sfn "$previous_target" "$current_link.tmp"
      mv -Tf "$current_link.tmp" "$current_link"
      sudo /usr/bin/systemctl restart "$service_name"
      echo "==> Rolled back to $previous_target"
    else
      echo "==> No previous release to roll back to"
    fi
    exit 1
  fi
  sleep 2
done

echo "==> $app_name release $release_id is live"

echo "==> Pruning old releases (keeping the 5 most recent)"
# shellcheck disable=SC2012
ls -1dt "$releases_dir"/*/ 2>/dev/null | tail -n +6 | xargs -r rm -rf
