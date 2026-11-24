#!/usr/bin/env bash
# One-time setup of the CTP internal landing page on a Linux server
# (Ubuntu/Debian with apt, or RHEL/Rocky/Alma with dnf).
#
#   sudo apt install -y git        # Ubuntu      (RHEL: sudo dnf install -y git)
#   sudo git clone https://github.com/NYUAD-Core-Technology-Platforms/ctp-internal-landing-page.git /opt/ctp-internal-landing-page
#   sudo bash /opt/ctp-internal-landing-page/deploy/install.sh
#
# What it does (safe to re-run):
#   1. installs git, rsync, PyYAML, and Apache if no web server is running
#   2. creates /etc/ctp-landing.conf from the example (keeps an existing one)
#   3. adds the command `ctp-landing-deploy`
#   4. enables a systemd timer that redeploys every 10 minutes
#      (skip with: sudo AUTO_DEPLOY=no bash install.sh)
#   5. runs the first deploy
# It never edits web-server configuration files.

set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Run as root: sudo bash $0"; exit 1; }

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd "$HERE/.." && pwd)

if command -v apt-get >/dev/null; then
  PKG=apt; YAML_PKG=python3-yaml; WEB_PKG=apache2; WEB_SVC=apache2
elif command -v dnf >/dev/null; then
  PKG=dnf; YAML_PKG=python3-pyyaml; WEB_PKG=httpd; WEB_SVC=httpd
else
  echo "Neither apt nor dnf found; install git, rsync, python3 PyYAML and a web server by hand, then re-run."; exit 1
fi
pkg_install() {
  if [[ $PKG == apt ]]; then apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
  else dnf install -y "$@"; fi
}

echo "==> Packages"
missing=()
command -v git   >/dev/null || missing+=(git)
command -v rsync >/dev/null || missing+=(rsync)
command -v flock >/dev/null || missing+=(util-linux)
python3 -c 'import yaml' 2>/dev/null || missing+=(python3 "$YAML_PKG")
if ((${#missing[@]})); then
  pkg_install "${missing[@]}"
else
  echo "  all present"
fi

echo "==> Web server"
running=""
for svc in apache2 httpd nginx; do
  systemctl is-active --quiet "$svc" 2>/dev/null && running=$svc
done
if [[ -n "$running" ]]; then
  echo "  $running is running"
elif [[ "${INSTALL_WEBSERVER:-yes}" == "no" ]]; then
  echo "  none running, and INSTALL_WEBSERVER=no: set one up yourself (see README, 'Web server')"
else
  echo "  none running; installing $WEB_PKG"
  pkg_install "$WEB_PKG"
  systemctl enable --now "$WEB_SVC"
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
  * Firewall closed? Ubuntu: sudo ufw allow 'Apache Full'
                     RHEL:   sudo firewall-cmd --permanent --add-service=http --add-service=https && sudo firewall-cmd --reload
  * Status any time:  sudo ctp-landing-deploy --status
EOF
