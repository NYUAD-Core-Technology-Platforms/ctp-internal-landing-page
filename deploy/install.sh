#!/usr/bin/env bash
# One-time setup of the CTP internal landing page on a RHEL server.
#
#   sudo dnf install -y git
#   sudo git clone https://github.com/NYUAD-Core-Technology-Platforms/ctp-internal-landing-page.git /opt/ctp-internal-landing-page
#   sudo bash /opt/ctp-internal-landing-page/deploy/install.sh
#
# What it does (safe to re-run):
#   1. installs git, rsync, python3-pyyaml if missing
#   2. creates /etc/ctp-landing.conf from the example (keeps an existing one)
#   3. adds the command `ctp-landing-deploy`
#   4. enables a systemd timer that redeploys every 10 minutes
#      (skip with: sudo AUTO_DEPLOY=no bash install.sh)
#   5. runs the first deploy
# It does NOT change your web-server configuration.

set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Run as root: sudo bash $0"; exit 1; }

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd "$HERE/.." && pwd)

echo "==> Packages"
missing=()
command -v git   >/dev/null || missing+=(git)
command -v rsync >/dev/null || missing+=(rsync)
command -v flock >/dev/null || missing+=(util-linux)
python3 -c 'import yaml' 2>/dev/null || missing+=(python3 python3-pyyaml)
if ((${#missing[@]})); then
  dnf install -y "${missing[@]}"
else
  echo "  all present"
fi

echo "==> /etc/ctp-landing.conf"
if [[ -f /etc/ctp-landing.conf ]]; then
  echo "  exists, left unchanged"
else
  sed "s#^REPO_DIR=.*#REPO_DIR=$REPO#" "$HERE/ctp-landing.conf.example" > /etc/ctp-landing.conf
  echo "  created (REPO_DIR=$REPO). Review WEB_ROOT in it if this server hosts other sites."
fi

echo "==> Command: ctp-landing-deploy"
# In /usr/bin because sudo on RHEL does not search /usr/local/bin.
# A wrapper, not a symlink: git (especially commits made on Windows) may not
# keep the executable bit on deploy.sh, and `git reset` would undo a chmod.
rm -f /usr/bin/ctp-landing-deploy
printf '#!/usr/bin/env bash\nexec bash "%s/deploy.sh" "$@"\n' "$HERE" > /usr/bin/ctp-landing-deploy
chmod 755 /usr/bin/ctp-landing-deploy
echo "  /usr/bin/ctp-landing-deploy runs $HERE/deploy.sh"

if [[ "${AUTO_DEPLOY:-yes}" != "no" ]]; then
  echo "==> Auto-deploy timer (every 10 minutes)"
  install -m 0644 "$HERE/systemd/ctp-landing-deploy.service" /etc/systemd/system/
  install -m 0644 "$HERE/systemd/ctp-landing-deploy.timer"   /etc/systemd/system/
  systemctl daemon-reload
  systemctl enable --now ctp-landing-deploy.timer
  systemctl list-timers ctp-landing-deploy.timer --no-pager | head -3
else
  echo "==> Auto-deploy skipped (AUTO_DEPLOY=no). Deploy by hand with: sudo ctp-landing-deploy"
fi

echo "==> First deploy"
/usr/bin/ctp-landing-deploy

cat <<'EOF'

Done. Next:
  * Open http://<this-server>/ in a browser.
  * Nothing shows, or Apache's test page? See README.md, "Web server".
  * Firewall closed? sudo firewall-cmd --permanent --add-service=http --add-service=https && sudo firewall-cmd --reload
  * Status any time:  sudo ctp-landing-deploy --status
EOF
