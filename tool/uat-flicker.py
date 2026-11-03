"""Detecta parpadeo/re-render continuo en la ventana de la app.

Captura N fotogramas seguidos con PrintWindow (funciona aunque la ventana este
tapada) y compara los pixeles entre fotogramas consecutivos. Informa cuantos
pixeles cambian y el rectangulo que los contiene.

Optimizacion: primero compara la fila completa como bytes; solo las filas que
difieren se recorren pixel a pixel.

Uso:
    py tool/uat-flicker.py [fotogramas] [segundos_entre_fotogramas]
"""
import ctypes
import ctypes.wintypes as wt
import sys
import time

user32 = ctypes.windll.user32
gdi32 = ctypes.windll.gdi32

WINDOW_TITLE = "Sistema Solares"
PW_RENDERFULLCONTENT = 0x2
DIB_RGB_COLORS = 0
BI_RGB = 0


class BITMAPINFOHEADER(ctypes.Structure):
    _fields_ = [
        ("biSize", wt.DWORD),
        ("biWidth", wt.LONG),
        ("biHeight", wt.LONG),
        ("biPlanes", wt.WORD),
        ("biBitCount", wt.WORD),
        ("biCompression", wt.DWORD),
        ("biSizeImage", wt.DWORD),
        ("biXPelsPerMeter", wt.LONG),
        ("biYPelsPerMeter", wt.LONG),
        ("biClrUsed", wt.DWORD),
        ("biClrImportant", wt.DWORD),
    ]


class BITMAPINFO(ctypes.Structure):
    _fields_ = [("bmiHeader", BITMAPINFOHEADER), ("bmiColors", wt.DWORD * 3)]


def hwnd_of():
    h = user32.FindWindowW(None, WINDOW_TITLE)
    if not h:
        sys.exit("no se encontro la ventana '%s'" % WINDOW_TITLE)
    return h


def grab(hwnd):
    r = wt.RECT()
    user32.GetClientRect(hwnd, ctypes.byref(r))
    w, ht = r.right, r.bottom

    hdc = user32.GetDC(hwnd)
    mem = gdi32.CreateCompatibleDC(hdc)
    bmp = gdi32.CreateCompatibleBitmap(hdc, w, ht)
    gdi32.SelectObject(mem, bmp)

    if not user32.PrintWindow(hwnd, mem, PW_RENDERFULLCONTENT):
        user32.PrintWindow(hwnd, mem, 0)

    bi = BITMAPINFO()
    bi.bmiHeader.biSize = ctypes.sizeof(BITMAPINFOHEADER)
    bi.bmiHeader.biWidth = w
    bi.bmiHeader.biHeight = -ht          # top-down
    bi.bmiHeader.biPlanes = 1
    bi.bmiHeader.biBitCount = 32
    bi.bmiHeader.biCompression = BI_RGB

    buf = ctypes.create_string_buffer(w * ht * 4)
    gdi32.GetDIBits(mem, bmp, 0, ht, buf, ctypes.byref(bi), DIB_RGB_COLORS)

    gdi32.DeleteObject(bmp)
    gdi32.DeleteDC(mem)
    user32.ReleaseDC(hwnd, hdc)
    return w, ht, buf.raw


def diff(a, b, w, h, threshold=8):
    """Devuelve (pixeles cambiados, bbox) entre dos fotogramas RGBA."""
    stride = w * 4
    changed = 0
    x0 = y0 = 10 ** 9
    x1 = y1 = -1

    for y in range(h):
        row = y * stride
        ra = a[row:row + stride]
        rb = b[row:row + stride]
        if ra == rb:
            continue

        row_changed = 0
        for x in range(w):
            i = x * 4
            if (abs(ra[i] - rb[i]) > threshold
                    or abs(ra[i + 1] - rb[i + 1]) > threshold
                    or abs(ra[i + 2] - rb[i + 2]) > threshold):
                row_changed += 1
                if x < x0:
                    x0 = x
                if x > x1:
                    x1 = x
        if row_changed:
            changed += row_changed
            if y < y0:
                y0 = y
            y1 = y

    bbox = None if x1 < 0 else (x0, y0, x1, y1)
    return changed, bbox


def main():
    frames = int(sys.argv[1]) if len(sys.argv) > 1 else 8
    delay = float(sys.argv[2]) if len(sys.argv) > 2 else 0.7

    hwnd = hwnd_of()
    w, h, prev = grab(hwnd)
    print("ventana=%s cliente=%dx%d" % (hex(hwnd), w, h))
    total = float(w * h)
    worst = 0

    for i in range(1, frames + 1):
        time.sleep(delay)
        w2, h2, cur = grab(hwnd)
        if (w2, h2) != (w, h):
            print("  el tamano cambio: %dx%d -> %dx%d" % (w, h, w2, h2))
            w, h, prev = w2, h2, cur
            continue
        changed, bbox = diff(prev, cur, w, h)
        worst = max(worst, changed)
        print("  frame %2d: %7d px distintos (%.2f%%) bbox=%s"
              % (i, changed, 100.0 * changed / total, bbox))
        prev = cur

    print("maximo entre fotogramas: %d px (%.2f%%)" % (worst, 100.0 * worst / total))


if __name__ == "__main__":
    main()
