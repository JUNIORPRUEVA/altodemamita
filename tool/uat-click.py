"""Controlador de UI con verificacion de estado (Windows + Flutter desktop).

Pasos (separados por ';'):
    focus                 trae la ventana al frente
    click:X,Y             clic de cursor real (coordenadas de cliente)
    dclick:X,Y            dos clics seguidos
    wait:MS               espera
    state                 imprime el estado detectado (velo del dialogo)
    until_dialog:X,Y[:N]  clic repetido en X,Y hasta que aparezca el dialogo
    until_closed:X,Y[:N]  clic repetido hasta que el dialogo desaparezca

El estado se mide sobre el pixel SCRIM: cuando hay un dialogo modal la pagina
queda oscurecida por el velo; sin dialogo es blanco puro.

Uso:
    py tool/uat-click.py "focus;click:600,566;wait:800;until_dialog:1823,679;state"
"""
import ctypes
import ctypes.wintypes as wt
import sys
import time

user32 = ctypes.windll.user32
gdi32 = ctypes.windll.gdi32

WINDOW_TITLE = "Sistema Solares"
SCRIM = (400, 400)
POINT = wt.POINT


def find_window():
    hwnd = user32.FindWindowW(None, WINDOW_TITLE)
    if not hwnd:
        sys.exit("no se encontro la ventana '%s'" % WINDOW_TITLE)
    return hwnd


def foreground():
    hwnd = find_window()
    # OJO: ShowWindow(SW_RESTORE) des-maximiza la ventana y cambia el area de
    # cliente, lo que invalida todas las coordenadas. Solo se restaura si esta
    # minimizada, y en ese caso se maximiza para conservar la geometria.
    if user32.IsIconic(hwnd):
        user32.ShowWindow(hwnd, 3)   # SW_MAXIMIZE
        time.sleep(0.6)
    user32.BringWindowToTop(hwnd)
    user32.SetForegroundWindow(hwnd)
    time.sleep(0.5)
    return hwnd


def origin(hwnd):
    p = POINT(0, 0)
    user32.ClientToScreen(hwnd, ctypes.byref(p))
    return p.x, p.y


def click(hwnd, cx, cy):
    ox, oy = origin(hwnd)
    user32.SetCursorPos(ox + cx, oy + cy)
    time.sleep(0.18)
    user32.mouse_event(0x0002, 0, 0, 0, 0)
    time.sleep(0.09)
    user32.mouse_event(0x0004, 0, 0, 0, 0)
    time.sleep(0.55)


def pixel(hwnd, cx, cy):
    ox, oy = origin(hwnd)
    dc = user32.GetDC(0)
    color = gdi32.GetPixel(dc, ox + cx, oy + cy)
    user32.ReleaseDC(0, dc)
    if color == 0xFFFFFFFF:
        return None
    return (color & 0xFF, (color >> 8) & 0xFF, (color >> 16) & 0xFF)


def dialog_open(hwnd):
    px = pixel(hwnd, *SCRIM)
    return px is not None and min(px) < 235


PW_RENDERFULLCONTENT = 0x2
BI_RGB = 0
DIB_RGB_COLORS = 0


class _BMIH(ctypes.Structure):
    _fields_ = [
        ("biSize", wt.DWORD), ("biWidth", wt.LONG), ("biHeight", wt.LONG),
        ("biPlanes", wt.WORD), ("biBitCount", wt.WORD),
        ("biCompression", wt.DWORD), ("biSizeImage", wt.DWORD),
        ("biXPelsPerMeter", wt.LONG), ("biYPelsPerMeter", wt.LONG),
        ("biClrUsed", wt.DWORD), ("biClrImportant", wt.DWORD),
    ]


class _BMI(ctypes.Structure):
    _fields_ = [("bmiHeader", _BMIH), ("bmiColors", wt.DWORD * 3)]


