#requires -Version 5.1
<#
    FASE 06 — Controlador de UI para la UAT de Windows.

    Solo se usa contra la aplicacion de ACEPTACION (el lanzador ya garantiza que
    el backend es local). Envia clics y teclas a la ventana real y guarda
    capturas como evidencia.
#>
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('click', 'type', 'paste', 'clear', 'key', 'shot', 'winshot', 'focus', 'maximize', 'drag', 'login', 'loginrel')]
    [string]$Action,
    [int]$X = 0,
    [int]$Y = 0,
    [int]$X2 = 0,
    [int]$Y2 = 0,
    [string]$Text = '',
    [string]$Out = '',
    [int]$ProcessId = 0
)

$ErrorActionPreference = 'Stop'

# Credenciales por variable de entorno: pasar 'email|password' por -Text en la
# linea de comandos se vuelve fragil (el separador se reinterpreta). La variable
# de entorno evita ese problema.
if (-not $Text -and $env:UAT_LOGIN) { $Text = $env:UAT_LOGIN }

Add-Type -AssemblyName System.Windows.Forms, System.Drawing, Microsoft.VisualBasic

function Assert-Foreground($app) {
    # Windows bloquea el robo de foco. Tres mecanismos, en orden:
    #  1) desactivar el tiempo de bloqueo de primer plano (SPI 0x2001);
    #  2) simular una pulsacion de ALT (cuenta como entrada del usuario);
    #  3) AppActivate / SetForegroundWindow, con reintentos.
    # Si aun asi no queda en primer plano, se ABORTA sin enviar teclas, para no
    # escribir en otra aplicacion (VS Code suele recuperar el foco).
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            [UatNative]::SystemParametersInfo(0x2001, 0, [IntPtr]::Zero, 0) | Out-Null
        } catch { }
        [System.Windows.Forms.SendKeys]::SendWait('%')
        Start-Sleep -Milliseconds 150
        [System.Windows.Forms.SendKeys]::SendWait('%')
        try { [Microsoft.VisualBasic.Interaction]::AppActivate($app.Id) | Out-Null } catch { }
        [UatNative]::ShowWindow($app.MainWindowHandle, 9) | Out-Null   # SW_RESTORE
        [UatNative]::BringWindowToTop($app.MainWindowHandle) | Out-Null
        [UatNative]::SetForegroundWindow($app.MainWindowHandle) | Out-Null
        Start-Sleep -Milliseconds 400
        $fg = [UatNative]::GetForegroundWindow()
        if ($fg -eq $app.MainWindowHandle) { return }
    }
    $fg = [UatNative]::GetForegroundWindow()
    throw "La aplicacion no esta en primer plano (fg=$fg, app=$($app.MainWindowHandle)). No se envia ninguna tecla."
}

if (-not ('UatNative' -as [type])) {
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class UatNative {
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, IntPtr dwExtraInfo);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool SystemParametersInfo(uint uiAction, uint uiParam, IntPtr pvParam, uint fWinIni);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdcBlt, uint nFlags);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("gdi32.dll")] public static extern IntPtr CreateCompatibleDC(IntPtr hdc);
    [DllImport("gdi32.dll")] public static extern IntPtr CreateCompatibleBitmap(IntPtr hdc, int width, int height);
    [DllImport("gdi32.dll")] public static extern IntPtr SelectObject(IntPtr hdc, IntPtr hObject);
    [DllImport("gdi32.dll")] public static extern bool DeleteDC(IntPtr hdc);
    [DllImport("gdi32.dll")] public static extern bool DeleteObject(IntPtr hObject);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
}
"@
}

