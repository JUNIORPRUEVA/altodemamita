"""Imprime los colores de una columna vertical de una captura PNG.

Uso:
    py tool/uat-scan.py <png> <x> <y0> <y1>

Sirve para localizar bordes de campos y botones con precision en lugar de
estimar coordenadas a ojo.
"""
import sys

from PIL import Image

path, x, y0, y1 = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
img = Image.open(path).convert("RGB")
px = img.load()

prev = None
for y in range(y0, min(y1, img.height)):
    color = px[x, y]
    if color != prev:
        print("y=%4d  rgb=%s   (cliente y=%d)" % (y, color, y - 23))
        prev = color
