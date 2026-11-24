#!/usr/bin/env bash
# One-time setup WITHOUT sudo: publishes the page into ~/public_html, which
# Apache serves at http://<server>/~<your-username>/ when its "userdir"
# module is on, and redeploys every 10 minutes from your own crontab.
#
#   git clone <this repo> ~/ctp-internal-landing-page
#   bash ~/ctp-internal-landing-page/deploy/install-user.sh
#
# Safe to re-run. Needs only git on the server (rsync and PyYAML are used if
# present). Undo: crontab -e (delete the "# ctp-landing" line), rm -r ~/public_html.

set -euo pipefail

[[ $EUID -ne 0 ]] || { echo "This is the no-sudo installer. As root, use deploy/install.sh."; exit 1; }
command -v git >/dev/null || { echo "git is not installed on this server; ask an admin to run: apt install git"; exit 1; }

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
CONF="$HOME/.config/ctp-landing.conf"
LOG_DIR="$HOME/.local/state"

echo "==> $CONF"
if [[ -f "$CONF" ]]; then
  echo "  exists, left unchanged"
else
  mkdir -p "$(dirname "$CONF")"
  cat > "$CONF" <<EOF
# Per-user settings for the CTP internal landing page (see deploy/ctp-landing.conf.example).
REPO_DIR=$REPO
BRANCH=main
COMMON_DIR=$HOME/.local/share/ctp-common
COMMON_URL=https://github.com/NYUAD-Core-Technology-Platforms/ctp-common.git
COMMON_REF=main
WEB_ROOT=$HOME/public_html
EOF
  echo "  created"
fi

echo "==> Auto-deploy (your crontab, every 10 minutes)"
mkdir -p "$LOG_DIR"
line="*/10 * * * * bash \"$HERE/deploy.sh\" >> \"$LOG_DIR/ctp-landing-deploy.log\" 2>&1 # ctp-landing"
if (crontab -l 2>/dev/null | grep -v '# ctp-landing'; echo "$line") | crontab - 2>/dev/null; then
  echo "  added"
else
  echo "  crontab is not allowed for your account; run 'bash $HERE/deploy.sh' after each push instead."
fi

echo "==> First deploy"
bash "$HERE/deploy.sh"

# The web server must be able to pass through your home folder to reach public_html.
perm_note=""
if [[ $(( $(stat -c '%a' "$HOME") % 2 )) -eq 0 ]]; then
  perm_note="  * Your home folder blocks the web server. To allow it to pass through (not list it):
      chmod o+x ~"
fi

host=$(hostname -I 2>/dev/null | awk '{print $1}')
cat <<EOF

Done. Open:  http://${host:-<server>}/~$USER/
$perm_note
  * 404 Not Found there means Apache's per-user folders are off. Ask the
    server admin to run once:  sudo a2enmod userdir && sudo systemctl reload apache2
    (or to do the system install instead; see README, "No sudo on the server").
  * Status any time:  bash $HERE/deploy.sh --status
  * Log of automatic runs:  $LOG_DIR/ctp-landing-deploy.log
EOF
