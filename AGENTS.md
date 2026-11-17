# AGENTS.md — guidance for coding agents

Read `README.md` first. This repo is the CTP internal landing page: a static hub served from a RHEL web server.

## Rules

| # | Rule | Why |
|---|------|-----|
| 1 | **Content lives in `site/links.yaml` only.** `index.html` is a shell; do not hard-code links or text in it or in `app.js`. | One place to edit. |
| 2 | **Never copy facts that exist in another CTP repo.** People, roles, emails, clusters, public URLs and mailboxes come from `ctp-common` (`common:` keys, `docs:` pages, or rendered from `data/*.yaml`). Only add a `url:` for something recorded nowhere else. | ctp-common is the single source of truth. |
| 3 | **Never put names in this repo.** Names are rendered from `ctp-common/data/people.yaml` by NetID. | Same rule as ctp-common. |
| 4 | **No secrets.** No passwords, tokens, chartfields, budget figures or Drive file IDs. | The repo may be public. |
| 5 | **Keep it build-free.** Plain HTML/CSS/JS; vendored libraries only. The server needs nothing but git, rsync, python3-pyyaml and a web server. | Easy deploys. |
| 6 | **Follow the CTP design system** (`ctp-templates/shared/brand/`): NYU Violet, squared corners, hairlines, no emoji, Lucide icons. | Brand consistency. |
| 7 | **After edits run** `python3 scripts/check.py --common-dir <path-to-ctp-common>/data` and preview with `cd site && python3 -m http.server`. | Same gate as CI and the server. |

## Deploy script invariants (`deploy/deploy.sh`)

- All logic stays inside `main()`; the script updates itself via `git reset` mid-run.
- Validation happens before publishing; a failure must leave `WEB_ROOT` untouched.
- Never write into a non-empty `WEB_ROOT` that lacks the `.ctp-landing` marker.
- Settings come from `/etc/ctp-landing.conf`; keep defaults in sync with `deploy/ctp-landing.conf.example`.
