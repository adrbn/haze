"""Regenerates the README art in assets/: gradient buttons, feature cards and the preset swatch book.

    python3 assets/make_svgs.py

Every colour is a real preset, read from Sources/HazeKit/Gradient/*Presets.swift, so the art follows the app.
The gradients are soft radial pools drifting over the palette's last colour: no filters, only SMIL
(<animateTransform>, <animate>), so they move inside GitHub's <img> sandbox (no scripts, no webfonts).
They show each palette, not the Metal shader itself.

The demo at the top of the README (demo.webp) is a screen recording (1440x900, 8 s), cut to 20 fps, 1120 px wide
(shown at 560, so sharp on Retina), with its corners rounded in the alpha channel:

    ffmpeg -i clip.mp4 -vf "fps=20,scale=1120:700:flags=lanczos,format=rgba,geq=r='r(X,Y)':g='g(X,Y)':b='b(X,Y)':\
a='255*clip(22.5-hypot(max(abs(X-W/2+0.5)-(W/2-22),0),max(abs(Y-H/2+0.5)-(H/2-22),0)),0,1)'" \
        -c:v libwebp -q:v 72 -compression_level 6 -loop 0 -an assets/demo.webp
"""
import math
import re
from pathlib import Path

OUT = Path(__file__).parent
SRC = OUT.parent / "Sources/HazeKit/Gradient"
FONT = "-apple-system,BlinkMacSystemFont,'SF Pro Display','Helvetica Neue',Arial,sans-serif"
PANEL, EDGE = "#100c0b", "#ffffff1f"

# --- text metrics (Helvetica widths per 1000 em: close enough to SF to place things) ------------------------
_LOW = "abcdefghijklmnopqrstuvwxyz"
REG = dict(zip(_LOW, [556, 556, 500, 556, 556, 278, 556, 556, 222, 222, 500, 222, 833, 556, 556, 556, 556, 333,
                      500, 278, 556, 500, 722, 500, 500, 500]))
BOLD = dict(zip(_LOW, [556, 611, 556, 611, 556, 333, 611, 611, 278, 278, 556, 278, 889, 611, 611, 611, 611, 389,
                       556, 333, 611, 556, 778, 556, 556, 500]))
_CAPS = [722, 722, 722, 722, 667, 611, 778, 722, 278, 556, 722, 611, 833, 722, 778, 667, 778, 722, 667, 611, 722,
         667, 944, 667, 667, 611]
for _t in (REG, BOLD):
    _t.update(zip(_LOW.upper(), _CAPS))
    _t.update({c: 556 for c in "0123456789"})
    _t.update({" ": 278, ".": 278, ",": 278, "-": 333, "&": 722, ":": 333, "%": 889})


def width(s, size, bold=False):
    t = BOLD if bold else REG
    return sum(t.get(c, 600) for c in s) / 1000 * size


def esc(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def text(x, y, s, size, fill="#fff", weight=400, anchor=None, op=None, extra=""):
    a = f' text-anchor="{anchor}"' if anchor else ""
    o = f' fill-opacity="{op}"' if op is not None else ""
    return (f'<text x="{x:g}" y="{y:g}" font-family="{FONT}" font-size="{size:g}" font-weight="{weight}" '
            f'fill="{fill}"{o}{a}{extra}>{esc(s)}</text>')


def svg(w, h, body, title, defs=""):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}" role="img">'
            f'<title>{esc(title)}</title>{f"<defs>{defs}</defs>" if defs else ""}{body}</svg>\n')


# --- the presets, from the Swift source ---------------------------------------------------------------------
def presets(fname):
    """(name, colours) for each preset in the file, in the app's order."""
    out = []
    for block in re.split(r"Preset\(\s*\n?\s*id:", (SRC / fname).read_text())[1:]:
        name = re.search(r'name: "([^"]+)"', block).group(1)
        out.append((name, re.findall(r'\.hex\("(#[0-9A-Fa-f]{6})"\)', block)))
    return out


FLUID = presets("ShaderGradientPresets.swift")
CLASSIC = presets("GradientPresets.swift")
P = dict(CLASSIC + FLUID)


