#!/usr/bin/env python3
"""Validate site/links.yaml before it goes live.

    python3 scripts/check.py                          # structure only
    python3 scripts/check.py --common-dir ../ctp-common/data
                                                      # also check `common:` keys exist

Runs in GitHub Actions on every push and in deploy/deploy.sh on the server.
A failure on the server leaves the live site untouched.
Needs PyYAML (pip install pyyaml, or dnf install python3-pyyaml).
"""
import argparse
import pathlib
import re
import sys

import yaml

ROOT = pathlib.Path(__file__).resolve().parent.parent
LINKS = ROOT / "site" / "links.yaml"
ICONS = ROOT / "site" / "assets" / "img" / "icons.svg"
TARGETS = ("url", "common", "docs", "repo", "pages", "ref")

errors, warnings = [], []


def err(where, msg):
    errors.append(f"{where}: {msg}")


def warn(where, msg):
    warnings.append(f"{where}: {msg}")


def lookup(obj, dotted):
    for key in dotted.split("."):
        if not isinstance(obj, dict) or key not in obj:
            return None
        obj = obj[key]
    return obj


def check_link(where, link, *, require_title, require_target, icons, ids, common):
    if not isinstance(link, dict):
        err(where, "must be a mapping (key: value lines)")
        return
    if require_title and not link.get("title"):
        err(where, "missing title")
    found = [t for t in TARGETS if t in link]
    if len(found) > 1:
        err(where, f"use only one of {', '.join(TARGETS)} (found {', '.join(found)})")
    if require_target and not found:
        err(where, f"needs one of {', '.join(TARGETS)}")
    if "url" in link:
        url = link["url"]
        if url in (None, ""):
            warn(where, "url is empty, shown as 'Link not set'")
        elif not re.match(r"^(https?://|mailto:)", str(url)):
            err(where, f"url must start with http://, https:// or mailto: (got {url!r})")
    if "ref" in link and link["ref"] not in ids:
        err(where, f"ref {link['ref']!r} does not match any id")
    if "common" in link and common is not None and lookup(common, str(link["common"])) is None:
        err(where, f"common key {link['common']!r} not found in ctp-common data/links.yaml")
    if link.get("icon") and icons and link["icon"] not in icons:
        err(where, f"icon {link['icon']!r} not in assets/img/icons.svg (available: {', '.join(sorted(icons))})")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--common-dir", help="path to ctp-common/data, to verify common: keys")
    args = ap.parse_args()

    try:
        cfg = yaml.safe_load(LINKS.read_text(encoding="utf-8")) or {}
    except yaml.YAMLError as e:
        print(f"ERROR: {LINKS.relative_to(ROOT)} is not valid YAML:\n{e}")
        return 1

    common = None
    if args.common_dir:
        p = pathlib.Path(args.common_dir) / "links.yaml"
        try:
            common = yaml.safe_load(p.read_text(encoding="utf-8")) or {}
        except Exception as e:  # noqa: BLE001
            err("ctp-common", f"cannot read {p}: {e}")

    icons = set(re.findall(r'<symbol id="i-([\w-]+)"', ICONS.read_text(encoding="utf-8"))) if ICONS.exists() else set()

    for key in ("github_org", "pages_base", "docs_site", "this_repo"):
        if not lookup(cfg, f"sources.{key}"):
            err("sources", f"missing {key}")

    every = list(cfg.get("highlights") or [])
    for s in cfg.get("sections") or []:
        every += (s or {}).get("links") or []
    ids = {}
    for link in every:
        if isinstance(link, dict) and link.get("id"):
            if link["id"] in ids:
                err(f"id {link['id']!r}", "used more than once")
            ids[link["id"]] = link

    opts = dict(icons=icons, ids=ids, common=common)
    for i, h in enumerate(cfg.get("highlights") or []):
        check_link(f"highlights[{i + 1}] {h.get('title', '') if isinstance(h, dict) else ''}", h,
                   require_title=True, require_target=True, **opts)
    for si, s in enumerate(cfg.get("sections") or []):
        if not isinstance(s, dict) or not s.get("title"):
            err(f"sections[{si + 1}]", "missing title")
            continue
        for li, link in enumerate(s.get("links") or []):
            check_link(f"{s['title']} > {link.get('title', li + 1) if isinstance(link, dict) else li + 1}", link,
                       require_title=True, require_target=True, **opts)
    for i, st in enumerate(cfg.get("first_steps") or []):
        if not isinstance(st, dict) or not st.get("text"):
            err(f"first_steps[{i + 1}]", "missing text")
            continue
        check_link(f"first_steps[{i + 1}]", st, require_title=False, require_target=False, **opts)
    for i, m in enumerate(cfg.get("mailboxes") or []):
        if not isinstance(m, dict) or not m.get("common") or not m.get("label"):
            err(f"mailboxes[{i + 1}]", "needs common and label")
            continue
        check_link(f"mailboxes[{i + 1}]", m, require_title=False, require_target=True, **opts)
    for i, w in enumerate(cfg.get("where_to_edit") or []):
        if not isinstance(w, dict) or not w.get("change") or not w.get("file"):
            err(f"where_to_edit[{i + 1}]", "needs change and file")
            continue
        check_link(f"where_to_edit[{i + 1}]", w, require_title=False, require_target=False, **opts)

    for w in warnings:
        print(f"  warning  {w}")
    for e in errors:
        print(f"  ERROR    {e}")
    n = len(every)
    if errors:
        print(f"links.yaml: {len(errors)} error(s)")
        return 1
    print(f"links.yaml OK: {n} links, {len(warnings)} warning(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
