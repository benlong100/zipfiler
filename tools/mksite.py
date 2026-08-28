#!/usr/bin/env python3
"""Build a single self-contained HTML file from web/index.html.

The site at web/ is what gets uploaded: a small index.html beside an assets
folder, which is what any host wants. A published preview cannot fetch those
files, so this flattens the whole thing into one document with every image as
a data URI, and drops the wrapper tags a publish supplies for itself.
"""
import base64, pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
src  = ROOT / "web" / "index.html"
out  = ROOT / "build" / "zipfiler-site.html"
html = src.read_text()

MIME = {".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png",
        ".gif": "image/gif", ".svg": "image/svg+xml"}

def inline(m):
    path = m.group(1)
    if path.startswith(("data:", "http:", "https:")):
        return m.group(0)
    f = (ROOT / "web" / path)
    if not f.exists():
        sys.exit(f"missing asset: {f}")
    b64 = base64.b64encode(f.read_bytes()).decode()
    return 'src="data:%s;base64,%s"' % (MIME[f.suffix.lower()], b64)

html = re.sub(r'src="([^"]+)"', inline, html)

# Keep the title, the font link and the stylesheet; drop the document wrapper,
# which the publish supplies.
title = re.search(r"<title>.*?</title>", html, re.S).group(0)
link  = re.search(r'<link rel="stylesheet" href="https://fonts\.googleapis[^>]*>', html).group(0)
style = re.search(r"<style>.*?</style>", html, re.S).group(0)
body  = re.search(r"<body>(.*)</body>", html, re.S).group(1)

out.parent.mkdir(exist_ok=True)
out.write_text("\n".join([title, link, style, body]))
print(f"{out}  {out.stat().st_size/1024:.0f} KB")