# --- the haze: soft pools drifting over the palette's last colour -------------------------------------------
def haze(uid, cols, x, y, w, h, dur=16.0, delay=0.0, still=False):
    """Returns (defs, body). Each colour but the last is a radial pool on its own slow loop, spread around the
    loop so the pools stay apart. still=True draws the first frame only."""
    base, pools = cols[-1], cols[:-1]
    defs, body = [], [f'<rect x="{x:g}" y="{y:g}" width="{w:g}" height="{h:g}" fill="{base}"/>']
    r = max(w, h) * 0.8
    for i, c in enumerate(pools):
        defs.append(f'<radialGradient id="{uid}{i}"><stop offset="0" stop-color="{c}"/>'
                    f'<stop offset=".45" stop-color="{c}" stop-opacity=".6"/>'
                    f'<stop offset="1" stop-color="{c}" stop-opacity="0"/></radialGradient>')
        phi = i * 2 * math.pi / len(pools) + 0.6
        loop = [(x + w * (0.5 + 0.36 * math.cos(t + phi)), y + h * (0.5 + 0.3 * math.sin(t + phi) * (1 if i % 2 else -1)))
                for t in (k * 2 * math.pi / 24 for k in range(25))]
        anim = "" if still else (
            f'<animateTransform attributeName="transform" type="translate" '
            f'values="{";".join(f"{px:.1f} {py:.1f}" for px, py in loop)}" dur="{dur:g}s" '
            f'begin="-{delay + i * dur / len(pools):.2f}s" repeatCount="indefinite"/>')
        px, py = loop[0]
        body.append(f'<circle r="{r:.0f}" fill="url(#{uid}{i})" transform="translate({px:.1f} {py:.1f})">{anim}</circle>')
    return "".join(defs), "".join(body)


# --- buttons: a pill of a real preset, lit from above like the app's glass -----------------------------------
def button(name, label, preset):
    cols = P[preset]
    tw = width(label, 14.5, True)
    w, h = round(tw + 44), 40
    stops = "".join(f'<stop offset="{i / (len(cols) - 1):.2f}" stop-color="{c}"/>' for i, c in enumerate(cols))
    defs = (f'<linearGradient id="g" x1="0" y1="0" x2="1" y2="0">{stops}'
            f'<animateTransform attributeName="gradientTransform" type="translate" values="-.25 0;.25 0;-.25 0" '
            f'dur="9s" repeatCount="indefinite"/></linearGradient>'
            f'<linearGradient id="l" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff" stop-opacity=".3"/>'
            f'<stop offset=".5" stop-color="#fff" stop-opacity="0"/></linearGradient>')
    rx = h / 2 - .5
    body = (f'<rect x=".5" y=".5" width="{w - 1}" height="{h - 1}" rx="{rx}" fill="url(#g)"/>'
            f'<rect x=".5" y=".5" width="{w - 1}" height="{h - 1}" rx="{rx}" fill="#000" fill-opacity=".22"/>'
            f'<rect x=".5" y=".5" width="{w - 1}" height="{h - 1}" rx="{rx}" fill="url(#l)" stroke="#fff" '
            f'stroke-opacity=".35"/>'
            + text(22, 26, label, 14.5, "#000", 600, op=.25, extra=f' textLength="{tw:.0f}" lengthAdjust="spacing"')
            + text(22, 25, label, 14.5, "#fff", 600, extra=f' textLength="{tw:.0f}" lengthAdjust="spacing"'))
    (OUT / f"btn-{name}.svg").write_text(svg(w, h, body, label, defs))


# --- cards: a small Mac screen, each telling one feature -----------------------------------------------------
CW, CH = 400, 250


def card(name, title, defs, body):
    clip = f'<clipPath id="c"><rect width="{CW}" height="{CH}" rx="22"/></clipPath>'
    out = (f'<g clip-path="url(#c)">{body}</g>'
           f'<rect x=".5" y=".5" width="{CW - 1}" height="{CH - 1}" rx="21.5" fill="none" stroke="{EDGE}"/>')
    (OUT / f"card-{name}.svg").write_text(svg(CW, CH, out, title, clip + defs))


def menubar(clock=True):
    bits = "".join(f'<rect x="{x}" y="6" width="{w}" height="4" rx="2" fill="#fff" fill-opacity=".75"/>'
                   for x, w in ((26, 22), (54, 16), (76, 14), (96, 18)))
    right = text(CW - 12, 12, "9:41", 9, weight=600, anchor="end", op=.9) if clock else ""
    return (f'<rect width="{CW}" height="16" fill="#000" fill-opacity=".18"/>'
            f'<circle cx="13" cy="8" r="3.2" fill="#fff" fill-opacity=".9"/>{bits}{right}')


