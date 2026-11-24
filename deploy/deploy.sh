#!/usr/bin/env bash
# Deploy the CTP internal landing page.
#
#   sudo ctp-landing-deploy            pull latest main + ctp-common, publish
#   sudo ctp-landing-deploy --status   show what is live and whether it is behind
#   bash deploy/deploy.sh              same, without sudo (see install-user.sh)
#
# Safe to run any time and as often as you like: if nothing changed, nothing
# changes. If validation fails, the live site is left untouched.
# Settings: /etc/ctp-landing.conf as root, ~/.config/ctp-landing.conf otherwise
# (see deploy/ctp-landing.conf.example).

set -euo pipefail

# The clone this script lives in (read before main() can git-reset it).
SELF_REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# Everything runs inside main() so that `git reset` updating this very file
# mid-run cannot confuse bash (it has already read the whole function).
main() {
  # Root: system install (/etc, /opt, /var/www/html).
  # Anyone else: per-user install (~/.config, ~/public_html), no sudo needed.
  local CONF
  if [[ -n "${CTP_LANDING_CONF:-}" ]]; then CONF=$CTP_LANDING_CONF
  elif [[ $EUID -eq 0 ]]; then CONF=/etc/ctp-landing.conf
  else CONF="$HOME/.config/ctp-landing.conf"; fi
  # shellcheck disable=SC1090
  [[ -f "$CONF" ]] && source "$CONF"

  REPO_DIR=${REPO_DIR:-$SELF_REPO}
  BRANCH=${BRANCH:-main}
  COMMON_URL=${COMMON_URL:-https://github.com/NYUAD-Core-Technology-Platforms/ctp-common.git}
  COMMON_REF=${COMMON_REF:-main}
  if [[ $EUID -eq 0 ]]; then
    COMMON_DIR=${COMMON_DIR:-/opt/ctp-common}
    WEB_ROOT=${WEB_ROOT:-/var/www/html}
  else
    COMMON_DIR=${COMMON_DIR:-$HOME/.local/share/ctp-common}
    WEB_ROOT=${WEB_ROOT:-$HOME/public_html}
  fi
  [[ -n "${HTTPS_PROXY:-}" ]] && export HTTPS_PROXY https_proxy="$HTTPS_PROXY"
  [[ -n "${HTTP_PROXY:-}"  ]] && export HTTP_PROXY  http_proxy="$HTTP_PROXY"

  local MARKER=".ctp-landing"

  if [[ "${1:-}" == "--status" ]]; then
    status; return
  fi

  # One deploy at a time (the timer and a manual run could overlap).
  local LOCK=/run/ctp-landing-deploy.lock
  [[ $EUID -eq 0 && -w /run ]] || LOCK="${XDG_RUNTIME_DIR:-/tmp}/ctp-landing-deploy-$(id -u).lock"
  exec 9>"$LOCK"
  if command -v flock >/dev/null; then
    flock -n 9 || { echo "Another deploy is running; try again in a minute."; exit 0; }
  fi

  command -v git >/dev/null || die "git is not installed on this server (ask an admin: apt install git)."

  step "Updating this repository ($REPO_DIR, branch $BRANCH)"
  [[ -d "$REPO_DIR/.git" ]] || die "No git clone at $REPO_DIR. Run deploy/install.sh first."
  git -C "$REPO_DIR" fetch --quiet origin "$BRANCH" \
    || die "git fetch failed. Check the server can reach github.com (proxy?) and, if the repo is private, that a deploy key is set up (README, 'Private repository')."
  git -C "$REPO_DIR" reset --quiet --hard "origin/$BRANCH"
  local LANDING_SHA LANDING_MSG
  LANDING_SHA=$(git -C "$REPO_DIR" rev-parse --short HEAD)
  LANDING_MSG=$(git -C "$REPO_DIR" log -1 --format=%s)
  echo "  at $LANDING_SHA  $LANDING_MSG"

  step "Updating shared data (ctp-common @ $COMMON_REF)"
  if [[ ! -d "$COMMON_DIR/.git" ]]; then
    mkdir -p "$(dirname "$COMMON_DIR")"
    git clone --quiet --depth 1 --branch "$COMMON_REF" "$COMMON_URL" "$COMMON_DIR" \
      || die "Could not download ctp-common from $COMMON_URL (network or proxy?)."
  else
    git -C "$COMMON_DIR" fetch --quiet --depth 1 origin "$COMMON_REF" \
      || die "Could not update ctp-common from $COMMON_URL (network or proxy?)."
    git -C "$COMMON_DIR" reset --quiet --hard FETCH_HEAD
  fi
  local COMMON_SHA
  COMMON_SHA=$(git -C "$COMMON_DIR" rev-parse --short HEAD)
  echo "  at $COMMON_SHA"

  step "Validating site/links.yaml"
  if command -v python3 >/dev/null && python3 -c 'import yaml' 2>/dev/null; then
    python3 "$REPO_DIR/scripts/check.py" --common-dir "$COMMON_DIR/data" \
      || die "Validation failed; the live site was NOT changed. Fix the errors above, push, and run this again."
  else
    echo "  skipped (install PyYAML to enable: sudo apt install python3-yaml, or sudo dnf install python3-pyyaml)"
  fi

  step "Building"
  STAGE=$(mktemp -d /tmp/ctp-landing.XXXXXX)
  trap 'rm -rf "${STAGE:-}"' EXIT
  cp -a "$REPO_DIR/site/." "$STAGE/"
  mkdir -p "$STAGE/data/ctp-common"
  for f in links.yaml people.yaml clusters.yaml; do
    cp "$COMMON_DIR/data/$f" "$STAGE/data/ctp-common/$f"
  done
  cat > "$STAGE/build-info.json" <<EOF
{
  "deployed_at": "$(date '+%Y-%m-%d %H:%M %Z')",
  "landing_commit": "$LANDING_SHA",
  "landing_message": $(json_str "$LANDING_MSG"),
  "common_commit": "$COMMON_SHA",
  "common_ref": "$COMMON_REF"
}
EOF
  touch "$STAGE/$MARKER"

  step "Publishing to $WEB_ROOT"
  mkdir -p "$WEB_ROOT"
  # A fresh Apache/nginx install leaves only its default welcome page here.
  # Move it aside (not delete) so this site can take over the folder.
  if [[ ! -e "$WEB_ROOT/$MARKER" ]] && only_default_page "$WEB_ROOT"; then
    local BACKUP="${WEB_ROOT%/}.default-page-backup"
    mkdir -p "$BACKUP"
    mv "$WEB_ROOT"/* "$BACKUP"/
    echo "  moved the web server's default welcome page to $BACKUP"
  fi
  if [[ ! -e "$WEB_ROOT/$MARKER" ]] && [[ -n "$(ls -A "$WEB_ROOT" 2>/dev/null)" ]]; then
    die "$WEB_ROOT already contains other files, so it was not touched.
  Either set WEB_ROOT in $CONF to an empty folder (and point
  the web server at it, see deploy/apache-ctp-landing.conf), or, if those files
  are disposable, move them away and run this again."
  fi
  if command -v rsync >/dev/null; then
    rsync -a --delete --exclude ".well-known/" "$STAGE/" "$WEB_ROOT/"
  else
    # No rsync (e.g. no sudo to install it): replace our files with plain cp.
    find "$WEB_ROOT" -mindepth 1 -maxdepth 1 ! -name .well-known -exec rm -rf {} +
    cp -a "$STAGE/." "$WEB_ROOT/"
  fi
  chmod -R a+rX "$WEB_ROOT"
  if command -v restorecon >/dev/null; then restorecon -R "$WEB_ROOT" || true; fi

  echo
  echo "Live: landing $LANDING_SHA, ctp-common $COMMON_SHA -> $WEB_ROOT"
}

status() {
  echo "Config:      $CONF"
  echo "Web root:    $WEB_ROOT"
  if [[ -f "$WEB_ROOT/build-info.json" ]]; then
    echo "Live build:  $(tr -d '\n' < "$WEB_ROOT/build-info.json" | sed 's/  */ /g')"
  else
    echo "Live build:  none (never deployed to $WEB_ROOT)"
  fi
  if [[ -d "$REPO_DIR/.git" ]]; then
    git -C "$REPO_DIR" fetch --quiet origin "$BRANCH" 2>/dev/null || true
    local behind
    behind=$(git -C "$REPO_DIR" rev-list --count "HEAD..origin/$BRANCH" 2>/dev/null || echo '?')
    echo "Repo:        $(git -C "$REPO_DIR" rev-parse --short HEAD), $behind commit(s) behind origin/$BRANCH"
  fi
  if [[ $EUID -ne 0 ]]; then
    if crontab -l 2>/dev/null | grep -q '# ctp-landing'; then
      echo "Auto-deploy: crontab, every 10 minutes (log: ~/.local/state/ctp-landing-deploy.log)"
    else
      echo "Auto-deploy: off (run deploy/install-user.sh)"
    fi
  elif command -v systemctl >/dev/null && systemctl list-unit-files ctp-landing-deploy.timer >/dev/null 2>&1; then
    echo "Auto-deploy: $(systemctl is-active ctp-landing-deploy.timer 2>/dev/null || true)"
  fi
}

# True when the folder holds nothing but a stock Apache/nginx welcome page.
only_default_page() {
  local f n=0
  for f in "$1"/* "$1"/.[!.]*; do
    [[ -e "$f" ]] || continue
    n=$((n + 1))
    case "$(basename "$f")" in
      index.nginx-debian.html) ;;
      index.html) grep -qiE 'Apache2 (Ubuntu|Debian) Default Page|Test Page for the (Apache|HTTP) Server|Welcome to nginx' "$f" || return 1 ;;
      *) return 1 ;;
    esac
  done
  (( n > 0 ))
}

step() { echo; echo "==> $*"; }
die()  { echo; echo "ERROR: $*" >&2; exit 1; }
json_str() { python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1" 2>/dev/null \
  || printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')"; }

main "$@"
exit $?
