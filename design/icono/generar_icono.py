"""Genera el icono de Crono: AppIcon.png (1024 px) y su SVG de referencia.

Sin dependencias: dibuja con funciones de distancia y escribe el PNG a mano,
para que cualquiera pueda regenerarlo con un Python normal.

    python design/icono/generar_icono.py

La idea: un anillo de progreso —el de la pantalla Hoy— con las agujas de un
reloj a las 10:08, la hora de los escaparates de relojería. A esa hora las dos
agujas dibujan una marca de hecho: hábito cumplido y despertador en una forma.
"""

import math
import os
import struct
import zlib

SIZE = 1024
CENTER = SIZE / 2

# Colores, derivados del acento de la app (#344C5C).
BG_TOP = (0x46, 0x66, 0x7B)
BG_BOTTOM = (0x1F, 0x2E, 0x39)
TRACK = (255, 255, 255, 0.13)
RING = (0x8E, 0xD3, 0xEE)
HANDS = (255, 255, 255)

RING_RADIUS = 330
RING_WIDTH = 68
# El arco empieza arriba y gira en sentido horario; el hueco queda arriba a la
# izquierda, justo donde apunta la aguja corta.
RING_START = 0.0
RING_END = 290.0

HAND_WIDTH = 58
# Ángulos de reloj: 0 es las doce, en sentido horario.
HOUR_ANGLE = 304.0     # 10:08
HOUR_LENGTH = 150
MINUTE_ANGLE = 48.0
MINUTE_LENGTH = 255


def clock_point(angle, length):
    rad = math.radians(angle)
    return (CENTER + length * math.sin(rad), CENTER - length * math.cos(rad))


def segment_distance(px, py, ax, ay, bx, by):
    abx, aby = bx - ax, by - ay
    t = ((px - ax) * abx + (py - ay) * aby) / (abx * abx + aby * aby)
    t = max(0.0, min(1.0, t))
    dx, dy = px - (ax + t * abx), py - (ay + t * aby)
    return math.hypot(dx, dy)


RING_CAP_A = clock_point(RING_START, RING_RADIUS)
RING_CAP_B = clock_point(RING_END, RING_RADIUS)
HOUR_TIP = clock_point(HOUR_ANGLE, HOUR_LENGTH)
MINUTE_TIP = clock_point(MINUTE_ANGLE, MINUTE_LENGTH)


def ring_distance(px, py):
    dx, dy = px - CENTER, py - CENTER
    angle = math.degrees(math.atan2(dx, -dy)) % 360
    if RING_START <= angle <= RING_END:
        return abs(math.hypot(dx, dy) - RING_RADIUS) - RING_WIDTH / 2
    return min(
        math.hypot(px - RING_CAP_A[0], py - RING_CAP_A[1]),
        math.hypot(px - RING_CAP_B[0], py - RING_CAP_B[1]),
    ) - RING_WIDTH / 2


def track_distance(px, py):
    return abs(math.hypot(px - CENTER, py - CENTER) - RING_RADIUS) - RING_WIDTH / 2


def hands_distance(px, py):
    return min(
        segment_distance(px, py, CENTER, CENTER, *HOUR_TIP),
        segment_distance(px, py, CENTER, CENTER, *MINUTE_TIP),
    ) - HAND_WIDTH / 2


def coverage(distance):
    return max(0.0, min(1.0, 0.5 - distance))


def blend(base, color, alpha):
    return tuple(b + (c - b) * alpha for b, c in zip(base, color))


def render():
    rows = []
    near = RING_RADIUS + RING_WIDTH
    for y in range(SIZE):
        t = y / (SIZE - 1)
        background = blend(BG_TOP, BG_BOTTOM, t)
        row = bytearray([0])  # filtro PNG: ninguno
        for x in range(SIZE):
            px, py = x + 0.5, y + 0.5
            color = background
            # Fuera del círculo exterior solo hay fondo: ahorra casi la mitad.
            if math.hypot(px - CENTER, py - CENTER) < near:
                color = blend(color, TRACK[:3], TRACK[3] * coverage(track_distance(px, py)))
                color = blend(color, RING, coverage(ring_distance(px, py)))
                color = blend(color, HANDS, coverage(hands_distance(px, py)))
            row.extend(int(round(c)) for c in color)
        rows.append(bytes(row))
    return b"".join(rows)


def write_png(path, raw):
    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    header = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)  # RGB, sin alfa
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", header))
        f.write(chunk(b"IDAT", zlib.compress(raw, 9)))
        f.write(chunk(b"IEND", b""))


def hex_color(rgb):
    return "#%02X%02X%02X" % tuple(int(c) for c in rgb)


def write_svg(path):
    large = 1 if (RING_END - RING_START) > 180 else 0
    svg = f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {SIZE} {SIZE}">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="{hex_color(BG_TOP)}"/>
      <stop offset="1" stop-color="{hex_color(BG_BOTTOM)}"/>
    </linearGradient>
  </defs>
  <rect width="{SIZE}" height="{SIZE}" fill="url(#bg)"/>
  <circle cx="{CENTER}" cy="{CENTER}" r="{RING_RADIUS}" fill="none" stroke="#FFFFFF" stroke-opacity="{TRACK[3]}" stroke-width="{RING_WIDTH}"/>
  <path d="M {RING_CAP_A[0]:.1f} {RING_CAP_A[1]:.1f} A {RING_RADIUS} {RING_RADIUS} 0 {large} 1 {RING_CAP_B[0]:.1f} {RING_CAP_B[1]:.1f}" fill="none" stroke="{hex_color(RING)}" stroke-width="{RING_WIDTH}" stroke-linecap="round"/>
  <path d="M {HOUR_TIP[0]:.1f} {HOUR_TIP[1]:.1f} L {CENTER} {CENTER} L {MINUTE_TIP[0]:.1f} {MINUTE_TIP[1]:.1f}" fill="none" stroke="{hex_color(HANDS)}" stroke-width="{HAND_WIDTH}" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
"""
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(svg)


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    root = os.path.abspath(os.path.join(here, "..", ".."))
    png = os.path.join(root, "Crono", "Resources", "Assets.xcassets", "AppIcon.appiconset", "AppIcon.png")
    write_svg(os.path.join(here, "icono.svg"))
    write_png(png, render())
    print(png)