def grab_png(hwnd, path):
    """Captura el area de cliente (incluye barra de titulo) a PNG."""
    from PIL import Image

    r = wt.RECT()
    user32.GetClientRect(hwnd, ctypes.byref(r))
    w, ht = r.right, r.bottom
    hdc = user32.GetDC(hwnd)
    mem = gdi32.CreateCompatibleDC(hdc)
    bmp = gdi32.CreateCompatibleBitmap(hdc, w, ht)
    gdi32.SelectObject(mem, bmp)
    if not user32.PrintWindow(hwnd, mem, PW_RENDERFULLCONTENT):
        user32.PrintWindow(hwnd, mem, 0)
    bi = _BMI()
    bi.bmiHeader.biSize = ctypes.sizeof(_BMIH)
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
    Image.frombuffer("RGBA", (w, ht), buf.raw, "raw", "BGRA", 0, 1) \
        .convert("RGB").save(path)


def set_clipboard(text):
    """Copia texto al portapapeles (CF_UNICODETEXT)."""
    CF_UNICODETEXT = 13
    GMEM_MOVEABLE = 0x0002
    kernel32 = ctypes.windll.kernel32

    kernel32.GlobalAlloc.restype = ctypes.c_void_p
    kernel32.GlobalAlloc.argtypes = [ctypes.c_uint, ctypes.c_size_t]
    kernel32.GlobalLock.restype = ctypes.c_void_p
    kernel32.GlobalLock.argtypes = [ctypes.c_void_p]
    kernel32.GlobalUnlock.argtypes = [ctypes.c_void_p]
    user32.SetClipboardData.restype = ctypes.c_void_p
    user32.SetClipboardData.argtypes = [ctypes.c_uint, ctypes.c_void_p]

    data = text.encode("utf-16-le") + b"\x00\x00"
    handle = kernel32.GlobalAlloc(GMEM_MOVEABLE, len(data))
    pointer = kernel32.GlobalLock(handle)
    ctypes.memmove(pointer, data, len(data))
    kernel32.GlobalUnlock(handle)

    user32.OpenClipboard(0)
    user32.EmptyClipboard()
    user32.SetClipboardData(CF_UNICODETEXT, handle)
    user32.CloseClipboard()


class _KEYBDINPUT(ctypes.Structure):
    _fields_ = [
        ("wVk", wt.WORD),
        ("wScan", wt.WORD),
        ("dwFlags", wt.DWORD),
        ("time", wt.DWORD),
        ("dwExtraInfo", ctypes.c_size_t),
    ]


class _INPUTUNION(ctypes.Union):
    _fields_ = [("ki", _KEYBDINPUT), ("pad", ctypes.c_byte * 32)]


class _INPUT(ctypes.Structure):
    _fields_ = [("type", wt.DWORD), ("u", _INPUTUNION)]


def type_unicode(text):
    """Teclea con SendInput/KEYEVENTF_UNICODE (Flutter lo acepta)."""
    INPUT_KEYBOARD = 1
    KEYEVENTF_UNICODE = 0x0004
    KEYEVENTF_KEYUP = 0x0002

    for ch in text:
        for flags in (KEYEVENTF_UNICODE, KEYEVENTF_UNICODE | KEYEVENTF_KEYUP):
            inp = _INPUT()
            inp.type = INPUT_KEYBOARD
            inp.u.ki = _KEYBDINPUT(0, ord(ch), flags, 0, 0)
            user32.SendInput(1, ctypes.byref(inp), ctypes.sizeof(_INPUT))
            time.sleep(0.012)
        time.sleep(0.012)


def press_vkey(vk):
    """Pulsa una tecla virtual con SendInput (Enter, Tab, flechas...)."""
    INPUT_KEYBOARD = 1
    KEYEVENTF_KEYUP = 0x0002
    for flags in (0, KEYEVENTF_KEYUP):
        inp = _INPUT()
        inp.type = INPUT_KEYBOARD
        inp.u.ki = _KEYBDINPUT(vk, 0, flags, 0, 0)
        user32.SendInput(1, ctypes.byref(inp), ctypes.sizeof(_INPUT))
        time.sleep(0.04)


