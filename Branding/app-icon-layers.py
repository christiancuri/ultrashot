#!/usr/bin/env python3
"""Generates the UltraShot AppIcon.icon layer SVGs (1024 pt Icon Composer canvas).

Layers:
  brackets.svg  four viewfinder selection corners (front group)
  dot.svg       center capture/record dot (front group)
  frame.svg     faint selection region behind the brackets (back group)
"""
import os
import sys

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "UltraShot", "AppIcon.icon", "Assets")

C = 512.0          # canvas center
HALF = 300.0       # half-size of the selection box (outer edge of brackets)
T = 92.0           # bracket thickness
ARM = 214.0        # arm length from the outer corner (incl. round cap)
R = 116.0          # outer corner radius
r = max(R - T, 0.0) or 0.0  # inner corner radius (sharp inside when R <= T)
DOT_R = 92.0       # center dot radius
FRAME_INSET = 46.0 # frame inset from the bracket box outer edge (mid-stroke)
FRAME_RADIUS = 70.0


def f(v):
    s = f"{v:.2f}".rstrip("0").rstrip(".")
    return s if s != "-0" else "0"


def bracket(sx, sy):
    """Top-left bracket in local coords, mirrored by (sx, sy) about the center."""
    x0, y0 = C - HALF, C - HALF
    h = T / 2

    def p(x, y):
        return f(C + (x - C) * sx), f(C + (y - C) * sy)

    flip = (sx * sy) < 0

    def sw(s):
        return 1 - s if flip else s

    cmds = []
    cmds.append("M%s %s" % p(x0 + ARM - h, y0))
    cmds.append("A%s %s 0 0 %d %s %s" % (f(h), f(h), sw(1), *p(x0 + ARM - h, y0 + T)))
    if r > 0:
        cmds.append("L%s %s" % p(x0 + T + r, y0 + T))
        cmds.append("A%s %s 0 0 %d %s %s" % (f(r), f(r), sw(0), *p(x0 + T, y0 + T + r)))
    else:
        cmds.append("L%s %s" % p(x0 + T, y0 + T))
    cmds.append("L%s %s" % p(x0 + T, y0 + ARM - h))
    cmds.append("A%s %s 0 0 %d %s %s" % (f(h), f(h), sw(1), *p(x0, y0 + ARM - h)))
    cmds.append("L%s %s" % p(x0, y0 + R))
    cmds.append("A%s %s 0 0 %d %s %s" % (f(R), f(R), sw(1), *p(x0 + R, y0)))
    cmds.append("Z")
    return "".join(cmds)


def circle(cx, cy, rad):
    return (f"M{f(cx - rad)} {f(cy)}A{f(rad)} {f(rad)} 0 1 0 {f(cx + rad)} {f(cy)}"
            f"A{f(rad)} {f(rad)} 0 1 0 {f(cx - rad)} {f(cy)}Z")


def rrect(x, y, w, h, rad):
    return (f"M{f(x + rad)} {f(y)}H{f(x + w - rad)}A{f(rad)} {f(rad)} 0 0 1 {f(x + w)} {f(y + rad)}"
            f"V{f(y + h - rad)}A{f(rad)} {f(rad)} 0 0 1 {f(x + w - rad)} {f(y + h)}"
            f"H{f(x + rad)}A{f(rad)} {f(rad)} 0 0 1 {f(x)} {f(y + h - rad)}"
            f"V{f(y + rad)}A{f(rad)} {f(rad)} 0 0 1 {f(x + rad)} {f(y)}Z")


def svg(d):
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">\n'
            f'  <path fill="#fff" fill-rule="evenodd" d="{d}"/>\n'
            '</svg>\n')


def main():
    os.makedirs(OUT, exist_ok=True)
    brackets = "".join(bracket(sx, sy) for sx, sy in [(1, 1), (-1, 1), (1, -1), (-1, -1)])
    fx = C - HALF + FRAME_INSET
    fw = 2 * (HALF - FRAME_INSET)
    layers = {
        "brackets.svg": brackets,
        "dot.svg": circle(C, C, DOT_R),
        "frame.svg": rrect(fx, fx, fw, fw, FRAME_RADIUS) + circle(C, C, DOT_R + 34),
    }
    for name, d in layers.items():
        with open(os.path.join(OUT, name), "w") as fh:
            fh.write(svg(d))
    print("wrote", ", ".join(layers), "to", OUT, file=sys.stderr)


if __name__ == "__main__":
    main()
