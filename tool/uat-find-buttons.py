"""Localiza los botones azules (#1F4B99) de la ficha de venta y da su centro.

Sirve para clicar con precision sobre los FAB 'Detalle de cuotas' e
'Historial de pagos' sin depender de estimaciones a ojo.

Uso:
    py tool/uat-find-buttons.py
"""
import ctypes
import ctypes.wintypes as wt

from PIL import Image

user32 = ctypes.windll.user32
gdi32 = ctypes.windll.gdi32

WINDOW_TITLE = "Sistema Solares"
PW_RENDERFULLCONTENT = 0x2
DIB_RGB_COLORS = 0
BI_RGB = 0
TARGET = (0x1F, 0x4B, 0x99)   # #1F4B99
TOL = 12
REGION = (1650, 620, 1900, 850)


class BITMAPINFOHEADER(ctypes.Structure):
    _fields_ = [
        ("biSize", wt.DWORD), ("biWidth", wt.LONG), ("biHeight", wt.LONG),
        ("biPlanes", wt.WORD), ("biBitCount", wt.WORD),
        ("biCompression", wt.DWORD), ("biSizeImage", wt.DWORD),
        ("biXPelsPerMeter", wt.LONG), ("biYPelsPerMeter", wt.LONG),
        ("biClrUsed", wt.DWORD), ("biClrImportant", wt.DWORD),
    ]


class BITMAPINFO(ctypes.Structure):
    _fields_ = [("bmiHeader", BITMAPINFOHEADER), ("bmiColors", wt.DWORD * 3)]


def grab_image():
    h = user32.FindWindowW(None, WINDOW_TITLE)
    if not h:
        raise SystemExit("no se encontro la ventana")
    r = wt.RECT()
    user32.GetClientRect(h, ctypes.byref(r))
    w, ht = r.right, r.bottom
    hdc = user32.GetDC(h)
    mem = gdi32.CreateCompatibleDC(hdc)
    bmp = gdi32.CreateCompatibleBitmap(hdc, w, ht)
    gdi32.SelectObject(mem, bmp)
    if not user32.PrintWindow(h, mem, PW_RENDERFULLCONTENT):
        user32.PrintWindow(h, mem, 0)
    bi = BITMAPINFO()
    bi.bmiHeader.biSize = ctypes.sizeof(BITMAPINFOHEADER)
    bi.bmiHeader.biWidth = w
    bi.bmiHeader.biHeight = -ht
    bi.bmiHeader.biPlanes = 1
    bi.bmiHeader.biBitCount = 32
    bi.bmiHeader.biCompression = BI_RGB
    buf = ctypes.create_string_buffer(w * ht * 4)
    gdi32.GetDIBits(mem, bmp, 0, ht, buf, ctypes.byref(bi), DIB_RGB_COLORS)
    gdi32.DeleteObject(bmp)
    gdi32.DeleteDC(mem)
    user32.ReleaseDC(h, hdc)
    img = Image.frombuffer("RGBA", (w, ht), buf.raw, "raw", "BGRA", 0, 1)
    return img.convert("RGB")


def main():
    img = grab_image()
    x0, y0, x1, y1 = REGION
    px = img.load()
    rows = {}
    for y in range(y0, min(y1, img.height)):
        for x in range(x0, min(x1, img.width)):
            r, g, b = px[x, y]
            if (abs(r - TARGET[0]) <= TOL and abs(g - TARGET[1]) <= TOL
                    and abs(b - TARGET[2]) <= TOL):
                rows.setdefault(y, []).append(x)

    # Agrupa filas contiguas en "pastillas".
    bands = []
    for y in sorted(rows):
        if bands and y - bands[-1][1] <= 2:
            bands[-1][1] = y
            bands[-1][2] = min(bands[-1][2], min(rows[y]))
            bands[-1][3] = max(bands[-1][3], max(rows[y]))
        else:
            bands.append([y, y, min(rows[y]), max(rows[y])])

    for i, (ya, yb, xa, xb) in enumerate(bands, 1):
        cx, cy = (xa + xb) // 2, (ya + yb) // 2
        print("boton %d: imagen y=%d..%d x=%d..%d  centro=(%d,%d)  "
              "-> clic en cliente (%d,%d)"
              % (i, ya, yb, xa, xb, cx, cy, cx, cy - 23))


if __name__ == "__main__":
    main()