def press_ctrl_v():
    """Pulsa Ctrl+V con entrada real (Flutter ignora WM_CHAR por PostMessage)."""
    press_ctrl_key(0x56)


def press_ctrl_key(vk):
    """Pulsa Ctrl+<vk> con entrada real."""
    VK_CONTROL = 0x11
    KEYEVENTF_KEYUP = 0x0002
    user32.keybd_event(VK_CONTROL, 0, 0, 0)
    time.sleep(0.05)
    user32.keybd_event(vk, 0, 0, 0)
    time.sleep(0.05)
    user32.keybd_event(vk, 0, KEYEVENTF_KEYUP, 0)
    time.sleep(0.05)
    user32.keybd_event(VK_CONTROL, 0, KEYEVENTF_KEYUP, 0)


def parse_xy(arg):
    parts = arg.split(":")
    x, y = parts[0].split(",")
    tries = int(parts[1]) if len(parts) > 1 else 6
    return int(x), int(y), tries


def main():
    steps = sys.argv[1]
    hwnd = find_window()

    for step in [s.strip() for s in steps.split(";") if s.strip()]:
        name, _, arg = step.partition(":")

        if name == "focus":
            hwnd = foreground()
            print("focus ok origen=%s" % (origin(hwnd),))

        elif name == "click":
            x, y, _ = parse_xy(arg)
            click(hwnd, x, y)
            print("click %d,%d dialogo=%s" % (x, y, dialog_open(hwnd)))

        elif name == "dclick":
            x, y, _ = parse_xy(arg)
            click(hwnd, x, y)
            click(hwnd, x, y)
            print("dclick %d,%d dialogo=%s" % (x, y, dialog_open(hwnd)))

        elif name == "wait":
            time.sleep(int(arg) / 1000.0)
            print("wait %s" % arg)

        elif name == "state":
            print("state dialogo=%s px=%s" % (dialog_open(hwnd), pixel(hwnd, *SCRIM)))

        elif name == "paste":
            set_clipboard(arg)
            time.sleep(0.25)
            press_ctrl_v()
            time.sleep(0.5)
            print("paste <%d chars>" % len(arg))

        elif name == "wtype":
            type_unicode(arg)
            time.sleep(0.4)
            print("wtype <%d chars>" % len(arg))

        elif name == "enter":
            press_vkey(0x0D)
            time.sleep(0.4)
            print("enter")

        elif name == "tab":
            press_vkey(0x09)
            time.sleep(0.3)
            print("tab")

        elif name == "selall":
            press_ctrl_key(0x41)      # Ctrl+A
            time.sleep(0.3)
            print("selall")

        elif name == "back":
            for _ in range(int(arg or "1")):
                press_vkey(0x08)      # VK_BACK
            time.sleep(0.3)
            print("back %s" % arg)

        elif name == "shot":
            grab_png(hwnd, arg)
            print("shot %s" % arg)

        elif name == "until_dialog":
            x, y, tries = parse_xy(arg)
            ok = False
            for i in range(tries):
                click(hwnd, x, y)
                if dialog_open(hwnd):
                    print("until_dialog abierto tras %d clic(s)" % (i + 1))
                    ok = True
                    break
            if not ok:
                print("until_dialog FALLO tras %d clic(s)" % tries)

        elif name == "until_closed":
            x, y, tries = parse_xy(arg)
            ok = False
            for i in range(tries):
                click(hwnd, x, y)
                if not dialog_open(hwnd):
                    print("until_closed cerrado tras %d clic(s)" % (i + 1))
                    ok = True
                    break
            if not ok:
                print("until_closed FALLO tras %d clic(s)" % tries)

        else:
            sys.exit("paso desconocido: %s" % step)


if __name__ == "__main__":
    main()
