"""Trae la ventana a primer plano sin des-maximizarla y reporta su geometria."""
import ctypes
import ctypes.wintypes as wt
import sys
import time

user32 = ctypes.windll.user32
WINDOW_TITLE = "Sistema Solares"


class WINDOWPLACEMENT(ctypes.Structure):
    _fields_ = [
        ("length", ctypes.c_uint),
        ("flags", ctypes.c_uint),
        ("showCmd", ctypes.c_uint),
        ("ptMinPosition", wt.POINT),
        ("ptMaxPosition", wt.POINT),
        ("rcNormalPosition", wt.RECT),
    ]


def hwnd_of():
    h = user32.FindWindowW(None, WINDOW_TITLE)
    if not h:
        sys.exit("no se encontro la ventana")
    return h


def geometry(h):
    r = wt.RECT()
    user32.GetClientRect(h, ctypes.byref(r))
    p = wt.POINT(0, 0)
    user32.ClientToScreen(h, ctypes.byref(p))
    wp = WINDOWPLACEMENT()
    wp.length = ctypes.sizeof(WINDOWPLACEMENT)
    user32.GetWindowPlacement(h, ctypes.byref(wp))
    return r.right, r.bottom, (p.x, p.y), wp.showCmd


def main():
    h = hwnd_of()
    mode = sys.argv[1] if len(sys.argv) > 1 else "report"

    if mode in ("focus", "maximize"):
        if mode == "maximize":
            user32.ShowWindow(h, 3)   # SW_MAXIMIZE
            time.sleep(0.5)
        user32.BringWindowToTop(h)
        user32.SetForegroundWindow(h)
        time.sleep(0.7)

    w, ht, org, cmd = geometry(h)
    print("client=%dx%d origin=%s showCmd=%d (1=normal 3=maximizada)" % (w, ht, org, cmd))


if __name__ == "__main__":
    main()
