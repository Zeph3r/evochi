"""The walking camera at 2x (an Evochi the size the Wilds draw it), the villagers room-lit as they were
and drawn flat like the Evochi as they are now, and the camera easing in for a conversation by the
Guild's door. Composited from the zoom_hd and zoom_talk renders (village_walk.py --view zoom_hd /
zoom_talk) with the real sprites. (The first pass also compared 1x, 1.5x and bigger characters; 2x won.)

    python3 zoom_concept.py VW_DIR OUT_DIR
"""
import sys

from PIL import Image, ImageDraw, ImageFilter

import village_concept as VC

VC.VW, OUT = sys.argv[1], sys.argv[2]
X = VC.X
FW, FH = 824, 1100                    # a phone frame's picture, px (412 x 550 dp)
PET = (0.8, -19.0)                    # walking down from the bridge to the plaza (clear of the waystone)
PIP, ALDER = (-4.5, -31.0), (4.6, -31.0)


def scene(big=1.0, classic=True):
    """The zoom_hd picture with everyone in it; characters drawn [big] times their usual size."""
    eh, nh = VC.EVOCHI_H, dict(VC.NPC_H)
    VC.EVOCHI_H, VC.NPC_H = eh * big, {k: h * big for k, h in nh.items()}
    v = VC.View('zoom_hd')
    pip = VC.npc(v, 'pip', *PIP, 'happy', classic)
    VC.npc(v, 'alder', *ALDER, 'neutral', classic)
    VC.evochi(v, *PET, 'SE')
    VC.EVOCHI_H, VC.NPC_H = eh, nh
    return v, pip


def framed(v, pip, zoom):
    """The camera's view at [zoom] (1 = the whole zoom_hd picture), the Evochi a little below the
    middle as in the Wilds; then the '!' over Pip, drawn at its usual size on screen."""
    W, H = v.img.size
    cw, ch = W / zoom, H / zoom
    px, py = v.at(*PET)
    x0 = min(max(px - cw / 2, 0), W - cw)
    y0 = min(max(py - 0.58 * ch, 0), H - ch)
    fr = v.img.crop((round(x0), round(y0), round(x0 + cw), round(y0 + ch))).resize((FW, FH), Image.LANCZOS)
    k = FW / cw
    mx, my = (pip[0] - x0) * k, (pip[1] - y0) * k
    if 0 < mx < FW and 40 * X < my < FH:
        VC.marker(fr, mx, my - 6 * X, 'quest')
    return fr


class Pic:
    def __init__(self, img):
        self.img = img


def tilt_shift(img, band=0.2, r=5):
    """Soft focus towards the top and bottom edges: the toy-diorama look."""
    blur = img.filter(ImageFilter.GaussianBlur(r))
    m = Image.new('L', img.size, 0)
    d = ImageDraw.Draw(m)
    h = img.height
    for y in range(h):
        t = y / h
        a = max(0.0, (band - t) / band, (t - (1 - band)) / band)
        if a > 0:
            d.line([(0, y), (img.width, y)], fill=int(255 * min(1.0, a) ** 1.3))
    return Image.composite(blur, img, m)


def main():
    vl, pipl = scene(classic=False)
    vf, pipf = scene(classic=True)
    shots = [('2x, villagers room-lit (before)', framed(vl, pipl, 2.0)),
             ('2x, villagers drawn flat like the Evochi', framed(vf, pipf, 2.0))]
    # a conversation: the camera eases in to frame you both
    t = VC.View('zoom_talk')
    hx, hy = VC.npc(t, 'pip', *PIP, 'happy')
    VC.evochi(t, -0.6, -28.2, 'NW')
    t.img = tilt_shift(t.img)
    VC.chip(t.img, hx, hy - 16 * X, 'Pip')
    VC.bubble(t.img, hx + 40 * X, hy - 38 * X,
              "Guild business! We've spotted an unusual Evochi near the Mossy Ruins. Leafy ears, a flower on its head, FAST.", 250)
    shots.append(('Talking: the camera eases in', t.img))
    s = 0.5
    panels = [(lab, VC.phone(Pic(img)).resize((int(FW * s), int((FH + 156 * X) * s)), Image.LANCZOS)) for lab, img in shots]
    VC.board('Walking at 2x, villagers drawn flat',
             'Your Evochi the size it is in the Wilds. The villagers lose the room lighting and match the Evochi: flat, even light and the same dark outline.',
             panels, f'{OUT}/village_zoom2x.jpg', gap=34)
    print('ok')


if __name__ == '__main__':
    main()
