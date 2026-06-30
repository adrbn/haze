#!/usr/bin/env python3
"""Generate a signed Sparkle appcast.xml for a single Haze release.

Shells out to Sparkle's `sign_update` for the EdDSA signature, then emits a
one-item appcast. Kept as a script (rather than inline in the workflow) so it
can be unit-tested and run locally with the same inputs CI uses.

The app's SUFeedURL points at the *latest* GitHub release asset
(`releases/latest/download/appcast.xml`), so one fresh item per release is all
Sparkle needs to detect and present an update.
"""
from __future__ import annotations

import argparse
import html
import re
import subprocess
import sys


def build_notes(notes_file: str | None) -> str:
    """One commit subject per line -> an escaped <li> list. Escaping matters:
    commit messages are untrusted HTML the changelog renders verbatim."""
    items: list[str] = []
    if notes_file:
        with open(notes_file, encoding="utf-8") as handle:
            for line in handle:
                line = line.strip()
                if line:
                    items.append(f"<li>{html.escape(line)}</li>")
    return "".join(items) or "<li>Maintenance and improvements.</li>"


def sign(sign_update: str, key_file: str, archive: str) -> str:
    """Return the `sparkle:edSignature="..." length="..."` enclosure attributes."""
    out = subprocess.run(
        [sign_update, "--ed-key-file", key_file, archive],
        capture_output=True, text=True, check=True,
    ).stdout.strip()
    match = re.search(r'(sparkle:edSignature="[^"]+"\s+length="[^"]+")', out)
    if not match:
        sys.exit(f"make_appcast: could not parse sign_update output: {out!r}")
    return match.group(1)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sign-update", required=True, help="path to Sparkle's sign_update")
    parser.add_argument("--key-file", required=True, help="EdDSA private key file (base64 seed)")
    parser.add_argument("--zip", required=True, help="the Haze.zip to sign")
    parser.add_argument("--short", required=True, help="marketing version, e.g. 0.1.0")
    parser.add_argument("--build", required=True, help="CFBundleVersion (monotonic build number)")
    parser.add_argument("--url", required=True, help="download URL of the zip")
    parser.add_argument("--pubdate", required=True, help="RFC-822 publication date")
    parser.add_argument("--min-system", default="15.0")
    parser.add_argument("--notes-file", default=None, help="commit subjects, one per line")
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    enclosure_attrs = sign(args.sign_update, args.key_file, args.zip)
    body = f"<h2>Haze {html.escape(args.short)}</h2><ul>{build_notes(args.notes_file)}</ul>"
    short = html.escape(args.short)
    url = html.escape(args.url, quote=True)

    xml = f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Haze</title>
    <description>Haze updates</description>
    <language>en</language>
    <item>
      <title>Haze {short}</title>
      <pubDate>{args.pubdate}</pubDate>
      <sparkle:version>{args.build}</sparkle:version>
      <sparkle:shortVersionString>{short}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{args.min_system}</sparkle:minimumSystemVersion>
      <description><![CDATA[{body}]]></description>
      <enclosure url="{url}" {enclosure_attrs} type="application/octet-stream" />
    </item>
  </channel>
</rss>
"""
    with open(args.out, "w", encoding="utf-8") as handle:
        handle.write(xml)
    print(f"make_appcast: wrote {args.out} (Haze {args.short}, build {args.build})")


if __name__ == "__main__":
    main()
