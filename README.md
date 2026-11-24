# CTP internal landing page

The internal start page for **NYU Abu Dhabi Core Technology Platforms (CTP)** staff: one place with the Discourse forum, the CTP dashboard, the strategy site, the org chart, booking, forms, templates and who to contact.

It is a plain static page (HTML, CSS, a little JavaScript). There is no build step and nothing to install on your computer to edit it.

## What lives here, and what does not

This page **does not copy information from other CTP repositories**. It links to them, or reads them live:

| Shown on the page | Comes from |
|---|---|
| Director, CTP Administration, cluster leads, mailboxes, address | [`ctp-common`](https://github.com/NYUAD-Core-Technology-Platforms/ctp-common) `data/*.yaml`, read at deploy time |
| Org chart, team directory, platform pages | the [ctp-common docs site](https://nyuad-core-technology-platforms.github.io/ctp-common/), linked |
| Booking system, requisition and bid-exception forms, Linktree, public website | `ctp-common/data/links.yaml`, referenced by key |
| Templates, brand, workshop decks | their own repositories and Pages sites, linked |
| **Discourse forum, CTP dashboard, strategy site**, the "New to CTP?" steps, the "Where does it live?" table | **this repo**, `site/links.yaml`: they are not recorded anywhere else |

So if a name, title, email or cluster is wrong on the page, fix it in `ctp-common`, not here. The page's own "Where does it live?" table says which file holds what.

---

## Changing the page

Almost every change is an edit to **one file: [`site/links.yaml`](site/links.yaml)**.

1. Open `site/links.yaml` on GitHub and click the pencil (or use the page's own *Edit this page* link in the footer). Editing locally and pushing works the same way.
2. Make the change and commit to `main`.
3. Done. The server picks it up within 10 minutes. To publish immediately, run `sudo ctp-landing-deploy` on the server.

GitHub checks the file on every push (the *Check links.yaml* action). If the check fails, the server also refuses to publish it and keeps the current page live, so a typo cannot take the page down.

### How a link is written

Every link says where it points with **exactly one** of these fields:

| Field | Use it for | Example |
|---|---|---|
| `url:` | an internal tool recorded nowhere else | `url: https://forum.example.nyu.edu` |
| `common:` | a URL or mailbox already in `ctp-common/data/links.yaml` | `common: public.booking_system` |
| `docs:` | a page of the ctp-common docs site | `docs: orgchart/` |
| `repo:` | a repo or file in the GitHub organisation | `repo: ctp-common/blob/main/operations/scheduling.md` |
| `pages:` | a GitHub Pages site of the organisation | `pages: ctp-upscaling-workshop-series/` |
| `ref:` | another link in this file, by its `id` | `ref: forum` |

Optional fields: `description`, `note` (small tag such as "NYU network or VPN"), `icon`, `id`.

Example, a new link in an existing section:

```yaml
      - title: Safety training records
        description: Who is cleared for which lab.
        icon: list-checks
        url: https://example.nyu.edu/safety
```

A link you do not have yet can stay as `url: ""`; the page shows it greyed out with *Link not set*.

**Icons** are [Lucide](https://lucide.dev/icons) names. The ones available are in `site/assets/img/icons.svg` (the check lists them if you pick a missing one). To add one, copy the inner lines of that icon's SVG into a new `<symbol id="i-NAME">` in the same file.

**Before adding a link:** if this repository is public, anyone can read `links.yaml`. Links themselves are usually fine (they still need an NYU login), but never put passwords, tokens or private file contents here.

### Preview on your computer (optional)

```powershell
cd site
python -m http.server 8000
```

Open <http://localhost:8000>. The preview reads shared data straight from GitHub, so it shows the same content as the server. (Opening `index.html` by double-clicking does not work: browsers block the data files over `file://`.)

---

## Deploying

The server is a Linux machine (Ubuntu with `apt`, or RHEL with `dnf`; both are handled) running a web server, Apache by default. The page is published by one script, [`deploy/deploy.sh`](deploy/deploy.sh), installed as the command `ctp-landing-deploy`. Each run:

1. pulls the latest `main` of this repo into `/opt/ctp-internal-landing-page`,
2. pulls `ctp-common` into `/opt/ctp-common`,
3. validates `site/links.yaml` (stops here on errors; the live page is untouched),
4. copies `site/` plus the three ctp-common data files into the web folder (`/var/www/html` by default), and stamps `build-info.json` (shown in the page footer).

It is safe to run any time, as often as you like.

### One-time setup on the server

SSH in, then:

```bash
sudo apt install -y git        # RHEL: sudo dnf install -y git
sudo git clone https://github.com/NYUAD-Core-Technology-Platforms/ctp-internal-landing-page.git /opt/ctp-internal-landing-page
sudo bash /opt/ctp-internal-landing-page/deploy/install.sh
```

`install.sh` installs `rsync`, PyYAML and (if no web server is running) Apache, creates `/etc/ctp-landing.conf`, adds the `ctp-landing-deploy` command, turns on a systemd timer that redeploys every 10 minutes, and runs the first deploy. It does not touch the web-server configuration. Then open `http://<server>/`.

If `/var/www/html` only holds the web server's default welcome page, it is moved to `/var/www/html.default-page-backup`. If it holds anything else, the deploy stops with a clear message instead of overwriting it: see [Web server](#web-server).

### No sudo on the server

Two ways, both ending with the same auto-updating page:

**1. Ask the server admin to do the one-time system install** (the three commands above). Message you can send:

> Could you run these once on 10.230.240.205? They install our team's internal landing page into /var/www/html and a timer that keeps it updated from GitHub; no further admin work is needed after that.
> `sudo apt install -y git && sudo git clone https://github.com/NYUAD-Core-Technology-Platforms/ctp-internal-landing-page.git /opt/ctp-internal-landing-page && sudo bash /opt/ctp-internal-landing-page/deploy/install.sh`

**2. Install it under your own account**, served at `http://<server>/~<username>/`. Needs only `git` on the server and Apache's per-user folders (`userdir`) switched on:

```bash
git clone https://github.com/NYUAD-Core-Technology-Platforms/ctp-internal-landing-page.git ~/ctp-internal-landing-page
bash ~/ctp-internal-landing-page/deploy/install-user.sh
```

It publishes into `~/public_html`, adds a line to your crontab that redeploys every 10 minutes (log: `~/.local/state/ctp-landing-deploy.log`), and tells you if your home folder needs `chmod o+x ~` so the web server can reach it. If the URL gives *404 Not Found*, per-user folders are off; an admin can enable them with `sudo a2enmod userdir && sudo systemctl reload apache2`. In this mode, run commands as `bash ~/ctp-internal-landing-page/deploy/deploy.sh` (add `--status` to check) instead of `sudo ctp-landing-deploy`. Settings live in `~/.config/ctp-landing.conf`.

If the repository is private, give the server a read-only deploy key first; see [Private repository](#private-repository) (in user mode, use `~/.ssh` instead of `/root/.ssh` and drop `sudo`).

### When something changes: what to do

| What changed | What to do |
|---|---|
| `site/links.yaml`, or anything else in `site/` | Push to `main`. Live within 10 minutes. Now: `sudo ctp-landing-deploy` |
| People, clusters, mailboxes or URLs in **ctp-common** | Nothing. The next timer run picks them up (pin a release with `COMMON_REF` in `/etc/ctp-landing.conf` if you prefer). |
| `deploy/deploy.sh` | Push. The next run uses the new version. |
| `deploy/install.sh` or `deploy/systemd/*` | Push, then on the server: `sudo git -C /opt/ctp-internal-landing-page pull && sudo bash /opt/ctp-internal-landing-page/deploy/install.sh` |
| Server settings (`/etc/ctp-landing.conf`) | Edit it on the server, then `sudo ctp-landing-deploy` |
| Apache configuration | `sudo apachectl configtest && sudo systemctl reload apache2` (RHEL: `httpd`) |

No auto-deploy wanted? Install with `sudo AUTO_DEPLOY=no bash /opt/ctp-internal-landing-page/deploy/install.sh` (or `sudo systemctl disable --now ctp-landing-deploy.timer`), and run `sudo ctp-landing-deploy` after each push.

### Checking and fixing

| Question | Command |
|---|---|
| What is live, and is the server behind GitHub? | `sudo ctp-landing-deploy --status` |
| What did the last automatic deploys say? | `journalctl -u ctp-landing-deploy -n 50` |
| When does the timer run next? | `systemctl list-timers ctp-landing-deploy.timer` |
| Undo a bad change | `git revert <commit>` and push (or fix forward), then `sudo ctp-landing-deploy` |

The page footer also shows the deployed time and both commit hashes.

| Symptom | Likely cause and fix |
|---|---|
| `git fetch failed` | The server cannot reach github.com. If NYU requires a proxy, set `HTTPS_PROXY` in `/etc/ctp-landing.conf`. If the repo is private, see below. |
| `Validation failed; the live site was NOT changed` | A mistake in `site/links.yaml`; the lines above the error say where. Fix, push, rerun. |
| `... already contains other files, so it was not touched` | `WEB_ROOT` points at a folder used by something else. See [Web server](#web-server). |
| Apache test page instead of the hub | Apache serves a different folder than `WEB_ROOT`. Check `DocumentRoot` (`grep -ri documentroot /etc/apache2/` on Ubuntu, `/etc/httpd/` on RHEL). |
| `403 Forbidden` | Ubuntu: check the `<Directory>` grant for `WEB_ROOT`. RHEL: SELinux labels; the script runs `restorecon` automatically, and if you moved `WEB_ROOT` outside `/var/www`, run `sudo semanage fcontext -a -t httpd_sys_content_t "/your/path(/.*)?" && sudo restorecon -R /your/path`. |
| Page loads but says shared data could not be loaded | `data/ctp-common/` is missing in the web folder. Run `sudo ctp-landing-deploy` and read its output. |
| Browser cannot connect at all | Firewall. Ubuntu: `sudo ufw allow 'Apache Full'`. RHEL: `sudo firewall-cmd --permanent --add-service=http --add-service=https && sudo firewall-cmd --reload` |

### Web server

- **Apache, this is the only site (default):** nothing to configure. Apache serves `/var/www/html` on both Ubuntu and RHEL, which is the default `WEB_ROOT`.
- **Apache, the server hosts other sites:** set `WEB_ROOT=/var/www/ctp-landing` in `/etc/ctp-landing.conf`, copy [`deploy/apache-ctp-landing.conf`](deploy/apache-ctp-landing.conf) to `/etc/apache2/sites-available/ctp-landing.conf` and run `sudo a2enmod headers && sudo a2ensite ctp-landing` (Ubuntu), or to `/etc/httpd/conf.d/ctp-landing.conf` (RHEL), set its `ServerName`, then `sudo apachectl configtest`, reload Apache, and `sudo ctp-landing-deploy`. That file also shows how to restrict access to campus/VPN addresses.
- **nginx:** Ubuntu's default root is already `/var/www/html`; on RHEL set `WEB_ROOT=/usr/share/nginx/html`. Or point a `server { root ...; }` block at your chosen folder.
- **HTTPS:** handled by the web server, not by this repo. If TLS is set up, the same `DocumentRoot` applies to the `:443` virtual host.

### Private repository

If `ctp-internal-landing-page` is private, give the server read-only access with a deploy key:

```bash
sudo ssh-keygen -t ed25519 -N "" -f /root/.ssh/ctp_landing_deploy
sudo cat /root/.ssh/ctp_landing_deploy.pub
# GitHub: repo Settings > Deploy keys > Add deploy key (read-only), paste the key
sudo tee -a /root/.ssh/config <<'EOF'
Host github.com
  IdentityFile /root/.ssh/ctp_landing_deploy
EOF
sudo git -C /opt/ctp-internal-landing-page remote set-url origin git@github.com:NYUAD-Core-Technology-Platforms/ctp-internal-landing-page.git
sudo ctp-landing-deploy
```

`ctp-common` is public and needs nothing.

---

## Repository layout

```
site/                         everything that is served
  links.yaml                  ← THE CONTENT. Edit this.
  index.html                  page shell (no content in it)
  assets/css/style.css        styling, following ctp-templates/shared/brand
  assets/js/app.js            reads links.yaml + ctp-common data, renders, filter box
  assets/js/vendor/           js-yaml (MIT), parses YAML in the browser
  assets/img/                 NYUAD logo, favicon, icons.svg (Lucide, ISC)
deploy/
  install.sh                  one-time server setup (with sudo)
  install-user.sh             one-time setup without sudo (~/public_html + crontab)
  deploy.sh                   every deploy (installed as `ctp-landing-deploy`)
  ctp-landing.conf.example    server settings template → /etc/ctp-landing.conf
  systemd/                    10-minute auto-deploy timer
  apache-ctp-landing.conf     only needed if the server hosts other sites
scripts/check.py              validates links.yaml (GitHub Actions + server)
.github/workflows/check.yml   runs the check on every push
```

Page features: a filter box (press `/` to focus, `Enter` opens the only match, `Esc` clears), works on phones, and greys out any link that is not set yet.
