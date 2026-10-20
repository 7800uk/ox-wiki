#!/usr/bin/env python3
"""Turn the vendored ResourceLoader modules into the scripts a skin ships.

A skin with scripts keeps them exactly as MediaWiki's ResourceLoader served
them, as a run of mw.loader.impl() calls under vendor/<name>/<name>.raw.js.
They run on js/mediawiki.js, the hand-written stand-in for the client runtime
a wiki would provide, so this script does not touch the code at all.

What it does change is a module's generated configuration.  ResourceLoader
builds some packageFiles -- config.json and the like -- from the serving
wiki's settings rather than from the skin's repository, so the vendored copy
carries that wiki's choices.  OVERRIDES puts back the skin's own defaults, and
the build fails if a file it expects to replace is not there, so a refreshed
upstream cannot drop an override silently.

Everything lands in js/, which, like css/, is installed with the package;
vendor/ is build-time only.

Run from anywhere:  python3 tools/build-js.py
"""

import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

HEADER = """/*
 * {out} -- {title}, vendored.
 *
 * GENERATED FILE -- do not edit.  Run tools/build-js.py to rebuild it from
 * {src}, which is the ResourceLoader build of {modules}
 * exactly as {site} serves it.  The build changes only
 * configuration ResourceLoader generates from the serving wiki's settings,
 * which is put back to the skin's defaults:
 *
{overrides}
 *
 * The modules run on js/mediawiki.js, which must be loaded first.
 *
 * Upstream: {upstream}
 * {copyright}
 */
"""

BUILDS = [
    dict(
        src="vendor/citizen/citizen.raw.js",
        out="js/citizen.js",
        title="the Citizen skin's scripts",
        modules="`skins.citizen.scripts`,\n"
        " * `skins.citizen.toc`, `skins.citizen.preferences`, `skins.citizen.share`\n"
        " * and MediaWiki's `vue`",
        site="starcitizen.tools",
        upstream="https://github.com/StarCitizenTools/mediawiki-skins-Citizen",
        copyright="Copyright the Citizen contributors, GPL-3.0-or-later (see\n"
        " * vendor/citizen/LICENSE); `vue` is MediaWiki's, GPL-2.0-or-later, around\n"
        " * Vue.js, MIT.",
        # packageFile -> the value Citizen's skin.json gives it by default
        overrides={
            "resources/skins.citizen.preferences/config.json": {
                "wgCitizenThemeDefault": "auto"
            },
        },
    ),
]


def override(js: str, name: str, value: object) -> "tuple[str, int]":
    """Replace every packageFile NAME's JSON value in JS with VALUE."""
    decoder = json.JSONDecoder()
    key = json.dumps(name) + ":"
    out, count, pos = [], 0, 0
    for match in re.finditer(re.escape(key), js):
        start = match.end()
        if start < pos:
            continue
        _, end = decoder.raw_decode(js, start)
        out.append(js[pos:start])
        out.append(json.dumps(value, separators=(",", ":")))
        pos = end
        count += 1
    out.append(js[pos:])
    return "".join(out), count


def build(src, out, title, modules, site, upstream, copyright, overrides) -> int:
    src_rel, out_rel = src, out
    js = (ROOT / src_rel).read_text(encoding="utf-8")
    for name, value in overrides.items():
        js, count = override(js, name, value)
        if count == 0:
            print(f"{src_rel}: no packageFile {name} to override", file=sys.stderr)
            return 1

    out = ROOT / out_rel
    out.parent.mkdir(parents=True, exist_ok=True)
    header = HEADER.format(
        out=out.name,
        title=title,
        src=src_rel,
        modules=modules,
        site=site,
        overrides="\n".join(
            f" *   {name} = {json.dumps(value)}" for name, value in overrides.items()
        ),
        upstream=upstream,
        copyright=copyright,
    )
    out.write_text(header + js, encoding="utf-8")
    print(f"wrote {out_rel} ({out.stat().st_size // 1024} KiB)")
    return 0


def main() -> int:
    return max(build(**spec) for spec in BUILDS)


if __name__ == "__main__":
    sys.exit(main())
