#requires -Version 5.1
<#
    UAT Windows — piloto de un solo proceso.

    Hace TODA la secuencia (traer al frente, clics, tecleo, captura) dentro del
    mismo proceso PowerShell. Necesario porque VS Code recupera el foco entre
    invocaciones separadas y el primer clic solo activa la ventana.

    Coordenadas en espacio CLIENTE (las mismas de la captura por PrintWindow).

    Ejemplo:
      powershell -File tool\uat-drive-one.ps1 -Steps "click:52,336;wait:1200;shot:C:\tmp\a.png"
#>
param(
    [Parameter(Mandatory = $true)][string]$Steps
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

Add-Type -ReferencedAssemblies 'System.Drawing','System.Windows.Forms' @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

public class UatOne {
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] public static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint f);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, IntPtr e);
    [DllImport("user32.dll")] public static extern bool SystemParametersInfo(uint a, uint p, IntPtr v, uint i);
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);

    public delegate bool EnumProc(IntPtr h, IntPtr l);
    public struct RECT { public int Left, Top, Right, Bottom; }
    public struct POINT { public int X, Y; }

    public static IntPtr FindMain(uint pid) {
        IntPtr found = IntPtr.Zero;
        EnumWindows((h, l) => {
            uint p; GetWindowThreadProcessId(h, out p);
            if (p != pid || !IsWindowVisible(h)) return true;
            var sb = new StringBuilder(256); GetWindowTextW(h, sb, 256);
            if (sb.Length > 0) { found = h; return false; }
            return true;
        }, IntPtr.Zero);
        return found;
    }

    public static void Focus(IntPtr h) {
        for (int i = 0; i < 5; i++) {
            SystemParametersInfo(0x2001, 0, IntPtr.Zero, 0);
            if (IsIconic(h)) ShowWindow(h, 9);
            ShowWindow(h, 3);
            SetForegroundWindow(h);
            Thread.Sleep(250);
            if (GetForegroundWindow() == h) return;
        }
    }

    public static void Click(IntPtr h, int cx, int cy) {
        POINT p = new POINT(); p.X = cx; p.Y = cy;
        ClientToScreen(h, ref p);
        SetCursorPos(p.X, p.Y);
        Thread.Sleep(120);
        mouse_event(0x0002, 0, 0, 0, IntPtr.Zero);
        Thread.Sleep(70);
        mouse_event(0x0004, 0, 0, 0, IntPtr.Zero);
        Thread.Sleep(300);
    }

    // Tecleo por mensajes WM_CHAR al hilo de la ventana: no depende del foco
    // del teclado ni del layout, y no pierde caracteres como SendKeys.
    public static void TypeText(IntPtr h, string text) {
        foreach (char c in text) {
            PostMessage(h, 0x0102, (IntPtr)c, (IntPtr)1);
            Thread.Sleep(60);
        }
    }

    public static void Key(IntPtr h, int vk) {
        PostMessage(h, 0x0100, (IntPtr)vk, (IntPtr)1);
        Thread.Sleep(40);
        PostMessage(h, 0x0101, (IntPtr)vk, (IntPtr)1);
        Thread.Sleep(120);
    }

    public static string Shot(IntPtr h, string path) {
        RECT r; GetClientRect(h, out r);
        int w = r.Right - r.Left, ht = r.Bottom - r.Top;
        if (w <= 0 || ht <= 0) return "client-size " + w + "x" + ht;
        using (var bmp = new System.Drawing.Bitmap(w, ht))
        using (var g = System.Drawing.Graphics.FromImage(bmp)) {
            IntPtr hdc = g.GetHdc();
            bool ok = PrintWindow(h, hdc, 2);
            g.ReleaseHdc(hdc);
            bmp.Save(path, System.Drawing.Imaging.ImageFormat.Png);
            return "shot " + w + "x" + ht + " ok=" + ok;
        }
    }

    // Captura de PANTALLA completa: sirve para leer coordenadas absolutas.
    public static string ScreenShot(string path) {
        var b = System.Windows.Forms.Screen.PrimaryScreen.Bounds;
        // Pantalla completa en coordenadas absolutas.
        using (var bmp = new System.Drawing.Bitmap(b.Width, b.Height))
        using (var g = System.Drawing.Graphics.FromImage(bmp)) {
            g.CopyFromScreen(b.Location, System.Drawing.Point.Empty, b.Size);
            bmp.Save(path, System.Drawing.Imaging.ImageFormat.Png);
            return "screen " + b.Width + "x" + b.Height;
        }
    }

    // Clic en coordenadas ABSOLUTAS de pantalla.
    public static void ScreenClick(int x, int y) {
        SetCursorPos(x, y);
        Thread.Sleep(150);
        mouse_event(0x0002, 0, 0, 0, IntPtr.Zero);
        Thread.Sleep(80);
        mouse_event(0x0004, 0, 0, 0, IntPtr.Zero);
        Thread.Sleep(400);
    }

    // Clic por MENSAJE directo a la ventana (coordenadas CLIENTE).
    // No depende del foco, del cursor ni de la posicion del raton: Flutter
    // recibe WM_LBUTTONDOWN/UP igual que con un clic real.
    public static void PostClick(IntPtr h, int cx, int cy) {
        IntPtr lp = (IntPtr)((cy << 16) | (cx & 0xFFFF));
        PostMessage(h, 0x0201, (IntPtr)0x0001, lp); // WM_LBUTTONDOWN, MK_LBUTTON
        Thread.Sleep(60);
        PostMessage(h, 0x0202, IntPtr.Zero, lp);    // WM_LBUTTONUP
        Thread.Sleep(350);
    }

    // Rueda del raton por mensaje (WM_MOUSEWHEEL) en coordenadas CLIENTE.
    public static void PostWheel(IntPtr h, int cx, int cy, int delta) {
        POINT p = new POINT(); p.X = cx; p.Y = cy;
        ClientToScreen(h, ref p);
        IntPtr lParam = (IntPtr)((p.Y << 16) | (p.X & 0xFFFF));
        IntPtr wParam = (IntPtr)((delta << 16) & 0xFFFF0000);
        PostMessage(h, 0x020A, wParam, lParam);
        Thread.Sleep(300);
    }
}
'@