def dock():
    n, s, gap = 8, 20, 7
    w = n * s + (n - 1) * gap + 20
    x0 = (CW - w) / 2
    icons = "".join(f'<rect x="{x0 + 10 + k * (s + gap):g}" y="{CH - 34}" width="{s}" height="{s}" rx="5.5" '
                    f'fill="#fff" fill-opacity="{.82 if k % 3 == 0 else .62}"/>' for k in range(n))
    return (f'<rect x="{x0:g}" y="{CH - 41}" width="{w}" height="34" rx="11" fill="#fff" fill-opacity=".16" '
            f'stroke="#fff" stroke-opacity=".28"/>{icons}')


def glass(x, y, w, h, rx=14, op=.42):
    return (f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="#0b0910" fill-opacity="{op}" '
            f'stroke="#fff" stroke-opacity=".18"/>')


def pill(x, y, label, op_values=None, dur=8):
    w = width(label, 11, True) + 20
    anim = (f'<animate attributeName="opacity" values="{op_values}" keyTimes="0;.42;.5;.92;1" dur="{dur}s" '
            f'repeatCount="indefinite"/>' if op_values else "")
    return (f'<g>{anim}<rect x="{x}" y="{y}" width="{w:.0f}" height="22" rx="11" fill="#000" fill-opacity=".35" '
            f'stroke="#fff" stroke-opacity=".2"/>{text(x + 10, y + 15, label, 11, weight=600)}</g>')


def card_wallpaper():
    d, b = haze("h", P["Lava"], 0, 0, CW, CH, 14)
    card("wallpaper", "A live gradient wallpaper behind the menu bar and the Dock", d, b + menubar() + dock())


def card_gradients():
    d, b = haze("h", P["Iris"], 0, 0, CW, CH, 12)
    x, y, w = 220, 34, 160
    dots = "".join(f'<circle cx="{x + 22 + k * 24}" cy="{y + 30}" r="8" fill="{c}" stroke="#fff" stroke-opacity=".6"/>'
                   for k, c in enumerate(P["Iris"]))
    rows = []
    for k, (label, a, z, dur) in enumerate((("Speed", .3, .8, 7), ("Blur", .7, .25, 9), ("Grain", .45, .6, 11))):
        ty, tx, tw = y + 72 + k * 44, x + 16, w - 32
        vals = f"{tx + tw * a:.1f};{tx + tw * z:.1f};{tx + tw * a:.1f}"
        ws = f"{tw * a:.1f};{tw * z:.1f};{tw * a:.1f}"
        spline = 'calcMode="spline" keyTimes="0;.5;1" keySplines=".45 0 .55 1;.45 0 .55 1"'
        rows.append(text(tx, ty - 9, label, 11, weight=600, op=.85)
                    + f'<rect x="{tx}" y="{ty}" width="{tw}" height="4" rx="2" fill="#fff" fill-opacity=".25"/>'
                    f'<rect x="{tx}" y="{ty}" width="{tw * a:.1f}" height="4" rx="2" fill="#fff" fill-opacity=".85">'
                    f'<animate attributeName="width" values="{ws}" dur="{dur}s" {spline} repeatCount="indefinite"/></rect>'
                    f'<circle cx="{tx + tw * a:.1f}" cy="{ty + 2}" r="7" fill="#fff">'
                    f'<animate attributeName="cx" values="{vals}" dur="{dur}s" {spline} repeatCount="indefinite"/></circle>')
    card("gradients", "The gradient editor: palette, speed, blur and grain over a live gradient", d,
         b + glass(x, y, w, 182) + text(x + 16, y + 14, "Colors", 11, weight=600, op=.85) + dots + "".join(rows))


def card_screensaver():
    d, b = haze("h", P["Dusk"], 0, 0, CW, CH, 14)
    fade = 'values="1;1;0;0;1" keyTimes="0;.42;.5;.92;1" dur="8s" repeatCount="indefinite"'
    chrome = f'<g><animate attributeName="opacity" {fade}/>{menubar()}{dock()}</g>'
    card("screensaver", "The same gradient as the wallpaper, then as the screensaver", d,
         b + chrome + pill(14, 26, "Wallpaper", "1;1;0;0;1") + pill(14, 26, "Screensaver", "0;0;1;1;0"))


