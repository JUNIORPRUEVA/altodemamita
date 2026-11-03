#requires -Version 5.1
<#
    Restaura/maximiza la ventana de la app UAT, informa su geometria real y
    guarda una captura por PrintWindow (no depende del foco).
#>
param(
    [string]$Out = '',
    [switch]$Restore
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing

Add-Type -ReferencedAssemblies 'System.Drawing' @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public class UatWin {
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] public static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);

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

    public static string Shot(IntPtr h, string path) {
        RECT r; if (!GetClientRect(h, out r)) return "no-client-rect";
        int w = r.Right - r.Left, ht = r.Bottom - r.Top;
        if (w <= 0 || ht <= 0) return "client-size " + w + "x" + ht;
        using (var bmp = new System.Drawing.Bitmap(w, ht))
        using (var g = System.Drawing.Graphics.FromImage(bmp)) {
            IntPtr hdc = g.GetHdc();
            bool ok = PrintWindow(h, hdc, 2);
            g.ReleaseHdc(hdc);
            bmp.Save(path, System.Drawing.Imaging.ImageFormat.Png);
            return "shot " + w + "x" + ht + " printwindow=" + ok;
        }
    }
}
'@

$proc = Get-Process sistema_solares -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $proc) { throw 'La app no esta corriendo.' }

$h = [UatWin]::FindMain([uint32]$proc.Id)
if ($h -eq [IntPtr]::Zero) { throw 'No se encontro ventana visible.' }

if ($Restore) {
    if ([UatWin]::IsIconic($h)) { [UatWin]::ShowWindow($h, 9) | Out-Null }  # SW_RESTORE
    [UatWin]::ShowWindow($h, 3) | Out-Null                                  # SW_MAXIMIZE
    [UatWin]::SetForegroundWindow($h) | Out-Null
    Start-Sleep -Milliseconds 700
}

$c = New-Object UatWin+RECT
[UatWin]::GetClientRect($h, [ref]$c) | Out-Null
$pt = New-Object UatWin+POINT
[UatWin]::ClientToScreen($h, [ref]$pt) | Out-Null

"hwnd=$($h.ToInt64()) pid=$($proc.Id) minimized=$([UatWin]::IsIconic($h))"
"client=$($c.Right)x$($c.Bottom) originScreen=$($pt.X),$($pt.Y)"

if ($Out) { [UatWin]::Shot($h, $Out) }
