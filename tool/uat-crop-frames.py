"""Recorta la zona que parpadea en varios fotogramas para poder leerla.

Captura N fotogramas con PrintWindow, recorta el rectangulo indicado y guarda
cada recorte ampliado como PNG, para comparar el texto entre fotogramas.

Uso:
    py tool/uat-crop-frames.py X0 Y0 X1 Y1 [fotogramas] [segundos]
"""
import ctypes
import ctypes.wintypes as wt
import io
import sys
import time

from PIL import Image

user32 = ctypes.windll.user32
gdi32 = ctypes.windll.gdi32

WINDOW_TITLE = "Sistema Solares"
PW_RENDERFULLCONTENT = 0x2
DIB_RGB_COLORS = 0
BI_RGB = 0
OUT_DIR = r"C:\src\ss-uat-shots"


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


def grab_image(hwnd):
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
    bi.bmiHeader.biHeight = -ht
    bi.bmiHeader.biPlanes = 1
    bi.bmiHeader.biBitCount = 32
    bi.bmiHeader.biCompression = BI_RGB

    buf = ctypes.create_string_buffer(w * ht * 4)
    gdi32.GetDIBits(mem, bmp, 0, ht, buf, ctypes.byref(bi), DIB_RGB_COLORS)

    gdi32.DeleteObject(bmp)
    gdi32.DeleteDC(mem)
    user32.ReleaseDC(hwnd, hdc)

    img = Image.frombuffer("RGBA", (w, ht), buf.raw, "raw", "BGRA", 0, 1)
    return img.convert("RGB")


def main():
    x0, y0, x1, y1 = (int(v) for v in sys.argv[1:5])
    frames = int(sys.argv[5]) if len(sys.argv) > 5 else 4
    delay = float(sys.argv[6]) if len(sys.argv) > 6 else 1.0

    hwnd = hwnd_of()
    for i in range(frames):
        img = grab_image(hwnd)
        crop = img.crop((x0, y0, x1, y1))
        crop = crop.resize((crop.width * 2, crop.height * 2), Image.LANCZOS)
        path = OUT_DIR + r"\crop-%d.png" % i
        crop.save(path)
        print("guardado %s (%dx%d)" % (path, crop.width, crop.height))
        time.sleep(delay)


if __name__ == "__main__":
    main()