def card_light():
    d, b = haze("h", P["Tide"], 0, 0, CW, CH, 10)
    kt = 'keyTimes="0;.12;.3;.7;.88;1" dur="9s" repeatCount="indefinite"'
    window = (f'<g transform="translate({CW} 0)"><animateTransform attributeName="transform" type="translate" '
              f'values="{CW} 0;{CW} 0;0 0;0 0;{CW} 0;{CW} 0" {kt}/>'
              f'<rect x="-1" y="16" width="{CW + 2}" height="{CH - 16}" fill="#1b1d22"/>'
              f'<rect x="-1" y="16" width="{CW + 2}" height="26" fill="#25282e"/>'
              + "".join(f'<circle cx="{16 + k * 14}" cy="29" r="4.5" fill="#fff" fill-opacity=".22"/>' for k in range(3))
              + "".join(f'<rect x="24" y="{62 + k * 22}" width="{w}" height="7" rx="3.5" fill="#fff" fill-opacity=".1"/>'
                        for k, w in enumerate((220, 300, 260, 180, 280, 140, 240)))
              + '</g>')
    bars = []
    for k, (hi, dur) in enumerate(((10, .9), (14, 1.1), (8, .8), (12, 1.3))):
        on = f"{hi};{hi * .45:.1f};{hi}"
        bars.append(f'<rect x="{CW - 96 + k * 6}" y="0" width="3.5" height="{hi}" rx="1.75" fill="#fff" '
                    f'transform="translate(0 {50}) scale(1 -1)">'
                    f'<animate attributeName="height" values="{on}" dur="{dur}s" repeatCount="indefinite"/>'
                    f'<animate attributeName="opacity" values="1;1;.35;.35;1;1" {kt}/></rect>')
    status = (f'<rect x="{CW - 106}" y="26" width="94" height="30" rx="15" fill="#000" fill-opacity=".45" '
              f'stroke="#fff" stroke-opacity=".2"/>' + "".join(bars)
              + f'<g><animate attributeName="opacity" values="1;1;0;0;1;1" {kt}/>'
              + text(CW - 66, 45, "rendering", 10.5, weight=600) + "</g>"
              + f'<g opacity="0"><animate attributeName="opacity" values="0;0;1;1;0;0" {kt}/>'
              + text(CW - 66, 45, "paused", 10.5, weight=600) + "</g>")
    card("light", "A window covers the desktop and the gradient stops rendering", d,
         b + window + menubar() + status)