function Get-AppWindow {
    param([int]$Id)
    if ($Id -gt 0) {
        $p = Get-Process -Id $Id -ErrorAction SilentlyContinue
    } else {
        $p = Get-Process -Name 'sistema_solares' -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    if (-not $p) { throw 'La aplicacion no esta en ejecucion.' }
    return $p
}

function Invoke-Click([int]$cx, [int]$cy) {
    [UatNative]::SetCursorPos($cx, $cy) | Out-Null
    Start-Sleep -Milliseconds 120
    [UatNative]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero)   # left down
    Start-Sleep -Milliseconds 60
    [UatNative]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)   # left up
    Start-Sleep -Milliseconds 250
}

function Save-Shot([string]$path) {
    $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose()
    $bmp.Dispose()
    Write-Host "shot: $path ($($b.Width)x$($b.Height))"
}

function Type-Slow([string]$value) {
    foreach ($ch in $value.ToCharArray()) {
        [System.Windows.Forms.SendKeys]::SendWait([string]$ch)
        Start-Sleep -Milliseconds 45
    }
    Start-Sleep -Milliseconds 250
}

$app = Get-AppWindow -Id $ProcessId

switch ($Action) {
    'focus' {
        [UatNative]::SetForegroundWindow($app.MainWindowHandle) | Out-Null
        Assert-Foreground $app
        Write-Host "focus: $($app.MainWindowHandle)"
    }
    'maximize' {
        [UatNative]::ShowWindow($app.MainWindowHandle, 3) | Out-Null
        [UatNative]::SetForegroundWindow($app.MainWindowHandle) | Out-Null
        Start-Sleep -Milliseconds 800
        Write-Host 'maximized'
    }
    'click' {
        [UatNative]::SetForegroundWindow($app.MainWindowHandle) | Out-Null
        Start-Sleep -Milliseconds 200
        Invoke-Click $X $Y
        Start-Sleep -Milliseconds 700
        Write-Host "click: $X,$Y"
        if ($Out) { Save-Shot $Out }
    }
    'type' {
        Assert-Foreground $app
        Type-Slow $Text
        Write-Host "type: **** (len=$($Text.Length))"
    }
    'key' {
        [System.Windows.Forms.SendKeys]::SendWait($Text)
        Start-Sleep -Milliseconds 250
        Write-Host "key: $Text"
    }
    'paste' {
        Assert-Foreground $app
        Set-Clipboard -Value $Text
        Start-Sleep -Milliseconds 200
        [System.Windows.Forms.SendKeys]::SendWait('^v')
        Start-Sleep -Milliseconds 400
        Write-Host "paste: **** (len=$($Text.Length))"
    }
    'clear' {
        Assert-Foreground $app
        [System.Windows.Forms.SendKeys]::SendWait('^a')
        Start-Sleep -Milliseconds 120
        [System.Windows.Forms.SendKeys]::SendWait('{DEL}')
        Start-Sleep -Milliseconds 200
        Write-Host 'clear: campo vaciado'
    }
    'winshot' {
        if (-not $Out) { throw 'Falta -Out' }
        # PrintWindow dibuja la ventana EN MEMORIA: no depende de que este
        # delante ni de que tenga el foco (VS Code se lo queda entre comandos).
        $rect = New-Object UatNative+RECT
        [UatNative]::GetWindowRect($app.MainWindowHandle, [ref]$rect) | Out-Null
        $width = $rect.Right - $rect.Left
        $height = $rect.Bottom - $rect.Top
        if ($width -le 0 -or $height -le 0) { throw 'La ventana no tiene tamanio utilizable.' }
        $bmp = New-Object System.Drawing.Bitmap $width, $height
        $gfx = [System.Drawing.Graphics]::FromImage($bmp)
        $hdc = $gfx.GetHdc()
        $ok = [UatNative]::PrintWindow($app.MainWindowHandle, $hdc, 2)
        $gfx.ReleaseHdc($hdc)
        $gfx.Dispose()
        $bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
        Write-Host "winshot: $Out ($width x $height) printwindow=$ok"
    }
    'shot' {
        if (-not $Out) { throw 'Falta -Out' }
        # Cada comando de terminal devuelve el foco a VS Code: se reactiva la
        # aplicacion y se captura en la MISMA invocacion.
        try { [Microsoft.VisualBasic.Interaction]::AppActivate($app.Id) | Out-Null } catch { }
        Start-Sleep -Milliseconds 700
        Save-Shot $Out
        Write-Host "foreground=$([UatNative]::GetForegroundWindow()) app=$($app.MainWindowHandle)"
    }
    'loginrel' {
        # Login con coordenadas RELATIVAS a la ventana (independiente de donde
        # este colocada), en una sola invocacion, y captura final por PrintWindow.
        $parts = $Text.Split('|')
        if ($parts.Count -ne 2) { throw 'Formato esperado: email|password' }
        $rect = New-Object UatNative+RECT
        [UatNative]::GetWindowRect($app.MainWindowHandle, [ref]$rect) | Out-Null
        Assert-Foreground $app
        Invoke-Click ($rect.Left + $X) ($rect.Top + $Y)
        [System.Windows.Forms.SendKeys]::SendWait('^a')
        [System.Windows.Forms.SendKeys]::SendWait('{DEL}')
        Type-Slow $parts[0]
        Invoke-Click ($rect.Left + $X2) ($rect.Top + $Y2)
        [System.Windows.Forms.SendKeys]::SendWait('^a')
        [System.Windows.Forms.SendKeys]::SendWait('{DEL}')
        Type-Slow $parts[1]
        [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
        Write-Host 'loginrel: credenciales enviadas'
        Start-Sleep -Seconds 9
        if ($Out) {
            $r2 = New-Object UatNative+RECT
            [UatNative]::GetWindowRect($app.MainWindowHandle, [ref]$r2) | Out-Null
            $w = $r2.Right - $r2.Left; $h = $r2.Bottom - $r2.Top
            $bmp = New-Object System.Drawing.Bitmap $w, $h
            $gfx = [System.Drawing.Graphics]::FromImage($bmp)
            $hdc = $gfx.GetHdc()
            [UatNative]::PrintWindow($app.MainWindowHandle, $hdc, 2) | Out-Null
            $gfx.ReleaseHdc($hdc); $gfx.Dispose()
            $bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
            Write-Host "winshot: $Out ($w x $h)"
        }
    }
    'login' {
        # -Text "email|password": inicio de sesion completo en una sola invocacion
        # (cada comando de terminal devuelve el foco a VS Code).
        Assert-Foreground $app
        $parts = $Text.Split('|')
        if ($parts.Count -ne 2) { throw 'Formato esperado: email|password' }
        Invoke-Click $X $Y
        [System.Windows.Forms.SendKeys]::SendWait('^a')
        [System.Windows.Forms.SendKeys]::SendWait('{DEL}')
        Type-Slow $parts[0]
        Invoke-Click $X2 $Y2
        [System.Windows.Forms.SendKeys]::SendWait('^a')
        [System.Windows.Forms.SendKeys]::SendWait('{DEL}')
        Type-Slow $parts[1]
        Write-Host 'login: credenciales escritas'
        if ($Out) { Save-Shot $Out }
        [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
        Start-Sleep -Seconds 8
    }
    'drag' {
        [UatNative]::SetForegroundWindow($app.MainWindowHandle) | Out-Null
        Start-Sleep -Milliseconds 200
        [UatNative]::SetCursorPos($X, $Y) | Out-Null
        Start-Sleep -Milliseconds 120
        [UatNative]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero)
        $steps = 12
        for ($i = 1; $i -le $steps; $i++) {
            $cx = [int]($X + (($X2 - $X) * $i / $steps))
            $cy = [int]($Y + (($Y2 - $Y) * $i / $steps))
            [UatNative]::SetCursorPos($cx, $cy) | Out-Null
            Start-Sleep -Milliseconds 30
        }
        [UatNative]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)
        Start-Sleep -Milliseconds 250
        Write-Host "drag: $X,$Y -> $X2,$Y2"
    }
}
