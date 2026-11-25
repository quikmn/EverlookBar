# Builds the CurseForge/site screenshots (1920x1080) from UISandbox renders in raw/ (render.py EverlookBar <scenario> --zoom 2).
from PIL import Image, ImageDraw
import math
W, H = 1920, 1080
BG = Image.new("RGB", (W, H)); px = BG.load()
for y in range(H):
    for x in range(W):
        d = min(1, math.hypot((x - W / 2) / W, (y - H * 0.38) / H) * 1.6)
        px[x, y] = tuple(int(a + (b - a) * d) for a, b in zip((0x13, 0x22, 0x3F), (0x07, 0x0D, 0x1A)))

def raw(name, crop=None, key=True):
    im = Image.open(f"raw/{name}.png").convert("RGBA")
    if crop: im = im.crop(crop)
    if key:  # the render's empty screen is pure black: make it see-through, then trim
        d = im.get_flattened_data() if hasattr(im, 'get_flattened_data') else im.getdata()
        im.putdata([(0, 0, 0, 0) if p[0] < 3 and p[1] < 3 and p[2] < 3 else p for p in d])
        im = im.crop(im.getbbox())
    return im

def shadow(c, box, r=14):
    sh = Image.new("RGBA", c.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle((box[0] + 10, box[1] + 14, box[2] + 10, box[3] + 14), r, fill=(0, 0, 0, 120))
    return Image.alpha_composite(c, sh)

def place(ims, out, gap=70, maxw=1760, maxh=980, shadows=True, up=1.0):
    tw = sum(i.width for i in ims) + gap * (len(ims) - 1); th = max(i.height for i in ims)
    s = min(up, maxw / tw, maxh / th)
    ims = [i.resize((int(i.width * s), int(i.height * s)), Image.LANCZOS) for i in ims]
    g = int(gap * s); tw = sum(i.width for i in ims) + g * (len(ims) - 1)
    c = BG.convert("RGBA"); x = (W - tw) // 2
    for i in ims:
        y = (H - i.height) // 2
        if shadows: c = shadow(c, (x, y, x + i.width, y + i.height))
        c.paste(i, (x, y), i); x += i.width + g
    c.convert("RGB").save(out)

# 1: the bar. The whole bar along the top, then its two ends larger underneath.
bar = Image.open("raw/bar.png").convert("RGBA")
bar = bar.crop((0, 0, bar.width, 44))  # the bar only (44 px at zoom 2), not the backdrop under it
c = BG.convert("RGBA")
def strip(im, w):
    s = w / im.width
    return im.resize((w, int(im.height * s)), Image.LANCZOS)
full = strip(bar, W); c.paste(full, (0, 0), full)
pieces = [bar.crop((0, 0, 520, bar.height)), bar.crop((1740, 0, 2100, bar.height)), bar.crop((2170, 0, 3840, bar.height))]
pieces = [strip(pieces[0], 900), strip(pieces[1], 640), strip(pieces[2], 1760)]
y = full.height + (H - full.height - sum(i.height for i in pieces) - 110 * (len(pieces) - 1)) // 2
for im in pieces:
    x = (W - im.width) // 2
    c = shadow(c, (x, y, x + im.width, y + im.height), 8)
    c.paste(im, (x, y), im)
    y += im.height + 110
c.convert("RGB").save("1-bar.png")

place([raw("bar-xp"), raw("bar-gold"), raw("tracking-menu")], "2-plugins-and-tooltips.png", gap=120, maxh=760, up=1.6)
place([raw("minimap-pieces"), raw("minimap-unlock")], "3-minimap-pieces.png", gap=140, maxh=820, up=1.3)
place([raw("plugins-drag", crop=(1060, 460, 2760, 1700), key=False)], "4-drag-plugins.png")
place([raw("page-minimap-pieces", key=False)], "5-minimap-settings.png")
place([raw("minimap-drawer")], "6-addon-drawer.png", maxw=1500, maxh=800, up=2.0)
place([raw("page-modules", key=False)], "7-built-in-plugins.png")
place([raw("page-bars", key=False)], "8-bars.png")
