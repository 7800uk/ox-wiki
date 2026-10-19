#!/usr/bin/env python3
"""Turn the vendored MediaWiki stylesheets into self-contained ones.

Each skin keeps the stylesheet exactly as MediaWiki's ResourceLoader served it,
under vendor/<name>/<name>.raw.css, beside the icons it references in
vendor/<name>/images/.  This script rewrites only the url() references -- icons
become data: URIs -- and writes css/<name>.css, so an exported page needs no
companion directory.

vendor/extras.raw.css (MediaWiki's diff and edit-font styles, shared by every
skin) is built the same way into css/mediawiki-extras.css.

Everything lands in css/, which is the only directory of stylesheets the
package installs; vendor/ is build-time only and no recipe needs to ship it.

The wiki logo is deliberately NOT baked in: ox-wiki.el writes a rule for it into
each page, from #+WIKI_LOGO or `org-wiki-logo'.  Wherever upstream points at
a project logo, this leaves a transparent pixel for that rule to override.

Run from anywhere:  python3 tools/build-css.py
"""

import base64
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

# A 1x1 transparent GIF, standing in for the project logo until ox-wiki.el
# writes the real rule.
BLANK = (
    "data:image/gif;base64,"
    "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"
)

MIME = {
    ".svg": "image/svg+xml",
    ".png": "image/png",
    ".gif": "image/gif",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
}

HEADER = """/*
 * {out} -- {title}, vendored.
 *
 * GENERATED FILE -- do not edit.  Run tools/build-css.py to rebuild it from
 * {src}, which is the ResourceLoader build of {modules}
 * exactly as en.wikipedia.org serves it.  The build changes only the url()
 * references: icons are inlined as data: URIs from the vendor/images/ beside
 * the source, and the project logo is left blank for ox-wiki.el to fill in.
 *
 * Upstream: {upstream}
 * Copyright the MediaWiki contributors.  GPL-2.0-or-later; see COPYING.
 *
 * Rules for Org's own markup live in css/org-wiki.css.  Put changes there.
 */
"""

# source stylesheet -> (output, title, modules, upstream)
BUILDS = [
    (
        "vendor/vector/vector.raw.css",
        "css/vector.css",
        'MediaWiki\'s "Vector legacy" (Vector 2010) skin',
        "`mediawiki.skins.legacy` and `skins.vector.styles.legacy`",
        "https://github.com/wikimedia/mediawiki-skins-Vector",
    ),
    (
        "vendor/monobook/monobook.raw.css",
        "css/monobook.css",
        "MediaWiki's MonoBook skin",
        "`mediawiki.skins.legacy` and `skins.monobook.styles`",
        "https://github.com/wikimedia/mediawiki-skins-MonoBook",
    ),
    (
        "vendor/extras.raw.css",
        "css/mediawiki-extras.css",
        "MediaWiki's diff and edit-font styles",
        "`mediawiki.diff.styles`, `mediawiki.editfont.styles` and `mediawiki.action.styles`",
        "https://gerrit.wikimedia.org/g/mediawiki/core",
    ),
]


def data_uri(path: pathlib.Path) -> str:
    payload = base64.b64encode(path.read_bytes()).decode("ascii")
    return f"data:{MIME[path.suffix.lower()]};base64,{payload}"


def build(src_rel, out_rel, title, modules, upstream) -> int:
    src = ROOT / src_rel
    out = ROOT / out_rel
    images = src.parent / "images"
    css = src.read_text(encoding="utf-8")
    missing = []

    def replace(match: "re.Match[str]") -> str:
        raw = match.group(1).strip().strip("\"'")
        if raw.startswith("data:"):
            return match.group(0)
        if "project-logos" in raw or "wordmark" in raw:
            return f'url("{BLANK}")'
        name = raw.split("?")[0].rsplit("/", 1)[-1]
        source = images / name
        if not source.exists():
            missing.append(raw)
            return match.group(0)
        return f'url("{data_uri(source)}")'

    css = re.sub(r"url\(([^)]*)\)", replace, css)
    if missing:
        print(
            f"{src_rel}: missing assets:\n  " + "\n  ".join(sorted(set(missing))),
            file=sys.stderr,
        )
        return 1

    out.parent.mkdir(parents=True, exist_ok=True)
    header = HEADER.format(
        out=out.name, title=title, src=src_rel, modules=modules, upstream=upstream
    )
    out.write_text(header + css, encoding="utf-8")
    print(f"wrote {out_rel} ({out.stat().st_size // 1024} KiB)")
    return 0


def main() -> int:
    return max(build(*spec) for spec in BUILDS)


if __name__ == "__main__":
    sys.exit(main())