def card_picker():
    picks = ["Halo", "Tide", "Magma"]
    defs, layers = [], []
    n = len(picks)
    for k, name in enumerate(picks):
        d, b = haze(f"h{k}", P[name], 0, 0, CW, CH, 14)
        defs.append(d)
        vals = ";".join("1" if j == k else "0" for j in range(n)) + (";1" if k == 0 else ";0")
        layers.append(f'<g><animate attributeName="opacity" values="{vals}" dur="{n * 3}s" calcMode="discrete" '
                      f'repeatCount="indefinite"/>{b}</g>')
    px, py, pw = 196, 24, 190
    grid_names = ["Halo", "Tide", "Magma", "Iris", "Coral", "Aurora"]
    tiles, tw, th = [], 52, 34
    for i, name in enumerate(grid_names):
        tx, ty = px + 12 + (i % 3) * (tw + 9), py + 52 + (i // 3) * (th + 9)
        cols = P[name]
        stops = "".join(f'<stop offset="{j / (len(cols) - 1):.2f}" stop-color="{c}"/>' for j, c in enumerate(cols))
        defs.append(f'<linearGradient id="t{i}" x1="0" y1="0" x2="1" y2="1">{stops}</linearGradient>')
        tiles.append(f'<rect x="{tx}" y="{ty}" width="{tw}" height="{th}" rx="7" fill="url(#t{i})"/>')
    ring_vals = ";".join(f"{px + 12 + k * (tw + 9) - 3} {py + 49}" for k in range(n))
    ring = (f'<rect width="{tw + 6}" height="{th + 6}" rx="9" fill="none" stroke="#fff" stroke-width="2">'
            f'<animateTransform attributeName="transform" type="translate" values="{ring_vals}" dur="{n * 3}s" '
            f'calcMode="discrete" repeatCount="indefinite"/></rect>')
    names = "".join(
        f'<g opacity="{1 if k == 0 else 0}"><animate attributeName="opacity" '
        f'values="{";".join("1" if j == k else "0" for j in range(n))}" dur="{n * 3}s" calcMode="discrete" '
        f'repeatCount="indefinite"/>{text(px + 12, py + 33, name, 12, weight=700)}</g>' for k, name in enumerate(picks))
    panel = (glass(px, py, pw, 164, 14, .55) + text(px + 12, py + 17, "Now playing", 9.5, weight=600, op=.6)
             + names + "".join(tiles) + ring
             + f'<rect x="{px + 12}" y="{py + 139}" width="{pw - 24}" height="14" rx="7" fill="#fff" fill-opacity=".12"/>'
             + f'<circle cx="{px + 22}" cy="{py + 146}" r="3" fill="none" stroke="#fff" stroke-opacity=".6"/>')
    glyph = f'<rect x="{CW - 70}" y="2" width="20" height="12" rx="4" fill="#fff" fill-opacity=".35"/>'
    card("picker", "The menu-bar picker: pick a preset and the desktop follows", "".join(defs),
         "".join(layers) + menubar() + glyph + panel)


def card_lock():
    d, b = haze("h", P["Halo 3D"], 0, 0, CW, CH, still=True)
    lock = ('<g transform="translate(200 52)" fill="none" stroke="#fff" stroke-width="2" stroke-opacity=".9">'
            '<path d="M-5 -2V-6A5 5 0 0 1 5 -6V-2"/><rect x="-8" y="-2" width="16" height="12" rx="3" fill="#fff" '
            'fill-opacity=".9" stroke="none"/></g>')
    card("lock", "The lock screen, on a still of the live wallpaper", d,
         b + lock + text(200, 148, "9:41", 76, weight=600, anchor="middle", op=.92))


# --- the swatch book: every preset that ships, by family ------------------------------------------------------
def swatches():
    W, pad, cols, gap, tile, label = 880, 30, 10, 12, 70, 18
    step = (W - 2 * pad - tile) / (cols - 1)
    rows_fluid = math.ceil(len(FLUID) / cols)
    y_fluid = pad + 26
    y_classic = y_fluid + rows_fluid * (tile + label + gap) + 34
    H = y_classic + tile + label + pad
    defs, body = [], [f'<rect width="{W}" height="{H}" rx="22" fill="{PANEL}"/>'
                      f'<rect x=".5" y=".5" width="{W - 1}" height="{H - 1}" rx="21.5" fill="none" stroke="{EDGE}"/>']
    for head, items, y0 in (("Fluid 3D", FLUID, y_fluid), ("Classic 2D", CLASSIC, y_classic)):
        body.append(text(pad, y0 - 12, head, 13, weight=700, op=.9))
        for i, (name, c) in enumerate(items):
            x, y = pad + (i % cols) * step, y0 + (i // cols) * (tile + label + gap)
            uid = re.sub(r"\W", "", name.lower()) + head[0]
            d, b = haze(uid, c, x, y, tile, tile, dur=11 + (i * 7) % 6, delay=i * 1.3)
            defs.append(d + f'<clipPath id="{uid}c"><rect x="{x:.1f}" y="{y}" width="{tile}" height="{tile}" rx="16"/></clipPath>')
            body.append(f'<g clip-path="url(#{uid}c)">{b}</g>'
                        f'<rect x="{x + .5:.1f}" y="{y + .5}" width="{tile - 1}" height="{tile - 1}" rx="15.5" fill="none" '
                        f'stroke="#fff" stroke-opacity=".14"/>'
                        + text(x + tile / 2, y + tile + 14, name, 11, "#e9e1dc", 500, anchor="middle", op=.85))
    (OUT / "presets.svg").write_text(svg(W, H, "".join(body),
                                         f"The {len(FLUID) + len(CLASSIC)} gradient presets that ship with Haze",
                                         "".join(defs)))


if __name__ == "__main__":
    assert len(FLUID) == 19 and len(CLASSIC) == 8, (len(FLUID), len(CLASSIC))
    for args in (("download", "Download", "Halo"), ("presets", "Presets", "Iris"),
                 ("build", "Build from source", "Tide"), ("how", "How it works", "Plum")):
        button(*args)
    for f in (card_wallpaper, card_gradients, card_screensaver, card_light, card_picker, card_lock):
        f()
    swatches()
    for p in sorted(OUT.glob("*.svg")):
        print(f"{p.name:24} {p.stat().st_size / 1024:6.1f} KB")
