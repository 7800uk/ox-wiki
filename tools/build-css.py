#!/usr/bin/env python3
"""Turn the vendored MediaWiki stylesheets into self-contained ones.

Each skin keeps the stylesheet exactly as MediaWiki's ResourceLoader served it,
under vendor/<name>/<name>.raw.css, beside the icons it references in
vendor/<name>/images/.  This script rewrites only the url() references -- icons
become data: URIs -- and writes css/<name>.css, so an exported page needs no
companion directory.

vendor/extras.raw.css (MediaWiki's diff and edit-font styles, shared by every
skin) is built the same way into css/mediawiki-extras.css.

Icons are found by file name.  An icon ResourceLoader generates itself -- a
load.php?modules=...&image=NAME URL, which is how Citizen serves its icons --
is looked for as NAME.svg.

Web fonts are dropped rather than inlined: Citizen points five @font-face rules
at each Roboto Flex file, so inlining them would add the best part of a
megabyte to every exported page.  Each rule keeps its local() sources, so the
font is still used where it is installed, and falls back to the skin's own
system font stack where it is not.

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
 * exactly as {site} serves it.  The build changes only the url()
 * references: icons are inlined as data: URIs from the vendor/images/ beside
 * the source, web fonts are dropped, and the project logo is left blank for
 * ox-wiki.el to fill in.
 *
 * Upstream: {upstream}
 * {copyright}
 *
 * Rules for Org's own markup live in css/org-wiki.css.  Put changes there.
 */
"""

MEDIAWIKI = "Copyright the MediaWiki contributors.  GPL-2.0-or-later; see COPYING."

BUILDS = [
    dict(
        src="vendor/vector/vector.raw.css",
        out="css/vector.css",
        title='MediaWiki\'s "Vector legacy" (Vector 2010) skin',
        modules="`mediawiki.skins.legacy` and `skins.vector.styles.legacy`",
        site="en.wikipedia.org",
        upstream="https://github.com/wikimedia/mediawiki-skins-Vector",
        copyright=MEDIAWIKI,
    ),
    dict(
        src="vendor/monobook/monobook.raw.css",
        out="css/monobook.css",
        title="MediaWiki's MonoBook skin",
        modules="`mediawiki.skins.legacy` and `skins.monobook.styles`",
        site="en.wikipedia.org",
        upstream="https://github.com/wikimedia/mediawiki-skins-MonoBook",
        copyright=MEDIAWIKI,
    ),
    dict(
        src="vendor/citizen/citizen.raw.css",
        out="css/citizen.css",
        title="the Citizen skin",
        modules="`skins.citizen.styles`, `skins.citizen.codex.styles`,\n"
        " * `skins.citizen.icons` and `skins.citizen.tokens.new`",
        site="starcitizen.tools",
        upstream="https://github.com/StarCitizenTools/mediawiki-skins-Citizen",
        copyright="Copyright the Citizen contributors.  GPL-3.0-or-later; see\n"
        " * vendor/citizen/LICENSE.",
    ),
    dict(
        src="vendor/extras.raw.css",
        out="css/mediawiki-extras.css",
        title="MediaWiki's diff and edit-font styles",
        modules="`mediawiki.diff.styles`, `mediawiki.editfont.styles` and `mediawiki.action.styles`",
        site="en.wikipedia.org",
        upstream="https://gerrit.wikimedia.org/g/mediawiki/core",
        copyright=MEDIAWIKI,
    ),
]

# A web font source inside an @font-face src list: url(...) and its format().
FONT_SOURCE = re.compile(
    r"""\s*,?\s*url\([^)]*\.(?:woff2?|ttf|otf|eot)(?:\?[^)]*)?\)"""
    r"""(?:\s*format\([^)]*\))?"""
)


def drop_fonts(css: str) -> str:
    """Strip web font files out of every @font-face rule, keeping local().
    A rule left with no source at all is removed."""

    def rule(match: "re.Match[str]") -> str:
        body = FONT_SOURCE.sub("", match.group(1))
        body = re.sub(r"src:\s*,\s*", "src:", body)
        if not re.search(r"src:\s*local\(", body):
            return ""
        return "@font-face{" + body + "}"

    return re.sub(r"@font-face\{([^}]*)\}", rule, css)


def data_uri(path: pathlib.Path) -> str:
    payload = base64.b64encode(path.read_bytes()).decode("ascii")
    return f"data:{MIME[path.suffix.lower()]};base64,{payload}"


def icon_name(raw: str) -> str:
    """The file an icon URL refers to, under the vendored images/."""
    path, _, query = raw.partition("?")
    image = re.search(r"(?:^|&)image=([^&]+)", query)
    if path.endswith("load.php") and image:
        return image.group(1) + ".svg"
    return path.rsplit("/", 1)[-1]


def build(src, out, title, modules, site, upstream, copyright) -> int:
    src_rel, out_rel = src, out
    src = ROOT / src_rel
    out = ROOT / out_rel
    images = src.parent / "images"
    css = drop_fonts(src.read_text(encoding="utf-8"))
    missing = []

    def replace(match: "re.Match[str]") -> str:
        raw = match.group(1).strip().strip("\"'")
        if raw.startswith("data:"):
            return match.group(0)
        if "project-logos" in raw or "wordmark" in raw:
            return f'url("{BLANK}")'
        source = images / icon_name(raw)
        if not source.exists():
            missing.append(raw)
            return match.group(0)
        return f'url("{data_uri(source)}")'

    # A data: URI may itself contain parentheses, so a quoted one is matched
    # whole rather than up to its first ")".
    css = re.sub(r"""url\(("[^"]*"|'[^']*'|[^)]*)\)""", replace, css)
    if missing:
        print(
            f"{src_rel}: missing assets:\n  " + "\n  ".join(sorted(set(missing))),
            file=sys.stderr,
        )
        return 1

    out.parent.mkdir(parents=True, exist_ok=True)
    header = HEADER.format(
        out=out.name,
        title=title,
        src=src_rel,
        modules=modules,
        site=site,
        upstream=upstream,
        copyright=copyright,
    )
    out.write_text(header + css, encoding="utf-8")
    print(f"wrote {out_rel} ({out.stat().st_size // 1024} KiB)")
    return 0


def main() -> int:
    return max(build(**spec) for spec in BUILDS)


if __name__ == "__main__":
    sys.exit(main())
