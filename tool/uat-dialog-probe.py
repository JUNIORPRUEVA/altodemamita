"""Sonda de UI para el dialogo 'Anular pago' (Windows, Flutter desktop).

Objetivo: averiguar con evidencia (pixeles) por que el desplegable de motivo
no responde, sin adivinar coordenadas.

Claves:
  - La ventana se trae al frente antes de tocar nada (si no, los clics y el
    muestreo de pantalla caen sobre el editor).
  - El dialogo se detecta por el VELO gris que oscurece la pagina de fondo,
    no por el blanco de la tarjeta (la lista tambien es casi blanca).

Uso:
    py tool/uat-dialog-probe.py
"""
import ctypes
import ctypes.wintypes as wt
import sys
import time

user32 = ctypes.windll.user32
gdi32 = ctypes.windll.gdi32

WINDOW_TITLE = "Sistema Solares"

SCRIM = (400, 400)          # sobre la lista: blanco si no hay dialogo
TRASH = (1823, 679)         # icono de anular en la fila mas reciente
DROPDOWN = (966, 588)       # campo "Seleccione un motivo"
BANNER = (760, 480)         # aviso amarillo, zona inerte dentro de la tarjeta

POINT = wt.POINT


def find_window():
    hwnd = user32.FindWindowW(None, WINDOW_TITLE)
    if not hwnd:
        sys.exit("no se encontro la ventana '%s'" % WINDOW_TITLE)
    return hwnd


def foreground(hwnd):
    user32.ShowWindow(hwnd, 9)          # SW_RESTORE
    user32.SetForegroundWindow(hwnd)
    time.sleep(0.7)


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
    if px is None:
        return False
    return min(px) < 235          # el velo oscurece la lista


def open_dialog(hwnd, attempts=6):
    for i in range(attempts):
        click(hwnd, *TRASH)
        if dialog_open(hwnd):
            print("  dialogo abierto tras %d clic(s) en el basurero" % (i + 1))
            return True
    return False


def main():
    hwnd = find_window()
    foreground(hwnd)
    print("ventana=%s origen=%s" % (hex(hwnd), origin(hwnd)))
    print("velo antes de abrir: px=%s -> abierto=%s"
          % (pixel(hwnd, *SCRIM), dialog_open(hwnd)))

    print("[1] abrir dialogo")
    if not open_dialog(hwnd):
        sys.exit("FALLO: el dialogo no se abrio")

    print("[2] clic en zona inerte de la tarjeta %s" % (BANNER,))
    click(hwnd, *BANNER)
    still = dialog_open(hwnd)
    print("  sigue abierto: %s" % still)
    if not still:
        print("  CONCLUSION: un clic dentro de la tarjeta cierra el dialogo")
        return

    print("[3] clic en el desplegable %s" % (DROPDOWN,))
    click(hwnd, *DROPDOWN)
    print("  sigue abierto: %s" % dialog_open(hwnd))
    print("  franja vertical en x=966 (el menu del dropdown se dibuja aqui):")
    for dy in range(556, 730, 10):
        print("   y=%d px=%s" % (dy, pixel(hwnd, 966, dy)))


if __name__ == "__main__":
    main()