$proc = Get-Process sistema_solares -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $proc) { throw 'La app no esta corriendo.' }
$h = [UatOne]::FindMain([uint32]$proc.Id)
if ($h -eq [IntPtr]::Zero) { throw 'No se encontro ventana visible.' }

[UatOne]::Focus($h)
"foreground=$([UatOne]::GetForegroundWindow() -eq $h) hwnd=$($h.ToInt64())"

foreach ($raw in $Steps.Split(';')) {
    $step = $raw.Trim()
    if (-not $step) { continue }
    $parts = $step.Split(':', 2)
    $verb = $parts[0].ToLowerInvariant()
    $arg = if ($parts.Length -gt 1) { $parts[1] } else { '' }
    switch ($verb) {
        'click' {
            $xy = $arg.Split(',')
            [UatOne]::Focus($h)
            [UatOne]::Click($h, [int]$xy[0], [int]$xy[1])
            Write-Host "click $($xy[0]),$($xy[1])"
        }
        'type' { [UatOne]::TypeText($h, $arg); Write-Host "type <$($arg.Length) chars>" }
        'key' { [UatOne]::Key($h, [int]$arg); Write-Host "key $arg" }
        'wait' { Start-Sleep -Milliseconds ([int]$arg); Write-Host "wait $arg ms" }
        'shot' { Write-Host ([UatOne]::Shot($h, $arg)) }
        'sshot' { Write-Host ([UatOne]::ScreenShot($arg)) }
        'sclick' {
            $xy = $arg.Split(',')
            [UatOne]::Focus($h)
            [UatOne]::ScreenClick([int]$xy[0], [int]$xy[1])
            Write-Host "sclick $($xy[0]),$($xy[1])"
        }
        'pclick' {
            $xy = $arg.Split(',')
            [UatOne]::PostClick($h, [int]$xy[0], [int]$xy[1])
            Write-Host "pclick $($xy[0]),$($xy[1])"
        }
        'wheel' {
            $xy = $arg.Split(',')
            [UatOne]::PostWheel($h, [int]$xy[0], [int]$xy[1], [int]$xy[2])
            Write-Host "wheel $($xy[0]),$($xy[1]) delta=$($xy[2])"
        }
        default { throw "Paso desconocido: $step" }
    }
}
