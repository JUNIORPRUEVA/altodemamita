"""Clica botones azules localizados por color en el mismo instante de la captura.

Evita el problema de que el panel se desplace entre la medicion y el clic.

Uso:
    py tool/uat-click-button.py [indice]   # 1 = primer boton, -1 = ultimo
"""
import ctypes
import ctypes.wintypes as wt
import sys
import time

from PIL import Image

user32 = ctypes.windll.user32
gdi32 = ctypes.windll.gdi32

WINDOW_TITLE = "Sistema Solares"
PW_RENDERFULLCONTENT = 0x2
DIB_RGB_COLORS = 0
BI_RGB = 0
TARGET = (0x1F, 0x4B, 0x99)
TOL = 12
REGION = (1650, 600, 1900, 900)
TITLE_BAR = 23


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


def hwnd_of():
    h = user32.FindWindowW(None, WINDOW_TITLE)
    if not h:
        raise SystemExit("no se encontro la ventana")
    return h


def grab(h):
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


def find_pills(img):
    x0, y0, x1, y1 = REGION
    px = img.load()
    rows = {}
    for y in range(y0, min(y1, img.height)):
        for x in range(x0, min(x1, img.width)):
            r, g, b = px[x, y]
            if (abs(r - TARGET[0]) <= TOL and abs(g - TARGET[1]) <= TOL
                    and abs(b - TARGET[2]) <= TOL):
                rows.setdefault(y, []).append(x)

    bands = []
    for y in sorted(rows):
        if bands and y - bands[-1][1] <= 3:
            bands[-1][1] = y
            bands[-1][2] = min(bands[-1][2], min(rows[y]))
            bands[-1][3] = max(bands[-1][3], max(rows[y]))
        else:
            bands.append([y, y, min(rows[y]), max(rows[y])])

    return [((xa + xb) // 2, (ya + yb) // 2, ya, yb)
            for ya, yb, xa, xb in bands if yb - ya >= 20]


def click(h, cx, cy):
    p = wt.POINT(0, 0)
    user32.ClientToScreen(h, ctypes.byref(p))
    user32.SetCursorPos(p.x + cx, p.y + cy)
    time.sleep(0.18)
    user32.mouse_event(0x0002, 0, 0, 0, 0)
    time.sleep(0.09)
    user32.mouse_event(0x0004, 0, 0, 0, 0)


def main():
    index = int(sys.argv[1]) if len(sys.argv) > 1 else -1
    h = hwnd_of()
    user32.SetForegroundWindow(h)
    time.sleep(0.3)

    pills = find_pills(grab(h))
    if not pills:
        raise SystemExit("no se encontraron botones azules")
    for i, (cx, cy, ya, yb) in enumerate(pills, 1):
        print("  pastilla %d: centro imagen (%d,%d) filas %d..%d"
              % (i, cx, cy, ya, yb))

    cx, cy, _, _ = pills[index - 1] if index > 0 else pills[index]
    client_y = cy - TITLE_BAR
    print("clic en cliente (%d,%d)" % (cx, client_y))
    click(h, cx, client_y)
    time.sleep(3.0)

    after = grab(h)
    diff = sum(1 for py in range(0, after.height, 7)
               for px_ in range(0, after.width, 7)
               if after.getpixel((px_, py)) != grab.__globals__['_before'](
                   px_, py)) if False else None
    out = r"C:\src\ss-uat-shots\after-click.png"
    after.save(out)
    print("captura posterior: %s" % out)


if __name__ == "__main__":
    main()
