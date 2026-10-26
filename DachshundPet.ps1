#requires -Version 5.1
# =============================================================================
# 臘腸狗桌寵 V1.15.0 - 旺旺, a dachshund desktop pet (low-risk edition)
#   Made from Fighter V24.7: only the dachshund is kept.
#   * Offline only: this program contains no network code.
#   * Writes only into its own folder, and only when something goes wrong
#     (DachshundPet_Error_*.txt, at most 5 files per run). One exception: the alarm clocks
#     are remembered in %APPDATA%\DachshundPet\alarms.txt (deleted together with the last alarm), and a
#     birthday that is set in %APPDATA%\DachshundPet\birthday.txt.
#   * 'Welcome back': reads only how long the PC has not been used (Windows' idle time), never what was typed.
#   * Alarm clock and automatic barking: play sounds\wangwang_bark*.wav (旺旺's real bark: two, three or four barks)
#     with Windows' own sound player.
#   * Changes no Windows settings, installs nothing, needs no admin rights.
#   * Smooth edges: a small display helper (C#, compiled in memory by Windows'
#     own .NET compiler) shows the picture with soft see-through edges. If that
#     is not possible on this PC, the old colour-key window is used instead.
#     START_Dachshund_Classic.cmd starts with the old window straight away.
#   * Outfits: optional pictures in clothes\<outfit>\ (same file names); a picture an
#     outfit does not have falls back to the plain picture.
# =============================================================================
param([switch]$Classic)
$ErrorActionPreference = 'Stop'
$script:appVersion = 'V1.15.0'
$script:appTitle = '臘腸狗桌寵 ' + $script:appVersion + '（旺旺）'
try { $Host.UI.RawUI.WindowTitle = '旺旺（臘腸狗桌寵）- 關閉這個視窗會結束旺旺' } catch { }
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# -----------------------------------------------------------------------------
# Smooth edges (display only: draws the picture into this program's own window)
# -----------------------------------------------------------------------------
$smoothCode = @'
using System;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace WangwangPet
{
    public class SmoothForm : Form
    {
        protected override CreateParams CreateParams
        {
            get
            {
                CreateParams cp = base.CreateParams;
                cp.ExStyle |= 0x00080000;
                return cp;
            }
        }
    }

    public static class SmoothWindow
    {
        [StructLayout(LayoutKind.Sequential)]
        private struct POINT { public int X; public int Y; }

        [StructLayout(LayoutKind.Sequential)]
        private struct SIZE { public int CX; public int CY; }

        [StructLayout(LayoutKind.Sequential, Pack = 1)]
        private struct BLENDFUNCTION
        {
            public byte BlendOp;
            public byte BlendFlags;
            public byte SourceConstantAlpha;
            public byte AlphaFormat;
        }

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool UpdateLayeredWindow(IntPtr hwnd, IntPtr hdcDst, ref POINT pptDst, ref SIZE psize,
            IntPtr hdcSrc, ref POINT pptSrc, int crKey, ref BLENDFUNCTION pblend, int dwFlags);

        [DllImport("user32.dll")]
        private static extern IntPtr GetDC(IntPtr hWnd);

        [DllImport("user32.dll")]
        private static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);

        [DllImport("gdi32.dll")]
        private static extern IntPtr CreateCompatibleDC(IntPtr hDC);

        [DllImport("gdi32.dll")]
        private static extern bool DeleteDC(IntPtr hDC);

        [DllImport("gdi32.dll")]
        private static extern IntPtr SelectObject(IntPtr hDC, IntPtr hObject);

        [DllImport("gdi32.dll")]
        private static extern bool DeleteObject(IntPtr hObject);

        [DllImport("user32.dll")]
        private static extern int GetWindowLong(IntPtr hWnd, int nIndex);

        [DllImport("user32.dll")]
        private static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);

        [DllImport("user32.dll")]
        private static extern bool SetProcessDPIAware();

        // Tells Windows that this program draws its pictures at the real screen size (sharp at 125 %, 150 % ...).
        public static bool MakeDpiAware()
        {
            try { return SetProcessDPIAware(); } catch { return false; }
        }

        // Shows a 32-bit picture (soft see-through edges) as the whole window. Returns 0 when it worked.
        public static int Show(IntPtr hwnd, Bitmap picture, int left, int top)
        {
            IntPtr screenDc = GetDC(IntPtr.Zero);
            IntPtr memDc = CreateCompatibleDC(screenDc);
            IntPtr hBitmap = IntPtr.Zero;
            IntPtr oldBitmap = IntPtr.Zero;
            try
            {
                hBitmap = picture.GetHbitmap(Color.FromArgb(0));
                oldBitmap = SelectObject(memDc, hBitmap);
                POINT dst = new POINT();
                dst.X = left;
                dst.Y = top;
                SIZE size = new SIZE();
                size.CX = picture.Width;
                size.CY = picture.Height;
                POINT src = new POINT();
                BLENDFUNCTION blend = new BLENDFUNCTION();
                blend.BlendOp = 0;
                blend.BlendFlags = 0;
                blend.SourceConstantAlpha = 255;
                blend.AlphaFormat = 1;
                if (UpdateLayeredWindow(hwnd, screenDc, ref dst, ref size, memDc, ref src, 0, ref blend, 2))
                {
                    return 0;
                }
                int err = Marshal.GetLastWin32Error();
                return (err == 0) ? -1 : err;
            }
            finally
            {
                if (hBitmap != IntPtr.Zero)
                {
                    SelectObject(memDc, oldBitmap);
                    DeleteObject(hBitmap);
                }
                DeleteDC(memDc);
                ReleaseDC(IntPtr.Zero, screenDc);
            }
        }

        // Starts the see-through mode of the window afresh (needed when switching between the two display modes).
        public static void Reset(IntPtr hwnd)
        {
            int ex = GetWindowLong(hwnd, -20);
            SetWindowLong(hwnd, -20, ex & ~0x00080000);
            SetWindowLong(hwnd, -20, ex | 0x00080000);
        }
    }
}
'@
$script:smoothAvailable = $false
$script:smoothError = ''
if ($Classic) {
    $script:smoothError = '用 START_Dachshund_Classic.cmd 啟動（一般顯示）'
} else {
    try {
        Add-Type -TypeDefinition $smoothCode -ReferencedAssemblies @('System.Windows.Forms', 'System.Drawing') -ErrorAction Stop
        $script:smoothAvailable = $true
        # Sharp pictures on high-resolution screens: draw at the real screen size instead of being enlarged by Windows.
        try { [void][WangwangPet.SmoothWindow]::MakeDpiAware() } catch { }
    } catch {
        $script:smoothError = $_.Exception.Message
        try { Write-Host ('Smooth edges are not available on this PC, the normal view is used: ' + $script:smoothError) } catch { }
    }
}
# Breaking out of the screen (called from the icon while hidden behind other windows): a see-through layer that
# clicks go straight through and that never takes the keyboard focus, and a check which window is in front of
# 旺旺 at a few points of its body (only window positions are read, nothing inside the windows).
$glassCode = @'
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace WangwangFx
{
    public class GlassForm : Form
    {
        protected override CreateParams CreateParams
        {
            get
            {
                CreateParams cp = base.CreateParams;
                cp.ExStyle |= 0x00080000 | 0x00000020 | 0x08000000 | 0x00000080;
                return cp;
            }
        }

        protected override bool ShowWithoutActivation
        {
            get { return true; }
        }
    }

    public static class Cover
    {
        [StructLayout(LayoutKind.Sequential)]
        private struct POINT { public int X; public int Y; }

        [DllImport("user32.dll")]
        private static extern IntPtr WindowFromPoint(POINT p);

        [DllImport("user32.dll")]
        private static extern IntPtr GetAncestor(IntPtr hwnd, uint flags);

        [DllImport("user32.dll")]
        private static extern IntPtr GetWindow(IntPtr hwnd, uint cmd);

        // How many of the points (x0, y0, x1, y1 ...) show another window that lies in front of hwnd.
        public static int CountCovered(IntPtr hwnd, int[] xy)
        {
            int covered = 0;
            for (int i = 0; i + 1 < xy.Length; i += 2)
            {
                POINT p = new POINT();
                p.X = xy[i];
                p.Y = xy[i + 1];
                IntPtr w = WindowFromPoint(p);
                if (w == IntPtr.Zero) { continue; }
                IntPtr root = GetAncestor(w, 2);
                if (root == IntPtr.Zero || root == hwnd) { continue; }
                // In front of hwnd = found when walking up the window order from hwnd.
                IntPtr cur = hwnd;
                for (int k = 0; k < 3000; k++)
                {
                    cur = GetWindow(cur, 3);
                    if (cur == IntPtr.Zero) { break; }
                    if (cur == root) { covered++; break; }
                }
            }
            return covered;
        }
    }
}
'@
$script:glassAvailable = $false
if ($script:smoothAvailable) {
    try {
        Add-Type -TypeDefinition $glassCode -ReferencedAssemblies @('System.Windows.Forms', 'System.Drawing') -ErrorAction Stop
        $script:glassAvailable = $true
    } catch {
        $script:glassAvailable = $false
    }
}
# How long the PC has not been used (for 'welcome back'): only the time since the last key press or mouse move
# is read, never what was typed. Compiled on its own, so a problem here never affects the dachshund itself.
$idleCode = @'
using System;
using System.Runtime.InteropServices;

namespace WangwangPet
{
    public static class UserIdle
    {
        [StructLayout(LayoutKind.Sequential)]
        private struct LASTINPUTINFO
        {
            public uint cbSize;
            public uint dwTime;
        }

        [DllImport("user32.dll")]
        private static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);

        // Milliseconds since the last keyboard or mouse input on this PC, or -1 when it cannot be read.
        public static long Milliseconds()
        {
            LASTINPUTINFO info = new LASTINPUTINFO();
            info.cbSize = (uint)Marshal.SizeOf(typeof(LASTINPUTINFO));
            if (!GetLastInputInfo(ref info)) { return -1; }
            uint now = unchecked((uint)Environment.TickCount);
            return (long)unchecked(now - info.dwTime);
        }
    }
}
'@
$script:idleAvailable = $false
try {
    Add-Type -TypeDefinition $idleCode -ErrorAction Stop
    $script:idleAvailable = $true
} catch {
    $script:idleAvailable = $false
}
$script:smoothMode = $false
[System.Windows.Forms.Application]::EnableVisualStyles()

# Screen scale (1.0 = 100 %, 1.5 = 150 % ...): sizes and movements are multiplied by it.
$script:dpiScale = 1.0
try {
    $dpiG = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero)
    try { $script:dpiScale = [Math]::Min(3.0, [Math]::Max(1.0, $dpiG.DpiX / 96.0)) } finally { $dpiG.Dispose() }
} catch {
    $script:dpiScale = 1.0
}

function Get-Scaled([double]$value) {
    return [int][Math]::Round($value * $script:dpiScale)
}

# -----------------------------------------------------------------------------
# Error log
# -----------------------------------------------------------------------------
$script:errorLogCount = 0
$script:errorSeen = @{}

function Write-ErrorLog([string]$text, [switch]$Force) {
    # At most 5 files per run, and each message only once, so a repeating problem
    # can never flood the folder (or OneDrive) with log files.
    try {
        $sig = if ($text.Length -gt 300) { $text.Substring(0, 300) } else { $text }
        if (-not $Force) {
            if ($script:errorLogCount -ge 5) { return $null }
            if ($script:errorSeen.ContainsKey($sig)) { return $null }
        }
        $script:errorSeen[$sig] = $true
        $script:errorLogCount++
        $name = 'DachshundPet_Error_{0}_{1}.txt' -f (Get-Date -Format 'yyyyMMdd_HHmmss_fff'), $PID
        $path = Join-Path $PSScriptRoot $name
        [System.IO.File]::WriteAllText($path, ($script:appTitle + "`r`n" + $text), [System.Text.Encoding]::UTF8)
        return $path
    } catch {
        return $null
    }
}

# -----------------------------------------------------------------------------
# What the dachshund says now and then
# -----------------------------------------------------------------------------
$script:dogLines = @('汪汪！', '旺旺想去散步～', '摸摸旺旺～', '旺旺肚子餓了…', '汪嗚～', 'Woof! 你好', '陪旺旺玩～')

# -----------------------------------------------------------------------------
# Pictures
#   Every picture is resized once to the pet size. Half see-through edge pixels
#   are made fully solid or fully clear, because the window's magenta
#   see-through colour would otherwise show through them as a pink halo.
# -----------------------------------------------------------------------------
function Convert-AlphaCut([System.Drawing.Bitmap]$source) {
    $w = $source.Width
    $h = $source.Height
    $out = [System.Drawing.Bitmap]::new($w, $h, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($out)
    $ia = [System.Drawing.Imaging.ImageAttributes]::new()
    try {
        # Opacity 48 or more becomes solid, anything lower becomes clear.
        $cm = [System.Drawing.Imaging.ColorMatrix]::new()
        $cm.Matrix33 = 255
        $cm.Matrix43 = -47
        $ia.SetColorMatrix($cm)
        $g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
        $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
        $g.DrawImage($source, [System.Drawing.Rectangle]::new(0, 0, $w, $h), 0, 0, $w, $h, [System.Drawing.GraphicsUnit]::Pixel, $ia)
    } finally {
        $ia.Dispose()
        $g.Dispose()
    }
    return $out
}

function Test-AlphaCut([System.Drawing.Bitmap]$before, [System.Drawing.Bitmap]$after) {
    # Self-test on a grid of points: the result must have almost no half see-through
    # pixels, and the solid area must match what the cut should produce.
    $soft = 0
    $expected = 0
    $solid = 0
    for ($y = 3; $y -lt $after.Height; $y += 10) {
        for ($x = 3; $x -lt $after.Width; $x += 10) {
            $a = $after.GetPixel($x, $y).A
            if ($a -gt 8 -and $a -lt 247) { $soft++ }
            if ($a -ge 128) { $solid++ }
            if ($before.GetPixel($x, $y).A -ge 48) { $expected++ }
        }
    }
    if ($expected -eq 0) { return ($solid -eq 0) }
    $ratio = $solid / $expected
    return ($soft -le 3 -and $ratio -ge 0.9 -and $ratio -le 1.1)
}

function Convert-ToDisplayBitmap([byte[]]$bytes, [int]$size) {
    $ms = [System.IO.MemoryStream]::new($bytes)
    $src = $null
    $scaled = $null
    try {
        $src = [System.Drawing.Image]::FromStream($ms)
        $scaled = [System.Drawing.Bitmap]::new($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $g = [System.Drawing.Graphics]::FromImage($scaled)
        try {
            $g.Clear([System.Drawing.Color]::Transparent)
            $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
            $ratio = [Math]::Min([double]$size / $src.Width, [double]$size / $src.Height)
            $w = [int][Math]::Round($src.Width * $ratio)
            $h = [int][Math]::Round($src.Height * $ratio)
            $x = [int][Math]::Floor(($size - $w) / 2.0)
            $y = [int][Math]::Floor(($size - $h) / 2.0)
            $g.DrawImage($src, [System.Drawing.Rectangle]::new($x, $y, $w, $h))
        } finally {
            $g.Dispose()
        }
    } finally {
        if ($null -ne $src) { $src.Dispose() }
        $ms.Dispose()
    }
    # Smooth mode keeps the soft edges; the colour-key window needs them cut hard.
    if ($script:smoothMode -or -not $script:alphaCutOk) { return $scaled }
    try {
        $cut = Convert-AlphaCut $scaled
    } catch {
        $script:alphaCutOk = $false
        $null = Write-ErrorLog ('邊緣處理無法使用，改用一般圖片：' + $_.ToString())
        return $scaled
    }
    if (-not $script:alphaCutTested) {
        $script:alphaCutTested = $true
        $passed = $false
        try { $passed = Test-AlphaCut $scaled $cut } catch { $passed = $false }
        if (-not $passed) {
            $script:alphaCutOk = $false
            $null = Write-ErrorLog '邊緣處理自我檢查沒有通過，改用一般圖片（只影響邊緣外觀，不影響功能）。'
            $cut.Dispose()
            return $scaled
        }
    }
    $scaled.Dispose()
    return $cut
}

function Get-ContentKey([byte[]]$bytes, [string]$fallback) {
    # Identical picture files share one copy in memory.
    try {
        $sha = [System.Security.Cryptography.SHA256CryptoServiceProvider]::new()
        try {
            return [System.BitConverter]::ToString($sha.ComputeHash($bytes))
        } finally {
            $sha.Dispose()
        }
    } catch {
        return $fallback
    }
}

function Get-DisplayBitmap([string]$path, [bool]$flip) {
    $side = if ($flip) { '|L' } else { '|R' }
    if ($script:pathKey.ContainsKey($path)) {
        $cached = $script:bmpCache[$script:pathKey[$path] + $side]
        if ($null -ne $cached) { return $cached }
    }
    if ($flip) {
        # Mirrored copy so the character faces the way it walks.
        $right = Get-DisplayBitmap $path $false
        $left = [System.Drawing.Bitmap]$right.Clone()
        $left.RotateFlip([System.Drawing.RotateFlipType]::RotateNoneFlipX)
        $script:bmpCache[$script:pathKey[$path] + '|L'] = $left
        return $left
    }
    $fs = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        $ms = [System.IO.MemoryStream]::new()
        try {
            $fs.CopyTo($ms)
            $bytes = $ms.ToArray()
        } finally {
            $ms.Dispose()
        }
    } finally {
        $fs.Dispose()
    }
    $key = Get-ContentKey $bytes $path
    $script:pathKey[$path] = $key
    $rightKey = $key + '|R'
    if (-not $script:bmpCache.ContainsKey($rightKey)) {
        $script:bmpCache[$rightKey] = (Convert-ToDisplayBitmap $bytes $script:displaySize)
    }
    return $script:bmpCache[$rightKey]
}

function Reset-ImageCache([int]$size) {
    $script:pic.Image = $null
    $script:dogBitmap = $null
    $script:viewDirty = $true
    foreach ($b in @($script:bmpCache.Values)) {
        try { $b.Dispose() } catch { }
    }
    $script:bmpCache = @{}
    $script:displaySize = $size
    $script:currentImagePath = $null
    $script:warmIndex = 0
}

function Set-DisplayImage([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path)) { return }
    if ($script:badPaths.ContainsKey($path)) { return }
    $flip = [bool]$script:facingLeft
    $key = if ($flip) { $path + '|L' } else { $path + '|R' }
    if ($script:currentImagePath -eq $key) { return }
    try {
        $img = Get-DisplayBitmap $path $flip
    } catch {
        $script:badPaths[$path] = $true
        $null = Write-ErrorLog ('圖片無法載入：' + $path + "`r`n" + $_.ToString())
        return
    }
    $script:pic.Image = $img
    $script:dogBitmap = $img
    $script:viewDirty = $true
    $script:currentImagePath = $key
}

# -----------------------------------------------------------------------------
# Smooth-edge window: the dachshund and the speech bubble drawn into one picture
# -----------------------------------------------------------------------------
function Add-BubbleToFrame([System.Drawing.Graphics]$g, [int]$width) {
    $text = [string]$script:bubbleText
    $k = $script:dpiScale
    $maxText = [Math]::Max(40 * $k, $width - 24 * $k)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $measured = $g.MeasureString($text, $script:bubbleFont, [int]$maxText)
    $tw = [int][Math]::Ceiling($measured.Width)
    $th = [int][Math]::Ceiling($measured.Height)
    $bx = Get-Scaled 6
    $by = Get-Scaled 6
    $bw = $tw + (Get-Scaled 10)
    $bh = $th + (Get-Scaled 8)
    $r = Get-Scaled 6
    $path = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $fill = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::White)
    $pen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(110, 110, 110), [single][Math]::Max(1.0, $k))
    $ink = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(20, 100, 45))
    try {
        $path.AddArc($bx, $by, 2 * $r, 2 * $r, 180, 90)
        $path.AddArc($bx + $bw - 2 * $r, $by, 2 * $r, 2 * $r, 270, 90)
        $path.AddArc($bx + $bw - 2 * $r, $by + $bh - 2 * $r, 2 * $r, 2 * $r, 0, 90)
        $path.AddArc($bx, $by + $bh - 2 * $r, 2 * $r, 2 * $r, 90, 90)
        $path.CloseFigure()
        $g.FillPath($fill, $path)
        $g.DrawPath($pen, $path)
        $textBox = [System.Drawing.RectangleF]::new([single]($bx + 5 * $k), [single]($by + 4 * $k), [single]($tw + 1), [single]($th + 1))
        $g.DrawString($text, $script:bubbleFont, $ink, $textBox)
    } finally {
        $ink.Dispose()
        $pen.Dispose()
        $fill.Dispose()
        $path.Dispose()
    }
}

function Update-SmoothView {
    if (-not $script:smoothMode) { return }
    $script:viewDirty = $false
    $w = $script:form.Width
    $h = $script:form.Height
    $frame = [System.Drawing.Bitmap]::new($w, $h, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        $g = [System.Drawing.Graphics]::FromImage($frame)
        try {
            if ($script:testBackground) {
                $g.Clear([System.Drawing.Color]::FromArgb(235, 242, 250))
            } else {
                $g.Clear([System.Drawing.Color]::Transparent)
            }
            if ($null -ne $script:dogBitmap) {
                # The display picture already has the window size: copy it pixel for pixel.
                $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
                $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
                $g.DrawImage($script:dogBitmap, [System.Drawing.Rectangle]::new(0, 0, $w, $h))
            }
            if ($script:bubbleTicks -gt 0 -and -not [string]::IsNullOrEmpty($script:bubbleText)) {
                Add-BubbleToFrame $g $w
            }
        } finally {
            $g.Dispose()
        }
        $code = [WangwangPet.SmoothWindow]::Show($script:form.Handle, $frame, $script:form.Left, $script:form.Top)
        if ($code -ne 0) { throw ('平滑邊緣顯示失敗，代碼 ' + $code) }
    } finally {
        $frame.Dispose()
    }
}

function Set-ViewMode([bool]$smooth) {
    # $true = smooth edges (layered picture), $false = the old colour-key window.
    if ($smooth -and -not $script:smoothAvailable) { return }
    if ($smooth -eq $script:smoothMode) { return }
    $script:smoothMode = $smooth
    $script:testBackground = $false
    if ($smooth) {
        $script:bubble.Visible = $false
        $script:pic.Visible = $false
        $script:form.TransparencyKey = [System.Drawing.Color]::Empty
        [WangwangPet.SmoothWindow]::Reset($script:form.Handle)
    } else {
        if ($script:smoothAvailable) { [WangwangPet.SmoothWindow]::Reset($script:form.Handle) }
        $script:form.BackColor = [System.Drawing.Color]::Magenta
        $script:form.TransparencyKey = [System.Drawing.Color]::Magenta
        $script:pic.Visible = $true
        $script:pic.BringToFront()
        if ($script:bubbleTicks -gt 0) {
            $script:bubble.Text = [string]$script:bubbleText
            $script:bubble.Visible = $true
            $script:bubble.BringToFront()
        }
    }
    try { $script:miDisplay.Text = '顯示測試（不透明背景）' } catch { }
    try { $script:miSmooth.Checked = $smooth } catch { }
    Reset-ImageCache $script:displaySize
    $nowPath = Get-DogFramePath
    if ($null -eq $nowPath) { $nowPath = Get-WagFramePath 'idle' 0 }
    Set-DisplayImage ([string]$nowPath)
    if ($smooth) { Update-SmoothView } else { $script:form.Refresh() }
}

# -----------------------------------------------------------------------------
# Pictures and outfits
# -----------------------------------------------------------------------------
function Get-OutfitPicture([string]$fileName) {
    # The outfit's own picture when it has one, otherwise the plain (no clothes) picture.
    if (-not [string]::IsNullOrEmpty($script:outfitDir)) {
        $op = Join-Path $script:outfitDir $fileName
        if (Test-Path -LiteralPath $op) { return $op }
    }
    $bp = Join-Path $PSScriptRoot $fileName
    if (Test-Path -LiteralPath $bp) { return $bp }
    return $null
}

function Import-DogPictures {
    $main = Get-OutfitPicture 'dachshund_3d_00.png'
    if ($null -eq $main) { throw ('找不到臘腸狗圖片：' + (Join-Path $PSScriptRoot 'dachshund_3d_00.png')) }
    $script:dogMain = $main
    # Tail wag: used only when all three pictures are present.
    $script:dogWagFrames = @()
    $wagFrames = @()
    foreach ($dn in @('dachshund_3d_01.png', 'dachshund_3d_00.png', 'dachshund_3d_02.png')) {
        $dp = Get-OutfitPicture $dn
        if ($null -ne $dp) { $wagFrames += $dp }
    }
    if ($wagFrames.Count -eq 3) { $script:dogWagFrames = $wagFrames }
    # Walking legs (4 poses): used only when all four pictures are present.
    $script:dogWalkFrames = @()
    $walkFrames = @()
    foreach ($wn in @('dachshund_3d_walk_00.png', 'dachshund_3d_walk_01.png', 'dachshund_3d_walk_02.png', 'dachshund_3d_walk_03.png')) {
        $wp = Get-OutfitPicture $wn
        if ($null -ne $wp) { $walkFrames += $wp }
    }
    if ($walkFrames.Count -eq 4) { $script:dogWalkFrames = $walkFrames }
    # Happy face with the tongue out (after a pat, a bark or petting), same tail positions as the wag.
    $script:dogHappyFrames = @()
    $happyFrames = @()
    foreach ($hn in @('dachshund_3d_happy_01.png', 'dachshund_3d_happy_00.png', 'dachshund_3d_happy_02.png')) {
        $hp = Get-OutfitPicture $hn
        if ($null -ne $hp) { $happyFrames += $hp }
    }
    if ($happyFrames.Count -eq 3) { $script:dogHappyFrames = $happyFrames }
    # Blinking while standing (eyes closed), same tail positions as the wag.
    $script:dogBlinkFrames = @()
    $blinkFrames = @()
    foreach ($bn in @('dachshund_3d_blink_01.png', 'dachshund_3d_blink_00.png', 'dachshund_3d_blink_02.png')) {
        $bp = Get-OutfitPicture $bn
        if ($null -ne $bp) { $blinkFrames += $bp }
    }
    if ($blinkFrames.Count -eq 3) { $script:dogBlinkFrames = $blinkFrames }
    # Extra poses: head tilt, sniffing, lying down, sleeping, play bow, crouch, yawn, sitting.
    $script:dogPoses = @{}
    foreach ($pn in @('tilt_00', 'tilt_01', 'sniff_00', 'sniff_01', 'lie_00', 'sleep_00', 'bow_00', 'crouch_00', 'sidesleep_00', 'belly_00', 'yawn_00', 'sit_00', 'flat_00', 'curl_00', 'bed_00', 'shake_00', 'shake_01', 'shake_02', 'shake_03', 'eat_00', 'eat_01', 'eat_02', 'drink_00', 'drink_01',
            'run_00', 'run_01', 'fall_00', 'rub_00', 'paw_00', 'jerky_00', 'jerky_01')) {
        $pp = Get-OutfitPicture ('dachshund_3d_' + $pn + '.png')
        if ($null -ne $pp) { $script:dogPoses[$pn] = $pp }
    }
    # Drinking, running, falling, the belly rub, the handshake and eating the jerky only with the outfit's own pictures
    # (the plain picture would take the clothes off for a moment).
    if (-not [string]::IsNullOrEmpty($script:outfitDir)) {
        foreach ($pn in @('drink_00', 'drink_01', 'run_00', 'run_01', 'fall_00', 'rub_00', 'paw_00', 'jerky_00', 'jerky_01')) {
            if (-not (Test-Path -LiteralPath (Join-Path $script:outfitDir ('dachshund_3d_' + $pn + '.png')))) { [void]$script:dogPoses.Remove($pn) }
        }
    }
}

function Update-WarmList {
    # Pictures to prepare in the background (one per animation tick).
    $script:warmList.Clear()
    $warmSeen = [System.Collections.Generic.HashSet[string]]::new()
    $warmOrder = @($script:dogMain)
    $warmOrder += $script:dogWagFrames
    $warmOrder += $script:dogWalkFrames
    $warmOrder += $script:dogHappyFrames
    $warmOrder += $script:dogBlinkFrames
    $warmOrder += @($script:dogPoses.Values)
    foreach ($wp in $warmOrder) {
        if ($warmSeen.Add([string]$wp)) { $script:warmList.Add([string]$wp) }
    }
    $script:warmIndex = 0
}

function Test-NightTime {
    # Night = 22:00 to 06:59 (this PC's clock).
    $h = (Get-Date).Hour
    return ($h -ge 22 -or $h -lt 7)
}

function Get-SwatchImage([string]$folder) {
    # clothes\<outfit>\swatch.png: a small piece of the outfit's fabric for the menu (optional).
    if ([string]::IsNullOrEmpty($folder)) { return $null }
    $sp = Join-Path (Join-Path $PSScriptRoot $folder) 'swatch.png'
    if (-not (Test-Path -LiteralPath $sp)) { return $null }
    try {
        $ms = [System.IO.MemoryStream]::new([System.IO.File]::ReadAllBytes($sp))
        try {
            $img = [System.Drawing.Image]::FromStream($ms)
            try {
                return [System.Drawing.Bitmap]::new($img)
            } finally {
                $img.Dispose()
            }
        } finally {
            $ms.Dispose()
        }
    } catch {
        return $null
    }
}

function Show-OutfitSwatch($g, [string]$id, [double]$right, [double]$centerY, [int]$rowHeight, [double]$minLeft) {
    # Draws the outfit's fabric swatch (with a thin grey frame), right-aligned at $right and centred on $centerY.
    $swb = $script:outfitSwatches[$id]
    if ($null -eq $swb) { return $false }
    $h = [Math]::Max(8, $rowHeight - 6)
    $w = [int][Math]::Round($h * 1.8)
    $x = [int][Math]::Round($right) - $w
    if ($x -lt $minLeft) { $x = [int][Math]::Round($minLeft) }
    $y = [int][Math]::Round($centerY - $h / 2.0)
    $state = $g.Save()
    try {
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
        $g.DrawImage($swb, [System.Drawing.Rectangle]::new($x, $y, $w, $h))
        $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Default
        $edge = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(140, 140, 140), 1)
        try { $g.DrawRectangle($edge, $x, $y, $w - 1, $h - 1) } finally { $edge.Dispose() }
    } finally {
        $g.Restore($state)
    }
    return $true
}

function Test-OutfitReady([string]$folder) {
    if ([string]::IsNullOrEmpty($folder)) { return $true }
    return [bool](Test-Path -LiteralPath (Join-Path (Join-Path $PSScriptRoot $folder) 'dachshund_3d_00.png'))
}

function Update-OutfitChecks {
    # The outfit being worn is ticked, and so is the group it is in.
    $grpOf = ''
    foreach ($o in $script:outfitList) {
        if ([string]$o[0] -eq $script:outfitId -and $o.Count -ge 4) { $grpOf = [string]$o[3] }
    }
    foreach ($item in $script:outfitMenuItems) { $item.Checked = ([string]$item.Tag -eq $script:outfitId) }
    if ($null -ne $script:outfitGroupItems) {
        foreach ($key in @($script:outfitGroupItems.Keys)) { $script:outfitGroupItems[$key].Checked = ([string]$key -eq $grpOf) }
    }
}

function Set-DogOutfit([string]$id) {
    $info = $null
    foreach ($o in $script:outfitList) {
        if ([string]$o[0] -eq $id) { $info = $o }
    }
    if ($null -eq $info) { return }
    if (-not (Test-OutfitReady ([string]$info[2]))) {
        Set-Bubble ('找不到「' + [string]$info[1] + '」的圖片')
        return
    }
    $script:outfitDir = ''
    if (-not [string]::IsNullOrEmpty([string]$info[2])) { $script:outfitDir = Join-Path $PSScriptRoot ([string]$info[2]) }
    $script:outfitId = $id
    Import-DogPictures
    Reset-ImageCache $script:displaySize
    Update-WarmList
    # Show the new clothes right away, in whatever pose the dachshund is in now.
    $nowPath = Get-DogFramePath
    if ($null -eq $nowPath) { $nowPath = Get-WagFramePath 'idle' 0 }
    Set-DisplayImage ([string]$nowPath)
    Update-OutfitChecks
    if ($id -eq 'none') {
        Set-Bubble '旺旺把衣服脫掉了，好輕鬆～'
    } else {
        Set-Bubble ('旺旺換上' + [string]$info[1] + '了！')
    }
}

# -----------------------------------------------------------------------------
# Pet behaviour
# -----------------------------------------------------------------------------
function Test-RunFrames {
    # Running: legs gathered under the body (run_00) and stretched out in a leap (run_01).
    return ($script:dogPoses.ContainsKey('run_00') -and $script:dogPoses.ContainsKey('run_01'))
}

function Get-RoamBounds {
    $wa = [System.Windows.Forms.Screen]::FromControl($script:form).WorkingArea
    $w = $script:form.Width
    $h = $script:form.Height
    # The work area of the screen the dachshund is on (never under the taskbar).
    $minX = $wa.Left + 10
    $maxX = $wa.Right - $w - 10
    if ($maxX -lt $minX) { $minX = $wa.Left; $maxX = [Math]::Max($wa.Left, $wa.Right - $w) }
    $minY = $wa.Top + 20
    $maxY = $wa.Bottom - $h
    if ($maxY -lt $minY) { $minY = $wa.Top; $maxY = [Math]::Max($wa.Top, $wa.Bottom - $h) }
    return @($minX, $maxX, $minY, $maxY)
}

function Get-GroundBounds {
    # Gravity mode: @(left, right, top, ground) for the window on the screen the dachshund is on.
    # The ground is the top of the taskbar: the feet (at 674 of the 768-pixel pictures) stand on it.
    $w = $script:form.Width
    $h = $script:form.Height
    $center = [System.Drawing.Point]::new([int]($script:baseLocation.X + $w / 2), [int]($script:baseLocation.Y + $h / 2))
    $wa = [System.Windows.Forms.Screen]::FromPoint($center).WorkingArea
    $ground = $wa.Bottom - [int][Math]::Round($h * 674.0 / 768.0)
    return @($wa.Left, [Math]::Max($wa.Left, $wa.Right - $w), $wa.Top, $ground)
}

function Step-Roam {
    if ($script:roamPauseTicks -gt 0) {
        $script:roamPauseTicks--
        $script:roamMoving = $false
        return
    }
    # When chasing the mouse, aim next to the pointer and re-aim about once a second.
    $circleChase = ($script:clockTick -lt $script:circleChaseUntil)
    $chasing = [bool]$script:dogChaseMouse -or [bool]$script:begging -or $circleChase
    if ($chasing -and ($script:clockTick % 15) -eq 0) { $script:roamTarget = $null }
    if ($null -eq $script:roamTarget) {
        $b = Get-RoamBounds
        if ($script:gravityMode) {
            # Gravity mode: only along the top of the taskbar.
            $gb = Get-GroundBounds
            $b = @($gb[0], $gb[1], $gb[3], $gb[3])
        }
        if ($chasing) {
            $cur = [System.Windows.Forms.Cursor]::Position
            $tx = [int]($cur.X - $script:form.Width / 2)
            $ty = [int]($cur.Y - $script:form.Height * 0.7)
            $tx = [Math]::Min([Math]::Max($tx, [int]$b[0]), [int]$b[1])
            $ty = [Math]::Min([Math]::Max($ty, [int]$b[2]), [int]$b[3])
        } else {
            $tx = $script:rng.Next([int]$b[0], [int]$b[1] + 1)
            $ty = $script:rng.Next([int]$b[2], [int]$b[3] + 1)
        }
        $script:roamTarget = [System.Drawing.Point]::new($tx, $ty)
    }
    # Re-sync after the pet was dragged or resized.
    if ([Math]::Abs($script:roamX - $script:baseLocation.X) -gt 2 -or [Math]::Abs($script:roamY - $script:baseLocation.Y) -gt 2) {
        $script:roamX = [double]$script:baseLocation.X
        $script:roamY = [double]$script:baseLocation.Y
    }
    $dx = $script:roamTarget.X - $script:roamX
    $dy = $script:roamTarget.Y - $script:roamY
    $dist = [Math]::Sqrt($dx * $dx + $dy * $dy)
    # Steps in proportion to the size: a mini dachshund takes small steps, a giant one big steps.
    $stepLen = $script:roamSpeed * $script:dpiScale * $script:sizeRatio
    # Running (chasing the pointer, or coming over to ask for food or water): at least the 'fast' speed.
    if ($chasing -and (Test-RunFrames)) { $stepLen = [Math]::Max($script:roamSpeed, 5.0) * $script:dpiScale * $script:sizeRatio }
    # Running after the circling pointer: faster than walking.
    if ($circleChase) { $stepLen = [Math]::Max($script:roamSpeed, 5.0) * 1.5 * $script:dpiScale * $script:sizeRatio }
    if ($dist -le $stepLen) {
        # Arrived: rest 2.4 to 8.4 seconds, then pick a new spot.
        $script:baseLocation = $script:roamTarget
        $script:roamX = [double]$script:roamTarget.X
        $script:roamY = [double]$script:roamTarget.Y
        $script:roamTarget = $null
        $script:roamMoving = $false
        if ($script:begging) {
            # Came over to ask for food or water.
            $script:roamPauseTicks = 60
            Invoke-DogBeg
        } elseif ($circleChase) {
            # Caught up with the circling pointer: spins round with it.
            $script:circleChaseUntil = 0
            $script:roamPauseTicks = 20
            Start-DogAction 'spin' '抓到了！一起轉圈圈～'
        } elseif ($chasing) {
            # Caught up with the pointer: short rest, sometimes a happy bark.
            if ($script:roamWalkTicks -gt 25 -and $script:rng.Next(0, 2) -eq 0) { Set-Bubble '汪！抓到你了' }
            $script:roamPauseTicks = $script:rng.Next(8, 30)
        } else {
            $script:roamPauseTicks = $script:rng.Next(40, 140)
        }
        $script:roamWalkTicks = 0
        return
    }
    if ([Math]::Abs($dx) -gt 2) { $script:facingLeft = ($dx -lt 0) }
    $script:roamX = $script:roamX + $dx / $dist * $stepLen
    $script:roamY = $script:roamY + $dy / $dist * $stepLen
    $script:baseLocation = [System.Drawing.Point]::new([int][Math]::Round($script:roamX), [int][Math]::Round($script:roamY))
    $script:roamMoving = $true
    $script:roamWalkTicks++
}

function Assert-OnScreen {
    # Bring the dachshund back if it is no longer on any screen (for example a second monitor was unplugged).
    $rect = [System.Drawing.Rectangle]::new($script:baseLocation.X, $script:baseLocation.Y, $script:form.Width, $script:form.Height)
    foreach ($scr in [System.Windows.Forms.Screen]::AllScreens) {
        $inter = [System.Drawing.Rectangle]::Intersect($scr.WorkingArea, $rect)
        if ($inter.Width -ge 40 -and $inter.Height -ge 40) { return }
    }
    $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $script:baseLocation = [System.Drawing.Point]::new([Math]::Max($wa.Left, $wa.Right - $script:form.Width - 110), [Math]::Max($wa.Top, $wa.Bottom - $script:form.Height))
    $script:roamTarget = $null
}

function Get-WagFramePath([string]$mode, [int]$tick) {
    # Standing tail wag: up, middle, down, middle ... (faster when happy).
    if ($script:dogWagFrames.Count -ne 3) { return $script:dogMain }
    $seq = @(0, 1, 2, 1)
    if ($mode -eq 'idle') {
        $speed = 8
    } else {
        $speed = 4
    }
    # Floor, not rounding: rounding could produce index 4 (no picture) for part of every cycle.
    $idx = $seq[([int][Math]::Floor($tick / $speed)) % $seq.Count]
    if ($mode -eq 'idle' -and $script:blinkTicks -gt 0 -and $script:dogBlinkFrames.Count -eq 3) { return $script:dogBlinkFrames[$idx] }
    return $script:dogWagFrames[$idx]
}

function Set-Bubble([string]$message) {
    $script:bubbleText = $message
    $script:bubbleTicks = 45
    if ($script:smoothMode) {
        $script:viewDirty = $true
    } else {
        $script:bubble.Text = $message
        $script:bubble.Visible = $true
        $script:bubble.BringToFront()
    }
}

function Update-BubbleFont {
    # The bubble text follows the size of the dachshund (kept readable: 10 to 18 px at 100 %).
    $px = [Math]::Max(10.0, [Math]::Min(18.0, 12.0 * $script:sizeRatio)) * $script:dpiScale
    $old = $script:bubbleFont
    $script:bubbleFont = [System.Drawing.Font]::new('Microsoft JhengHei', [single]$px, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    if ($null -ne $old) { try { $old.Dispose() } catch { } }
    if ($null -ne $script:bubble) {
        $pt = [Math]::Max(8.0, [Math]::Min(13.0, 9.0 * $script:sizeRatio))
        $oldLabel = $script:bubble.Font
        $script:bubble.Font = [System.Drawing.Font]::new('Microsoft JhengHei', [single]$pt, [System.Drawing.FontStyle]::Bold)
        if ($null -ne $oldLabel) { try { $oldLabel.Dispose() } catch { } }
    }
}

function Set-PetSize([int]$size) {
    foreach ($item in $script:sizeMenuItems) { $item.Checked = ([int]$item.Tag -eq $size) }
    # Never taller than 60 % of the screen (a giant dachshund on a small or very high-DPI screen).
    $wa = [System.Windows.Forms.Screen]::FromControl($script:form).WorkingArea
    $fit = [Math]::Max(60, [int]($wa.Height * 0.6))
    $script:sizeCapped = ($size -gt $fit)
    if ($script:sizeCapped) { $size = $fit }
    if ($size -eq $script:form.Width) { return }
    # Keep the feet and the middle of the dachshund where they were.
    $old = $script:form.Width
    $centerX = $script:baseLocation.X + [int][Math]::Floor($old / 2.0)
    $bottom = $script:baseLocation.Y + $old
    $script:form.Size = [System.Drawing.Size]::new($size, $size)
    $script:pic.Size = $script:form.ClientSize
    $script:bubble.MaximumSize = [System.Drawing.Size]::new($size - 12, 0)
    $script:baseLocation = [System.Drawing.Point]::new($centerX - [int][Math]::Floor($size / 2.0), $bottom - $size)
    # Growing near the edge of the screen: move back so the whole dachshund stays visible.
    $keepX = [Math]::Min([Math]::Max($script:baseLocation.X, $wa.Left), [Math]::Max($wa.Left, $wa.Right - $size))
    $keepY = [Math]::Min([Math]::Max($script:baseLocation.Y, $wa.Top), [Math]::Max($wa.Top, $wa.Bottom - $size))
    $script:baseLocation = [System.Drawing.Point]::new([int]$keepX, [int]$keepY)
    if ($script:gravityMode) {
        # Gravity mode: stays standing on the taskbar.
        $gb = Get-GroundBounds
        $script:baseLocation = [System.Drawing.Point]::new($script:baseLocation.X, [int]$gb[3])
    }
    $script:form.Location = $script:baseLocation
    $script:roamTarget = $null
    # Hops, breathing, walking speed and the bubble text all follow the new size.
    $script:sizeRatio = [double]$size / [double](Get-Scaled 250)
    Update-BubbleFont
    Reset-ImageCache $size
    # Keep the pose it is in now (lying, sitting, sleeping ...).
    $nowPath = Get-DogFramePath
    if ($null -eq $nowPath) { $nowPath = Get-WagFramePath 'idle' 0 }
    Set-DisplayImage ([string]$nowPath)
}

# -----------------------------------------------------------------------------
# Hiding for a meeting or screen sharing: a dachshund icon by the clock brings it back
# -----------------------------------------------------------------------------
function Get-TrayIcon {
    if ($null -ne $script:trayIcon) { return $script:trayIcon }
    $ni = New-Object System.Windows.Forms.NotifyIcon
    $icon = $null
    $icoPath = Join-Path $PSScriptRoot 'wangwang.ico'
    if (Test-Path -LiteralPath $icoPath) {
        try { $icon = [System.Drawing.Icon]::new($icoPath, [System.Windows.Forms.SystemInformation]::SmallIconSize) } catch { $icon = $null }
    }
    if ($null -eq $icon) { $icon = [System.Drawing.SystemIcons]::Application }
    $ni.Icon = $icon
    $ni.Text = $script:trayTextNormal
    $ni.Add_MouseClick({
        param($sender, $e)
        if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
            try { Invoke-DogSummon } catch { $null = Write-ErrorLog ('叫旺旺過來錯誤：' + $_.ToString()) }
        }
    })
    $trayMenu = New-Object System.Windows.Forms.ContextMenuStrip
    $trayBack = $trayMenu.Items.Add('叫旺旺過來')
    $trayBack.Add_Click({ try { Invoke-DogSummon } catch { $null = Write-ErrorLog ('叫旺旺過來錯誤：' + $_.ToString()) } })
    $trayQuit = $trayMenu.Items.Add('關閉旺旺')
    $trayQuit.Add_Click({ $script:form.Close() })
    $ni.ContextMenuStrip = $trayMenu
    $script:trayIcon = $ni
    return $ni
}

function Test-DogCovered {
    # Is 旺旺 behind another window? Six points on its body; two or more covered = behind.
    if (-not $script:glassAvailable -or $script:dogHidden) { return $false }
    $w = [double]$script:form.Width
    $h = [double]$script:form.Height
    $pts = New-Object 'int[]' 12
    $i = 0
    foreach ($fy in @(0.62, 0.72)) {
        foreach ($fx in @(0.33, 0.45, 0.57)) {
            $px = $fx
            if ($script:facingLeft) { $px = 1.0 - $fx }
            $pts[$i] = [int]($script:form.Left + $w * $px)
            $pts[$i + 1] = [int]($script:form.Top + $h * $fy)
            $i += 2
        }
    }
    return ([WangwangFx.Cover]::CountCovered($script:form.Handle, $pts) -ge 2)
}

function Initialize-GlassWindow {
    if ($null -ne $script:glassForm) { return }
    $gf = New-Object WangwangFx.GlassForm
    $gf.Text = '旺旺衝出來'
    $gf.FormBorderStyle = 'None'
    $gf.StartPosition = 'Manual'
    $gf.TopMost = $true
    $gf.ShowInTaskbar = $false
    $gf.Width = 20
    $gf.Height = 20
    $gf.Location = [System.Drawing.Point]::new(-25000, -25000)
    $script:glassBlank = [System.Drawing.Bitmap]::new(2, 2, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $script:glassForm = $gf
    $gf.Show()
    [WangwangPet.SmoothWindow]::Reset($gf.Handle)
}

function Hide-GlassFx {
    $script:glassTick = -1
    if ($null -eq $script:glassForm) { return }
    try { [void][WangwangPet.SmoothWindow]::Show($script:glassForm.Handle, $script:glassBlank, -25000, -25000) } catch { }
}

function Start-GlassBurst {
    # Called after 旺旺 was moved next to the mouse pointer: it is kept out of sight while the screen cracks,
    # then it jumps out of the hole (drawn on the glass layer) and the real 旺旺 takes over when it lands.
    Initialize-GlassWindow
    $w = [double]$script:form.Width
    $h = [double]$script:form.Height
    $S = [int][Math]::Round($w * 2.6)
    $script:glassSize = $S
    $script:glassCx = [double]$script:baseLocation.X + $w * 0.5
    $script:glassCy = [double]$script:baseLocation.Y + $h * 0.58
    $script:glassLeft = [int]($script:glassCx - $S / 2.0)
    $script:glassTop = [int]($script:glassCy - $S / 2.0)
    $c = $S / 2.0
    $rng = $script:rng
    # Cracks: jagged lines out from the point of impact, and broken rings between them.
    $n = 11
    $angles = @()
    for ($i = 0; $i -lt $n; $i++) { $angles += (2 * [Math]::PI * $i / $n + ($rng.NextDouble() - 0.5) * 0.35) }
    $cracks = @()
    foreach ($a in $angles) {
        $len = $S * (0.30 + $rng.NextDouble() * 0.16)
        $pl = New-Object 'System.Drawing.PointF[]' 6
        for ($k = 0; $k -lt 6; $k++) {
            $r = $S * 0.03 + ($len - $S * 0.03) * $k / 5.0
            $aa = $a + ($rng.NextDouble() - 0.5) * 0.12
            $pl[$k] = [System.Drawing.PointF]::new([float]($c + [Math]::Cos($aa) * $r), [float]($c + [Math]::Sin($aa) * $r))
        }
        $cracks += ,$pl
    }
    $script:glassCracks = $cracks
    $rings = @()
    foreach ($rr in @(0.11, 0.21)) {
        for ($i = 0; $i -lt $n; $i++) {
            if ($rng.NextDouble() -gt 0.75) { continue }
            $a1 = $angles[$i]
            $a2 = $angles[($i + 1) % $n]
            if ($a2 -lt $a1) { $a2 += 2 * [Math]::PI }
            $r1 = $S * $rr * (0.9 + $rng.NextDouble() * 0.2)
            $r2 = $S * $rr * (0.9 + $rng.NextDouble() * 0.2)
            $am = ($a1 + $a2) / 2.0
            $rm = ($r1 + $r2) / 2.0 * 0.96
            $seg = New-Object 'System.Drawing.PointF[]' 3
            $seg[0] = [System.Drawing.PointF]::new([float]($c + [Math]::Cos($a1) * $r1), [float]($c + [Math]::Sin($a1) * $r1))
            $seg[1] = [System.Drawing.PointF]::new([float]($c + [Math]::Cos($am) * $rm), [float]($c + [Math]::Sin($am) * $rm))
            $seg[2] = [System.Drawing.PointF]::new([float]($c + [Math]::Cos($a2) * $r2), [float]($c + [Math]::Sin($a2) * $r2))
            $rings += ,$seg
        }
    }
    $script:glassRings = $rings
    # The hole 旺旺 jumps through.
    $hole = New-Object 'System.Drawing.PointF[]' $n
    for ($i = 0; $i -lt $n; $i++) {
        $r = $S * (0.08 + $rng.NextDouble() * 0.05)
        $hole[$i] = [System.Drawing.PointF]::new([float]($c + [Math]::Cos($angles[$i]) * $r), [float]($c + [Math]::Sin($angles[$i]) * $r))
    }
    $script:glassHole = $hole
    # Glass pieces: wedges between the cracks, and small splinters. Each: centre, speed, turn, corner offsets.
    $shards = @()
    for ($i = 0; $i -lt $n; $i++) {
        $a1 = $angles[$i]
        $a2 = $angles[($i + 1) % $n]
        if ($a2 -lt $a1) { $a2 += 2 * [Math]::PI }
        $r1 = $S * (0.04 + $rng.NextDouble() * 0.04)
        $r2 = $S * (0.10 + $rng.NextDouble() * 0.09)
        $corner = @(@($a1, $r1), @($a1, $r2), @($a2, $r2 * 0.9), @($a2, $r1))
        $shards += ,(New-GlassShard $corner $c $S $rng)
    }
    for ($i = 0; $i -lt 16; $i++) {
        $a = $rng.NextDouble() * 2 * [Math]::PI
        $r = $S * (0.03 + $rng.NextDouble() * 0.12)
        $sz = $S * (0.008 + $rng.NextDouble() * 0.018)
        $corner = @(@($a, $r), @($a + $sz / $r, $r + $sz), @($a - $sz / $r, $r + $sz * 0.6))
        $shards += ,(New-GlassShard $corner $c $S $rng)
    }
    $script:glassShards = $shards
    # 旺旺 in mid-jump (the short-legged hop) when that picture is there.
    $script:glassDogPath = [string]$script:dogMain
    if ($script:dogPoses.ContainsKey('run_01')) { $script:glassDogPath = [string]$script:dogPoses['run_01'] }
    $script:glassDogFlip = [bool]$script:facingLeft
    $script:glassTick = 0
    # The dachshund itself waits out of sight until it lands.
    $script:dogSleeping = $false
    $script:dogNightSleep = $false
    $script:dogAct = 'burst'
    $script:dogActTick = 0
    $script:dogActLen = 26
    $script:actionMode = 'idle'
    $script:actionTick = 0
    $script:form.Location = [System.Drawing.Point]::new(-25000, -25000)
    # The glass layer in front of everything.
    $script:glassForm.TopMost = $false
    $script:glassForm.TopMost = $true
    Update-GlassFx
}

function New-GlassShard($corner, [double]$c, [double]$S, $rng) {
    $px = @()
    $py = @()
    foreach ($cr in $corner) {
        $px += ($c + [Math]::Cos([double]$cr[0]) * [double]$cr[1])
        $py += ($c + [Math]::Sin([double]$cr[0]) * [double]$cr[1])
    }
    $mx = 0.0
    $my = 0.0
    for ($k = 0; $k -lt $px.Count; $k++) {
        $mx += $px[$k] / $px.Count
        $my += $py[$k] / $py.Count
    }
    $dx = @()
    $dy = @()
    for ($k = 0; $k -lt $px.Count; $k++) {
        $dx += ($px[$k] - $mx)
        $dy += ($py[$k] - $my)
    }
    $dir = [Math]::Atan2($my - $c, $mx - $c)
    $spd = $S * (0.010 + $rng.NextDouble() * 0.020)
    return @{
        X = $mx; Y = $my; DX = $dx; DY = $dy; Rot = 0.0
        VX = [Math]::Cos($dir) * $spd; VY = [Math]::Sin($dir) * $spd - $S * 0.012
        VR = ($rng.NextDouble() - 0.5) * 0.5
    }
}

function Update-GlassFx {
    # One picture of the breaking glass per animation tick (about 1.8 seconds in all).
    if ($script:glassTick -lt 0) { return }
    $g0 = $script:glassTick
    $script:glassTick++
    if ($g0 -gt 30) { Hide-GlassFx; return }
    $S = $script:glassSize
    $c = $S / 2.0
    if ($g0 -eq 4 -and $script:autoBarkSound) {
        # The sound of breaking glass (only when 旺旺's sounds are switched on).
        try {
            if ($null -eq $script:glassPlayer) {
                $gw = Join-Path $PSScriptRoot 'sounds\glass_break.wav'
                if (Test-Path -LiteralPath $gw) { $script:glassPlayer = New-Object System.Media.SoundPlayer($gw); $script:glassPlayer.Load() }
            }
            if ($null -ne $script:glassPlayer) { $script:glassPlayer.Play() }
        } catch { $null = Write-ErrorLog ('玻璃聲音錯誤：' + $_.ToString()) }
    }
    $bmp = [System.Drawing.Bitmap]::new($S, $S, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        try {
            $g.Clear([System.Drawing.Color]::Transparent)
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $lw = [float][Math]::Max(1.5, $S / 300.0)
            # The flash of the impact.
            if ($g0 -le 1) {
                $fr = [float]($S * (0.04 + 0.03 * $g0))
                $fb = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(170 - 60 * $g0, 255, 255, 255))
                try { $g.FillEllipse($fb, [float]($c - $fr), [float]($c - $fr), [float](2 * $fr), [float](2 * $fr)) } finally { $fb.Dispose() }
            }
            # The hole, fading as 旺旺 comes through.
            if ($g0 -ge 4 -and $g0 -lt 13) {
                $ha = [int](210 * [Math]::Min(1.0, (13 - $g0) / 5.0))
                $hb = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb($ha, 18, 20, 28))
                try { $g.FillPolygon($hb, $script:glassHole) } finally { $hb.Dispose() }
            }
            # Cracks: grow in the first four pictures, fade out after the landing.
            $ca = 235
            if ($g0 -gt 10) { $ca = [int](235 * [Math]::Max(0.0, (20 - $g0) / 10.0)) }
            if ($ca -gt 0) {
                $grow = [Math]::Min(1.0, ($g0 + 1) / 4.0)
                $dark = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb([int]($ca * 0.55), 40, 48, 60), [float]($lw + 1.6))
                $light = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb($ca, 250, 252, 255), $lw)
                try {
                    foreach ($pl in $script:glassCracks) {
                        $m = [Math]::Max(2, [int][Math]::Ceiling($pl.Count * $grow))
                        $part = New-Object 'System.Drawing.PointF[]' $m
                        [Array]::Copy($pl, $part, $m)
                        $g.DrawLines($dark, $part)
                        $g.DrawLines($light, $part)
                    }
                    if ($g0 -ge 2) {
                        foreach ($seg in $script:glassRings) { $g.DrawLines($dark, $seg); $g.DrawLines($light, $seg) }
                    }
                } finally {
                    $dark.Dispose()
                    $light.Dispose()
                }
            }
            # 旺旺 jumping out of the hole: grows from small to full size.
            if ($g0 -ge 4 -and $g0 -le 10 -and $script:dogAct -eq 'burst' -and -not [string]::IsNullOrEmpty($script:glassDogPath)) {
                $p = ($g0 - 4) / 6.0
                $k = 0.45 + 0.55 * (1 - (1 - $p) * (1 - $p))
                $dog = Get-DisplayBitmap $script:glassDogPath $script:glassDogFlip
                $dw = [double]$script:form.Width
                $dh = [double]$script:form.Height
                $ox = [double]$script:baseLocation.X - $script:glassLeft
                $oy = [double]$script:baseLocation.Y - $script:glassTop
                $lift = [Math]::Sin([Math]::PI * $p) * $dh * 0.10
                $rx = $c + ($ox - $c) * $k
                $ry = $c + ($oy - $c) * $k - $lift
                $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $g.DrawImage($dog, [System.Drawing.RectangleF]::new([float]$rx, [float]$ry, [float]($dw * $k), [float]($dh * $k)))
            }
            # Glass pieces fly out and fall, turning, then fade.
            if ($g0 -ge 4) {
                $sa = 225
                if ($g0 -gt 16) { $sa = [int](225 * [Math]::Max(0.0, (30 - $g0) / 14.0)) }
                $fill = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb([int]($sa * 0.55), 205, 228, 245))
                $edge = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb($sa, 250, 253, 255), [float]([Math]::Max(1.0, $lw * 0.8)))
                $shade = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb([int]($sa * 0.5), 60, 75, 95), [float]([Math]::Max(1.0, $lw * 0.6)))
                try {
                    foreach ($sh in $script:glassShards) {
                        if ($g0 -gt 4) {
                            $sh.X += $sh.VX
                            $sh.Y += $sh.VY
                            $sh.VY += $S * 0.0028
                            $sh.VX *= 0.97
                            $sh.Rot += $sh.VR
                        }
                        $cn = $sh.DX.Count
                        $poly = New-Object 'System.Drawing.PointF[]' $cn
                        $cs = [Math]::Cos($sh.Rot)
                        $sn = [Math]::Sin($sh.Rot)
                        for ($q = 0; $q -lt $cn; $q++) {
                            $qx = $sh.DX[$q] * $cs - $sh.DY[$q] * $sn
                            $qy = $sh.DX[$q] * $sn + $sh.DY[$q] * $cs
                            $poly[$q] = [System.Drawing.PointF]::new([float]($sh.X + $qx), [float]($sh.Y + $qy))
                        }
                        $g.FillPolygon($fill, $poly)
                        $g.DrawPolygon($shade, $poly)
                        $g.DrawLine($edge, $poly[0], $poly[1])
                    }
                } finally {
                    $fill.Dispose()
                    $edge.Dispose()
                    $shade.Dispose()
                }
            }
        } finally {
            $g.Dispose()
        }
        $code = [WangwangPet.SmoothWindow]::Show($script:glassForm.Handle, $bmp, $script:glassLeft, $script:glassTop)
        if ($code -ne 0) { throw ('玻璃效果顯示失敗，代碼 ' + $code) }
    } finally {
        $bmp.Dispose()
    }
}

function Invoke-DogSummon {
    # From the icon at the bottom right: 旺旺 comes to the top, next to the mouse pointer (also when it was
    # hidden behind other windows, walked off somewhere, or was hiding).
    # Behind other windows: it breaks out of the screen (can be switched off in 互動設定).
    $burst = $false
    if ($script:glassEnabled -and $script:smoothMode -and -not $script:dogHidden -and $script:glassTick -lt 0 -and $script:dogAct -ne 'burst') {
        try { $burst = Test-DogCovered } catch { $burst = $false; $null = Write-ErrorLog ('視窗檢查錯誤：' + $_.ToString()) }
    }
    if ($script:dogHidden) { Show-Dog '我在這裡！汪～' }
    if ($script:isDragging) { return }
    if ($script:dogSleeping) { Stop-DogSleep $false }
    if ($script:dogAct -eq 'fling' -or $script:dogAct -eq 'tease') { $script:dogAct = '' }
    $cur = [System.Windows.Forms.Cursor]::Position
    $wa = [System.Windows.Forms.Screen]::FromPoint($cur).WorkingArea
    $w = $script:form.Width
    $h = $script:form.Height
    $x = [int]($cur.X - $w / 2)
    $y = [int]($cur.Y - $h * 0.7)
    $x = [Math]::Min([Math]::Max($x, $wa.Left), [Math]::Max($wa.Left, $wa.Right - $w))
    $y = [Math]::Min([Math]::Max($y, $wa.Top), [Math]::Max($wa.Top, $wa.Bottom - $h))
    $script:baseLocation = [System.Drawing.Point]::new($x, $y)
    if ($script:gravityMode) {
        # Gravity mode: stands on the taskbar of that screen.
        $gb = Get-GroundBounds
        $script:baseLocation = [System.Drawing.Point]::new($x, [int]$gb[3])
    }
    $script:roamX = [double]$script:baseLocation.X
    $script:roamY = [double]$script:baseLocation.Y
    $script:roamTarget = $null
    $script:roamMoving = $false
    $script:begging = $false
    $script:circleChaseUntil = 0
    $script:roamPauseTicks = 100
    $script:lastInteractTick = $script:clockTick
    $script:form.Location = $script:baseLocation
    # Back on top of the other windows (switched off and on again, so Windows puts it in front once more).
    $keepTop = [bool]$script:form.TopMost
    $script:form.TopMost = -not $keepTop
    $script:form.TopMost = $true
    $script:form.TopMost = $keepTop
    $script:viewDirty = $true
    if ($burst) {
        try {
            Start-GlassBurst
            return
        } catch {
            $null = Write-ErrorLog ('衝出來效果錯誤：' + $_.ToString())
            Hide-GlassFx
            if ($script:dogAct -eq 'burst') { $script:dogAct = '' }
            $script:form.Location = $script:baseLocation
        }
    }
    if ($script:dogAct -eq '' -and $script:actionMode -eq 'idle') {
        $script:actionMode = 'happy'
        $script:actionTick = 0
    }
    $lines = @('汪！我在這裡～', '來了來了！', '找我嗎？汪！')
    Set-Bubble ([string]$lines[$script:rng.Next(0, $lines.Count)])
}

function Hide-Dog([int]$minutes) {
    # $minutes = 0: hidden until it is called back.
    if ($script:dogHidden) { return }
    if ($script:alarmRinging) { Stop-AlarmRing '' }
    $script:hiddenUntil = if ($minutes -gt 0) { (Get-Date).AddMinutes($minutes) } else { [DateTime]::MaxValue }
    $script:dogHidden = $true
    Hide-Jerky
    if ($script:dogAct -eq 'fetch') { $script:dogAct = '' }
    Hide-GlassFx
    if ($script:dogAct -eq 'burst') { $script:dogAct = '' }
    $script:isDragging = $false
    $script:dragMoved = $false
    $script:hovering = $false
    $script:hoverTicks = 0
    $script:bubbleTicks = 0
    $script:bubble.Visible = $false
    $ni = Get-TrayIcon
    if ($minutes -gt 0) {
        $ni.Text = '旺旺躲起來了，' + $script:hiddenUntil.ToString('HH:mm') + ' 回來（點一下叫牠回來）'
    } else {
        $ni.Text = '旺旺躲起來了（點一下叫牠回來）'
    }
    $ni.Visible = $true
    # Moved far outside every screen instead of hidden, so coming back never takes the keyboard focus
    # away from the window being worked in (screen sharing only shows what is on the screens).
    $script:form.Location = [System.Drawing.Point]::new(-25000, -25000)
    # Nothing to animate while hidden: check once a second whether it is time to come back.
    $script:timer.Interval = 1000
}

function Show-Dog([string]$say = '旺旺回來了！') {
    if (-not $script:dogHidden) { return }
    $script:dogHidden = $false
    $script:hiddenUntil = [DateTime]::MaxValue
    try { $script:trayIcon.Text = $script:trayTextNormal } catch { }
    $script:lastInteractTick = $script:clockTick
    $script:timer.Interval = 60
    $script:form.Location = $script:baseLocation
    $script:viewDirty = $true
    if ($script:dogSleeping) { Set-Bubble 'Zzz…' } else { Set-Bubble $say }
}

# -----------------------------------------------------------------------------
# Alarm clocks (several, each with its own line; only once or every day): at the set time the dachshund
# comes out (also when hidden), wakes up and barks with 旺旺's real bark (sounds\wangwang_bark*.wav)
# until it is clicked, for at most one minute.
# -----------------------------------------------------------------------------
function Get-BarkPlayer([int]$count = 2) {
    # $count barks: sounds\wangwang_bark.wav (2), wangwang_bark3.wav (3), wangwang_bark4.wav (4); falls back to the two barks.
    if ($script:barkPlayers.ContainsKey($count)) { return $script:barkPlayers[$count] }
    $file = 'wangwang_bark.wav'
    if ($count -ne 2) { $file = 'wangwang_bark' + $count + '.wav' }
    $wav = Join-Path $PSScriptRoot ('sounds\' + $file)
    if (-not (Test-Path -LiteralPath $wav)) {
        if ($count -ne 2) { return (Get-BarkPlayer 2) }
        return $null
    }
    $player = $null
    try {
        $player = New-Object System.Media.SoundPlayer($wav)
        $player.Load()
    } catch {
        $player = $null
        $null = Write-ErrorLog ('旺旺的叫聲無法播放：' + $_.ToString())
    }
    $script:barkPlayers[$count] = $player
    return $player
}

function Get-AutoBarkTicks {
    # Animation ticks until the next automatic bark: the chosen interval, or 10 to 60 seconds at random.
    if ($script:autoBarkRandom) { return $script:rng.Next(167, 1001) }
    return $script:autoBarkIntervalTicks
}

function Invoke-BarkSound([bool]$fallback = $true) {
    # $true when 旺旺's own bark was played: two barks, sometimes three or four.
    # Without the sound files a Windows sound is played instead ($fallback = $false: then nothing is played).
    $roll = $script:rng.Next(0, 100)
    $count = 2
    if ($roll -ge 80) { $count = 4 } elseif ($roll -ge 45) { $count = 3 }
    $player = Get-BarkPlayer $count
    if ($null -ne $player) {
        try {
            $player.Play()
            $script:barkLast = $player
            $script:barkSeconds = [double]$script:barkLengths[$count]
            return $true
        } catch { }
    }
    if ($fallback) {
        try { [System.Media.SystemSounds]::Exclamation.Play() } catch { }
    }
    $script:barkSeconds = 1.0
    return $false
}

function Get-NextAlarmTime([string]$hhmm) {
    # The next time the clock shows HH:mm: today, or tomorrow when that time has already passed.
    $parts = $hhmm.Split(':')
    $now = Get-Date
    $at = $now.Date.AddHours([int]$parts[0]).AddMinutes([int]$parts[1])
    if ($at -le $now) { $at = $at.AddDays(1) }
    return $at
}

function Get-CleanAlarmNote([string]$note) {
    # One line of at most 20 characters (it is said in the bubble).
    if ([string]::IsNullOrEmpty($note)) { return '' }
    $clean = ($note -replace '[\t\r\n]+', ' ').Trim()
    if ($clean.Length -gt 20) { $clean = $clean.Substring(0, 20) }
    return $clean
}

function New-DogAlarm([string]$hhmm, [bool]$daily, [string]$note) {
    # One alarm. A hashtable, so the alarm window, the menu and the timer all share the same alarm.
    $parts = $hhmm.Split(':')
    $script:alarmNextId++
    return @{
        Id      = $script:alarmNextId
        HHmm    = ('{0:D2}:{1:D2}' -f [int]$parts[0], [int]$parts[1])
        Daily   = $daily
        Note    = (Get-CleanAlarmNote $note)
        Enabled = $false
        NextAt  = $null
    }
}

function Get-AlarmDateWord([DateTime]$at) {
    $today = (Get-Date).Date
    if ($at.Date -eq $today) { return '今天' }
    if ($at.Date -eq $today.AddDays(1)) { return '明天' }
    return $at.ToString('M/d', [System.Globalization.CultureInfo]::InvariantCulture)
}

function Get-AlarmKindText([hashtable]$alarm) {
    # The small line next to the time in the alarm window.
    if ($alarm['Daily']) {
        if ($alarm['Enabled']) { return '每天' }
        return '每天（關閉中）'
    }
    if ($alarm['Enabled'] -and $null -ne $alarm['NextAt']) { return '只響一次（' + (Get-AlarmDateWord ([DateTime]$alarm['NextAt'])) + '）' }
    return '只響一次（關閉中，打勾就能再用）'
}

function Get-AlarmMenuText([hashtable]$alarm) {
    $kind = '一次'
    if ($alarm['Daily']) { $kind = '每天' }
    $text = [string]$alarm['HHmm'] + '　' + $kind
    if (-not [string]::IsNullOrEmpty([string]$alarm['Note'])) { $text += '　' + [string]$alarm['Note'] }
    # '&' would underline the next letter in a menu.
    return $text.Replace('&', '&&')
}

function Get-NextAlarmText {
    # '今天 07:30「起床」' for the alarm that rings next; '' when every alarm is off.
    $best = $null
    foreach ($a in $script:alarms) {
        if ($a['Enabled'] -and $null -ne $a['NextAt']) {
            if ($null -eq $best -or [DateTime]$a['NextAt'] -lt [DateTime]$best['NextAt']) { $best = $a }
        }
    }
    if ($null -eq $best) { return '' }
    $text = (Get-AlarmDateWord ([DateTime]$best['NextAt'])) + ' ' + [string]$best['HHmm']
    if (-not [string]::IsNullOrEmpty([string]$best['Note'])) { $text += '「' + [string]$best['Note'] + '」' }
    return $text
}

function Update-AlarmSoonest {
    # The earliest time any alarm rings: the timer only compares the clock with this.
    $soonest = [DateTime]::MaxValue
    foreach ($a in $script:alarms) {
        if ($a['Enabled'] -and $null -ne $a['NextAt'] -and [DateTime]$a['NextAt'] -lt $soonest) { $soonest = [DateTime]$a['NextAt'] }
    }
    $script:alarmSoonest = $soonest
}

function Update-AlarmOrder {
    # Earliest time first (alarms with the same time: in the order they were made).
    $sorted = @($script:alarms | Sort-Object -Property @{ Expression = { [string]$_['HHmm'] } }, @{ Expression = { [int]$_['Id'] } })
    $script:alarms.Clear()
    foreach ($a in $sorted) { [void]$script:alarms.Add($a) }
}

function Save-DogAlarms {
    # Remembered in %APPDATA%\DachshundPet\alarms.txt (one alarm per line), so the alarms survive a restart;
    # the file is deleted together with the last alarm.
    Update-AlarmSoonest
    $script:alarmSaveOk = $false
    try {
        if ([string]::IsNullOrEmpty($script:alarmListFile)) { return }
        if ($script:alarms.Count -eq 0) {
            if (Test-Path -LiteralPath $script:alarmListFile) { Remove-Item -LiteralPath $script:alarmListFile -Force }
            $script:alarmSaveOk = $true
            return
        }
        $dir = Split-Path -Parent $script:alarmListFile
        if (-not (Test-Path -LiteralPath $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }
        $inv = [System.Globalization.CultureInfo]::InvariantCulture
        $lines = [System.Collections.Generic.List[string]]::new()
        $lines.Add('# 旺旺的鬧鐘（每行一個，用 Tab 分開）：開啟 1/0、時間、每天 1/0、下次響的時間、提醒文字')
        foreach ($a in $script:alarms) {
            $on = '0'
            if ($a['Enabled']) { $on = '1' }
            $daily = '0'
            if ($a['Daily']) { $daily = '1' }
            $next = '-'
            if ($null -ne $a['NextAt']) { $next = ([DateTime]$a['NextAt']).ToString('yyyy-MM-dd HH:mm', $inv) }
            $lines.Add((([string[]]@($on, [string]$a['HHmm'], $daily, $next, (Get-CleanAlarmNote ([string]$a['Note'])))) -join "`t"))
        }
        [System.IO.File]::WriteAllLines($script:alarmListFile, $lines.ToArray(), [System.Text.UTF8Encoding]::new($false))
        $script:alarmSaveOk = $true
    } catch {
        $null = Write-ErrorLog ('鬧鐘沒辦法記下來（下次開旺旺要重新設定）：' + $_.ToString())
    }
}

function Import-DogAlarms {
    $script:alarms.Clear()
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $now = Get-Date
    $timeRx = '^([01]?\d|2[0-3]):[0-5]\d$'
    try {
        if (-not [string]::IsNullOrEmpty($script:alarmListFile) -and (Test-Path -LiteralPath $script:alarmListFile)) {
            foreach ($line in [System.IO.File]::ReadAllLines($script:alarmListFile, [System.Text.Encoding]::UTF8)) {
                if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) { continue }
                if ($script:alarms.Count -ge $script:alarmMax) { break }
                $f = $line.Split("`t")
                if ($f.Count -lt 4 -or $f[1] -notmatch $timeRx) { continue }
                $note = ''
                if ($f.Count -ge 5) { $note = [string]$f[4] }
                $a = New-DogAlarm ([string]$f[1]) ($f[2] -eq '1') $note
                if ($f[0] -eq '1') {
                    if ($a['Daily']) {
                        $a['Enabled'] = $true
                        $a['NextAt'] = Get-NextAlarmTime ([string]$a['HHmm'])
                    } else {
                        # Only once: still on when its time has not come yet. Otherwise its time passed while
                        # 旺旺 was closed: it stays in the list, switched off.
                        $parsed = [DateTime]::MinValue
                        if ([DateTime]::TryParseExact([string]$f[3], 'yyyy-MM-dd HH:mm', $inv, [System.Globalization.DateTimeStyles]::None, [ref]$parsed) -and $parsed -gt $now) {
                            $a['Enabled'] = $true
                            $a['NextAt'] = $parsed
                        }
                    }
                }
                [void]$script:alarms.Add($a)
            }
        } elseif (-not [string]::IsNullOrEmpty($script:alarmFile) -and (Test-Path -LiteralPath $script:alarmFile)) {
            # V1.13.3 and earlier: one alarm in alarm.txt (time, every day 1/0, note, next time); moved into alarms.txt.
            $old = [System.IO.File]::ReadAllLines($script:alarmFile, [System.Text.Encoding]::UTF8)
            if ($old.Count -ge 2 -and $old[0] -match $timeRx) {
                $note = ''
                if ($old.Count -ge 3) { $note = [string]$old[2] }
                $a = New-DogAlarm ([string]$old[0]) ($old[1] -eq '1') $note
                if ($a['Daily']) {
                    $a['Enabled'] = $true
                    $a['NextAt'] = Get-NextAlarmTime ([string]$a['HHmm'])
                } elseif ($old.Count -ge 4) {
                    $parsed = [DateTime]::MinValue
                    if ([DateTime]::TryParseExact([string]$old[3], 'yyyy-MM-dd HH:mm', $inv, [System.Globalization.DateTimeStyles]::None, [ref]$parsed) -and $parsed -gt $now) {
                        $a['Enabled'] = $true
                        $a['NextAt'] = $parsed
                    }
                }
                [void]$script:alarms.Add($a)
                Save-DogAlarms
            }
            if ($script:alarmSaveOk) { Remove-Item -LiteralPath $script:alarmFile -Force -ErrorAction SilentlyContinue }
        }
    } catch { }
    Update-AlarmOrder
    Update-AlarmSoonest
}

function Set-AlarmEnabled([hashtable]$alarm, [bool]$on, [bool]$say = $true, [bool]$refresh = $true) {
    # On: rings the next time the clock shows its time (today, or tomorrow when that has passed).
    # Off: stays in the list with its time and line, ready to be switched on again.
    if ($null -eq $alarm) { return }
    $alarm['Enabled'] = $on
    if ($on) { $alarm['NextAt'] = Get-NextAlarmTime ([string]$alarm['HHmm']) } else { $alarm['NextAt'] = $null }
    Save-DogAlarms
    if ($refresh) { Request-AlarmManagerRefresh }
    if (-not $say) { return }
    if ($on) {
        $day = '每天'
        if (-not $alarm['Daily']) { $day = Get-AlarmDateWord ([DateTime]$alarm['NextAt']) }
        Set-Bubble ('好！' + $day + ' ' + [string]$alarm['HHmm'] + ' 旺旺會汪汪叫你')
    } else {
        Set-Bubble ([string]$alarm['HHmm'] + ' 的鬧鐘關掉了（設定還留著）')
    }
}

function Get-DogAlarmById([int]$id) {
    # The window rows and menu items only remember the number of their alarm; the alarm itself is looked up
    # here at the moment it is clicked, so they always change the alarm that is really in the list.
    foreach ($a in $script:alarms) {
        if ([int]$a['Id'] -eq $id) { return $a }
    }
    return $null
}

function Remove-DogAlarm([int]$id) {
    for ($i = $script:alarms.Count - 1; $i -ge 0; $i--) {
        if ([int]$script:alarms[$i]['Id'] -eq $id) { $script:alarms.RemoveAt($i) }
    }
    Save-DogAlarms
}

function Disable-AllDogAlarms {
    foreach ($a in $script:alarms) {
        $a['Enabled'] = $false
        $a['NextAt'] = $null
    }
    Save-DogAlarms
    Request-AlarmManagerRefresh
    Set-Bubble '鬧鐘全部關掉了（設定都還留著）'
}

function Start-DogCountdown([int]$minutes) {
    if ($script:alarmRinging) { Stop-AlarmRing '' }
    $script:timerUntil = (Get-Date).AddMinutes($minutes)
    $label = if ($minutes -ge 60 -and ($minutes % 60) -eq 0) { [string]($minutes / 60) + ' 小時' } else { [string]$minutes + ' 分鐘' }
    Set-Bubble ('好！' + $label + '後（' + $script:timerUntil.ToString('HH:mm') + '）叫你')
}

function Start-AlarmRing([string]$note, [int]$seconds = 60) {
    if ($script:dogHidden) { Show-Dog '汪汪！' }
    if ($script:dogSleeping) { Stop-DogSleep $false }
    $script:alarmRinging = $true
    $script:alarmRingNote = $note
    $script:alarmRingUntil = (Get-Date).AddSeconds($seconds)
    $script:alarmNextBark = [DateTime]::MinValue
    $script:lastInteractTick = $script:clockTick
}

function Stop-AlarmRing([string]$say) {
    if (-not $script:alarmRinging) { return }
    $script:alarmRinging = $false
    try { if ($null -ne $script:barkLast) { $script:barkLast.Stop() } } catch { }
    if (-not [string]::IsNullOrEmpty($say)) { Set-Bubble $say }
}

function Step-AlarmRing([DateTime]$now) {
    # Barks (two, three or four times) with a happy hop, then a short pause, until clicked (at most one minute).
    if ($now -ge $script:alarmRingUntil) { Stop-AlarmRing '旺旺叫累了，鬧鐘先停囉'; return }
    if ($now -lt $script:alarmNextBark) { return }
    [void](Invoke-BarkSound)
    $script:alarmNextBark = $now.AddSeconds($script:barkSeconds + 1.4)
    $script:lastInteractTick = $script:clockTick
    Set-Bubble ('汪汪！' + $script:alarmRingNote + '（點我停止）')
    if (-not $script:isDragging) {
        if ($script:dogSleeping) { Stop-DogSleep $false }
        $script:dogAct = ''
        $script:actionMode = 'happy'
        $script:actionTick = 0
    }
}

function Update-DogAlarms {
    # Checked every animation tick (once a second while hidden).
    $now = Get-Date
    if ($now -ge $script:alarmSoonest) {
        $due = New-Object System.Collections.ArrayList
        foreach ($a in $script:alarms) {
            if ($a['Enabled'] -and $null -ne $a['NextAt'] -and $now -ge [DateTime]$a['NextAt']) { [void]$due.Add($a) }
        }
        if ($due.Count -eq 0) {
            Update-AlarmSoonest
        } else {
            $notes = New-Object System.Collections.ArrayList
            $missed = New-Object System.Collections.ArrayList
            foreach ($a in $due) {
                $lateMinutes = ($now - [DateTime]$a['NextAt']).TotalMinutes
                if ($a['Daily']) {
                    $a['NextAt'] = Get-NextAlarmTime ([string]$a['HHmm'])
                } else {
                    # Only once: switched off, but kept in the list (tick it to use it again).
                    $a['Enabled'] = $false
                    $a['NextAt'] = $null
                }
                if ($lateMinutes -le 10) {
                    $note = [string]$a['Note']
                    if ([string]::IsNullOrEmpty($note)) { $note = [string]$a['HHmm'] + ' 到囉！' }
                    [void]$notes.Add($note)
                } else {
                    [void]$missed.Add([string]$a['HHmm'])
                }
            }
            Save-DogAlarms
            Request-AlarmManagerRefresh
            if ($notes.Count -gt 0) {
                # Several alarms in the same minute: one ring that says them (the first two).
                $say = (@($notes) | Select-Object -First 2) -join '／'
                if ($notes.Count -gt 2) { $say += '…' }
                Start-AlarmRing $say
            } elseif ($missed.Count -gt 0 -and -not $script:dogHidden) {
                # The computer was asleep at that time: no barking long afterwards, it only says so.
                Set-Bubble ('錯過了 ' + (@($missed) -join '、') + ' 的鬧鐘（電腦剛剛在睡覺）')
            }
        }
    }
    if ($null -ne $script:timerUntil -and $now -ge $script:timerUntil) {
        $script:timerUntil = $null
        Start-AlarmRing '時間到囉！'
    }
    if ($script:alarmRinging) { Step-AlarmRing $now }
}

function Show-AlarmError([string]$what, $err) {
    # A problem with the alarms is shown (and written down), never swallowed: a screenshot says what went wrong.
    $detail = ''
    try {
        if ($err -is [System.Management.Automation.ErrorRecord]) {
            $detail = $err.ToString()
            if ($null -ne $err.InvocationInfo) { $detail += "`r`n" + [string]$err.InvocationInfo.PositionMessage }
        } else {
            $detail = [string]$err
        }
    } catch { }
    $null = Write-ErrorLog ($what + '：' + $detail)
    try {
        $owner = $script:form
        if ($null -ne $script:alarmMgrForm -and -not $script:alarmMgrForm.IsDisposed) { $owner = $script:alarmMgrForm }
        $text = $what + "`r`n`r`n" + $detail + "`r`n`r`n" + '可以把這個畫面截圖給我。'
        [void][System.Windows.Forms.MessageBox]::Show([System.Windows.Forms.IWin32Window]$owner, $text, '旺旺鬧鐘',
            [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
    } catch { }
}

function Request-AlarmManagerRefresh {
    # The alarm window is rebuilt a moment later by a small timer, outside the click that changed something:
    # a row is never taken away while its own button is still handling the click.
    if ($null -eq $script:alarmMgrForm) { return }
    if ($null -eq $script:alarmMgrRefresh) {
        $t = New-Object System.Windows.Forms.Timer
        $t.Interval = 40
        $t.Add_Tick({
            try {
                $script:alarmMgrRefresh.Stop()
                Update-AlarmManagerList
            } catch { Show-AlarmError '鬧鐘視窗更新時出了問題' $_ }
        })
        $script:alarmMgrRefresh = $t
    }
    $script:alarmMgrRefresh.Stop()
    $script:alarmMgrRefresh.Start()
}

function Edit-DogAlarm([int]$id) {
    $alarm = Get-DogAlarmById $id
    if ($null -eq $alarm) {
        Set-Bubble '找不到這個鬧鐘（可能已經刪掉了）'
        Request-AlarmManagerRefresh
        return
    }
    Show-AlarmEditor $alarm
    Request-AlarmManagerRefresh
}

function Confirm-RemoveDogAlarm([int]$id) {
    # Asks once more; only 確定刪除 deletes.
    $alarm = Get-DogAlarmById $id
    if ($null -eq $alarm) {
        Request-AlarmManagerRefresh
        return
    }
    $ok = Show-AlarmDeleteConfirm $alarm
    if ($ok -eq $true) {
        Remove-DogAlarm $id
        Request-AlarmManagerRefresh
        Set-Bubble ([string]$alarm['HHmm'] + ' 的鬧鐘刪掉了')
    }
}

function New-AlarmMenuItem([string]$text, [int]$id, [string]$kind) {
    # $kind: 'toggle' (switch on/off), 'edit' or 'delete'.
    $item = New-Object System.Windows.Forms.ToolStripMenuItem($text)
    $item.Tag = $id
    $item.Name = $kind
    $item.Add_Click({
        param($sender, $e)
        try { Invoke-AlarmMenuAction ([string]$sender.Name) ([int]$sender.Tag) } catch { Show-AlarmError '鬧鐘選單出了問題' $_ }
    })
    return $item
}

function Invoke-AlarmMenuAction([string]$kind, [int]$id) {
    if ($kind -eq 'edit') {
        Edit-DogAlarm $id
        return
    }
    if ($kind -eq 'delete') {
        Confirm-RemoveDogAlarm $id
        return
    }
    $alarm = Get-DogAlarmById $id
    if ($null -ne $alarm) { Set-AlarmEnabled $alarm (-not [bool]$alarm['Enabled']) $true $true }
}

function Update-AlarmMenu {
    $now = Get-Date
    $next = Get-NextAlarmText
    if (-not [string]::IsNullOrEmpty($next)) {
        $script:miAlarmInfo.Text = ('下一個鬧鐘：' + $next).Replace('&', '&&')
    } elseif ($script:alarms.Count -gt 0) {
        $script:miAlarmInfo.Text = '鬧鐘都關著（點下面的鬧鐘就會開啟）'
    } else {
        $script:miAlarmInfo.Text = '還沒有設定鬧鐘'
    }
    # Every alarm is in the menu: click it to switch it on or off. 修改鬧鐘 / 刪除鬧鐘 list them once more.
    foreach ($old in @($script:alarmMenuItems)) {
        try {
            $script:miAlarm.DropDownItems.Remove($old)
            $old.Dispose()
        } catch { }
    }
    $script:alarmMenuItems.Clear()
    foreach ($sub in @($script:miAlarmEdit, $script:miAlarmDelete)) {
        $olds = @($sub.DropDownItems)
        $sub.DropDownItems.Clear()
        foreach ($old in $olds) { try { $old.Dispose() } catch { } }
    }
    $at = $script:miAlarm.DropDownItems.IndexOf($script:miAlarmNew)
    $shown = 0
    foreach ($a in $script:alarms) {
        $label = Get-AlarmMenuText $a
        $id = [int]$a['Id']
        if ($shown -lt 10) {
            $item = New-AlarmMenuItem $label $id 'toggle'
            $item.Checked = [bool]$a['Enabled']
            $item.ToolTipText = '點一下開啟或關閉'
            $script:miAlarm.DropDownItems.Insert($at + $shown, $item)
            [void]$script:alarmMenuItems.Add($item)
            $shown++
        }
        $editItem = New-AlarmMenuItem ($label + '…') $id 'edit'
        [void]$script:miAlarmEdit.DropDownItems.Add($editItem)
        $deleteItem = New-AlarmMenuItem ($label + '…') $id 'delete'
        [void]$script:miAlarmDelete.DropDownItems.Add($deleteItem)
    }
    if ($script:alarms.Count -gt $shown) {
        $more = New-Object System.Windows.Forms.ToolStripMenuItem(('…還有 ' + ($script:alarms.Count - $shown) + ' 組，在鬧鐘設定視窗裡'))
        $more.Enabled = $false
        $script:miAlarm.DropDownItems.Insert($at + $shown, $more)
        [void]$script:alarmMenuItems.Add($more)
    }
    $script:miAlarmEdit.Enabled = ($script:alarms.Count -gt 0)
    $script:miAlarmDelete.Enabled = ($script:alarms.Count -gt 0)
    $anyOn = $false
    foreach ($a in $script:alarms) { if ($a['Enabled']) { $anyOn = $true } }
    $script:miAlarmOff.Enabled = $anyOn
    if ($null -ne $script:timerUntil) {
        $left = [Math]::Max(1, [int][Math]::Ceiling(($script:timerUntil - $now).TotalMinutes))
        $script:miTimerInfo.Text = '倒數：' + $script:timerUntil.ToString('HH:mm') + ' 叫你（還有 ' + $left + ' 分鐘）'
        $script:miTimerInfo.Available = $true
    } else {
        $script:miTimerInfo.Available = $false
    }
    $script:miTimerOff.Enabled = ($null -ne $script:timerUntil)
    $script:miAlarmStop.Available = $script:alarmRinging
}

function Get-AlarmTimeFont {
    # Kept for the whole run (shared by every row of the alarm window).
    if ($null -eq $script:alarmTimeFont) { $script:alarmTimeFont = [System.Drawing.Font]::new('Microsoft JhengHei UI', [single]17, [System.Drawing.FontStyle]::Bold) }
    return $script:alarmTimeFont
}

function Get-AlarmTrashIcon {
    # A small dustbin, drawn here so it looks the same on every PC (no icon font needed). Kept for the whole run.
    if ($null -ne $script:alarmTrashIcon) { return $script:alarmTrashIcon }
    $size = Get-Scaled 20
    $bmp = New-Object System.Drawing.Bitmap($size, $size)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $pen = $null
    try {
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $w = [double]$size
        $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(196, 64, 52), ([single][Math]::Max(1.5, $w / 11.0)))
        $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
        $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
        $segments = @(
            @(0.16, 0.25, 0.84, 0.25),
            @(0.39, 0.25, 0.39, 0.12), @(0.39, 0.12, 0.61, 0.12), @(0.61, 0.12, 0.61, 0.25),
            @(0.25, 0.34, 0.31, 0.89), @(0.31, 0.89, 0.69, 0.89), @(0.69, 0.89, 0.75, 0.34),
            @(0.43, 0.43, 0.44, 0.79), @(0.57, 0.43, 0.56, 0.79))
        foreach ($sg in $segments) {
            $g.DrawLine($pen, [single]($sg[0] * $w), [single]($sg[1] * $w), [single]($sg[2] * $w), [single]($sg[3] * $w))
        }
    } finally {
        if ($null -ne $pen) { $pen.Dispose() }
        $g.Dispose()
    }
    $script:alarmTrashIcon = $bmp
    return $bmp
}

function Show-AlarmEditor([hashtable]$alarm) {
    # Adds a new alarm ($alarm = $null) or changes one: the time, only once or every day, and the line for
    # the bubble. Saving switches the alarm on (like the alarm on a phone).
    $isNew = ($null -eq $alarm)
    if ($isNew -and $script:alarms.Count -ge $script:alarmMax) {
        Set-Bubble ('鬧鐘最多 ' + $script:alarmMax + ' 組喔')
        return
    }
    $dlg = New-Object System.Windows.Forms.Form
    try {
        if ($isNew) { $dlg.Text = '新增鬧鐘' } else { $dlg.Text = '修改鬧鐘' }
        $dlg.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
        $dlg.MaximizeBox = $false
        $dlg.MinimizeBox = $false
        $dlg.ShowInTaskbar = $false
        $dlg.TopMost = $true
        $dlg.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
        $dlg.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
        $dlg.Font = [System.Drawing.Font]::new('Microsoft JhengHei UI', 10)
        $dlg.ClientSize = [System.Drawing.Size]::new((Get-Scaled 340), (Get-Scaled 254))

        $lblTime = New-Object System.Windows.Forms.Label
        $lblTime.Text = '時間：'
        $lblTime.AutoSize = $true
        $lblTime.Location = [System.Drawing.Point]::new((Get-Scaled 16), (Get-Scaled 24))
        $dlg.Controls.Add($lblTime)

        $picker = New-Object System.Windows.Forms.DateTimePicker
        $picker.Format = [System.Windows.Forms.DateTimePickerFormat]::Custom
        $picker.CustomFormat = 'HH:mm'
        $picker.ShowUpDown = $true
        $picker.Font = [System.Drawing.Font]::new('Microsoft JhengHei UI', [single]15, [System.Drawing.FontStyle]::Bold)
        $picker.Location = [System.Drawing.Point]::new((Get-Scaled 72), (Get-Scaled 14))
        $picker.Width = Get-Scaled 110
        if ($isNew) {
            # Half an hour from now, on a 5-minute mark.
            $soon = (Get-Date).AddMinutes(30)
            $picker.Value = $soon.Date.AddHours($soon.Hour).AddMinutes([Math]::Ceiling($soon.Minute / 5.0) * 5)
        } else {
            $parts = ([string]$alarm['HHmm']).Split(':')
            $picker.Value = (Get-Date).Date.AddHours([int]$parts[0]).AddMinutes([int]$parts[1])
        }
        $dlg.Controls.Add($picker)

        $rbOnce = New-Object System.Windows.Forms.RadioButton
        $rbOnce.Text = '只響一次（響完會自動關閉，設定會留著）'
        $rbOnce.AutoSize = $true
        $rbOnce.Location = [System.Drawing.Point]::new((Get-Scaled 16), (Get-Scaled 64))
        $dlg.Controls.Add($rbOnce)
        $rbDaily = New-Object System.Windows.Forms.RadioButton
        $rbDaily.Text = '每天這個時間都叫我'
        $rbDaily.AutoSize = $true
        $rbDaily.Location = [System.Drawing.Point]::new((Get-Scaled 16), (Get-Scaled 92))
        $dlg.Controls.Add($rbDaily)
        if ((-not $isNew) -and [bool]$alarm['Daily']) { $rbDaily.Checked = $true } else { $rbOnce.Checked = $true }

        $lblNote = New-Object System.Windows.Forms.Label
        $lblNote.Text = '提醒文字（可以空白，最多 20 個字）：'
        $lblNote.AutoSize = $true
        $lblNote.Location = [System.Drawing.Point]::new((Get-Scaled 16), (Get-Scaled 130))
        $dlg.Controls.Add($lblNote)
        $txtNote = New-Object System.Windows.Forms.TextBox
        $txtNote.MaxLength = 20
        if (-not $isNew) { $txtNote.Text = [string]$alarm['Note'] }
        $txtNote.Location = [System.Drawing.Point]::new((Get-Scaled 16), (Get-Scaled 156))
        $txtNote.Width = Get-Scaled 308
        $dlg.Controls.Add($txtNote)

        $btnOk = New-Object System.Windows.Forms.Button
        if ($isNew) { $btnOk.Text = '新增' } else { $btnOk.Text = '儲存' }
        $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $btnOk.Location = [System.Drawing.Point]::new((Get-Scaled 132), (Get-Scaled 206))
        $btnOk.Size = [System.Drawing.Size]::new((Get-Scaled 84), (Get-Scaled 32))
        $dlg.Controls.Add($btnOk)
        $btnCancel = New-Object System.Windows.Forms.Button
        $btnCancel.Text = '取消'
        $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $btnCancel.Location = [System.Drawing.Point]::new((Get-Scaled 240), (Get-Scaled 206))
        $btnCancel.Size = [System.Drawing.Size]::new((Get-Scaled 84), (Get-Scaled 32))
        $dlg.Controls.Add($btnCancel)
        $dlg.AcceptButton = $btnOk
        $dlg.CancelButton = $btnCancel
        $dlg.Add_Shown({
            param($sender, $e)
            try { $sender.Activate() } catch { }
        })

        $owner = $script:form
        if ($null -ne $script:alarmMgrForm -and -not $script:alarmMgrForm.IsDisposed) {
            $owner = $script:alarmMgrForm
            $dlg.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
        }
        $result = $dlg.ShowDialog([System.Windows.Forms.IWin32Window]$owner)
        if ($result -ne [System.Windows.Forms.DialogResult]::OK) { return }
        $hhmm = $picker.Value.ToString('HH:mm', [System.Globalization.CultureInfo]::InvariantCulture)
        $note = Get-CleanAlarmNote ([string]$txtNote.Text)
        $daily = [bool]$rbDaily.Checked
        if ($isNew) {
            $alarm = New-DogAlarm $hhmm $daily $note
            [void]$script:alarms.Add($alarm)
        } else {
            # The alarm may have been deleted meanwhile (for example from the menu): then nothing to change.
            $alarm = Get-DogAlarmById ([int]$alarm['Id'])
            if ($null -eq $alarm) { return }
            $alarm['HHmm'] = $hhmm
            $alarm['Daily'] = $daily
            $alarm['Note'] = $note
        }
        Update-AlarmOrder
        Set-AlarmEnabled $alarm $true $true $false
    } finally {
        $dlg.Dispose()
    }
}

function Show-AlarmDeleteConfirm([hashtable]$alarm) {
    # Asked once more before an alarm is deleted. $true = delete it.
    $dlg = New-Object System.Windows.Forms.Form
    try {
        $dlg.Text = '刪除鬧鐘'
        $dlg.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
        $dlg.MaximizeBox = $false
        $dlg.MinimizeBox = $false
        $dlg.ShowInTaskbar = $false
        $dlg.TopMost = $true
        $dlg.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
        $dlg.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
        $dlg.Font = [System.Drawing.Font]::new('Microsoft JhengHei UI', 10)
        $dlg.ClientSize = [System.Drawing.Size]::new((Get-Scaled 360), (Get-Scaled 200))

        $kind = '只響一次'
        if ($alarm['Daily']) { $kind = '每天' }
        $text = '要刪除這個鬧鐘嗎？' + "`r`n`r`n" + [string]$alarm['HHmm'] + '　' + $kind
        if (-not [string]::IsNullOrEmpty([string]$alarm['Note'])) { $text += '　「' + [string]$alarm['Note'] + '」' }
        $text += "`r`n`r`n" + '（只是暫時不想響的話，把勾勾拿掉就好）'
        $lbl = New-Object System.Windows.Forms.Label
        $lbl.UseMnemonic = $false
        $lbl.AutoSize = $false
        $lbl.Text = $text
        $lbl.Location = [System.Drawing.Point]::new((Get-Scaled 16), (Get-Scaled 14))
        $lbl.Size = [System.Drawing.Size]::new((Get-Scaled 328), (Get-Scaled 130))
        $dlg.Controls.Add($lbl)

        # 取消 first, so pressing Enter by accident never deletes.
        $btnCancel = New-Object System.Windows.Forms.Button
        $btnCancel.Text = '取消'
        $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $btnCancel.Location = [System.Drawing.Point]::new((Get-Scaled 260), (Get-Scaled 154))
        $btnCancel.Size = [System.Drawing.Size]::new((Get-Scaled 84), (Get-Scaled 32))
        $btnCancel.TabIndex = 0
        $dlg.Controls.Add($btnCancel)
        $btnDelete = New-Object System.Windows.Forms.Button
        $btnDelete.Text = '確定刪除'
        $btnDelete.ForeColor = [System.Drawing.Color]::FromArgb(180, 40, 30)
        $btnDelete.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $btnDelete.Location = [System.Drawing.Point]::new((Get-Scaled 154), (Get-Scaled 154))
        $btnDelete.Size = [System.Drawing.Size]::new((Get-Scaled 98), (Get-Scaled 32))
        $btnDelete.TabIndex = 1
        $dlg.Controls.Add($btnDelete)
        $dlg.CancelButton = $btnCancel
        $dlg.Add_Shown({
            param($sender, $e)
            try { $sender.Activate() } catch { }
        })

        $owner = $script:form
        if ($null -ne $script:alarmMgrForm -and -not $script:alarmMgrForm.IsDisposed) {
            $owner = $script:alarmMgrForm
            $dlg.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
        }
        $result = $dlg.ShowDialog([System.Windows.Forms.IWin32Window]$owner)
        return ($result -eq [System.Windows.Forms.DialogResult]::OK)
    } finally {
        $dlg.Dispose()
    }
}

function Get-RowPart($row, [string]$name) {
    foreach ($c in $row.Controls) {
        if ($c.Name -eq $name) { return $c }
    }
    return $null
}

function Update-AlarmRowLook($row, [hashtable]$alarm) {
    # Grey when the alarm is off; the small line says every day / only once (today or tomorrow).
    $timeColor = [System.Drawing.Color]::FromArgb(160, 160, 160)
    $textColor = [System.Drawing.Color]::FromArgb(160, 160, 160)
    if ([bool]$alarm['Enabled']) {
        $timeColor = [System.Drawing.Color]::FromArgb(45, 35, 30)
        $textColor = [System.Drawing.Color]::FromArgb(110, 80, 50)
    }
    $time = Get-RowPart $row 'time'
    if ($null -ne $time) {
        $time.LinkColor = $timeColor
        $time.VisitedLinkColor = $timeColor
        $time.ActiveLinkColor = [System.Drawing.Color]::FromArgb(196, 64, 52)
    }
    $info = Get-RowPart $row 'info'
    if ($null -ne $info) {
        $info.ForeColor = $textColor
        $info.Text = Get-AlarmKindText $alarm
    }
    $note = Get-RowPart $row 'note'
    if ($null -ne $note) {
        $noteText = [string]$alarm['Note']
        if ([string]::IsNullOrEmpty($noteText)) { $noteText = '（沒有提醒文字）' }
        $note.ForeColor = $textColor
        $note.Text = $noteText
    }
}

function New-AlarmRow([hashtable]$alarm, [int]$width, [bool]$shade) {
    # One row: [tick] 07:30  每天 / 提醒文字  [修改] [dustbin]. Every part only remembers the alarm's number.
    $id = [int]$alarm['Id']
    $height = Get-Scaled 56
    $back = [System.Drawing.Color]::White
    if ($shade) { $back = [System.Drawing.Color]::FromArgb(247, 243, 236) }
    $row = New-Object System.Windows.Forms.Panel
    $row.Size = [System.Drawing.Size]::new($width, $height)
    $row.Margin = New-Object System.Windows.Forms.Padding(0)
    $row.BackColor = $back
    $row.Tag = $id

    $chk = New-Object System.Windows.Forms.CheckBox
    $chk.Name = 'chk'
    $chk.AutoSize = $true
    $chk.Text = ''
    $chk.Checked = [bool]$alarm['Enabled']
    $chk.Location = [System.Drawing.Point]::new((Get-Scaled 12), [int](($height - (Get-Scaled 14)) / 2))
    $chk.Cursor = [System.Windows.Forms.Cursors]::Hand

    $time = New-Object System.Windows.Forms.LinkLabel
    $time.Name = 'time'
    $time.AutoSize = $true
    $time.Text = [string]$alarm['HHmm']
    $time.Font = Get-AlarmTimeFont
    $time.LinkBehavior = [System.Windows.Forms.LinkBehavior]::HoverUnderline
    $time.Location = [System.Drawing.Point]::new((Get-Scaled 36), (Get-Scaled 11))

    $infoX = Get-Scaled 118
    $textW = [int][Math]::Max([double](Get-Scaled 60), [double]($width - $infoX - (Get-Scaled 110)))
    $info = New-Object System.Windows.Forms.Label
    $info.Name = 'info'
    $info.UseMnemonic = $false
    $info.AutoSize = $false
    $info.AutoEllipsis = $true
    $info.Location = [System.Drawing.Point]::new($infoX, (Get-Scaled 8))
    $info.Size = [System.Drawing.Size]::new($textW, (Get-Scaled 20))
    $info.Cursor = [System.Windows.Forms.Cursors]::Hand
    $note = New-Object System.Windows.Forms.Label
    $note.Name = 'note'
    $note.UseMnemonic = $false
    $note.AutoSize = $false
    $note.AutoEllipsis = $true
    $note.Location = [System.Drawing.Point]::new($infoX, (Get-Scaled 29))
    $note.Size = [System.Drawing.Size]::new($textW, (Get-Scaled 20))
    $note.Cursor = [System.Windows.Forms.Cursors]::Hand

    $btnEdit = New-Object System.Windows.Forms.Button
    $btnEdit.Name = 'edit'
    $btnEdit.Text = '修改'
    $btnEdit.UseVisualStyleBackColor = $true
    $btnEdit.Size = [System.Drawing.Size]::new((Get-Scaled 54), (Get-Scaled 30))
    $btnEdit.Location = [System.Drawing.Point]::new($width - (Get-Scaled 104), [int](($height - (Get-Scaled 30)) / 2))
    $btnEdit.Cursor = [System.Windows.Forms.Cursors]::Hand

    $del = New-Object System.Windows.Forms.Button
    $del.Name = 'del'
    $del.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $del.FlatAppearance.BorderSize = 0
    $del.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(250, 222, 218)
    $del.BackColor = $back
    $del.Text = ''
    $del.Image = Get-AlarmTrashIcon
    $del.Size = [System.Drawing.Size]::new((Get-Scaled 36), (Get-Scaled 36))
    $del.Location = [System.Drawing.Point]::new($width - (Get-Scaled 44), [int](($height - (Get-Scaled 36)) / 2))
    $del.Cursor = [System.Windows.Forms.Cursors]::Hand

    foreach ($c in @($chk, $time, $info, $note, $btnEdit, $del)) {
        $c.Tag = $id
        $row.Controls.Add($c)
    }
    Update-AlarmRowLook $row $alarm
    if ($null -ne $script:alarmMgrTip) {
        $script:alarmMgrTip.SetToolTip($chk, '打勾＝開啟，拿掉勾＝關閉（設定會留著）')
        $script:alarmMgrTip.SetToolTip($time, '點一下修改時間和提醒文字')
        $script:alarmMgrTip.SetToolTip($btnEdit, '修改時間、提醒文字、只響一次或每天')
        $script:alarmMgrTip.SetToolTip($del, '刪除這個鬧鐘（會再問一次）')
    }

    # The handlers are added after Checked was set, so building the row never switches an alarm.
    $chk.Add_CheckedChanged({
        param($sender, $e)
        try {
            $alarm = Get-DogAlarmById ([int]$sender.Tag)
            if ($null -ne $alarm) {
                Set-AlarmEnabled $alarm ([bool]$sender.Checked) $true $false
                Update-AlarmRowLook $sender.Parent $alarm
                Update-AlarmManagerStatus
            }
        } catch { Show-AlarmError '開關鬧鐘時出了問題' $_ }
    })
    $edit = {
        param($sender, $e)
        try { Edit-DogAlarm ([int]$sender.Tag) } catch { Show-AlarmError '修改鬧鐘時出了問題' $_ }
    }
    $time.Add_LinkClicked($edit)
    $info.Add_Click($edit)
    $note.Add_Click($edit)
    $btnEdit.Add_Click($edit)
    $del.Add_Click({
        param($sender, $e)
        try { Confirm-RemoveDogAlarm ([int]$sender.Tag) } catch { Show-AlarmError '刪除鬧鐘時出了問題' $_ }
    })
    return $row
}

function Update-AlarmManagerStatus {
    if ($null -eq $script:alarmMgrStatus) { return }
    $next = Get-NextAlarmText
    if ([string]::IsNullOrEmpty($next)) { $script:alarmMgrStatus.Text = '目前沒有開啟的鬧鐘' } else { $script:alarmMgrStatus.Text = '下一個：' + $next }
    if ($null -ne $script:alarmMgrAdd) { $script:alarmMgrAdd.Enabled = ($script:alarms.Count -lt $script:alarmMax) }
}

function Update-AlarmManagerList {
    # (Re)builds the rows of the alarm window, when it is open. Old rows are only taken out here and are thrown
    # away when the window closes (a dialog opened from one of them may still be on its way back).
    $list = $script:alarmMgrList
    if ($null -eq $list -or $list.IsDisposed) { return }
    foreach ($old in @($list.Controls)) { [void]$script:alarmMgrOldRows.Add($old) }
    $list.Controls.Clear()
    $width = $list.ClientSize.Width - [System.Windows.Forms.SystemInformation]::VerticalScrollBarWidth - 2
    if ($script:alarms.Count -eq 0) {
        $empty = New-Object System.Windows.Forms.Label
        $empty.UseMnemonic = $false
        $empty.AutoSize = $false
        $empty.Size = [System.Drawing.Size]::new($width, (Get-Scaled 90))
        $empty.Margin = New-Object System.Windows.Forms.Padding(0)
        $empty.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
        $empty.ForeColor = [System.Drawing.Color]::FromArgb(130, 130, 130)
        $empty.Text = '還沒有鬧鐘。' + "`r`n" + '按下面的「＋ 新增鬧鐘」設定第一個吧！'
        $list.Controls.Add($empty)
    }
    $i = 0
    foreach ($a in @($script:alarms)) {
        $rowCtl = New-AlarmRow $a $width (($i % 2) -eq 1)
        $list.Controls.Add($rowCtl)
        $i++
    }
    Update-AlarmManagerStatus
}

function Close-AlarmManagerParts {
    if ($null -ne $script:alarmMgrRefresh) { try { $script:alarmMgrRefresh.Stop() } catch { } }
    $script:alarmMgrForm = $null
    $script:alarmMgrList = $null
    $script:alarmMgrStatus = $null
    $script:alarmMgrAdd = $null
    foreach ($old in @($script:alarmMgrOldRows)) { try { $old.Dispose() } catch { } }
    $script:alarmMgrOldRows.Clear()
    if ($null -ne $script:alarmMgrTip) {
        try { $script:alarmMgrTip.Dispose() } catch { }
        $script:alarmMgrTip = $null
    }
}

function Show-AlarmManager {
    # The alarm window: every alarm with a tick (on/off), its time (click to change it), what it says, a
    # 修改 button and a dustbin (asks once more before deleting). Stays open next to 旺旺; only one at a time.
    $open = $script:alarmMgrForm
    if ($null -ne $open) {
        $alive = $false
        try { $alive = (-not $open.IsDisposed) -and $open.Visible } catch { $alive = $false }
        if ($alive) {
            $open.Activate()
            return
        }
        try { if (-not $open.IsDisposed) { $open.Dispose() } } catch { }
        Close-AlarmManagerParts
    }
    $f = New-Object System.Windows.Forms.Form
    try {
        $f.Text = '旺旺鬧鐘'
        $f.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
        $f.MaximizeBox = $false
        $f.MinimizeBox = $false
        $f.ShowInTaskbar = $true
        $f.TopMost = $true
        $f.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
        $f.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
        $f.Font = [System.Drawing.Font]::new('Microsoft JhengHei UI', 10)
        $f.ClientSize = [System.Drawing.Size]::new((Get-Scaled 540), (Get-Scaled 442))
        $icoPath = Join-Path $PSScriptRoot 'wangwang.ico'
        if (Test-Path -LiteralPath $icoPath) { try { $f.Icon = New-Object System.Drawing.Icon($icoPath) } catch { } }

        $hint = New-Object System.Windows.Forms.Label
        $hint.UseMnemonic = $false
        $hint.AutoSize = $false
        $hint.Location = [System.Drawing.Point]::new((Get-Scaled 16), (Get-Scaled 12))
        $hint.Size = [System.Drawing.Size]::new((Get-Scaled 508), (Get-Scaled 62))
        $hint.Text = '可以設定好幾組鬧鐘，每組有自己的提醒文字。' + "`r`n" +
            '打勾＝開啟；按「修改」或點時間可以修改；按垃圾桶會再問一次，確定才刪除。' + "`r`n" +
            '「只響一次」響完會自動關閉，設定會留著，下次打勾就能再用。'
        $f.Controls.Add($hint)

        $list = New-Object System.Windows.Forms.FlowLayoutPanel
        $list.FlowDirection = [System.Windows.Forms.FlowDirection]::TopDown
        $list.WrapContents = $false
        $list.AutoScroll = $true
        $list.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
        $list.BackColor = [System.Drawing.Color]::White
        $list.Location = [System.Drawing.Point]::new((Get-Scaled 16), (Get-Scaled 80))
        $list.Size = [System.Drawing.Size]::new((Get-Scaled 508), (Get-Scaled 296))
        $f.Controls.Add($list)

        $btnAdd = New-Object System.Windows.Forms.Button
        $btnAdd.Text = '＋ 新增鬧鐘'
        $btnAdd.Location = [System.Drawing.Point]::new((Get-Scaled 16), (Get-Scaled 390))
        $btnAdd.Size = [System.Drawing.Size]::new((Get-Scaled 130), (Get-Scaled 36))
        $f.Controls.Add($btnAdd)

        $status = New-Object System.Windows.Forms.Label
        $status.UseMnemonic = $false
        $status.AutoSize = $false
        $status.AutoEllipsis = $true
        $status.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
        $status.ForeColor = [System.Drawing.Color]::FromArgb(110, 80, 50)
        $status.Location = [System.Drawing.Point]::new((Get-Scaled 154), (Get-Scaled 390))
        $status.Size = [System.Drawing.Size]::new((Get-Scaled 278), (Get-Scaled 36))
        $f.Controls.Add($status)

        $btnClose = New-Object System.Windows.Forms.Button
        $btnClose.Text = '關閉'
        $btnClose.Location = [System.Drawing.Point]::new((Get-Scaled 440), (Get-Scaled 390))
        $btnClose.Size = [System.Drawing.Size]::new((Get-Scaled 84), (Get-Scaled 36))
        $f.Controls.Add($btnClose)
        $f.CancelButton = $btnClose

        $script:alarmMgrTip = New-Object System.Windows.Forms.ToolTip
        $script:alarmMgrForm = $f
        $script:alarmMgrList = $list
        $script:alarmMgrStatus = $status
        $script:alarmMgrAdd = $btnAdd

        $btnAdd.Add_Click({
            try {
                Show-AlarmEditor $null
                Request-AlarmManagerRefresh
            } catch { Show-AlarmError '新增鬧鐘時出了問題' $_ }
        })
        $btnClose.Add_Click({ try { if ($null -ne $script:alarmMgrForm) { $script:alarmMgrForm.Close() } } catch { } })
        $f.Add_FormClosed({ try { Close-AlarmManagerParts } catch { } })

        Update-AlarmManagerList
        $f.Show()
        $f.Activate()
    } catch {
        $problem = $_
        Close-AlarmManagerParts
        try { $f.Dispose() } catch { }
        Show-AlarmError '鬧鐘設定視窗打不開' $problem
    }
}

# -----------------------------------------------------------------------------
# Interactions: welcome back, fling, teasing, health reminders, focus timer, holiday clothes, hunger
# -----------------------------------------------------------------------------
function Start-DogRest([string]$kind, [string]$say) {
    # $kind = 'wait' (waiting for the person to come back) or 'focus' (lying quietly during a focus period).
    if (-not $script:dogPoses.ContainsKey('lie_00')) { return }
    $script:dogSleeping = $false
    $script:dogNightSleep = $false
    $script:dogAct = $kind
    $script:dogActTick = 0
    $script:dogActLen = 0
    $script:actionMode = 'idle'
    $script:actionTick = 0
    $script:roamMoving = $false
    if (-not [string]::IsNullOrEmpty($say)) { Set-Bubble $say }
}

function Update-DogAway([bool]$menuOpen) {
    # Nobody has used the PC for 5 minutes: lie down and wait. The first key press or mouse move afterwards: welcome back.
    $idleMs = [long][WangwangPet.UserIdle]::Milliseconds()
    if ($idleMs -lt 0) { return }
    if ($idleMs -ge 300000) {
        if (-not $script:awaySeen) {
            $script:awaySeen = $true
            $script:awayBubble = $true
        }
        if ($script:dogAct -eq '' -and $script:actionMode -eq 'idle' -and -not $script:isDragging -and -not $menuOpen -and -not $script:alarmRinging) {
            $say = ''
            if ($script:awayBubble) { $say = '你去哪裡了？旺旺在這裡等你～' }
            $script:awayBubble = $false
            Start-DogRest 'wait' $say
        }
    } elseif ($idleMs -lt 2000 -and $script:awaySeen) {
        $script:awaySeen = $false
        Invoke-DogWelcome
    }
}

function Invoke-DogWelcome {
    if ($script:dogHidden -or $script:isDragging) { return }
    if ($script:dogSleeping) {
        # A night's sleep, or a sleep chosen from the menu, is not disturbed.
        if ($script:dogNightSleep -or $script:dogActLen -eq 0) { return }
        Stop-DogSleep $false
    }
    $script:dogAct = ''
    $script:actionMode = 'happy'
    $script:actionTick = 0
    $script:lastInteractTick = $script:clockTick
    $lines = @('你回來了！汪汪！', '汪！等你好久了～', '你回來了～陪旺旺玩！')
    Set-Bubble ([string]$lines[$script:rng.Next(0, $lines.Count)])
    if ($script:autoBarkSound) { try { [void](Invoke-BarkSound $false) } catch { } }
    # Turn towards the person (the mouse pointer).
    $cur = [System.Windows.Forms.Cursor]::Position
    $script:facingLeft = ($cur.X -lt ($script:baseLocation.X + $script:form.Width / 2))
}

function Start-DogFling([double]$vx, [double]$vy, [string]$say = '哇～～～') {
    # Thrown: $vx, $vy = pixels per animation tick when it was let go. In gravity mode also used to fall down.
    $max = [double](Get-Scaled 70)
    $speed = [Math]::Sqrt($vx * $vx + $vy * $vy)
    if ($speed -gt $max) {
        $vx = $vx * $max / $speed
        $vy = $vy * $max / $speed
    }
    $script:flingVX = $vx
    $script:flingVY = $vy
    $script:fallFrameOn = $false
    $script:dogSleeping = $false
    $script:dogNightSleep = $false
    $script:dogAct = 'fling'
    $script:dogActTick = 0
    $script:dogActLen = 0
    $script:actionMode = 'idle'
    $script:actionTick = 0
    $script:roamMoving = $false
    $script:roamTarget = $null
    if ([Math]::Abs($vx) -gt 1) { $script:facingLeft = ($vx -lt 0) }
    if (-not [string]::IsNullOrEmpty($say)) { Set-Bubble $say }
}

function Set-DogPounceTarget {
    # Jump at the mouse pointer: at most about one body length, and never off the screen.
    $b = Get-RoamBounds
    $cur = [System.Windows.Forms.Cursor]::Position
    $w = [double]$script:form.Width
    $fx = [double]$script:baseLocation.X
    $fy = [double]$script:baseLocation.Y
    $tx = [double]$cur.X - $w / 2
    $ty = [double]$cur.Y - $w * 0.7
    $dx = $tx - $fx
    $dy = $ty - $fy
    $dist = [Math]::Sqrt($dx * $dx + $dy * $dy)
    $maxJump = $w * 0.9
    if ($dist -gt $maxJump) {
        $tx = $fx + $dx / $dist * $maxJump
        $ty = $fy + $dy / $dist * $maxJump
    }
    $tx = [Math]::Min([Math]::Max($tx, [double]$b[0]), [double]$b[1])
    $ty = [Math]::Min([Math]::Max($ty, [double]$b[2]), [double]$b[3])
    if ($script:gravityMode) {
        # Gravity mode: the pounce lands on the taskbar again.
        $gb = Get-GroundBounds
        $tx = [Math]::Min([Math]::Max($tx, [double]$gb[0]), [double]$gb[1])
        $ty = [double]$gb[3]
    }
    $script:pounceFrom = $script:baseLocation
    $script:pounceTo = [System.Drawing.Point]::new([int]$tx, [int]$ty)
    if ([Math]::Abs($dx) -gt 2) { $script:facingLeft = ($dx -lt 0) }
}

function Update-DogTease {
    # The mouse pointer swinging quickly left and right in front of the dachshund (4 swings in a row).
    $cur = [System.Windows.Forms.Cursor]::Position
    $w = [double]$script:form.Width
    $left = [double]$script:baseLocation.X
    $top = [double]$script:baseLocation.Y
    $near = ($cur.X -ge ($left - $w * 0.6)) -and ($cur.X -le ($left + $w * 1.6)) -and ($cur.Y -ge ($top - $w * 0.2)) -and ($cur.Y -le ($top + $w * 1.1))
    if (-not $near) {
        $script:teaseFlips = 0
        $script:teaseDir = 0
        return
    }
    $x = [double]$cur.X
    $amp = $w * 0.12
    $flipped = $false
    if ($script:teaseDir -eq 0) {
        $script:teaseDir = 1
        $script:teaseExt = $x
    } elseif ($script:teaseDir -gt 0) {
        if ($x -gt $script:teaseExt) {
            $script:teaseExt = $x
        } elseif (($script:teaseExt - $x) -ge $amp) {
            $script:teaseDir = -1
            $script:teaseExt = $x
            $flipped = $true
        }
    } else {
        if ($x -lt $script:teaseExt) {
            $script:teaseExt = $x
        } elseif (($x - $script:teaseExt) -ge $amp) {
            $script:teaseDir = 1
            $script:teaseExt = $x
            $flipped = $true
        }
    }
    if (-not $flipped) { return }
    if (($script:clockTick - $script:teaseFlipTick) -gt 12) { $script:teaseFlips = 1 } else { $script:teaseFlips++ }
    $script:teaseFlipTick = $script:clockTick
    if ($script:teaseFlips -lt 4) { return }
    $script:teaseFlips = 0
    # Ready to play? Awake, not busy, not during a focus period, and at most every 10 seconds.
    if ($script:dogSleeping -or $script:alarmRinging -or $script:dogAct -ne '' -or $script:actionMode -ne 'idle') { return }
    if ($script:focusState -eq 'focus' -or $script:clockTick -lt $script:teaseReadyTick) { return }
    if (Test-DogAction 'tease') {
        Start-DogAction 'tease' '*'
        $script:lastInteractTick = $script:clockTick
    }
}

function Update-DogCircle {
    # The mouse pointer going round and round (two loops in the same direction within about 4 seconds):
    # 旺旺 comes running over. Only the pointer's position on the screen is used.
    $cur = [System.Windows.Forms.Cursor]::Position
    $dx = [double]($cur.X - $script:circleLastX)
    $dy = [double]($cur.Y - $script:circleLastY)
    if ([Math]::Sqrt($dx * $dx + $dy * $dy) -lt [double](Get-Scaled 4)) {
        # Hardly moving: after half a second the counting starts again.
        $script:circleStill++
        if ($script:circleStill -gt 8) {
            $script:circleTurn = 0.0
            $script:circleHasDir = $false
        }
        return
    }
    $script:circleStill = 0
    $script:circleLastX = $cur.X
    $script:circleLastY = $cur.Y
    $ang = [Math]::Atan2($dy, $dx)
    if ($script:circleHasDir) {
        $turn = $ang - $script:circleDir
        while ($turn -gt [Math]::PI) { $turn -= 2 * [Math]::PI }
        while ($turn -lt -[Math]::PI) { $turn += 2 * [Math]::PI }
        if ([Math]::Abs($turn) -gt 2.0) {
            # A sharp turn back (a zigzag) is not a circle.
            $script:circleTurn = 0.0
            $script:circleStartTick = $script:clockTick
        } elseif ([Math]::Abs($script:circleTurn) -gt 0.5 -and (($turn -ge 0) -ne ($script:circleTurn -ge 0))) {
            # Turning the other way: start counting again.
            $script:circleTurn = $turn
            $script:circleStartTick = $script:clockTick
        } else {
            if ($script:circleTurn -eq 0.0) { $script:circleStartTick = $script:clockTick }
            $script:circleTurn += $turn
        }
        if (($script:clockTick - $script:circleStartTick) -gt 70) {
            # Too slow for a circle (two loops taking more than about 4 seconds): start counting again.
            $script:circleTurn = 0.0
            $script:circleStartTick = $script:clockTick
        }
    }
    $script:circleDir = $ang
    $script:circleHasDir = $true
    if ([Math]::Abs($script:circleTurn) -ge (4 * [Math]::PI)) {
        $script:circleTurn = 0.0
        Start-CircleChase
    }
}

function Start-CircleChase {
    # Runs over to the circling pointer for up to about 10 seconds.
    if ($script:dogHidden -or $script:isDragging -or $script:alarmRinging -or $script:focusState -eq 'focus') { return }
    if ($script:clockTick -lt $script:circleChaseUntil) { return }
    if ($script:dogSleeping -and ($script:dogNightSleep -or $script:dogActLen -eq 0)) { return }
    if ($script:dogAct -eq 'eat' -or $script:dogAct -eq 'drink' -or $script:dogAct -eq 'fling' -or $script:dogAct -eq 'spin' -or
        $script:dogAct -eq 'paw' -or $script:dogAct -eq 'playdead' -or $script:dogAct -eq 'fetch' -or $script:dogAct -eq 'jerky' -or $script:dogAct -eq 'burst') { return }
    if ($script:dogSleeping) { Stop-DogSleep $false }
    $script:dogAct = ''
    $script:lastInteractTick = $script:clockTick
    $cur = [System.Windows.Forms.Cursor]::Position
    $script:facingLeft = ($cur.X -lt ($script:baseLocation.X + $script:form.Width / 2))
    if (-not $script:roamEnabled) {
        # Walking is switched off: only a look and a happy hop.
        $script:actionMode = 'happy'
        $script:actionTick = 0
        Set-Bubble '汪？你在轉圈圈？'
        return
    }
    $script:actionMode = 'idle'
    $script:circleChaseUntil = $script:clockTick + 160
    $script:roamTarget = $null
    $script:roamPauseTicks = 0
    $lines = @('汪！你在轉圈圈！我來了～', '汪汪！等等我！', '那是什麼？追！')
    Set-Bubble ([string]$lines[$script:rng.Next(0, $lines.Count)])
}

function Invoke-HealthReminder {
    $now = Get-Date
    # Not now (tried again in 5 minutes): at night, when sent to bed, while the person is away, during a focus period.
    $busy = ($script:nightSleepEnabled -and $script:isNight) -or ($script:dogSleeping -and ($script:dogNightSleep -or $script:dogActLen -eq 0)) -or
        $script:awaySeen -or $script:focusState -eq 'focus' -or $script:alarmRinging -or $script:isDragging
    if ($busy) {
        $script:healthNext = $now.AddMinutes(5)
        return
    }
    $script:healthNext = $now.AddMinutes($script:healthMinutes)
    $script:healthCount++
    if ($script:dogSleeping) { Stop-DogSleep $false }
    if ((($script:healthCount % 2) -eq 1) -and (Test-DogAction 'drink')) {
        Start-DogAction 'drink' '該喝水囉！旺旺陪你一起喝～'
    } elseif (Test-DogAction 'bow') {
        Start-DogAction 'bow' '坐好久了，起來伸展一下吧！'
    } else {
        Set-Bubble '坐好久了，起來動一動、喝口水吧！'
    }
    $script:bubbleTicks = 120
    $script:lastInteractTick = $script:clockTick
}

function Start-FocusTimer([int]$work, [int]$rest) {
    if ($script:alarmRinging) { Stop-AlarmRing '' }
    $script:focusState = 'focus'
    $script:focusWork = $work
    $script:breakMinutes = $rest
    $script:focusUntil = (Get-Date).AddMinutes($work)
    if ($script:dogSleeping) { Stop-DogSleep $false }
    Start-DogRest 'focus' ('開始專心 ' + $work + ' 分鐘！旺旺安靜陪你～')
    $script:bubbleTicks = 90
}

function Stop-FocusTimer([string]$say) {
    $script:focusState = ''
    $script:focusUntil = [DateTime]::MaxValue
    if ($script:dogAct -eq 'focus') { $script:dogAct = '' }
    if (-not [string]::IsNullOrEmpty($say)) { Set-Bubble $say }
}

function Update-FocusTimer {
    if ([string]::IsNullOrEmpty($script:focusState)) { return }
    $now = Get-Date
    if ($now -lt $script:focusUntil) { return }
    # More than 2 minutes late (the PC was asleep or the dachshund was hidden): no barking long afterwards.
    $late = ($now - $script:focusUntil).TotalMinutes
    if ($script:focusState -eq 'focus') {
        $script:focusState = 'break'
        $script:focusUntil = $now.AddMinutes($script:breakMinutes)
        if ($script:dogAct -eq 'focus') { $script:dogAct = '' }
        if ($late -le 2) {
            Start-AlarmRing ('專心 ' + $script:focusWork + ' 分鐘完成！休息 ' + $script:breakMinutes + ' 分鐘吧～') 20
        } else {
            Set-Bubble '專心時間結束了，休息一下吧～'
        }
    } else {
        $script:focusState = ''
        $script:focusUntil = [DateTime]::MaxValue
        if ($late -le 2) { Start-AlarmRing '休息結束！要再專心一次嗎？（右鍵 → 番茄鐘）' 15 }
    }
}

function Update-FocusMenu {
    $now = Get-Date
    if ($script:focusState -eq 'focus') {
        $left = [Math]::Max(1, [int][Math]::Ceiling(($script:focusUntil - $now).TotalMinutes))
        $script:miFocusInfo.Text = '專心中：還有 ' + $left + ' 分鐘（' + $script:focusUntil.ToString('HH:mm') + ' 休息）'
    } elseif ($script:focusState -eq 'break') {
        $left = [Math]::Max(1, [int][Math]::Ceiling(($script:focusUntil - $now).TotalMinutes))
        $script:miFocusInfo.Text = '休息中：還有 ' + $left + ' 分鐘'
    } else {
        $script:miFocusInfo.Text = '還沒開始'
    }
    $script:miFocusStop.Enabled = -not [string]::IsNullOrEmpty($script:focusState)
}

function Test-OutfitIdReady([string]$id) {
    foreach ($o in $script:outfitList) {
        if ([string]$o[0] -eq $id) { return (Test-OutfitReady ([string]$o[2])) }
    }
    return $false
}

function Get-HolidayOutfit([DateTime]$d) {
    # @(outfit, bubble) for a holiday or the birthday, or $null on other days.
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $md = $d.ToString('MM-dd', $inv)
    $ymd = $d.ToString('yyyy-MM-dd', $inv)
    if (-not [string]::IsNullOrEmpty($script:birthdayMD) -and $md -eq $script:birthdayMD) { return @('party', '今天是生日！汪汪～生日快樂！') }
    foreach ($cny in $script:lunarNewYear) {
        # Lunar New Year: from New Year's Eve to the 5th day.
        $first = [DateTime]::ParseExact([string]$cny, 'yyyy-MM-dd', $inv)
        if ($d.Date -ge $first.AddDays(-1) -and $d.Date -le $first.AddDays(4)) { return @('cny', '新年快樂！旺旺換上唐裝了～') }
    }
    if ($script:dragonBoat -contains $ymd) { return @('zongzi', '端午節快樂！旺旺變成粽子了～') }
    if ($script:midAutumn -contains $ymd) { return @('rabbit', '中秋節快樂！旺旺變成小兔子了～') }
    if ($md -eq '10-31') { return @('halloween', '萬聖節快樂！不給糖就搗蛋～') }
    if ($md -eq '12-24' -or $md -eq '12-25') { return @('xmas', '聖誕快樂！汪汪～') }
    return $null
}

function Update-HolidayOutfit {
    # Checked when the date changes: put on the holiday clothes, and afterwards change back to the clothes from before.
    $today = (Get-Date).Date
    if ($today -eq $script:holidayDate) { return }
    $script:holidayDate = $today
    if (-not $script:holidayEnabled) { return }
    $h = Get-HolidayOutfit $today
    if ($null -ne $h -and (Test-OutfitIdReady ([string]$h[0]))) {
        if ($script:outfitId -ne [string]$h[0]) {
            if ([string]::IsNullOrEmpty($script:holidayOutfit)) { $script:outfitBeforeHoliday = $script:outfitId }
            $script:holidayOutfit = [string]$h[0]
            Set-DogOutfit ([string]$h[0])
        }
        Set-Bubble ([string]$h[1])
        $script:bubbleTicks = 90
    } elseif (-not [string]::IsNullOrEmpty($script:holidayOutfit)) {
        $back = $script:outfitBeforeHoliday
        $script:holidayOutfit = ''
        if ([string]::IsNullOrEmpty($back)) { $back = 'none' }
        Set-DogOutfit $back
    }
}

function Save-Birthday {
    try {
        if ([string]::IsNullOrEmpty($script:birthdayFile)) { return }
        if ([string]::IsNullOrEmpty($script:birthdayMD)) {
            if (Test-Path -LiteralPath $script:birthdayFile) { Remove-Item -LiteralPath $script:birthdayFile -Force }
            return
        }
        $dir = Split-Path -Parent $script:birthdayFile
        if (-not (Test-Path -LiteralPath $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }
        [System.IO.File]::WriteAllText($script:birthdayFile, $script:birthdayMD, [System.Text.UTF8Encoding]::new($false))
    } catch {
        $null = Write-ErrorLog ('生日沒辦法記下來（下次開旺旺要重新設定）：' + $_.ToString())
    }
}

function Import-Birthday {
    try {
        if ([string]::IsNullOrEmpty($script:birthdayFile) -or -not (Test-Path -LiteralPath $script:birthdayFile)) { return }
        $text = ([System.IO.File]::ReadAllText($script:birthdayFile)).Trim()
        if ($text -match '^(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])$') { $script:birthdayMD = $text }
    } catch { }
}

function Show-BirthdayDialog {
    $dlg = New-Object System.Windows.Forms.Form
    try {
        $dlg.Text = '設定生日'
        $dlg.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
        $dlg.MaximizeBox = $false
        $dlg.MinimizeBox = $false
        $dlg.ShowInTaskbar = $false
        $dlg.TopMost = $true
        $dlg.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
        $dlg.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
        $dlg.Font = [System.Drawing.Font]::new('Microsoft JhengHei UI', 10)
        $dlg.ClientSize = [System.Drawing.Size]::new((Get-Scaled 340), (Get-Scaled 150))

        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text = '生日（每年這一天旺旺會穿生日派對裝）：'
        $lbl.AutoSize = $true
        $lbl.Location = [System.Drawing.Point]::new((Get-Scaled 16), (Get-Scaled 18))
        $dlg.Controls.Add($lbl)

        $picker = New-Object System.Windows.Forms.DateTimePicker
        $picker.Format = [System.Windows.Forms.DateTimePickerFormat]::Custom
        $picker.CustomFormat = "MM'月'dd'日'"
        $picker.ShowUpDown = $true
        $picker.Location = [System.Drawing.Point]::new((Get-Scaled 16), (Get-Scaled 52))
        $picker.Width = Get-Scaled 130
        # A leap year, so that 29 February can be chosen too.
        $today = Get-Date
        $start = [DateTime]::new(2024, $today.Month, $today.Day)
        if (-not [string]::IsNullOrEmpty($script:birthdayMD)) {
            $parsed = [DateTime]::MinValue
            if ([DateTime]::TryParseExact('2024-' + $script:birthdayMD, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture,
                    [System.Globalization.DateTimeStyles]::None, [ref]$parsed)) { $start = $parsed }
        }
        $picker.Value = $start
        $dlg.Controls.Add($picker)

        $btnOk = New-Object System.Windows.Forms.Button
        $btnOk.Text = '設定'
        $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $btnOk.Location = [System.Drawing.Point]::new((Get-Scaled 52), (Get-Scaled 100))
        $btnOk.Size = [System.Drawing.Size]::new((Get-Scaled 84), (Get-Scaled 30))
        $dlg.Controls.Add($btnOk)
        $btnClear = New-Object System.Windows.Forms.Button
        $btnClear.Text = '清除生日'
        $btnClear.DialogResult = [System.Windows.Forms.DialogResult]::No
        $btnClear.Location = [System.Drawing.Point]::new((Get-Scaled 146), (Get-Scaled 100))
        $btnClear.Size = [System.Drawing.Size]::new((Get-Scaled 84), (Get-Scaled 30))
        $dlg.Controls.Add($btnClear)
        $btnCancel = New-Object System.Windows.Forms.Button
        $btnCancel.Text = '取消'
        $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $btnCancel.Location = [System.Drawing.Point]::new((Get-Scaled 240), (Get-Scaled 100))
        $btnCancel.Size = [System.Drawing.Size]::new((Get-Scaled 84), (Get-Scaled 30))
        $dlg.Controls.Add($btnCancel)
        $dlg.AcceptButton = $btnOk
        $dlg.CancelButton = $btnCancel

        $result = $dlg.ShowDialog([System.Windows.Forms.IWin32Window]$script:form)
        if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
            $script:birthdayMD = $picker.Value.ToString('MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
            Save-Birthday
            Set-Bubble ('記住了！' + $picker.Value.Month + ' 月 ' + $picker.Value.Day + ' 日要穿生日派對裝～')
            $script:holidayDate = [DateTime]::MinValue
        } elseif ($result -eq [System.Windows.Forms.DialogResult]::No) {
            $script:birthdayMD = ''
            Save-Birthday
            Set-Bubble '生日清除了'
            $script:holidayDate = [DateTime]::MinValue
        }
    } finally {
        $dlg.Dispose()
    }
}

function Update-DogHunger {
    # Too long without treats (2 hours) or water (1.5 hours): it comes over to the mouse pointer and asks.
    $now = Get-Date
    if ($now -lt $script:begNextAt -or $script:begging) { return }
    if (($script:nightSleepEnabled -and $script:isNight) -or $script:dogSleeping -or $script:awaySeen -or $script:focusState -eq 'focus') { return }
    if ($script:alarmRinging -or $script:isDragging -or $script:dogAct -ne '' -or $script:actionMode -ne 'idle') { return }
    $hungry = ($now - $script:lastFedAt).TotalMinutes -ge $script:hungryMinutes
    $thirsty = (Test-DogAction 'drink') -and (($now - $script:lastDrinkAt).TotalMinutes -ge $script:thirstyMinutes)
    if (-not ($hungry -or $thirsty)) { return }
    $script:begNextAt = $now.AddMinutes(20)
    $script:begWhat = 'drink'
    if ($hungry) { $script:begWhat = 'eat' }
    if ($script:roamEnabled) {
        # Walks over to the mouse pointer first (asks when it gets there).
        $script:begging = $true
        $script:roamTarget = $null
        $script:roamPauseTicks = 0
    } else {
        Invoke-DogBeg
    }
}

function Invoke-DogBeg {
    $script:begging = $false
    $lines = @('好渴喔…可以給我水嗎？', '旺旺想喝水～（右鍵 → 餵水）')
    if ($script:begWhat -eq 'eat') { $lines = @('肚子好餓…可以給我點心嗎？', '旺旺想吃點心～（右鍵 → 餵點心）') }
    if (Test-DogAction 'tilt') { Start-DogAction 'tilt' '' }
    Set-Bubble ([string]$lines[$script:rng.Next(0, $lines.Count)])
    $script:bubbleTicks = 100
}

function Set-PlaySetting([string]$name, [bool]$on) {
    switch ($name) {
        'away' {
            $script:awayEnabled = $on
            $script:awaySeen = $false
            if ($script:dogAct -eq 'wait') { $script:dogAct = '' }
            if ($on) { Set-Bubble '你離開時旺旺會等你～' } else { Set-Bubble '好，不等你了' }
        }
        'tease' {
            $script:teaseEnabled = $on
            if ($on) { Set-Bubble '來逗我玩吧！' } else { Set-Bubble '好，不撲了' }
        }
        'circle' {
            $script:circleEnabled = $on
            $script:circleTurn = 0.0
            $script:circleChaseUntil = 0
            if ($on) { Set-Bubble '繞圈圈給我看，我就追過去！' } else { Set-Bubble '好，繞圈圈不追了' }
        }
        'hunger' {
            $script:hungerEnabled = $on
            $script:begging = $false
            if ($on) { Set-Bubble '肚子餓會跟你說喔～' } else { Set-Bubble '好，不吵著要吃的了' }
        }
        'glass' {
            $script:glassEnabled = $on
            if ($on) { Set-Bubble '被視窗擋住時，叫我我就衝出來！' } else { Set-Bubble '好，叫我時直接跑過來' }
        }
        'holiday' {
            $script:holidayEnabled = $on
            if ($on) {
                $script:holidayDate = [DateTime]::MinValue
                Update-HolidayOutfit
                if ([string]::IsNullOrEmpty($script:holidayOutfit)) { Set-Bubble '節日到了會自動換衣服～' }
            } else {
                if (-not [string]::IsNullOrEmpty($script:holidayOutfit)) {
                    $back = $script:outfitBeforeHoliday
                    $script:holidayOutfit = ''
                    if ([string]::IsNullOrEmpty($back)) { $back = 'none' }
                    Set-DogOutfit $back
                }
                Set-Bubble '好，節日不自動換衣服了'
            }
        }
    }
}

# -----------------------------------------------------------------------------
# Dachshund actions
#   Len = length in animation ticks (60 ms), Poses = pictures the action needs,
#   Say = bubble lines (one is picked at random).
# -----------------------------------------------------------------------------
$script:dogActionSpec = @{
    tilt  = @{ Len = 40;  Poses = @('tilt_00', 'tilt_01');   Say = @('汪？', '嗯？', '你在說什麼？') }
    sniff = @{ Len = 50;  Poses = @('sniff_00', 'sniff_01'); Say = @('嗅嗅…', '好像有好吃的味道', '聞聞看～') }
    shake = @{ Len = 17;  Poses = @('shake_00', 'shake_01', 'shake_02', 'shake_03'); Say = @('甩甩～') }
    look  = @{ Len = 40;  Poses = @();                        Say = @('咦？', '') }
    bow   = @{ Len = 30;  Poses = @('bow_00');                Say = @('伸懶腰～') }
    lie   = @{ Len = 160; Poses = @('lie_00');                Say = @('趴一下～', '好舒服～', '趴著吹風～') }
    pet   = @{ Len = 40;  Poses = @();                        Say = @('好舒服～♥') }
    yawn  = @{ Len = 34;  Poses = @('yawn_00');               Say = @('哈～啊～', '好睏喔…', '打個哈欠～') }
    sit   = @{ Len = 120; Poses = @('sit_00');                Say = @('旺旺坐好了！', '乖乖坐下～', '坐下等點心～') }
    eat   = @{ Len = 90;  Poses = @('eat_00', 'eat_01', 'eat_02'); Say = @('哇！有點心！', '好香喔～', '點心！點心！') }
    drink = @{ Len = 70;  Poses = @('drink_00', 'drink_01'); Say = @('咕嚕咕嚕～', '好渴喔～', '喝水水～') }
    spin  = @{ Len = 36;  Poses = @();                        Say = @('轉圈圈～') }
    tease = @{ Len = 70;  Poses = @('tilt_00', 'tilt_01', 'bow_00'); Say = @('咦？那是什麼？', '嗯？要跟我玩嗎？') }
    paw   = @{ Len = 74;  Poses = @('sit_00', 'paw_00');      Say = @('握手！汪！', '給你我的手手～', '握握手～好朋友！') }
    playdead = @{ Len = 110; Poses = @('lie_00', 'belly_00'); Say = @('碰！旺旺倒下了…', '啊～被打中了…', '旺旺裝死中…') }
    jerky = @{ Len = 84;  Poses = @('jerky_00', 'jerky_01');  Say = @('肉乾！我的！', '咬到了～', '好香的肉乾！') }
    fetch = @{ Len = 0;   Poses = @();                        Say = @('肉乾！我來了～') }
}

function Test-DogAction([string]$name) {
    if (-not $script:dogActionSpec.ContainsKey($name)) { return $false }
    foreach ($p in $script:dogActionSpec[$name].Poses) {
        if (-not $script:dogPoses.ContainsKey($p)) { return $false }
    }
    return $true
}

function Start-DogAction([string]$name, [string]$say) {
    # $say: '' = no bubble, '*' = a random line for this action, anything else = that text.
    if (-not (Test-DogAction $name)) { Set-Bubble '少了這個動作的圖片'; return }
    $spec = $script:dogActionSpec[$name]
    $script:dogSleeping = $false
    $script:bellyRubTicks = 0
    $script:trickPoked = $false
    $script:dogNightSleep = $false
    $script:dogAct = $name
    $script:dogActTick = 0
    $script:dogActLen = [int]$spec.Len
    $script:dogActPose = if ($script:rng.Next(0, 2) -eq 0) { 'tilt_00' } else { 'tilt_01' }
    $script:actionMode = 'idle'
    $script:actionTick = 0
    $script:roamMoving = $false
    if ($name -eq 'look') { $script:facingLeft = -not $script:facingLeft }
    if ($name -eq 'eat' -or $name -eq 'drink' -or $name -eq 'jerky') {
        # Hungry or thirsty before this? Then it is extra happy afterwards. The jerky counts as a treat.
        $food = ($name -eq 'eat' -or $name -eq 'jerky')
        $last = $script:lastDrinkAt
        $limit = $script:thirstyMinutes
        if ($food) {
            $last = $script:lastFedAt
            $limit = $script:hungryMinutes
        }
        $script:fedWhileHungry = ((Get-Date) - $last).TotalMinutes -ge $limit
        if ($food) { $script:lastFedAt = Get-Date } else { $script:lastDrinkAt = Get-Date }
        $script:begging = $false
        $script:begNextAt = (Get-Date).AddMinutes(20)
    }
    if ($say -eq '*') {
        $lines = @($spec.Say)
        $say = [string]$lines[$script:rng.Next(0, $lines.Count)]
    }
    if (-not [string]::IsNullOrEmpty($say)) { Set-Bubble $say }
}

# -----------------------------------------------------------------------------
# 丟肉乾: a piece of jerky (jerky.png) is thrown from the mouse pointer and lands on the desktop (in gravity mode
# on the taskbar); 旺旺 watches it fly, runs over and eats it (counts as a treat). The jerky has its own small
# window; while it is not on the screen the window waits far outside every screen (never hidden or shown again,
# so it never takes the keyboard focus).
# -----------------------------------------------------------------------------
function Initialize-JerkyWindow {
    if ($null -ne $script:jerkyForm) { return }
    $jf = $null
    $smooth = $false
    if ($script:smoothAvailable) {
        try { $jf = New-Object WangwangPet.SmoothForm; $smooth = $true } catch { $jf = $null; $smooth = $false }
    }
    if ($null -eq $jf) { $jf = New-Object System.Windows.Forms.Form }
    $jf.Text = '旺旺的肉乾'
    $jf.FormBorderStyle = 'None'
    $jf.StartPosition = 'Manual'
    $jf.TopMost = $true
    $jf.ShowInTaskbar = $false
    $jf.BackColor = [System.Drawing.Color]::Magenta
    if (-not $smooth) {
        $jf.TransparencyKey = [System.Drawing.Color]::Magenta
        $jp = New-Object System.Windows.Forms.PictureBox
        $jp.SizeMode = 'Normal'
        $jp.BackColor = [System.Drawing.Color]::Transparent
        $jp.Dock = 'Fill'
        $jf.Controls.Add($jp)
        $script:jerkyPic = $jp
    }
    $jf.Width = 40
    $jf.Height = 20
    $jf.Location = [System.Drawing.Point]::new(-25000, -25000)
    $script:jerkyForm = $jf
    $script:jerkySmooth = $smooth
    $jf.Show()
    if ($smooth) { [WangwangPet.SmoothWindow]::Reset($jf.Handle) }
}

function Get-JerkyBitmap {
    # The jerky at the size it has in the eating pictures (140 of the 768 pixels).
    $w = [Math]::Max(8, [int][Math]::Round($script:form.Width * 140.0 / 768.0))
    $key = [string]$w + '|' + [string]$script:jerkyFlip + '|' + [string]$script:jerkySmooth
    if ($script:jerkyBmpKey -eq $key -and $null -ne $script:jerkyBmp) { return $script:jerkyBmp }
    $src = [System.Drawing.Image]::FromFile($script:jerkyPath)
    try {
        $h = [Math]::Max(4, [int][Math]::Round($w * $src.Height / [double]$src.Width))
        $bmp = [System.Drawing.Bitmap]::new($w, $h, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        try {
            $g.Clear([System.Drawing.Color]::Transparent)
            if ($script:jerkySmooth) {
                $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            } else {
                # Colour-key window: hard edges, no pink fringe.
                $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
                $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
            }
            $g.DrawImage($src, [System.Drawing.Rectangle]::new(0, 0, $w, $h))
        } finally {
            $g.Dispose()
        }
    } finally {
        $src.Dispose()
    }
    if ($script:jerkyFlip) { $bmp.RotateFlip([System.Drawing.RotateFlipType]::RotateNoneFlipX) }
    if ($null -ne $script:jerkyBmp) { try { $script:jerkyBmp.Dispose() } catch { } }
    $script:jerkyBmp = $bmp
    $script:jerkyBmpKey = $key
    return $bmp
}

function Show-JerkyWindow {
    $bmp = Get-JerkyBitmap
    $x = [int][Math]::Round($script:jerkyX)
    $y = [int][Math]::Round($script:jerkyY)
    if ($script:jerkySmooth) {
        $code = [WangwangPet.SmoothWindow]::Show($script:jerkyForm.Handle, $bmp, $x, $y)
        if ($code -ne 0) { throw ('肉乾顯示失敗，代碼 ' + $code) }
    } else {
        if ($script:jerkyForm.Width -ne $bmp.Width -or $script:jerkyForm.Height -ne $bmp.Height) {
            $script:jerkyForm.Size = [System.Drawing.Size]::new($bmp.Width, $bmp.Height)
        }
        if (-not [object]::ReferenceEquals($script:jerkyPic.Image, $bmp)) { $script:jerkyPic.Image = $bmp }
        $script:jerkyForm.Location = [System.Drawing.Point]::new($x, $y)
    }
}

function Hide-Jerky {
    $script:jerkyState = ''
    $script:jerkyTicks = 0
    if ($null -eq $script:jerkyForm) { return }
    try {
        if ($script:jerkySmooth) {
            $bmp = Get-JerkyBitmap
            [void][WangwangPet.SmoothWindow]::Show($script:jerkyForm.Handle, $bmp, -25000, -25000)
        } else {
            $script:jerkyForm.Location = [System.Drawing.Point]::new(-25000, -25000)
        }
    } catch { }
}

function Start-JerkyThrow {
    if (-not (Test-DogAction 'jerky')) { Set-Bubble '這件衣服還沒有吃肉乾的圖片，換別件或脫掉衣服再試試～'; return }
    if (-not (Test-Path -LiteralPath $script:jerkyPath)) { Set-Bubble '找不到肉乾的圖片（jerky.png）'; return }
    if ($script:dogAct -eq 'jerky') { Set-Bubble '我還在吃上一片～等一下！'; return }
    if ($script:dogAct -eq 'burst') { return }
    Initialize-JerkyWindow
    if ($script:dogSleeping) { Stop-DogSleep $false }
    if ($script:alarmRinging) { Stop-AlarmRing '' }
    $script:jerkyFlip = ($script:rng.Next(0, 2) -eq 0)
    $bmp = Get-JerkyBitmap
    $jw = [double]$bmp.Width
    $jh = [double]$bmp.Height
    $cur = [System.Windows.Forms.Cursor]::Position
    $wa = [System.Windows.Forms.Screen]::FromPoint($cur).WorkingArea
    $script:jerkyArea = $wa
    $script:jerkyX = [double]$cur.X - $jw / 2
    $script:jerkyY = [double]$cur.Y - $jh / 2
    # Thrown away from 旺旺, a little up and then down.
    $dogCx = [double]$script:baseLocation.X + $script:form.Width / 2.0
    $dir = if ([double]$cur.X -ge $dogCx) { 1.0 } else { -1.0 }
    $spd = [double]$script:dpiScale
    $script:jerkyVX = $dir * ($script:rng.Next(70, 140) / 10.0) * $spd
    $script:jerkyVY = -($script:rng.Next(100, 170) / 10.0) * $spd
    # Where it lands: in gravity mode on the taskbar, otherwise at the height of 旺旺's paws
    # (or lower when it is thrown from further down), always on the screen.
    $floor = [double]$wa.Bottom - $jh
    if (-not $script:gravityMode) {
        $feet = [double]$script:baseLocation.Y + $script:form.Height * 674.0 / 768.0 - $jh
        $floor = [Math]::Min($floor, [Math]::Max($feet, [double]$cur.Y + $jh))
    }
    $script:jerkyFloor = $floor
    $script:jerkyState = 'fly'
    $script:jerkyTicks = 0
    Show-JerkyWindow
    # 旺旺 watches it fly (also stops roaming, begging and other small actions).
    $script:begging = $false
    $script:circleChaseUntil = 0
    $script:roamTarget = $null
    $script:roamMoving = $false
    $script:actionMode = 'idle'
    $script:actionTick = 0
    $script:dogSleeping = $false
    $script:dogNightSleep = $false
    $script:dogAct = 'fetch'
    $script:dogActTick = 0
    $script:dogActLen = 0
    $script:fetchMoving = $false
    $script:lastInteractTick = $script:clockTick
    $lines = @('哇！肉乾！', '是肉乾！汪汪！', '肉乾！肉乾！')
    Set-Bubble ([string]$lines[$script:rng.Next(0, $lines.Count)])
}

function Update-Jerky([bool]$menuOpen) {
    if ($script:jerkyState -eq '') { return }
    $script:jerkyTicks++
    $wa = $script:jerkyArea
    if ($script:jerkyState -eq 'fly') {
        # Flies, falls, bounces once and slides to a stop.
        $bmp = Get-JerkyBitmap
        $script:jerkyVY = [Math]::Min($script:jerkyVY + 1.8 * $script:dpiScale, 40.0 * $script:dpiScale)
        $script:jerkyX += $script:jerkyVX
        $script:jerkyY += $script:jerkyVY
        $minX = [double]$wa.Left
        $maxX = [double]$wa.Right - $bmp.Width
        if ($script:jerkyX -lt $minX) { $script:jerkyX = $minX; $script:jerkyVX = -$script:jerkyVX * 0.4 }
        if ($script:jerkyX -gt $maxX) { $script:jerkyX = $maxX; $script:jerkyVX = -$script:jerkyVX * 0.4 }
        if ($script:jerkyY -ge $script:jerkyFloor) {
            $script:jerkyY = $script:jerkyFloor
            if ($script:jerkyVY -gt (8.0 * $script:dpiScale)) {
                $script:jerkyVY = -$script:jerkyVY * 0.25
                $script:jerkyVX = $script:jerkyVX * 0.6
            } else {
                $script:jerkyVY = 0.0
                $script:jerkyVX = $script:jerkyVX * 0.6
                if ([Math]::Abs($script:jerkyVX) -lt 0.6) { $script:jerkyState = 'land'; $script:jerkyTicks = 0 }
            }
        }
        if ($script:jerkyTicks -gt 200) {
            $script:jerkyY = $script:jerkyFloor
            $script:jerkyState = 'land'
            $script:jerkyTicks = 0
        }
        Show-JerkyWindow
        return
    }
    # On the ground: when 旺旺 was busy with something else (picked up, thrown, petted ...), it goes again.
    if ($script:dogAct -eq '' -and $script:actionMode -eq 'idle' -and -not $script:isDragging -and -not $menuOpen -and
        -not $script:dogSleeping -and -not $script:alarmRinging -and $script:jerkyTicks -gt 10) {
        $script:dogAct = 'fetch'
        $script:dogActTick = 0
        $script:dogActLen = 0
        $script:fetchMoving = $false
    }
    # Left lying for about three minutes (旺旺 asleep, or no pictures for this outfit): it is tidied away.
    if ($script:jerkyTicks -gt 3000 -and $script:dogAct -ne 'fetch') { Hide-Jerky }
}

function Get-FetchTarget {
    # Where the window has to be so that the jerky in the eating picture lies where the real one landed:
    # in the picture (facing right) its centre is at 628 and its lower edge at 691 of the 768 pixels.
    $bmp = Get-JerkyBitmap
    $w = [double]$script:form.Width
    $h = [double]$script:form.Height
    $cx = $script:jerkyX + $bmp.Width / 2.0
    $bottom = $script:jerkyY + $bmp.Height
    $wa = $script:jerkyArea
    $right = $cx - $w * 628.0 / 768.0
    $left = $cx - $w * (768.0 - 628.0) / 768.0
    $minX = [double]$wa.Left - $w * 0.05
    $maxX = [double]$wa.Right - $w * 0.95
    $dogCx = [double]$script:baseLocation.X + $w / 2.0
    # Comes from the side it is on; when there is no room there, from the other side.
    $faceLeft = ($dogCx -gt $cx)
    $tx = if ($faceLeft) { $left } else { $right }
    if ($tx -lt $minX -or $tx -gt $maxX) {
        $faceLeft = -not $faceLeft
        $tx = if ($faceLeft) { $left } else { $right }
    }
    $tx = [Math]::Min([Math]::Max($tx, $minX), $maxX)
    $ty = $bottom - $h * 691.0 / 768.0
    if ($script:gravityMode) {
        $gb = Get-GroundBounds
        $ty = [double]$gb[3]
    }
    $ty = [Math]::Max($ty, [double]$wa.Top)
    return @($tx, $ty, $faceLeft)
}

function Start-RandomDogAction {
    # Weighted pick among the actions whose pictures are present.
    $pool = @(@('tilt', 22), @('sniff', 22), @('look', 16), @('shake', 14), @('sit', 12), @('lie', 10), @('bow', 6), @('yawn', 6))
    $ok = @()
    $total = 0
    foreach ($entry in $pool) {
        if (Test-DogAction ([string]$entry[0])) {
            $ok += , $entry
            $total += [int]$entry[1]
        }
    }
    if ($total -le 0) { return }
    $roll = $script:rng.Next(0, $total)
    foreach ($entry in $ok) {
        $roll -= [int]$entry[1]
        if ($roll -lt 0) {
            Start-DogAction ([string]$entry[0]) '*'
            return
        }
    }
}

function Start-DogSleep([bool]$manual, [string]$style = '', [bool]$night = $false) {
    # $style: 'sleep_00' (chin on the paws), 'sidesleep_00' (on its side), 'belly_00' (belly up),
    #         'flat_00' (flat on its side, belly out), 'curl_00' (curled up), 'bed_00' (in its dog bed), '' = random.
    if (-not ($script:dogPoses.ContainsKey('lie_00') -and $script:dogPoses.ContainsKey('sleep_00'))) { Set-Bubble '少了睡覺的圖片'; return }
    # At night (22:00-06:59) the dachshund always goes to its dog bed, unless a style was picked from the menu.
    if (([string]::IsNullOrEmpty($style) -or -not $script:dogPoses.ContainsKey($style)) -and ($night -or (Test-NightTime)) -and $script:dogPoses.ContainsKey('bed_00')) {
        $style = 'bed_00'
    }
    if ([string]::IsNullOrEmpty($style) -or -not $script:dogPoses.ContainsKey($style)) {
        # Random among the sleeping pictures that are present (chin on the paws is the favourite).
        $choices = @('sleep_00', 'sleep_00')
        if ($script:dogPoses.ContainsKey('sidesleep_00')) { $choices += 'sidesleep_00' }
        foreach ($extra in @('belly_00', 'flat_00', 'curl_00', 'bed_00')) {
            if ($script:dogPoses.ContainsKey($extra)) { $choices += $extra }
        }
        $style = [string]$choices[$script:rng.Next(0, $choices.Count)]
    }
    $script:dogSleepPose = $style
    $script:dogSleeping = $true
    $script:bellyRubTicks = 0
    $script:dogNightSleep = $night
    $script:dogAct = 'sleep'
    $script:dogActTick = 0
    # First a yawn, then turning around on the spot (like a real dog), then lying down.
    $script:dogSleepYawn = 0
    if ($script:dogPoses.ContainsKey('yawn_00')) { $script:dogSleepYawn = 22 }
    # One quick turn when sent to bed from the menu, a little longer for a nap of its own.
    $circleTicks = 0
    if ($script:dogWalkFrames.Count -eq 4) { $circleTicks = if ($manual) { 10 } else { 18 } }
    $script:dogSleepPre = $script:dogSleepYawn + $circleTicks
    # A nap lasts 1 to 2 minutes; from the menu, or at night, it sleeps until woken (night: until 7:00).
    $script:dogActLen = if ($manual -or $night) { 0 } else { $script:dogSleepPre + $script:rng.Next(1000, 2000) }
    $script:actionMode = 'idle'
    $script:actionTick = 0
    $script:roamMoving = $false
    if ($night -and $style -eq 'bed_00') { Set-Bubble '晚安～旺旺回狗窩睡覺了' }
    elseif ($night) { Set-Bubble '晚安～旺旺要睡覺了' }
    elseif ($style -eq 'sidesleep_00') { Set-Bubble '旺旺躺下來曬太陽～' }
    elseif ($style -eq 'belly_00') { Set-Bubble '旺旺翻肚睡～' }
    elseif ($style -eq 'flat_00') { Set-Bubble '旺旺攤平曬肚子～' }
    elseif ($style -eq 'curl_00') { Set-Bubble '旺旺縮成一團睡～' }
    elseif ($style -eq 'bed_00') { Set-Bubble '旺旺窩進狗窩囉～' }
    else { Set-Bubble '呼～旺旺想睡了…' }
}

function Stop-DogSleep([bool]$stretch, [string]$say = '汪～旺旺睡飽了！') {
    $wasSleeping = $script:dogSleeping
    $script:dogSleeping = $false
    $script:bellyRubTicks = 0
    $script:dogNightSleep = $false
    if ($script:dogAct -eq 'sleep') { $script:dogAct = '' }
    $script:lastInteractTick = $script:clockTick
    $script:napAfterTicks = $script:rng.Next(4000, 8000)
    if ($wasSleeping -and $stretch) {
        if (Test-DogAction 'bow') { Start-DogAction 'bow' $say } else { Set-Bubble $say }
    }
}

function Test-BellyRubClick {
    # A click on the belly while it sleeps belly up (settled after rolling over, with its own belly-rub picture).
    if ($script:dogAct -ne 'sleep' -or $script:dogSleepPose -ne 'belly_00') { return $false }
    if (-not $script:dogPoses.ContainsKey('rub_00')) { return $false }
    if (($script:dogActTick - $script:dogSleepPre) -lt 28) { return $false }
    try {
        $p = $script:form.PointToClient([System.Windows.Forms.Cursor]::Position)
        $w = [double]$script:form.ClientSize.Width
        $h = [double]$script:form.ClientSize.Height
        if ($w -le 0 -or $h -le 0) { return $false }
        $fx = [double]$p.X / $w
        $fy = [double]$p.Y / $h
        # The pictures face right (mirrored when it faces left): the head is the right end, the belly the middle.
        if ($script:facingLeft) { $fx = 1.0 - $fx }
        return ($fx -ge 0.15 -and $fx -le 0.72 -and $fy -ge 0.25 -and $fy -le 0.95)
    } catch {
        return $false
    }
}

function Start-BellyRub {
    # Belly rub: wriggles happily with the tongue out for about 3 seconds, then sleeps on (another click: longer).
    $first = ($script:bellyRubTicks -le 0)
    $script:bellyRubTicks = 46
    $script:lastInteractTick = $script:clockTick
    if ($first) {
        $lines = @('嘿嘿～好癢喔～', '好舒服～再摸摸～♥', '肚肚被摸了～開心！', '摸摸肚～旺旺最喜歡了～♥')
        Set-Bubble ([string]$lines[$script:rng.Next(0, $lines.Count)])
    }
}

function Invoke-DogHover {
    # The pointer touched the dachshund: a curious head tilt (at most every 10 seconds).
    if ($script:isDragging) { return }
    if (($script:clockTick - $script:hoverReactTick) -lt 160) { return }
    $script:hoverReactTick = $script:clockTick
    if ($script:dogSleeping) {
        if ($script:bellyRubTicks -gt 0) { return }
        if ($script:dogSleepPose -eq 'belly_00' -and $script:dogPoses.ContainsKey('rub_00')) { Set-Bubble 'Zzz…（點肚子摸摸，點頭叫醒旺旺）' } else { Set-Bubble 'Zzz…（點我叫醒旺旺）' }
        return
    }
    if ($script:dogAct -eq '' -and $script:actionMode -eq 'idle' -and (Test-DogAction 'tilt')) { Start-DogAction 'tilt' '汪？' }
}

function Get-DogFramePath {
    # Picture for the dachshund this tick, or $null for the normal standing tail wag.
    $walkSeq = @(1, 0, 1, 2, 3, 2)
    if ($script:isDragging -and $script:dragMoved) {
        # Picked up: the legs paddle in the air.
        if ($script:dogWalkFrames.Count -eq 4) { return $script:dogWalkFrames[$walkSeq[$script:clockTick % 6]] }
        return $null
    }
    $t = $script:dogActTick
    switch ($script:dogAct) {
        'tilt' {
            if ($t -ge 2 -and $t -lt ($script:dogActLen - 3)) { return $script:dogPoses[$script:dogActPose] }
            return $null
        }
        'shake' {
            # Head shake: head, neck and shoulders sway together from side to side (4 and 8 degrees), then settle.
            $shakeSeq = @('', 'shake_00', 'shake_01', 'shake_00', '', 'shake_02', 'shake_03', 'shake_02', '',
                'shake_00', 'shake_01', 'shake_00', '', 'shake_02', '', 'shake_00', '')
            $k = [string]$shakeSeq[[Math]::Min($t, $shakeSeq.Count - 1)]
            if ([string]::IsNullOrEmpty($k)) { return $null }
            return $script:dogPoses[$k]
        }
        'sniff' {
            if ($t -lt 3 -or $t -ge ($script:dogActLen - 3)) { return $script:dogPoses['sniff_00'] }
            $sniffPoses = @('sniff_01', 'sniff_00')
            return $script:dogPoses[$sniffPoses[([int][Math]::Floor($t / 3)) % 2]]
        }
        'bow' {
            # Getting up from lying down (or starting the stretch) goes through a short crouch.
            if ($t -lt 4 -and $script:dogPoses.ContainsKey('crouch_00')) { return $script:dogPoses['crouch_00'] }
            if ($t -ge 2 -and $t -lt ($script:dogActLen - 2)) { return $script:dogPoses['bow_00'] }
            return $null
        }
        'lie' {
            # Lying down and getting up again go through a short crouch.
            if (($t -lt 5 -or $t -ge ($script:dogActLen - 5)) -and $script:dogPoses.ContainsKey('crouch_00')) { return $script:dogPoses['crouch_00'] }
            return $script:dogPoses['lie_00']
        }
        'sleep' {
            # Before lying down: a yawn, then stepping round in a circle.
            $pre = $t - $script:dogSleepPre
            if ($pre -lt 0) {
                if ($t -lt $script:dogSleepYawn) {
                    if ($t -ge 2 -and $t -lt ($script:dogSleepYawn - 2)) { return $script:dogPoses['yawn_00'] }
                    return $null
                }
                if ($script:dogWalkFrames.Count -eq 4) { return $script:dogWalkFrames[$walkSeq[$t % 6]] }
                return $null
            }
            if ($pre -lt 5 -and $script:dogPoses.ContainsKey('crouch_00')) { return $script:dogPoses['crouch_00'] }
            if ($pre -lt 20) { return $script:dogPoses['lie_00'] }
            # Belly up: rolls onto its side first.
            if (($script:dogSleepPose -eq 'belly_00' -or $script:dogSleepPose -eq 'flat_00') -and $pre -lt 28 -and $script:dogPoses.ContainsKey('sidesleep_00')) { return $script:dogPoses['sidesleep_00'] }
            # Belly rub: wriggles happily with its eyes open and the tongue out.
            if ($script:bellyRubTicks -gt 0 -and $script:dogSleepPose -eq 'belly_00' -and $script:dogPoses.ContainsKey('rub_00')) { return $script:dogPoses['rub_00'] }
            if ($script:dogPoses.ContainsKey($script:dogSleepPose)) { return $script:dogPoses[$script:dogSleepPose] }
            return $script:dogPoses['sleep_00']
        }
        'pet' {
            # Fast happy tail wag, tongue out when that picture is there.
            $wagSeq = @(0, 1, 2, 1)
            if ($script:dogHappyFrames.Count -eq 3) { return $script:dogHappyFrames[$wagSeq[$t % 4]] }
            if ($script:dogWagFrames.Count -eq 3) { return $script:dogWagFrames[$wagSeq[$t % 4]] }
            return $null
        }
        'yawn' {
            if ($t -ge 3 -and $t -lt ($script:dogActLen - 3)) { return $script:dogPoses['yawn_00'] }
            return $null
        }
        'sit' {
            return $script:dogPoses['sit_00']
        }
        'eat' {
            # Eating from the bowl: a look at the treats, then snout in the bowl (bite, chew, bite, chew),
            # head up a little to chew, three times; at the end a happy face with the tongue out.
            # eat_00 = snout in the bowl, mouth open; eat_01 = snout in the bowl, mouth closed; eat_02 = head just above the bowl.
            if ($t -lt 6) { return $script:dogPoses['eat_02'] }
            if ($t -lt 66) {
                $c = ($t - 6) % 20
                if ($c -lt 12) {
                    if ((([int][Math]::Floor($c / 3)) % 2) -eq 0) { return $script:dogPoses['eat_00'] }
                    return $script:dogPoses['eat_01']
                }
                return $script:dogPoses['eat_02']
            }
            if ($t -lt 72) { return $script:dogPoses['eat_02'] }
            $eatWag = @(0, 1, 2, 1)
            if ($script:dogHappyFrames.Count -eq 3) { return $script:dogHappyFrames[$eatWag[$t % 4]] }
            return $null
        }
        'drink' {
            # Drinking from the water bowl: the tongue laps the water (drink_00) with the mouth closed in between
            # (drink_01), about four laps a second with a short pause; at the end a happy face with the tongue out.
            if ($t -lt 4 -or ($t -ge 24 -and $t -lt 28) -or ($t -ge 44 -and $t -lt 50)) { return $script:dogPoses['drink_01'] }
            if ($t -lt 44) {
                if ((([int][Math]::Floor($t / 2)) % 2) -eq 0) { return $script:dogPoses['drink_00'] }
                return $script:dogPoses['drink_01']
            }
            $drinkWag = @(0, 1, 2, 1)
            if ($script:dogHappyFrames.Count -eq 3) { return $script:dogHappyFrames[$drinkWag[$t % 4]] }
            return $null
        }
        'paw' {
            # Shaking hands: sits, holds out a front paw, puts it down, then a happy face.
            if ($t -lt 8 -or ($t -ge 50 -and $t -lt 56)) { return $script:dogPoses['sit_00'] }
            if ($t -lt 50) { return $script:dogPoses['paw_00'] }
            $pawWag = @(0, 1, 2, 1)
            if ($script:dogHappyFrames.Count -eq 3) { return $script:dogHappyFrames[$pawWag[$t % 4]] }
            return $null
        }
        'playdead' {
            # Playing dead: drops down, rolls over belly up and lies still, then jumps up happily.
            if ($t -lt 4 -and $script:dogPoses.ContainsKey('crouch_00')) { return $script:dogPoses['crouch_00'] }
            if ($t -lt 9) { return $script:dogPoses['lie_00'] }
            if ($t -lt 15 -and $script:dogPoses.ContainsKey('sidesleep_00')) { return $script:dogPoses['sidesleep_00'] }
            if ($t -lt 84) { return $script:dogPoses['belly_00'] }
            if ($t -lt 89 -and $script:dogPoses.ContainsKey('sidesleep_00')) { return $script:dogPoses['sidesleep_00'] }
            if ($t -lt 94) { return $script:dogPoses['lie_00'] }
            $deadWag = @(0, 1, 2, 1)
            if ($script:dogHappyFrames.Count -eq 3) { return $script:dogHappyFrames[$deadWag[$t % 4]] }
            return $null
        }
        'spin' {
            # Spinning round on the spot: stepping legs, facing one way and then the other.
            if ($script:dogWalkFrames.Count -eq 4) { return $script:dogWalkFrames[$walkSeq[$t % 6]] }
            return $null
        }
        'fling' {
            # Gravity mode, coming down: the ears fly up and out like wings (not while going up).
            if ($script:gravityMode -and $script:fallFrameOn -and $script:dogPoses.ContainsKey('fall_00')) { return $script:dogPoses['fall_00'] }
            # Thrown: the legs paddle while it flies or slides.
            if ($script:dogWalkFrames.Count -eq 4) { return $script:dogWalkFrames[$walkSeq[$script:clockTick % 6]] }
            return $null
        }
        'tease' {
            # Watching the pointer (head tilts), a play bow, a pounce, then a happy face.
            if ($t -lt 24) {
                if ((([int][Math]::Floor($t / 4)) % 2) -eq 0) { return $script:dogPoses['tilt_00'] }
                return $script:dogPoses['tilt_01']
            }
            if ($t -lt 27 -and $script:dogPoses.ContainsKey('crouch_00')) { return $script:dogPoses['crouch_00'] }
            if ($t -lt 40) { return $script:dogPoses['bow_00'] }
            if ($t -le 52) {
                # The pounce: pushes off with the legs under the body, flies with the legs stretched out, lands.
                if (Test-RunFrames) {
                    if ($t -le 42 -or $t -ge 51) { return $script:dogPoses['run_00'] }
                    return $script:dogPoses['run_01']
                }
                if ($script:dogWalkFrames.Count -eq 4) { return $script:dogWalkFrames[$walkSeq[$t % 6]] }
                return $null
            }
            $teaseWag = @(0, 1, 2, 1)
            if ($script:dogHappyFrames.Count -eq 3) { return $script:dogHappyFrames[$teaseWag[$t % 4]] }
            return $null
        }
        'fetch' {
            # Watching the jerky fly (standing, tail wagging), then running over to it.
            if ($script:fetchMoving) {
                if (Test-RunFrames) {
                    $fetchPhase = [int]($script:idleTick % 4)
                    if ($fetchPhase -eq 1 -or $fetchPhase -eq 2) { return $script:dogPoses['run_01'] }
                    return $script:dogPoses['run_00']
                }
                if ($script:dogWalkFrames.Count -eq 4) { return $script:dogWalkFrames[$walkSeq[$script:clockTick % 6]] }
            }
            return $null
        }
        'jerky' {
            # Eating the jerky: bites it on the ground (jerky_00), lifts the head and chews (jerky_01), then a happy face.
            if ($t -lt 14) { return $script:dogPoses['jerky_00'] }
            if ($t -lt 62) { return $script:dogPoses['jerky_01'] }
            $jerkyWag = @(0, 1, 2, 1)
            if ($script:dogHappyFrames.Count -eq 3) { return $script:dogHappyFrames[$jerkyWag[$t % 4]] }
            return $null
        }
        'burst' {
            # Landed after breaking out: happy face with the tongue out.
            $burstWag = @(0, 1, 2, 1)
            if ($t -ge 11 -and $script:dogHappyFrames.Count -eq 3) { return $script:dogHappyFrames[$burstWag[$t % 4]] }
            return $null
        }
        'wait' {
            # Lying down, waiting for the person to come back.
            if ($t -lt 5 -and $script:dogPoses.ContainsKey('crouch_00')) { return $script:dogPoses['crouch_00'] }
            return $script:dogPoses['lie_00']
        }
        'focus' {
            # Lying quietly during a focus period.
            if ($t -lt 5 -and $script:dogPoses.ContainsKey('crouch_00')) { return $script:dogPoses['crouch_00'] }
            return $script:dogPoses['lie_00']
        }
    }
    if ($script:roamMoving -and $script:dogRunning -and (Test-RunFrames)) {
        # Running: legs under the body (ears down), then stretched out in a leap (ears flying up and back).
        if ($script:dogRunStep -eq 0) { return $script:dogPoses['run_00'] }
        return $script:dogPoses['run_01']
    }
    if ($script:roamMoving -and $script:dogWalkFrames.Count -eq 4) { return $script:dogWalkFrames[$walkSeq[$script:dogWalkStep]] }
    if ($script:actionMode -ne 'idle') {
        # Happy hop after a pat or a bark: tongue out when that picture is there.
        $wagSeq = @(0, 1, 2, 1)
        if ($script:dogHappyFrames.Count -eq 3) { return $script:dogHappyFrames[$wagSeq[$script:actionTick % 4]] }
        if ($script:dogWagFrames.Count -eq 3) { return $script:dogWagFrames[$wagSeq[$script:actionTick % 4]] }
    }
    return $null
}

# =============================================================================
# Start
# =============================================================================
try {
    # Only one dachshund at a time (double-clicking START twice does not make two dogs).
    $script:instanceMutex = [System.Threading.Mutex]::new($false, 'Local\DachshundDesktopPet')
    $gotMutex = $false
    try { $gotMutex = $script:instanceMutex.WaitOne(0) } catch { $gotMutex = $true }
    if (-not $gotMutex) {
        $msg = '旺旺已經在桌面上了。' + "`r`n" + '如果看不到旺旺，可能是躲起來了：點右下角工作列的旺旺圖示叫牠回來。' + "`r`n" +
            '還是看不到的話，請關閉工作列上的「旺旺（臘腸狗桌寵）」視窗後再重新啟動。'
        [void][System.Windows.Forms.MessageBox]::Show($msg, '臘腸狗桌寵', 'OK', 'Information')
        exit 0
    }

    # ----- Pictures -----
    # Outfits: a folder under clothes\ with the same picture names. 'none' = no clothes.
    # id, menu name, folder, menu group ('' = straight under 換衣服)
    $script:outfitList = @(
        @('none', '不穿衣服', '', ''),
        @('blue_bear', '藍色小熊衣', 'clothes\blue_bear', 'daily'),
        @('happy_dino', 'HAPPY 恐龍衣', 'clothes\happy_dino', 'daily'),
        @('red_vest', '紅色鋪棉背心', 'clothes\red_vest', 'daily'),
        @('camo_jacket', '迷彩鋪棉外套', 'clothes\camo_jacket', 'daily'),
        @('olive_vest', '軍綠鋪棉背心', 'clothes\olive_vest', 'daily'),
        @('knit_red', '學院風針織背心（酒紅）', 'clothes\knit_red', 'daily'),
        @('knit_green', '學院風針織背心（墨綠）', 'clothes\knit_green', 'daily'),
        @('knit_grey', '學院風針織背心（淺灰）', 'clothes\knit_grey', 'daily'),
        @('knit_camel', '學院風針織背心（焦糖）', 'clothes\knit_camel', 'daily'),
        @('raincoat', '黃色小雨衣', 'clothes\raincoat', 'daily'),
        @('cny', '過年紅色唐裝', 'clothes\cny', 'holiday'),
        @('zongzi', '端午節粽子裝', 'clothes\zongzi', 'holiday'),
        @('rabbit', '中秋節小兔子裝', 'clothes\rabbit', 'holiday'),
        @('halloween', '萬聖節小巫師裝', 'clothes\halloween', 'holiday'),
        @('xmas', '聖誕老公公裝', 'clothes\xmas', 'holiday'),
        @('party', '生日派對裝', 'clothes\party', 'holiday'),
        @('bee', '小蜜蜂裝', 'clothes\bee', 'costume'),
        @('hotdog', '熱狗堡裝', 'clothes\hotdog', 'costume'),
        @('boba', '珍珠奶茶裝', 'clothes\boba', 'costume'),
        @('lion', '小獅子裝', 'clothes\lion', 'costume'),
        @('dino', '恐龍連帽裝', 'clothes\dino', 'costume')
    )
    $script:outfitId = 'none'
    $script:outfitDir = ''
    $script:outfitMenuItems = @()
    $script:dogWalkStep = 0
    Import-DogPictures

    # ----- Shared state -----
    $script:petSize = Get-Scaled 250
    $script:sizeRatio = 1.0
    $script:sizeCapped = $false
    $script:displaySize = $script:petSize
    $script:isDragging = $false
    $script:dragMoved = $false
    $script:dragStart = [System.Drawing.Point]::Empty
    $script:formStart = [System.Drawing.Point]::Empty
    $script:idleTick = 0
    $script:clockTick = 0
    $script:actionMode = 'idle'
    $script:actionTick = 0
    $script:baseLocation = [System.Drawing.Point]::Empty
    $script:rng = [System.Random]::new()
    $script:autoBarkEnabled = $true
    $script:autoBarkIntervalTicks = 417   # 25 seconds between barks
    $script:autoBarkCountdown = 417
    $script:autoBarkRandom = $false      # $true = 10 to 60 seconds at random
    $script:autoBarkSound = $false        # the automatic barking plays 旺旺's real bark only when switched on in the menu
    $script:roamEnabled = $true
    $script:roamSpeed = 3.0
    $script:gravityMode = $false      # $true = walks only on the taskbar, falls when let go
    $script:roamTarget = $null
    $script:roamPauseTicks = 60
    $script:roamMoving = $false
    $script:roamX = 0.0
    $script:roamY = 0.0
    $script:roamWalkTicks = 0
    $script:facingLeft = $false
    $script:tickErrors = 0
    $script:dogAct = ''
    $script:dogActTick = 0
    $script:dogActLen = 0
    $script:dogActPose = 'tilt_00'
    $script:dogSleeping = $false
    $script:dogSleepPose = 'sleep_00'
    $script:dogNapEnabled = $true
    $script:dogSleepYawn = 0
    $script:dogSleepPre = 0
    $script:dogNightSleep = $false
    $script:nightSleepEnabled = $true
    $script:dogHidden = $false
    $script:hiddenUntil = [DateTime]::MaxValue
    $script:trayIcon = $null
    $script:trayTextNormal = '旺旺（點一下叫牠過來）'
    $script:glassEnabled = $true
    $script:glassForm = $null
    $script:glassTick = -1
    $script:glassSize = 0
    $script:glassLeft = 0
    $script:glassTop = 0
    $script:glassCx = 0.0
    $script:glassCy = 0.0
    $script:glassCracks = @()
    $script:glassRings = @()
    $script:glassShards = @()
    $script:glassHole = $null
    $script:glassDogPath = ''
    $script:glassDogFlip = $false
    $script:glassPlayer = $null
    $script:glassBlank = $null
    $script:nextClockCheck = 0
    $script:nextScreenCheck = 0
    $script:isNight = Test-NightTime
    $script:blinkTicks = 0
    $script:blinkCountdown = 80
    $script:dogChaseMouse = $false
    $script:lastInteractTick = 0
    $script:napAfterTicks = $script:rng.Next(4000, 8000)
    $script:hovering = $false
    $script:hoverTicks = 0
    $script:hoverReactTick = -1000
    $script:bubbleTicks = 0
    $script:sizeMenuItems = @()
    # Alarm clocks (as many as wanted, remembered across restarts in %APPDATA%\DachshundPet\alarms.txt) and countdown
    $script:alarms = New-Object System.Collections.ArrayList
    $script:alarmNextId = 0
    $script:alarmMax = 20
    $script:alarmSoonest = [DateTime]::MaxValue
    $script:alarmSaveOk = $true
    $script:alarmListFile = ''
    $script:alarmMgrForm = $null
    $script:alarmMgrList = $null
    $script:alarmMgrStatus = $null
    $script:alarmMgrAdd = $null
    $script:alarmMgrTip = $null
    $script:alarmMgrRefresh = $null
    $script:alarmMgrOldRows = New-Object System.Collections.ArrayList
    $script:alarmMenuItems = New-Object System.Collections.ArrayList
    $script:alarmTimeFont = $null
    $script:alarmTrashIcon = $null
    $script:timerUntil = $null
    $script:alarmRinging = $false
    $script:alarmRingNote = ''
    $script:alarmRingUntil = [DateTime]::MinValue
    $script:alarmNextBark = [DateTime]::MinValue
    $script:barkPlayers = @{}
    $script:barkLast = $null
    $script:barkSeconds = 1.0
    $script:barkLengths = @{ 2 = 1.0; 3 = 1.6; 4 = 2.2 }   # seconds of each bark sound
    $script:alarmFile = ''
    try {
        $appData = [Environment]::GetFolderPath('ApplicationData')
        if (-not [string]::IsNullOrEmpty($appData)) {
            # alarm.txt: the one alarm of V1.13.3 and earlier (moved into alarms.txt the first time).
            $script:alarmFile = Join-Path $appData 'DachshundPet\alarm.txt'
            $script:alarmListFile = Join-Path $appData 'DachshundPet\alarms.txt'
        }
    } catch {
        $script:alarmFile = ''
        $script:alarmListFile = ''
    }
    Import-DogAlarms
    # Interactions (V1.13.0)
    $script:birthdayFile = ''
    if (-not [string]::IsNullOrEmpty($script:alarmFile)) { $script:birthdayFile = Join-Path (Split-Path -Parent $script:alarmFile) 'birthday.txt' }
    $script:birthdayMD = ''
    Import-Birthday
    $script:awayEnabled = $script:idleAvailable
    $script:awaySeen = $false
    $script:awayBubble = $false
    $script:awayCheckTick = 0
    $script:lastClickMs = 0
    $script:lastClickPat = $false
    $script:dragTrail = [System.Collections.Generic.List[object]]::new()
    $script:flingVX = 0.0
    $script:flingVY = 0.0
    $script:fallFrameOn = $false      # gravity mode: showing the falling picture (ears flying up)
    $script:bellyRubTicks = 0         # belly rub while sleeping belly up (ticks left)
    $script:trickPoked = $false       # the handshake / playing dead was ended early by a click
    $script:dogRunning = $false       # running pictures this tick
    $script:dogRunStep = 0
    $script:teaseEnabled = $true
    $script:circleEnabled = $true
    $script:circleLastX = 0
    $script:circleLastY = 0
    $script:circleDir = 0.0
    $script:circleHasDir = $false
    $script:circleTurn = 0.0
    $script:circleStill = 0
    $script:circleStartTick = 0
    $script:circleChaseUntil = 0
    $script:teaseDir = 0
    $script:teaseExt = 0.0
    $script:teaseFlips = 0
    $script:teaseFlipTick = 0
    $script:teaseReadyTick = 0
    $script:pounceFrom = [System.Drawing.Point]::Empty
    $script:pounceTo = [System.Drawing.Point]::Empty
    $script:healthMinutes = 0               # off until an interval is chosen in the menu
    $script:healthNext = [DateTime]::MaxValue
    $script:healthCount = 0
    $script:focusState = ''
    $script:focusUntil = [DateTime]::MaxValue
    $script:focusWork = 25
    $script:breakMinutes = 5
    $script:holidayEnabled = $true
    $script:holidayDate = [DateTime]::MinValue
    $script:holidayOutfit = ''
    $script:outfitBeforeHoliday = ''
    # Lunar holidays (Lunar New Year's day, Dragon Boat Festival, Mid-Autumn Festival), 2026 to 2030.
    $script:lunarNewYear = @('2026-02-17', '2027-02-06', '2028-01-26', '2029-02-13', '2030-02-03')
    $script:dragonBoat = @('2026-06-19', '2027-06-09', '2028-05-28', '2029-06-16', '2030-06-05')
    $script:midAutumn = @('2026-09-25', '2027-09-15', '2028-10-03', '2029-09-22', '2030-09-12')
    $script:hungerEnabled = $true
    $script:hungryMinutes = 120
    $script:thirstyMinutes = 90
    $script:lastFedAt = Get-Date
    $script:lastDrinkAt = Get-Date
    $script:fedWhileHungry = $false
    $script:begNextAt = Get-Date
    $script:begging = $false
    $script:begWhat = 'eat'
    $script:jerkyPath = Join-Path $PSScriptRoot 'jerky.png'
    $script:jerkyForm = $null
    $script:jerkyPic = $null
    $script:jerkySmooth = $false
    $script:jerkyBmp = $null
    $script:jerkyBmpKey = ''
    $script:jerkyFlip = $false
    $script:jerkyState = ''
    $script:jerkyTicks = 0
    $script:jerkyX = 0.0
    $script:jerkyY = 0.0
    $script:jerkyVX = 0.0
    $script:jerkyVY = 0.0
    $script:jerkyFloor = 0.0
    $script:jerkyArea = [System.Drawing.Rectangle]::new(0, 0, 800, 600)
    $script:fetchMoving = $false
    $script:bmpCache = @{}
    $script:pathKey = @{}
    $script:badPaths = @{}
    $script:currentImagePath = $null
    $script:alphaCutOk = $true
    $script:alphaCutTested = $false
    $script:warmList = [System.Collections.Generic.List[string]]::new()
    $script:warmIndex = 0
    $script:dogBitmap = $null
    $script:viewDirty = $true
    $script:bubbleText = ''
    $script:testBackground = $false
    # 12 px at 100 % (= 9 pt), scaled with the screen.
    $script:bubbleFont = $null
    $script:bubble = $null
    Update-BubbleFont

    # ----- Main window -----
    $form = $null
    if ($script:smoothAvailable) {
        try {
            $form = New-Object WangwangPet.SmoothForm
            $script:smoothMode = $true
        } catch {
            $form = $null
            $script:smoothMode = $false
            $script:smoothAvailable = $false
            $script:smoothError = $_.Exception.Message
        }
    }
    if ($null -eq $form) { $form = New-Object System.Windows.Forms.Form }
    $form.Text = $script:appTitle
    $form.FormBorderStyle = 'None'
    $form.StartPosition = 'Manual'
    $form.TopMost = $true
    $form.ShowInTaskbar = $false
    $form.BackColor = [System.Drawing.Color]::Magenta
    if (-not $script:smoothMode) { $form.TransparencyKey = [System.Drawing.Color]::Magenta }
    $form.Cursor = [System.Windows.Forms.Cursors]::Hand
    $form.Width = $script:petSize
    $form.Height = $script:petSize
    $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $startX = [Math]::Max($wa.Left, $wa.Right - $form.Width - 110)
    $startY = [Math]::Max($wa.Top, $wa.Bottom - $form.Height)
    $form.Location = [System.Drawing.Point]::new([int]$startX, [int]$startY)
    $script:baseLocation = $form.Location
    $script:form = $form

    $pic = New-Object System.Windows.Forms.PictureBox
    $pic.SizeMode = 'Zoom'
    $pic.BackColor = [System.Drawing.Color]::Transparent
    $pic.Left = 0
    $pic.Top = 0
    $pic.Width = $form.ClientSize.Width
    $pic.Height = $form.ClientSize.Height
    $pic.Cursor = [System.Windows.Forms.Cursors]::Hand
    $form.Controls.Add($pic)
    $script:pic = $pic
    if ($script:smoothMode) { $pic.Visible = $false }

    # Speech bubble: sizes itself to the text and wraps inside the pet window.
    $bubble = New-Object System.Windows.Forms.Label
    $bubble.AutoSize = $true
    $bubble.MaximumSize = [System.Drawing.Size]::new($script:petSize - 12, 0)
    $bubble.Padding = [System.Windows.Forms.Padding]::new((Get-Scaled 4), (Get-Scaled 3), (Get-Scaled 4), (Get-Scaled 3))
    $bubble.Left = Get-Scaled 6
    $bubble.Top = Get-Scaled 6
    $bubble.BackColor = [System.Drawing.Color]::White
    $bubble.ForeColor = [System.Drawing.Color]::FromArgb(20, 100, 45)
    $bubble.BorderStyle = 'FixedSingle'
    $bubble.Font = [System.Drawing.Font]::new('Microsoft JhengHei', 9, [System.Drawing.FontStyle]::Bold)
    $bubble.Text = ''
    $bubble.Visible = $false
    $form.Controls.Add($bubble)
    $bubble.BringToFront()
    $script:bubble = $bubble

    Set-DisplayImage (Get-WagFramePath 'idle' 0)
    if ($null -eq $script:pic.Image) { throw '臘腸狗圖片沒有成功載入。' }

    Update-WarmList

    # ----- Right-click menu -----
    $cms = New-Object System.Windows.Forms.ContextMenuStrip
    $script:cms = $cms
    $cms.Add_Opening({ $script:lastInteractTick = $script:clockTick })

    $miActions = New-Object System.Windows.Forms.ToolStripMenuItem('叫旺旺做動作')
    foreach ($da in @(@('歪頭', 'tilt'), @('聞聞', 'sniff'), @('甩甩頭', 'shake'), @('東張西望', 'look'), @('伸懶腰', 'bow'), @('趴一下', 'lie'), @('坐下', 'sit'), @('打哈欠', 'yawn'))) {
        $daItem = New-Object System.Windows.Forms.ToolStripMenuItem([string]$da[0])
        $daItem.Tag = [string]$da[1]
        $daItem.Add_Click({
            param($sender, $e)
            try { Start-DogAction ([string]$sender.Tag) '*' } catch { $null = Write-ErrorLog ('臘腸狗動作錯誤：' + $_.ToString()) }
        })
        [void]$miActions.DropDownItems.Add($daItem)
    }
    [void]$cms.Items.Add($miActions)
    $miTricks = New-Object System.Windows.Forms.ToolStripMenuItem('才藝表演')
    foreach ($tr in @(@('握手', 'paw'), @('轉圈', 'spin'), @('裝死（翻肚）', 'playdead'), @('坐下', 'sit'), @('趴下', 'lie'))) {
        $trItem = New-Object System.Windows.Forms.ToolStripMenuItem([string]$tr[0])
        $trItem.Tag = [string]$tr[1]
        $trItem.Add_Click({
            param($sender, $e)
            try {
                $act = [string]$sender.Tag
                if (-not (Test-DogAction $act)) { Set-Bubble '這件衣服還沒有這個才藝的圖片，換別件或脫掉衣服再試試～'; return }
                $say = '*'
                if ($act -eq 'spin') { $say = '看我轉圈圈～汪！' }
                elseif ($act -eq 'sit') { $say = '坐下！旺旺坐好了～' }
                elseif ($act -eq 'lie') { $say = '趴下！旺旺趴好了～' }
                Start-DogAction $act $say
            } catch { $null = Write-ErrorLog ('才藝表演錯誤：' + $_.ToString()) }
        })
        [void]$miTricks.DropDownItems.Add($trItem)
    }
    [void]$cms.Items.Add($miTricks)
    $miFeed = New-Object System.Windows.Forms.ToolStripMenuItem('餵點心')
    $miFeed.Add_Click({
        try {
            if ($script:dogSleeping) { Start-DogAction 'eat' '聞到點心的味道，旺旺醒來了！' } else { Start-DogAction 'eat' '*' }
        } catch { $null = Write-ErrorLog ('餵點心錯誤：' + $_.ToString()) }
    })
    [void]$cms.Items.Add($miFeed)
    $miJerky = New-Object System.Windows.Forms.ToolStripMenuItem('丟肉乾')
    $miJerky.Add_Click({
        try { Start-JerkyThrow } catch { $null = Write-ErrorLog ('丟肉乾錯誤：' + $_.ToString()); try { Hide-Jerky } catch { } }
    })
    [void]$cms.Items.Add($miJerky)
    $miWater = New-Object System.Windows.Forms.ToolStripMenuItem('餵水')
    $miWater.Add_Click({
        try {
            if (-not (Test-DogAction 'drink')) { Set-Bubble '這件衣服還沒有喝水的圖片，換別件或脫掉衣服再餵水喔～'; return }
            if ($script:dogSleeping) { Start-DogAction 'drink' '聽到倒水的聲音，旺旺醒來了！' } else { Start-DogAction 'drink' '*' }
        } catch { $null = Write-ErrorLog ('餵水錯誤：' + $_.ToString()) }
    })
    [void]$cms.Items.Add($miWater)
    $miSleep = New-Object System.Windows.Forms.ToolStripMenuItem('睡覺')
    foreach ($sl in @(@('隨便睡', ''), @('趴著睡', 'sleep_00'), @('側躺曬太陽', 'sidesleep_00'), @('翻肚睡', 'belly_00'), @('攤平曬肚子', 'flat_00'), @('縮成一團', 'curl_00'), @('窩在狗窩', 'bed_00'))) {
        $slItem = New-Object System.Windows.Forms.ToolStripMenuItem([string]$sl[0])
        $slItem.Tag = [string]$sl[1]
        $slItem.Add_Click({
            param($sender, $e)
            try { Start-DogSleep $true ([string]$sender.Tag) } catch { $null = Write-ErrorLog ('臘腸狗動作錯誤：' + $_.ToString()) }
        })
        [void]$miSleep.DropDownItems.Add($slItem)
    }
    [void]$cms.Items.Add($miSleep)
    $miWake = New-Object System.Windows.Forms.ToolStripMenuItem('叫醒旺旺')
    $miWake.Add_Click({
        try {
            if ($script:dogSleeping) { Stop-DogSleep $true } else { Set-Bubble '旺旺醒著啦！' }
        } catch { $null = Write-ErrorLog ('臘腸狗動作錯誤：' + $_.ToString()) }
    })
    [void]$cms.Items.Add($miWake)
    $miOutfit = New-Object System.Windows.Forms.ToolStripMenuItem('換衣服')
    # After each name: a small piece of that outfit's fabric, drawn where a shortcut key would be shown.
    $script:outfitSwatches = @{}
    $script:swatchGap = ([string][char]0x3000) * 4
    $script:swatchViaRenderer = $false
    # Grouped: no clothes first, then everyday clothes, holiday clothes and dress-up costumes.
    $script:outfitGroups = @(@('daily', '日常衣服'), @('holiday', '節日衣服'), @('costume', '造型扮裝'))
    $script:outfitGroupItems = @{}
    foreach ($grp in $script:outfitGroups) {
        $gi = New-Object System.Windows.Forms.ToolStripMenuItem([string]$grp[1])
        $gi.Tag = 'group'
        $script:outfitGroupItems[[string]$grp[0]] = $gi
    }
    foreach ($oi in $script:outfitList) {
        $outfitItem = New-Object System.Windows.Forms.ToolStripMenuItem([string]$oi[1])
        $outfitItem.Tag = [string]$oi[0]
        $sw = Get-SwatchImage ([string]$oi[2])
        if ($null -ne $sw) { $script:outfitSwatches[[string]$oi[0]] = $sw }
        $outfitItem.ShortcutKeyDisplayString = $script:swatchGap
        $outfitItem.ShowShortcutKeys = $true
        $outfitItem.Checked = ([string]$oi[0] -eq $script:outfitId)
        $outfitItem.Enabled = (Test-OutfitReady ([string]$oi[2]))
        $outfitItem.Add_Click({
            param($sender, $e)
            try {
                # Chosen by hand: no changing back after a holiday.
                $script:holidayOutfit = ''
                Set-DogOutfit ([string]$sender.Tag)
            } catch { $null = Write-ErrorLog ('換衣服錯誤：' + $_.ToString()) }
        })
        $outfitItem.Add_Paint({
            param($sender, $e)
            try {
                if (-not $script:swatchViaRenderer) {
                    [void](Show-OutfitSwatch $e.Graphics ([string]$sender.Tag) ($sender.Width - 24 * $script:dpiScale) ($sender.Height / 2.0) $sender.Height 0)
                }
            } catch { }
        })
        $grpId = if ($oi.Count -ge 4) { [string]$oi[3] } else { '' }
        if ($script:outfitGroupItems.ContainsKey($grpId)) {
            [void]$script:outfitGroupItems[$grpId].DropDownItems.Add($outfitItem)
        } else {
            [void]$miOutfit.DropDownItems.Add($outfitItem)
        }
        $script:outfitMenuItems += $outfitItem
    }
    foreach ($grp in $script:outfitGroups) {
        $gi = $script:outfitGroupItems[[string]$grp[0]]
        if ($gi.DropDownItems.Count -gt 0) { [void]$miOutfit.DropDownItems.Add($gi) }
    }
    Update-OutfitChecks
    # A swatch picture that arrives after start-up (OneDrive still syncing) is picked up the next time the menu opens.
    $miOutfit.Add_DropDownOpening({
        try {
            foreach ($oi in $script:outfitList) {
                $oid = [string]$oi[0]
                if (-not $script:outfitSwatches.ContainsKey($oid)) {
                    $late = Get-SwatchImage ([string]$oi[2])
                    if ($null -ne $late) { $script:outfitSwatches[$oid] = $late }
                }
            }
            foreach ($item in $script:outfitMenuItems) {
                foreach ($oi in $script:outfitList) {
                    if ([string]$oi[0] -eq [string]$item.Tag) { $item.Enabled = (Test-OutfitReady ([string]$oi[2])) }
                }
            }
        } catch { }
    })
    if ($true) {
        try {
            $swatchRenderer = New-Object System.Windows.Forms.ToolStripProfessionalRenderer
            $swatchRenderer.Add_RenderItemText({
                param($sender, $e)
                try {
                    if ([string]$e.Text -ne $script:swatchGap) { return }
                    $r = $e.TextRectangle
                    if (Show-OutfitSwatch $e.Graphics ([string]$e.Item.Tag) ($r.Right - 2) ($r.Top + $r.Height / 2.0) $e.Item.Height $r.Left) {
                        $script:swatchViaRenderer = $true
                    }
                } catch { }
            })
            # Submenus that Windows creates by itself always use the main menu's renderer, so it goes on the main menu.
            # It looks the same as the default; it only adds the swatches to the outfit names.
            $cms.Renderer = $swatchRenderer
        } catch {
            $null = Write-ErrorLog ('衣服色塊無法顯示：' + $_.ToString())
        }
    }
    [void]$cms.Items.Add($miOutfit)
    $miHide = New-Object System.Windows.Forms.ToolStripMenuItem('先躲起來（開會、分享螢幕時）')
    foreach ($hideInfo in @(@('15 分鐘', 15), @('30 分鐘', 30), @('1 小時', 60), @('直到我叫牠回來', 0))) {
        $hideItem = New-Object System.Windows.Forms.ToolStripMenuItem([string]$hideInfo[0])
        $hideItem.Tag = [int]$hideInfo[1]
        $hideItem.Add_Click({
            param($sender, $e)
            try { Hide-Dog ([int]$sender.Tag) } catch { $null = Write-ErrorLog ('躲起來錯誤：' + $_.ToString()) }
        })
        [void]$miHide.DropDownItems.Add($hideItem)
    }
    [void]$cms.Items.Add($miHide)
    $miAlarm = New-Object System.Windows.Forms.ToolStripMenuItem('鬧鐘（時間到旺旺會汪汪叫）')
    $script:miAlarmInfo = New-Object System.Windows.Forms.ToolStripMenuItem('還沒有設定鬧鐘')
    $script:miAlarmInfo.Enabled = $false
    [void]$miAlarm.DropDownItems.Add($script:miAlarmInfo)
    $script:miTimerInfo = New-Object System.Windows.Forms.ToolStripMenuItem('倒數')
    $script:miTimerInfo.Enabled = $false
    $script:miTimerInfo.Available = $false
    [void]$miAlarm.DropDownItems.Add($script:miTimerInfo)
    $script:miAlarmStop = New-Object System.Windows.Forms.ToolStripMenuItem('停止叫聲')
    $script:miAlarmStop.Available = $false
    $script:miAlarmStop.Add_Click({ try { Stop-AlarmRing '好～知道了！' } catch { $null = Write-ErrorLog ('鬧鐘錯誤：' + $_.ToString()) } })
    [void]$miAlarm.DropDownItems.Add($script:miAlarmStop)
    [void]$miAlarm.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    # Every alarm is put in here (above 新增鬧鐘) each time this menu opens: Update-AlarmMenu.
    $script:miAlarm = $miAlarm
    $script:miAlarmNew = New-Object System.Windows.Forms.ToolStripMenuItem('新增鬧鐘…')
    $script:miAlarmNew.Add_Click({
        try {
            Show-AlarmEditor $null
            Request-AlarmManagerRefresh
        } catch { Show-AlarmError '新增鬧鐘時出了問題' $_ }
    })
    [void]$miAlarm.DropDownItems.Add($script:miAlarmNew)
    # 修改鬧鐘 / 刪除鬧鐘: one entry per alarm, filled in each time this menu opens.
    $script:miAlarmEdit = New-Object System.Windows.Forms.ToolStripMenuItem('修改鬧鐘')
    [void]$miAlarm.DropDownItems.Add($script:miAlarmEdit)
    $script:miAlarmDelete = New-Object System.Windows.Forms.ToolStripMenuItem('刪除鬧鐘')
    [void]$miAlarm.DropDownItems.Add($script:miAlarmDelete)
    $miAlarmSet = New-Object System.Windows.Forms.ToolStripMenuItem('鬧鐘設定視窗（全部鬧鐘）…')
    $miAlarmSet.Add_Click({ try { Show-AlarmManager } catch { Show-AlarmError '鬧鐘設定視窗打不開' $_ } })
    [void]$miAlarm.DropDownItems.Add($miAlarmSet)
    $script:miAlarmOff = New-Object System.Windows.Forms.ToolStripMenuItem('全部關閉（設定會留著）')
    $script:miAlarmOff.Add_Click({ try { Disable-AllDogAlarms } catch { Show-AlarmError '關閉鬧鐘時出了問題' $_ } })
    [void]$miAlarm.DropDownItems.Add($script:miAlarmOff)
    [void]$miAlarm.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    foreach ($countInfo in @(@('5 分鐘後叫我', 5), @('10 分鐘後叫我', 10), @('30 分鐘後叫我', 30), @('1 小時後叫我', 60))) {
        $countItem = New-Object System.Windows.Forms.ToolStripMenuItem([string]$countInfo[0])
        $countItem.Tag = [int]$countInfo[1]
        $countItem.Add_Click({
            param($sender, $e)
            try { Start-DogCountdown ([int]$sender.Tag) } catch { $null = Write-ErrorLog ('倒數錯誤：' + $_.ToString()) }
        })
        [void]$miAlarm.DropDownItems.Add($countItem)
    }
    $script:miTimerOff = New-Object System.Windows.Forms.ToolStripMenuItem('取消倒數')
    $script:miTimerOff.Add_Click({ try { $script:timerUntil = $null; Set-Bubble '倒數取消了' } catch { } })
    [void]$miAlarm.DropDownItems.Add($script:miTimerOff)
    [void]$miAlarm.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    $miBarkTest = New-Object System.Windows.Forms.ToolStripMenuItem('聽聽旺旺的叫聲')
    $miBarkTest.Add_Click({
        try {
            if (Invoke-BarkSound) {
                Set-Bubble '汪汪！'
                if (-not $script:dogSleeping) { $script:dogAct = ''; $script:actionMode = 'happy'; $script:actionTick = 0 }
            } else {
                Set-Bubble '找不到叫聲檔案（sounds 資料夾裡的 wangwang_bark.wav）'
            }
        } catch { $null = Write-ErrorLog ('叫聲錯誤：' + $_.ToString()) }
    })
    [void]$miAlarm.DropDownItems.Add($miBarkTest)
    $miAlarm.Add_DropDownOpening({ try { Update-AlarmMenu } catch { Show-AlarmError '鬧鐘選單出了問題' $_ } })
    [void]$cms.Items.Add($miAlarm)
    $miFocus = New-Object System.Windows.Forms.ToolStripMenuItem('番茄鐘（專心時旺旺安靜陪你）')
    $script:miFocusInfo = New-Object System.Windows.Forms.ToolStripMenuItem('還沒開始')
    $script:miFocusInfo.Enabled = $false
    [void]$miFocus.DropDownItems.Add($script:miFocusInfo)
    [void]$miFocus.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    foreach ($focusInfo in @(@('專心 25 分鐘，休息 5 分鐘', 25, 5), @('專心 50 分鐘，休息 10 分鐘', 50, 10))) {
        $focusItem = New-Object System.Windows.Forms.ToolStripMenuItem([string]$focusInfo[0])
        $focusItem.Tag = @([int]$focusInfo[1], [int]$focusInfo[2])
        $focusItem.Add_Click({
            param($sender, $e)
            try { Start-FocusTimer ([int]$sender.Tag[0]) ([int]$sender.Tag[1]) } catch { $null = Write-ErrorLog ('番茄鐘錯誤：' + $_.ToString()) }
        })
        [void]$miFocus.DropDownItems.Add($focusItem)
    }
    $script:miFocusStop = New-Object System.Windows.Forms.ToolStripMenuItem('停止番茄鐘')
    $script:miFocusStop.Add_Click({ try { Stop-FocusTimer '番茄鐘停止了' } catch { $null = Write-ErrorLog ('番茄鐘錯誤：' + $_.ToString()) } })
    [void]$miFocus.DropDownItems.Add($script:miFocusStop)
    $miFocus.Add_DropDownOpening({ try { Update-FocusMenu } catch { } })
    [void]$cms.Items.Add($miFocus)
    $miHealth = New-Object System.Windows.Forms.ToolStripMenuItem('健康提醒（喝水、起來動一動）')
    foreach ($healthInfo in @(@('每 30 分鐘', 30), @('每 45 分鐘', 45), @('每 60 分鐘', 60), @('關閉', 0))) {
        $healthItem = New-Object System.Windows.Forms.ToolStripMenuItem([string]$healthInfo[0])
        $healthItem.Tag = [int]$healthInfo[1]
        $healthItem.Checked = ([int]$healthInfo[1] -eq $script:healthMinutes)
        $healthItem.Add_Click({
            param($sender, $e)
            try {
                $script:healthMinutes = [int]$sender.Tag
                foreach ($item in $sender.Owner.Items) { $item.Checked = ($item -eq $sender) }
                if ($script:healthMinutes -gt 0) {
                    $script:healthNext = (Get-Date).AddMinutes($script:healthMinutes)
                    Set-Bubble ('好！每 ' + $script:healthMinutes + ' 分鐘提醒你喝水、動一動')
                } else {
                    Set-Bubble '健康提醒關掉了'
                }
            } catch { $null = Write-ErrorLog ('健康提醒錯誤：' + $_.ToString()) }
        })
        [void]$miHealth.DropDownItems.Add($healthItem)
    }
    [void]$cms.Items.Add($miHealth)
    [void]$cms.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

    $miRoam = New-Object System.Windows.Forms.ToolStripMenuItem('自由走動（在桌面到處走）')
    $miRoam.CheckOnClick = $true
    $miRoam.Checked = $script:roamEnabled
    $miRoam.Add_Click({
        param($sender, $e)
        $script:roamEnabled = [bool]$sender.Checked
        $script:roamTarget = $null
        $script:roamPauseTicks = 0
        if ($script:roamEnabled) {
            Set-Bubble '開始走動'
        } else {
            # Chasing the mouse needs walking, so it stops as well.
            $script:dogChaseMouse = $false
            try { $script:miChase.Checked = $false } catch { }
            Set-Bubble '停下來了'
        }
    })
    [void]$cms.Items.Add($miRoam)
    $script:miRoam = $miRoam

    $miRoamSpeed = New-Object System.Windows.Forms.ToolStripMenuItem('走動速度')
    foreach ($speedInfo in @(@('慢', 1.5), @('一般', 3.0), @('快', 5.0))) {
        $speedItem = New-Object System.Windows.Forms.ToolStripMenuItem([string]$speedInfo[0])
        $speedItem.Tag = [double]$speedInfo[1]
        $speedItem.Checked = ([double]$speedInfo[1] -eq $script:roamSpeed)
        $speedItem.Add_Click({
            param($sender, $e)
            $script:roamSpeed = [double]$sender.Tag
            foreach ($item in $sender.Owner.Items) { $item.Checked = ($item -eq $sender) }
            Set-Bubble ('走動速度：' + $sender.Text)
        })
        [void]$miRoamSpeed.DropDownItems.Add($speedItem)
    }
    [void]$cms.Items.Add($miRoamSpeed)
    $miChase = New-Object System.Windows.Forms.ToolStripMenuItem('追著滑鼠跑')
    $miChase.CheckOnClick = $true
    $miChase.Checked = $script:dogChaseMouse
    $miChase.Add_Click({
        param($sender, $e)
        $script:dogChaseMouse = [bool]$sender.Checked
        $script:roamTarget = $null
        if ($script:dogChaseMouse) {
            $script:roamEnabled = $true
            $script:roamPauseTicks = 0
            try { $script:miRoam.Checked = $true } catch { }
            Set-Bubble '汪！來追你了'
        } else {
            Set-Bubble '不追了，自己逛逛'
        }
    })
    [void]$cms.Items.Add($miChase)
    $script:miChase = $miChase
    $miGravity = New-Object System.Windows.Forms.ToolStripMenuItem('重力模式（只在工作列上走，放開會掉下來）')
    $miGravity.CheckOnClick = $true
    $miGravity.Checked = $script:gravityMode
    $miGravity.Add_Click({
        param($sender, $e)
        try {
            $script:gravityMode = [bool]$sender.Checked
            $script:roamTarget = $null
            if ($script:gravityMode) {
                if ($script:dogSleeping) { Stop-DogSleep $false }
                $script:dogAct = ''
                Start-DogFling 0.0 0.0 '重力模式！旺旺回到工作列上～'
            } else {
                Set-Bubble '重力模式關了，旺旺可以到處走～'
            }
        } catch { $null = Write-ErrorLog ('重力模式錯誤：' + $_.ToString()) }
    })
    [void]$cms.Items.Add($miGravity)
    [void]$cms.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

    $miAuto = New-Object System.Windows.Forms.ToolStripMenuItem('自動汪汪叫')
    $miAuto.CheckOnClick = $true
    $miAuto.Checked = $script:autoBarkEnabled
    $miAuto.Add_Click({
        param($sender, $e)
        $script:autoBarkEnabled = [bool]$sender.Checked
        $script:autoBarkCountdown = Get-AutoBarkTicks
        if ($script:autoBarkEnabled) {
            Set-Bubble '汪！我會常常叫你'
            if ($script:autoBarkSound) { try { [void](Invoke-BarkSound $false) } catch { } }
        } else {
            Set-Bubble '好，我安靜一點'
        }
    })
    [void]$cms.Items.Add($miAuto)
    $miAutoSound = New-Object System.Windows.Forms.ToolStripMenuItem('汪汪叫時發出旺旺的叫聲')
    $miAutoSound.CheckOnClick = $true
    $miAutoSound.Checked = $script:autoBarkSound
    $miAutoSound.Add_Click({
        param($sender, $e)
        $script:autoBarkSound = [bool]$sender.Checked
        if ($script:autoBarkSound) {
            try {
                if (Invoke-BarkSound $false) { Set-Bubble '汪汪！叫的時候會有聲音' } else { Set-Bubble '找不到叫聲檔案（sounds 資料夾裡的 wangwang_bark.wav）' }
            } catch { $null = Write-ErrorLog ('叫聲錯誤：' + $_.ToString()) }
        } else {
            Set-Bubble '好，只冒泡泡、不出聲'
        }
    })
    [void]$cms.Items.Add($miAutoSound)

    $miBarkGap = New-Object System.Windows.Forms.ToolStripMenuItem('汪汪叫間隔')
    foreach ($seconds in @(15, 25, 40, 0)) {
        # 0 = at random, 10 to 60 seconds
        $gapText = '{0} 秒' -f $seconds
        if ($seconds -eq 0) { $gapText = '隨機（10～60 秒）' }
        $gapItem = New-Object System.Windows.Forms.ToolStripMenuItem($gapText)
        $gapItem.Tag = [int]$seconds
        $gapItem.Checked = ($seconds -eq 25)
        $gapItem.Add_Click({
            param($sender, $e)
            $script:autoBarkRandom = ([int]$sender.Tag -eq 0)
            if (-not $script:autoBarkRandom) { $script:autoBarkIntervalTicks = [int]([int]$sender.Tag * 1000 / 60) }
            $script:autoBarkCountdown = Get-AutoBarkTicks
            foreach ($item in $sender.Owner.Items) { $item.Checked = ($item -eq $sender) }
            if ($script:autoBarkRandom) { Set-Bubble '汪汪叫的間隔變成隨機（10～60 秒）' } else { Set-Bubble ('每 {0} 秒汪一下' -f $sender.Tag) }
        })
        [void]$miBarkGap.DropDownItems.Add($gapItem)
    }
    [void]$cms.Items.Add($miBarkGap)

    $miNap = New-Object System.Windows.Forms.ToolStripMenuItem('沒人理旺旺時會自己午睡')
    $miNap.CheckOnClick = $true
    $miNap.Checked = $script:dogNapEnabled
    $miNap.Add_Click({
        param($sender, $e)
        $script:dogNapEnabled = [bool]$sender.Checked
        $script:lastInteractTick = $script:clockTick
        if ($script:dogNapEnabled) {
            Set-Bubble '想睡就睡～'
        } elseif ($script:dogSleeping -and -not $script:dogNightSleep -and $script:dogActLen -gt 0) {
            # It is having a nap of its own right now: wake it up.
            Stop-DogSleep $true '不睡午覺了'
        } else {
            Set-Bubble '不睡午覺了'
        }
    })
    [void]$cms.Items.Add($miNap)
    $miNight = New-Object System.Windows.Forms.ToolStripMenuItem('晚上自動睡覺（晚上10點～早上7點）')
    $miNight.CheckOnClick = $true
    $miNight.Checked = $script:nightSleepEnabled
    $miNight.Add_Click({
        param($sender, $e)
        $script:nightSleepEnabled = [bool]$sender.Checked
        $script:lastInteractTick = $script:clockTick
        if ($script:nightSleepEnabled) {
            Set-Bubble '晚上會乖乖睡覺～'
        } elseif ($script:dogSleeping -and $script:dogNightSleep) {
            # It is asleep for the night right now: wake it up.
            Stop-DogSleep $true '晚上也陪你！'
        } else {
            Set-Bubble '晚上也陪你！'
        }
    })
    [void]$cms.Items.Add($miNight)
    $miPlay = New-Object System.Windows.Forms.ToolStripMenuItem('互動設定')
    foreach ($playInfo in @(@('離開電腦時等你、回來時迎接你', 'away'), @('滑鼠在牠面前左右晃會撲過來', 'tease'), @('滑鼠一直繞圈圈會跑過來追', 'circle'), @('肚子餓、口渴會來討吃的', 'hunger'), @('節日自動換衣服', 'holiday'), @('從右下角叫旺旺時，被視窗擋住會打破螢幕衝出來', 'glass'))) {
        $playItem = New-Object System.Windows.Forms.ToolStripMenuItem([string]$playInfo[0])
        $playItem.Tag = [string]$playInfo[1]
        $playItem.CheckOnClick = $true
        $playItem.Checked = $true
        if ([string]$playInfo[1] -eq 'glass' -and -not $script:glassAvailable) {
            # Needs the smooth-edge display: shown greyed out.
            $playItem.Checked = $false
            $playItem.Enabled = $false
        }
        if ([string]$playInfo[1] -eq 'away' -and -not $script:idleAvailable) {
            # This PC does not let the program read the idle time: shown greyed out.
            $playItem.Checked = $false
            $playItem.Enabled = $false
        }
        $playItem.Add_Click({
            param($sender, $e)
            try { Set-PlaySetting ([string]$sender.Tag) ([bool]$sender.Checked) } catch { $null = Write-ErrorLog ('互動設定錯誤：' + $_.ToString()) }
        })
        [void]$miPlay.DropDownItems.Add($playItem)
    }
    $miBirthday = New-Object System.Windows.Forms.ToolStripMenuItem('設定生日（當天穿生日派對裝）…')
    $miBirthday.Add_Click({ try { Show-BirthdayDialog } catch { $null = Write-ErrorLog ('生日設定錯誤：' + $_.ToString()) } })
    [void]$miPlay.DropDownItems.Add($miBirthday)
    [void]$cms.Items.Add($miPlay)
    [void]$cms.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

    $miTopMost = New-Object System.Windows.Forms.ToolStripMenuItem('永遠顯示在最上層')
    $miTopMost.CheckOnClick = $true
    $miTopMost.Checked = $true
    $miTopMost.Add_Click({
        param($sender, $e)
        $script:form.TopMost = [bool]$sender.Checked
        if ($sender.Checked) { Set-Bubble '已啟用最上層顯示' } else { Set-Bubble '已關閉最上層顯示' }
    })
    [void]$cms.Items.Add($miTopMost)

    # Sizes in the same proportion as small : normal : large (x0.72 / x1.28 per step).
    $miSize = New-Object System.Windows.Forms.ToolStripMenuItem('尺寸')
    foreach ($sizeInfo in @(@('迷你', 130), @('小', 180), @('一般', 250), @('大', 320), @('巨大', 410))) {
        $sizeItem = New-Object System.Windows.Forms.ToolStripMenuItem([string]$sizeInfo[0])
        $sizeItem.Tag = Get-Scaled ([int]$sizeInfo[1])
        $sizeItem.Checked = ([int]$sizeItem.Tag -eq $script:petSize)
        $sizeItem.Add_Click({
            param($sender, $e)
            try {
                Set-PetSize ([int]$sender.Tag)
                if ($script:sizeCapped) { Set-Bubble '螢幕放不下這麼大，旺旺變成放得下的最大尺寸了！' } else { Set-Bubble ('旺旺變成' + $sender.Text + '尺寸了！') }
            } catch { $null = Write-ErrorLog ('尺寸調整錯誤：' + $_.ToString()) }
        })
        [void]$miSize.DropDownItems.Add($sizeItem)
        $script:sizeMenuItems += $sizeItem
    }
    [void]$cms.Items.Add($miSize)
    [void]$cms.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

    $miSmooth = New-Object System.Windows.Forms.ToolStripMenuItem('平滑邊緣（建議）')
    $miSmooth.CheckOnClick = $true
    $miSmooth.Checked = $script:smoothMode
    $miSmooth.Enabled = $script:smoothAvailable
    if (-not $script:smoothAvailable) {
        if ($Classic) { $miSmooth.Text = '平滑邊緣（用一般顯示啟動）' } else { $miSmooth.Text = '平滑邊緣（這台電腦無法使用）' }
        if (-not [string]::IsNullOrEmpty($script:smoothError)) { $miSmooth.ToolTipText = [string]$script:smoothError }
    }
    $miSmooth.Add_Click({
        param($sender, $e)
        $want = [bool]$sender.Checked
        try {
            Set-ViewMode $want
            if ($want) { Set-Bubble '邊緣變平滑了～' } else { Set-Bubble '改回一般顯示' }
        } catch {
            $null = Write-ErrorLog ('切換平滑邊緣錯誤：' + $_.ToString())
            try { Set-ViewMode $false } catch { }
            $sender.Checked = $script:smoothMode
        }
    })
    [void]$cms.Items.Add($miSmooth)
    $script:miSmooth = $miSmooth

    $miDisplay = New-Object System.Windows.Forms.ToolStripMenuItem('顯示測試（不透明背景）')
    $script:miDisplay = $miDisplay
    $miDisplay.Add_Click({
        param($sender, $e)
        if ($script:smoothMode) {
            $script:testBackground = -not $script:testBackground
            if ($script:testBackground) { $sender.Text = '恢復透明背景' } else { $sender.Text = '顯示測試（不透明背景）' }
            $script:viewDirty = $true
            return
        }
        if ($script:form.TransparencyKey -eq [System.Drawing.Color]::Magenta) {
            $script:form.TransparencyKey = [System.Drawing.Color]::Empty
            $script:form.BackColor = [System.Drawing.Color]::FromArgb(235, 242, 250)
            $sender.Text = '恢復透明背景'
        } else {
            $script:form.BackColor = [System.Drawing.Color]::Magenta
            $script:form.TransparencyKey = [System.Drawing.Color]::Magenta
            $sender.Text = '顯示測試（不透明背景）'
        }
        $script:form.Refresh()
    })
    [void]$cms.Items.Add($miDisplay)
    $miClose = $cms.Items.Add('關閉旺旺')
    $miClose.Add_Click({ $script:form.Close() })
    [void]$cms.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    # About: a short description and the version number.
    $miAbout = New-Object System.Windows.Forms.ToolStripMenuItem('關於旺旺（' + $script:appVersion + '）')
    $miAbout.Add_Click({
        try {
            $nl = "`r`n"
            $outfitCount = [Math]::Max(0, $script:outfitList.Count - 1)
            $about = $script:appTitle + $nl + $nl +
                '一隻住在桌面上的黑棕色臘腸狗，照著真正的旺旺畫的：' + $nl +
                '會散步、搖尾巴、歪頭、甩甩頭、坐下、打哈欠、吃點心、喝水、睡午覺，' + $nl +
                '還有 ' + $outfitCount + ' 件衣服可以換。' + $nl + $nl +
                '‧左鍵點一下：摸摸牠（睡著時會叫醒牠）' + $nl +
                '‧左鍵拖曳：把牠抱到別的地方；拖著快速放開會把牠甩出去' + $nl +
                '‧雙擊：轉圈圈；滑鼠在牠面前快速左右晃：牠會撲過來' + $nl +
                '‧滑鼠一直繞圈圈：牠會跑過來追，追到就一起轉圈圈' + $nl +
                '‧重力模式：只在工作列上走，抓起來放開或甩出去都會掉回工作列（往下掉時耳朵會飛起來）' + $nl +
                '‧追滑鼠、走很快、討吃的和追繞圈圈的滑鼠時，會像真的旺旺一樣一蹦一蹦地跑' + $nl +
                '‧翻肚睡的時候點牠的肚子：會開心地扭來扭去（點頭才會叫醒牠）' + $nl +
                '‧右鍵「才藝表演」：握手、轉圈、裝死（翻肚）、坐下、趴下' + $nl +
                '‧右鍵：做動作、才藝表演、餵點心、餵水、睡覺、換衣服、鬧鐘、番茄鐘、健康提醒和各種設定' + $nl +
                '‧鬧鐘：可以設好幾組（只響一次或每天），時間到旺旺會用真的叫聲汪汪叫，點牠一下就停' + $nl +
                '‧自動汪汪叫會發出旺旺真的叫聲（右鍵可以關掉聲音）' + $nl +
                '‧開會或分享螢幕時：右鍵「先躲起來」，點右下角的旺旺圖示叫牠回來' + $nl +
                '‧晚上 10 點～早上 7 點會回狗窩睡覺' + $nl + $nl +
                '不連網、不安裝任何東西、不改 Windows 設定。' + $nl +
                '完整說明請看資料夾裡的「使用說明.txt」。'
            [void][System.Windows.Forms.MessageBox]::Show([System.Windows.Forms.IWin32Window]$script:form, $about, '關於旺旺',
                [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        } catch {
            $null = Write-ErrorLog ('關於視窗錯誤：' + $_.ToString())
        }
    })
    [void]$cms.Items.Add($miAbout)
    $pic.ContextMenuStrip = $cms
    $bubble.ContextMenuStrip = $cms
    $form.ContextMenuStrip = $cms

    # ----- Mouse: left-drag carries the dachshund, a left click pats it -----
    $mouseDownHandler = {
        if ($_.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
        $script:isDragging = $true
        $script:dragMoved = $false
        $script:dragStart = [System.Windows.Forms.Cursor]::Position
        $script:formStart = $script:baseLocation
        $script:lastInteractTick = $script:clockTick
        $script:dragTrail.Clear()
    }
    $mouseMoveHandler = {
        if (-not $script:isDragging) { return }
        $current = [System.Windows.Forms.Cursor]::Position
        $dx = $current.X - $script:dragStart.X
        $dy = $current.Y - $script:dragStart.Y
        if ((-not $script:dragMoved) -and ([Math]::Abs($dx) + [Math]::Abs($dy)) -lt 8) { return }
        if (-not $script:dragMoved) {
            # Picked up: wakes up, stops what it was doing and paddles its legs.
            $script:dogSleeping = $false
            $script:bellyRubTicks = 0
            $script:dogNightSleep = $false
            $script:dogAct = ''
            Set-Bubble '汪！放旺旺下來～'
        }
        $script:dragMoved = $true
        # The last moments of the drag (to know how fast it is let go).
        $nowMs = [Environment]::TickCount
        $script:dragTrail.Add(@($nowMs, [int]$current.X, [int]$current.Y))
        while ($script:dragTrail.Count -gt 2 -and ($nowMs - [int]$script:dragTrail[0][0]) -gt 120) { $script:dragTrail.RemoveAt(0) }
        $script:baseLocation = [System.Drawing.Point]::new([int]($script:formStart.X + $dx), [int]($script:formStart.Y + $dy))
        $script:form.Location = $script:baseLocation
    }
    $mouseUpHandler = {
        if ($_.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
        $wasDragging = $script:isDragging
        $moved = $script:dragMoved
        $script:isDragging = $false
        $script:dragMoved = $false
        if (-not $wasDragging) { return }
        # A click (or picking it up) while the alarm is barking stops the alarm.
        $stoppedAlarm = $false
        if ($script:alarmRinging) {
            try { Stop-AlarmRing '' } catch { }
            $stoppedAlarm = $true
        }
        $wasPat = $script:lastClickPat
        $script:lastClickPat = $false
        if ($moved) {
            $script:roamTarget = $null
            # Let go while still moving fast: the dachshund is thrown and slides on.
            $vx = 0.0
            $vy = 0.0
            try {
                if ($script:dragTrail.Count -ge 2) {
                    $first = $script:dragTrail[0]
                    $last = $script:dragTrail[$script:dragTrail.Count - 1]
                    $spanMs = [double]([int]$last[0] - [int]$first[0])
                    $ageMs = [double]([Environment]::TickCount - [int]$last[0])
                    if ($spanMs -ge 15 -and $ageMs -lt 120) {
                        $vx = ([double]$last[1] - [double]$first[1]) / $spanMs * 60.0
                        $vy = ([double]$last[2] - [double]$first[2]) / $spanMs * 60.0
                    }
                }
            } catch { }
            if ([Math]::Sqrt($vx * $vx + $vy * $vy) -gt (Get-Scaled 28)) {
                try { Start-DogFling $vx $vy } catch { }
                return
            }
            if ($script:gravityMode) {
                # Gravity mode: let go above the taskbar = falls back down.
                try {
                    $gb = Get-GroundBounds
                    if (($gb[3] - $script:baseLocation.Y) -gt 6 -or ($script:baseLocation.Y - $gb[3]) -gt 6) {
                        Start-DogFling ($vx * 0.5) 0.0 '咻～'
                        return
                    }
                } catch { }
            }
            # Put down: shakes itself, rests about 6 seconds, then walks again.
            $script:roamPauseTicks = 100
            try { Start-DogAction 'shake' '甩甩～' } catch { }
            return
        }
        if ($stoppedAlarm) {
            $script:dogAct = ''
            $script:actionMode = 'happy'
            $script:actionTick = 0
            Set-Bubble '好～知道了！汪！'
            return
        }
        if ($script:dogSleeping) {
            # Sleeping belly up: a click on the belly is a belly rub (it wriggles happily and sleeps on).
            # A click anywhere else (or in another sleeping pose) wakes it up.
            $rub = $false
            try { $rub = Test-BellyRubClick } catch { $rub = $false }
            if ($rub) {
                try { Start-BellyRub } catch { }
                return
            }
            try { Stop-DogSleep $true } catch { }
            return
        }
        if ($script:dogAct -eq 'jerky' -or $script:dogAct -eq 'fetch') {
            # Going for the jerky or eating it: a click does not stop it.
            if ($script:dogAct -eq 'jerky') { Set-Bubble '吃肉乾中～等我吃完！' } else { Set-Bubble '等等～我要去吃肉乾！' }
            return
        }
        if ($script:dogAct -eq 'eat' -or $script:dogAct -eq 'drink') {
            # Eating or drinking: a click does not take the bowl away halfway.
            if ($script:dogAct -eq 'eat') { Set-Bubble '吃點心中～等我吃完！' } else { Set-Bubble '喝水中～咕嚕咕嚕' }
            return
        }
        if ($script:dogAct -eq 'paw' -and $script:dogActTick -ge 8 -and $script:dogActTick -lt 50) {
            # Holding out its paw: a click shakes it.
            $script:dogActTick = 50
            $script:trickPoked = $true
            Set-Bubble '握到了！好朋友～汪！'
            return
        }
        if ($script:dogAct -eq 'playdead' -and $script:dogActTick -lt 84) {
            # Playing dead: a poke and it gives up and jumps up.
            $script:dogActTick = 84
            $script:trickPoked = $true
            Set-Bubble '被你發現了～嘿嘿！'
            return
        }
        # Two quick clicks (a double-click): 旺旺 spins round.
        $nowMs = [Environment]::TickCount
        $sinceMs = $nowMs - $script:lastClickMs
        $script:lastClickMs = $nowMs
        if ($wasPat -and $sinceMs -ge 0 -and $sinceMs -le [System.Windows.Forms.SystemInformation]::DoubleClickTime) {
            try { Start-DogAction 'spin' '轉圈圈～汪！' } catch { }
            return
        }
        $script:lastClickPat = $true
        # A click is a pat: a happy hop and a fast tail wag.
        $script:dogAct = ''
        $script:actionMode = 'happy'
        $script:actionTick = 0
        $patLines = @('汪！', '旺旺最乖～', '嘿嘿～', '再摸一下～')
        Set-Bubble $patLines[$script:rng.Next(0, $patLines.Count)]
    }
    $pic.Add_MouseDown($mouseDownHandler)
    $pic.Add_MouseMove($mouseMoveHandler)
    $pic.Add_MouseUp($mouseUpHandler)
    $bubble.Add_MouseDown($mouseDownHandler)
    $bubble.Add_MouseMove($mouseMoveHandler)
    $bubble.Add_MouseUp($mouseUpHandler)
    $form.Add_MouseDown($mouseDownHandler)
    $form.Add_MouseMove($mouseMoveHandler)
    $form.Add_MouseUp($mouseUpHandler)
    # The dachshund notices the mouse pointer; resting the pointer on it = petting.
    $enterHandler = {
        $script:hovering = $true
        $script:hoverTicks = 0
        $script:lastInteractTick = $script:clockTick
        try { Invoke-DogHover } catch { $null = Write-ErrorLog ('臘腸狗互動錯誤：' + $_.ToString()) }
    }
    $leaveHandler = {
        $script:hovering = $false
        $script:hoverTicks = 0
    }
    $pic.Add_MouseEnter($enterHandler)
    $pic.Add_MouseLeave($leaveHandler)
    $form.Add_MouseEnter($enterHandler)
    $form.Add_MouseLeave($leaveHandler)

    # ----- Animation (every 60 ms) -----
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 60
    $script:timer = $timer
    $timer.Add_Tick({
        try {
            # Alarm clock and countdown (also while hidden: the dachshund comes back to bark).
            # Kept apart, so a problem with the alarm can never stop the dachshund itself.
            try { Update-DogAlarms } catch { $null = Write-ErrorLog ('鬧鐘錯誤：' + $_.ToString()) }
            # Hidden (meeting): only check whether it is time to come back.
            if ($script:dogHidden) {
                if ((Get-Date) -ge $script:hiddenUntil) { Show-Dog '我回來了！旺旺躲好久喔～' }
                return
            }
            # A tick is 60 ms; in power-saving mode one 240 ms tick counts as 4.
            $step = [Math]::Max(1, [int][Math]::Round($script:timer.Interval / 60.0))
            $script:idleTick += $step
            $script:clockTick += $step
            if ($script:bubbleTicks -gt 0) {
                $script:bubbleTicks -= $step
                if ($script:bubbleTicks -le 0) {
                    $script:bubble.Visible = $false
                    $script:viewDirty = $true
                }
            }
            $menuOpen = [bool]$script:cms.Visible

            # 1) Standing: gentle breathing, and a blink every few seconds
            $xOffset = 0
            $yOffset = [int]([Math]::Sin($script:idleTick / 7.0) * 1.5)
            if ($script:blinkTicks -gt 0) {
                $script:blinkTicks--
            } else {
                $script:blinkCountdown--
                if ($script:blinkCountdown -le 0) {
                    $script:blinkTicks = 3
                    $script:blinkCountdown = $script:rng.Next(50, 120)
                }
            }
            # Night or day? (checked every 3 seconds); wake up at 7:00 after a night's sleep
            if ($script:clockTick -ge $script:nextClockCheck) {
                $script:nextClockCheck = $script:clockTick + 50
                $script:isNight = Test-NightTime
                if ($script:dogNightSleep -and $script:dogSleeping -and -not $script:isNight) { Stop-DogSleep $true '早安！旺旺睡飽了～' }
                # Holiday clothes, focus timer, health reminders, hunger (each kept apart: one problem cannot stop the rest).
                try { if ((Get-Date).Date -ne $script:holidayDate) { Update-HolidayOutfit } } catch { $null = Write-ErrorLog ('節日換衣服錯誤：' + $_.ToString()) }
                try { Update-FocusTimer } catch { $null = Write-ErrorLog ('番茄鐘錯誤：' + $_.ToString()) }
                try { if ($script:healthMinutes -gt 0 -and (Get-Date) -ge $script:healthNext) { Invoke-HealthReminder } } catch { $null = Write-ErrorLog ('健康提醒錯誤：' + $_.ToString()) }
                try { if ($script:hungerEnabled) { Update-DogHunger } } catch { $null = Write-ErrorLog ('肚子餓錯誤：' + $_.ToString()) }
            }
            # 1b) Away and back (only the time since the last key press or mouse move is read, never what was typed)
            if ($script:awayEnabled -and $script:idleAvailable -and $script:clockTick -ge $script:awayCheckTick) {
                $script:awayCheckTick = $script:clockTick + 10
                try {
                    Update-DogAway $menuOpen
                } catch {
                    $script:idleAvailable = $false
                    $null = Write-ErrorLog ('離開偵測錯誤，已停用：' + $_.ToString())
                }
            }

            # 2) Happy hop (after a pat or a bark)
            if ($script:actionMode -ne 'idle') {
                $script:actionTick++
                $xOffset = [int]([Math]::Sin($script:actionTick / 1.0) * 4)
                $yOffset = [int]([Math]::Abs([Math]::Sin($script:actionTick / 1.1)) * -16)
                if ($script:actionTick -gt 24) { $script:actionMode = 'idle'; $script:actionTick = 0 }
            }

            # 2b) The thrown jerky (flying, or lying on the desktop)
            if ($script:jerkyState -ne '') {
                try { Update-Jerky $menuOpen } catch { $null = Write-ErrorLog ('肉乾錯誤：' + $_.ToString()); Hide-Jerky }
            }

            # 2c) Breaking out of the screen (glass layer)
            if ($script:glassTick -ge 0) {
                try {
                    Update-GlassFx
                } catch {
                    $null = Write-ErrorLog ('衝出來效果錯誤：' + $_.ToString())
                    Hide-GlassFx
                }
            }

            # 3) Actions: tilting, sniffing, shaking, lying, sleeping, petting
            # A pat or a bark takes over from a small action (not from sleeping or petting).
            if ($script:dogAct -ne '' -and $script:dogAct -ne 'sleep' -and $script:dogAct -ne 'pet' -and $script:actionMode -ne 'idle') { $script:dogAct = '' }
            if ($script:dogAct -ne '') {
                $script:dogActTick++
                $t = $script:dogActTick
                switch ($script:dogAct) {
                    'shake' {
                        # Only the head moves.
                        $xOffset = 0
                        $yOffset = 0
                    }
                    'sleep' {
                        $pre = $t - $script:dogSleepPre
                        if ($pre -lt 0 -and $t -ge $script:dogSleepYawn) {
                            # Turning around before lying down: steps on the spot, facing one way, then the other.
                            $c = $t - $script:dogSleepYawn
                            if (($c % 8) -eq 0) { $script:facingLeft = -not $script:facingLeft }
                            $xOffset = [int]([Math]::Sin($c / 3.2) * 2)
                            $yOffset = @(-2, 0, -2, -2, 0, -2)[$t % 6]
                        } elseif ($script:bellyRubTicks -gt 0) {
                            # Belly rub: wriggles from side to side, then sleeps on.
                            $script:bellyRubTicks--
                            $xOffset = [int]([Math]::Sin($script:bellyRubTicks / 1.4) * 4)
                            $yOffset = [int]([Math]::Abs([Math]::Sin($script:bellyRubTicks / 2.2)) * -3)
                            if ($script:bellyRubTicks -eq 0) { Set-Bubble '呼～好舒服… Zzz' }
                        } else {
                            # Slow breathing, and a Zzz now and then.
                            $xOffset = 0
                            $yOffset = [int][Math]::Round([Math]::Sin($script:clockTick / 14.0) * 1.2)
                            if ($pre -ge 0 -and ($pre % 180) -eq 40) { Set-Bubble 'Zzz…' }
                            if ($pre -ge 0 -and ($pre % 180) -eq 130) { Set-Bubble '旺旺睡得好香… Zzz' }
                        }
                    }
                    'sit' {
                        $xOffset = 0
                        $yOffset = [int][Math]::Round([Math]::Sin($script:clockTick / 12.0))
                    }
                    'lie' {
                        $xOffset = 0
                        $yOffset = [int][Math]::Round([Math]::Sin($script:clockTick / 12.0))
                    }
                    'pet' {
                        $xOffset = 0
                        $yOffset = [int]([Math]::Abs([Math]::Sin($t / 1.3)) * -6)
                    }
                    'eat' {
                        $xOffset = 0
                        $yOffset = 0
                        if ($t -ge 72) { $yOffset = [int]([Math]::Abs([Math]::Sin($t / 1.3)) * -6) }
                        if ($t -eq 72) {
                            $yum = @('好好吃！謝謝～', '吃飽飽了～汪！', '還有嗎？再一個～')
                            if ($script:fedWhileHungry) { $yum = @('終於吃到了！最愛你了～♥', '好好吃！肚子不餓了～♥') }
                            Set-Bubble ([string]$yum[$script:rng.Next(0, $yum.Count)])
                        }
                    }
                    'fetch' {
                        $xOffset = 0
                        $yOffset = 0
                        $script:fetchMoving = $false
                        if ($script:jerkyState -eq 'fly') {
                            # Watching the jerky fly.
                            $jcx = $script:jerkyX + 20.0
                            $script:facingLeft = ($jcx -lt ($script:baseLocation.X + $script:form.Width / 2.0))
                        } elseif ($script:jerkyState -eq 'land') {
                            if (-not $script:isDragging) {
                                $tg = Get-FetchTarget
                                $fdx = [double]$tg[0] - $script:baseLocation.X
                                $fdy = [double]$tg[1] - $script:baseLocation.Y
                                $fdist = [Math]::Sqrt($fdx * $fdx + $fdy * $fdy)
                                $fstep = [Math]::Max($script:roamSpeed, 5.0) * 1.4 * $script:dpiScale * $script:sizeRatio
                                if ($fdist -le $fstep) {
                                    # Got there: eats it (the jerky in the picture takes the place of the real one).
                                    $script:baseLocation = [System.Drawing.Point]::new([int][Math]::Round([double]$tg[0]), [int][Math]::Round([double]$tg[1]))
                                    $script:roamX = [double]$script:baseLocation.X
                                    $script:roamY = [double]$script:baseLocation.Y
                                    $script:facingLeft = [bool]$tg[2]
                                    Hide-Jerky
                                    Start-DogAction 'jerky' '*'
                                    $script:roamPauseTicks = 60
                                    $t = 0
                                } else {
                                    if ([Math]::Abs($fdx) -gt 2) { $script:facingLeft = ($fdx -lt 0) }
                                    $nx = $script:baseLocation.X + $fdx / $fdist * $fstep
                                    $ny = $script:baseLocation.Y + $fdy / $fdist * $fstep
                                    $script:baseLocation = [System.Drawing.Point]::new([int][Math]::Round($nx), [int][Math]::Round($ny))
                                    $script:fetchMoving = $true
                                    # Short legs: bounds along in little hops.
                                    if (Test-RunFrames) { $yOffset = @(0, -7, -12, -5)[[int]($script:idleTick % 4)] } else { $yOffset = @(-6, 0, -6, -6, 0, -6)[$script:clockTick % 6] }
                                }
                            }
                        } else {
                            # The jerky is gone.
                            $script:dogAct = ''
                        }
                    }
                    'jerky' {
                        $xOffset = 0
                        $yOffset = 0
                        if ($t -ge 14 -and $t -lt 62) { $yOffset = @(0, -1, -2, -1)[[int]([Math]::Floor($t / 2)) % 4] }
                        if ($t -ge 62) { $yOffset = [int]([Math]::Abs([Math]::Sin($t / 1.3)) * -6) }
                        if ($t -eq 14) { Set-Bubble '嚼嚼嚼～' }
                        if ($t -eq 62) {
                            $yumJ = @('肉乾好好吃！謝謝～', '還有嗎？再丟一片～', '最喜歡肉乾了！汪！')
                            if ($script:fedWhileHungry) { $yumJ = @('終於吃到了！最愛你了～♥', '肉乾好好吃！肚子不餓了～♥') }
                            Set-Bubble ([string]$yumJ[$script:rng.Next(0, $yumJ.Count)])
                        }
                    }
                    'burst' {
                        $xOffset = 0
                        $yOffset = 0
                        # The glass layer is gone early (an error, hidden ...): shows up straight away.
                        if ($t -lt 11 -and $script:glassTick -lt 0) { $script:dogActTick = 11; $t = 11 }
                        if ($t -ge 11) { $yOffset = [int]([Math]::Abs([Math]::Sin($t / 1.3)) * -6) }
                        if ($t -eq 11) {
                            # Landed: in front of the broken glass from now on.
                            $keepDogTop = [bool]$script:form.TopMost
                            $script:form.TopMost = -not $keepDogTop
                            $script:form.TopMost = $true
                            $script:form.TopMost = $keepDogTop
                            $outLines = @('汪！我衝出來了！', '哈囉～我從螢幕裡跑出來了！', '找我嗎？我在這！汪汪！')
                            Set-Bubble ([string]$outLines[$script:rng.Next(0, $outLines.Count)])
                        }
                    }
                    'drink' {
                        $xOffset = 0
                        $yOffset = 0
                        if ($t -ge 50) { $yOffset = [int]([Math]::Abs([Math]::Sin($t / 1.3)) * -6) }
                        if ($t -eq 50) {
                            $ahh = @('喝飽了～哈～', '好好喝！謝謝～', '咕嚕～喝飽飽了！')
                            if ($script:fedWhileHungry) { $ahh = @('終於喝到水了！最愛你了～♥', '咕嚕咕嚕～不渴了！謝謝～♥') }
                            Set-Bubble ([string]$ahh[$script:rng.Next(0, $ahh.Count)])
                        }
                    }
                    'paw' {
                        $xOffset = 0
                        $yOffset = [int][Math]::Round([Math]::Sin($script:clockTick / 12.0))
                        if ($t -ge 56) { $yOffset = [int]([Math]::Abs([Math]::Sin($t / 1.3)) * -6) }
                        if ($t -eq 56 -and -not $script:trickPoked) {
                            $pawLines = @('好朋友！汪！', '握到手了～開心！', '嘿嘿～有點心嗎？')
                            Set-Bubble ([string]$pawLines[$script:rng.Next(0, $pawLines.Count)])
                        }
                    }
                    'playdead' {
                        $xOffset = 0
                        $yOffset = 0
                        if ($t -ge 94) { $yOffset = [int]([Math]::Abs([Math]::Sin($t / 1.3)) * -6) }
                        if ($t -eq 50) { Set-Bubble '……（偷看）' }
                        if ($t -eq 94 -and -not $script:trickPoked) {
                            $deadLines = @('嘿嘿～騙到你了吧！', '旺旺復活了！汪！', '裝死成功～有點心嗎？')
                            Set-Bubble ([string]$deadLines[$script:rng.Next(0, $deadLines.Count)])
                        }
                    }
                    'spin' {
                        if (($t % 6) -eq 0) { $script:facingLeft = -not $script:facingLeft }
                        $xOffset = [int]([Math]::Sin($t / 3.0) * 3)
                        $yOffset = @(-3, 0, -3, -3, 0, -3)[$t % 6]
                    }
                    'fling' {
                        $xOffset = 0
                        $yOffset = 0
                        if ($script:gravityMode) {
                            # Gravity mode: flies, falls, bounces once on the taskbar and slides to a stop.
                            $gb = Get-GroundBounds
                            $script:flingVY = [Math]::Min($script:flingVY + 4.5 * $script:dpiScale, 60.0 * $script:dpiScale)
                            $script:flingVX = $script:flingVX * 0.99
                            $nx = [double]$script:baseLocation.X + $script:flingVX
                            $ny = [double]$script:baseLocation.Y + $script:flingVY
                            if ($nx -lt $gb[0]) { $nx = [double]$gb[0]; $script:flingVX = -$script:flingVX * 0.5 }
                            if ($nx -gt $gb[1]) { $nx = [double]$gb[1]; $script:flingVX = -$script:flingVX * 0.5 }
                            if ($ny -lt $gb[2]) { $ny = [double]$gb[2]; if ($script:flingVY -lt 0) { $script:flingVY = 0.0 } }
                            $landed = $false
                            if ($ny -ge $gb[3]) {
                                $ny = [double]$gb[3]
                                if ($script:flingVY -gt (12.0 * $script:dpiScale)) {
                                    # A hard landing: one small bounce.
                                    $script:flingVY = -$script:flingVY * 0.3
                                    $script:flingVX = $script:flingVX * 0.8
                                } else {
                                    # On the ground: slides to a stop.
                                    $script:flingVY = 0.0
                                    $script:flingVX = $script:flingVX * 0.8
                                    if ([Math]::Abs($script:flingVX) -lt 1.0) { $landed = $true }
                                }
                            }
                            $script:baseLocation = [System.Drawing.Point]::new([int][Math]::Round($nx), [int][Math]::Round($ny))
                            # The falling picture (ears flying up): switched on a moment after the highest point, once it is
                            # clearly coming down, and kept until it touches the taskbar (also after the bounce).
                            if ($ny -ge $gb[3]) {
                                $script:fallFrameOn = $false
                            } elseif ($script:fallFrameOn) {
                                if ($script:flingVY -lt 0) { $script:fallFrameOn = $false }
                            } elseif ($script:flingVY -gt (3.0 * $script:dpiScale) -and ([double]$gb[3] - $ny) -gt ([double]$script:form.Height * 0.05)) {
                                $script:fallFrameOn = $true
                            }
                            if ($landed -or $t -gt 250) {
                                $landSay = '甩甩～'
                                if ($t -gt 12) { $landSay = '嚇我一跳～甩甩～' }
                                Start-DogAction 'shake' $landSay
                                $script:roamPauseTicks = 100
                                $t = 0
                            }
                        } else {
                        # Thrown: slides on, slows down, bounces back from the edge of the screen.
                        $b = Get-RoamBounds
                        $nx = [double]$script:baseLocation.X + $script:flingVX
                        $ny = [double]$script:baseLocation.Y + $script:flingVY
                        if ($nx -lt $b[0]) { $nx = [double]$b[0]; $script:flingVX = -$script:flingVX * 0.5 }
                        if ($nx -gt $b[1]) { $nx = [double]$b[1]; $script:flingVX = -$script:flingVX * 0.5 }
                        if ($ny -lt $b[2]) { $ny = [double]$b[2]; $script:flingVY = -$script:flingVY * 0.5 }
                        if ($ny -gt $b[3]) { $ny = [double]$b[3]; $script:flingVY = -$script:flingVY * 0.5 }
                        $script:baseLocation = [System.Drawing.Point]::new([int][Math]::Round($nx), [int][Math]::Round($ny))
                        $script:flingVX = $script:flingVX * 0.86
                        $script:flingVY = $script:flingVY * 0.86
                        if (([Math]::Abs($script:flingVX) + [Math]::Abs($script:flingVY)) -lt 1.5 -or $t -gt 120) {
                            # Landed: a shake and a short rest.
                            Start-DogAction 'shake' '嚇我一跳～甩甩～'
                            $script:roamPauseTicks = 100
                            $t = 0
                        }
                        }
                    }
                    'tease' {
                        $xOffset = 0
                        $yOffset = 0
                        if ($t -lt 24) {
                            # Watching the pointer: turns towards it.
                            $cur = [System.Windows.Forms.Cursor]::Position
                            $script:facingLeft = ($cur.X -lt ($script:baseLocation.X + $script:form.Width / 2))
                        } elseif ($t -eq 40) {
                            Set-DogPounceTarget
                        } elseif ($t -gt 40 -and $t -le 52) {
                            # The pounce: an arc towards the pointer.
                            $p = ($t - 40) / 12.0
                            $nx = $script:pounceFrom.X + ($script:pounceTo.X - $script:pounceFrom.X) * $p
                            $ny = $script:pounceFrom.Y + ($script:pounceTo.Y - $script:pounceFrom.Y) * $p
                            $script:baseLocation = [System.Drawing.Point]::new([int][Math]::Round($nx), [int][Math]::Round($ny))
                            $yOffset = [int](-[Math]::Sin([Math]::PI * $p) * 26)
                        } elseif ($t -gt 52) {
                            $yOffset = [int]([Math]::Abs([Math]::Sin($t / 1.3)) * -6)
                            if ($t -eq 53) { Set-Bubble '抓到了！汪！' }
                        }
                    }
                    'wait' {
                        $xOffset = 0
                        $yOffset = [int][Math]::Round([Math]::Sin($script:clockTick / 12.0))
                        if ($script:nightSleepEnabled -and $script:isNight) {
                            # Waiting until it is night: off to bed.
                            Start-DogSleep $false '' $true
                            $t = 0
                        } elseif ($t -ge 10000 -and $script:dogNapEnabled) {
                            # Waited 10 minutes: falls asleep while waiting.
                            Start-DogSleep $false
                            $t = 0
                        } elseif (($t % 500) -eq 250) {
                            Set-Bubble '旺旺在這裡等你回來～'
                        }
                    }
                    'focus' {
                        $xOffset = 0
                        $yOffset = [int][Math]::Round([Math]::Sin($script:clockTick / 12.0))
                    }
                    'look' {
                        if ($t -eq 22 -and $script:rng.Next(0, 2) -eq 0) { $script:facingLeft = -not $script:facingLeft }
                    }
                    default {
                        $xOffset = 0
                        $yOffset = 0
                    }
                }
                if ($script:dogActLen -gt 0 -and $t -ge $script:dogActLen) {
                    if ($script:dogAct -eq 'sleep') {
                        Stop-DogSleep $true
                    } else {
                        if ($script:dogAct -eq 'spin') {
                            # Dizzy but happy after spinning round.
                            $script:actionMode = 'happy'
                            $script:actionTick = 0
                        }
                        if ($script:dogAct -eq 'tease') { $script:teaseReadyTick = $script:clockTick + 160 }
                        $script:dogAct = ''
                    }
                }
            } elseif (-not $script:isDragging -and -not $menuOpen -and -not $script:roamMoving -and $script:actionMode -eq 'idle') {
                $idleFor = $script:clockTick - $script:lastInteractTick
                if ($script:focusState -eq 'focus') {
                    # Focus period: back to lying quietly.
                    Start-DogRest 'focus' ''
                } elseif ($script:nightSleepEnabled -and $script:isNight -and $idleFor -gt 1000) {
                    # Night: about a minute without anyone around and it goes to bed until 7:00.
                    Start-DogSleep $false '' $true
                } elseif ($script:dogNapEnabled -and $idleFor -gt $script:napAfterTicks) {
                    Start-DogSleep $false
                } elseif ($script:rng.Next(0, 110) -eq 0) {
                    Start-RandomDogAction
                }
            }
            if ($script:hovering -and -not $script:isDragging -and -not $menuOpen) {
                $script:hoverTicks++
                if ($script:hoverTicks -eq 25 -and -not $script:dogSleeping -and $script:dogAct -ne 'eat' -and $script:dogAct -ne 'drink' -and $script:dogAct -ne 'fling' -and $script:dogAct -ne 'tease' -and $script:dogAct -ne 'fetch' -and $script:dogAct -ne 'jerky' -and -not $script:alarmRinging) { Start-DogAction 'pet' '*' }
            }
            # 3b) Teasing: the mouse pointer swinging quickly left and right in front of the dachshund
            if ($script:teaseEnabled -and -not $script:isDragging -and -not $menuOpen) {
                try { Update-DogTease } catch { $null = Write-ErrorLog ('逗旺旺錯誤：' + $_.ToString()) }
            }
            # 3c) The mouse pointer going round and round: 旺旺 runs over to it
            if ($script:circleEnabled -and -not $script:isDragging -and -not $menuOpen) {
                try { Update-DogCircle } catch { $null = Write-ErrorLog ('追繞圈錯誤：' + $_.ToString()) }
            }

            # 4) Barking now and then (paused while dragging, in the menu, or during an action)
            $quietNight = $script:nightSleepEnabled -and $script:isNight
            if ($script:autoBarkEnabled -and -not $quietNight -and -not $script:isDragging -and -not $menuOpen -and -not $script:alarmRinging -and $script:focusState -ne 'focus' -and $script:actionMode -eq 'idle' -and $script:dogAct -eq '') {
                $script:autoBarkCountdown--
                if ($script:autoBarkCountdown -le 0) {
                    $script:autoBarkCountdown = Get-AutoBarkTicks
                    Set-Bubble ($script:dogLines[$script:rng.Next(0, $script:dogLines.Count)])
                    $script:actionMode = 'happy'
                    $script:actionTick = 0
                    # 旺旺's real bark (can be switched off in the menu; nothing is played without the sound file).
                    if ($script:autoBarkSound) {
                        try { [void](Invoke-BarkSound $false) } catch { $null = Write-ErrorLog ('叫聲錯誤：' + $_.ToString()) }
                    }
                }
            }

            # 4b) Gravity mode: not standing on the taskbar (just switched on, another screen ...) = falls down.
            if ($script:gravityMode -and -not $script:isDragging -and $script:dogAct -ne 'fling' -and $script:dogAct -ne 'tease' -and -not $script:dogSleeping) {
                try {
                    $gb = Get-GroundBounds
                    if ([Math]::Abs($script:baseLocation.Y - $gb[3]) -gt 2) { Start-DogFling 0.0 0.0 '' }
                } catch { $null = Write-ErrorLog ('重力模式錯誤：' + $_.ToString()) }
            }

            # 5) Free roaming (not during an action)
            if ($script:roamEnabled -and -not $script:isDragging -and -not $menuOpen -and $script:dogAct -eq '' -and $script:focusState -ne 'focus') {
                try {
                    Step-Roam
                } catch {
                    $script:roamEnabled = $false
                    $script:roamMoving = $false
                    $script:dogChaseMouse = $false
                    try { $script:miRoam.Checked = $false } catch { }
                    try { $script:miChase.Checked = $false } catch { }
                    $null = Write-ErrorLog ('走動功能錯誤，已自動停止走動：' + $_.ToString())
                }
            } else {
                $script:roamMoving = $false
            }
            $script:dogRunning = $false
            if ($script:roamMoving) {
                $runningAfter = ($script:clockTick -lt $script:circleChaseUntil)
                $wantRun = ([bool]$script:dogChaseMouse -or $script:roamSpeed -ge 5.0 -or $runningAfter -or [bool]$script:begging)
                if ($wantRun -and (Test-RunFrames)) {
                    # Running like the real 旺旺 (chasing the pointer, walking fast, coming over to ask for food or
                    # water, running after the circling pointer): short legs, so it bounds along in little hops -
                    # crouched with the legs gathered (run_00) on landing, then a hop with the short legs out (run_01).
                    $script:dogRunning = $true
                    $runPhase = [int]($script:idleTick % 4)
                    $script:dogRunStep = if ($runPhase -eq 1 -or $runPhase -eq 2) { 1 } else { 0 }
                    $yOffset += @(0, -7, -12, -5)[$runPhase]
                } elseif ($script:dogWalkFrames.Count -eq 4) {
                    # The legs do the walking; a faster walking speed means quicker steps.
                    $walkHold = [Math]::Max(1, [int][Math]::Round(6.0 / $script:roamSpeed))
                    $runningAfter = ($script:clockTick -lt $script:circleChaseUntil)
                    if ($runningAfter) { $walkHold = 1 }
                    $script:dogWalkStep = [int]([Math]::Floor($script:idleTick / $walkHold) % 6)
                    if ($script:dogChaseMouse -or $script:roamSpeed -ge 5.0 -or $runningAfter) {
                        # Running (chasing the mouse, or walking fast): a bounce on every stride, like the real 旺旺.
                        $runBob = @(-6, 0, -6, -6, 0, -6)
                        $yOffset += $runBob[$script:dogWalkStep]
                    } else {
                        $walkBob = @(-2, 0, -2, -2, 0, -2)
                        $yOffset += $walkBob[$script:dogWalkStep]
                    }
                } else {
                    $yOffset += [int]([Math]::Abs([Math]::Sin($script:idleTick / 1.1)) * -4)
                }
            }

            # 6) Bring the dachshund back if it is off every screen (checked every 3 seconds)
            if ($script:clockTick -ge $script:nextScreenCheck -and -not $script:isDragging) {
                $script:nextScreenCheck = $script:clockTick + 50
                Assert-OnScreen
            }

            # 7) Position and picture
            $dogLoc = [System.Drawing.Point]::new([int]($script:baseLocation.X + (Get-Scaled ($xOffset * $script:sizeRatio))), [int]($script:baseLocation.Y + (Get-Scaled ($yOffset * $script:sizeRatio))))
            # Breaking out of the screen: out of sight until it lands.
            if ($script:dogAct -eq 'burst' -and $script:dogActTick -lt 11) { $dogLoc = [System.Drawing.Point]::new(-25000, -25000) }
            $script:form.Location = $dogLoc
            $displayPath = $null
            $dogPath = Get-DogFramePath
            if ($null -ne $dogPath -and -not $script:badPaths.ContainsKey([string]$dogPath)) { $displayPath = [string]$dogPath }
            if ($null -eq $displayPath) {
                $frameTick = if ($script:actionMode -eq 'idle') { $script:idleTick } else { $script:actionTick }
                $frameMode = if ($script:roamMoving -and $script:actionMode -eq 'idle') { 'walk' } else { $script:actionMode }
                $displayPath = Get-WagFramePath $frameMode $frameTick
            }
            Set-DisplayImage $displayPath

            # 8) Prepare one picture in the background per tick, so the first action does not stutter
            if (-not $script:isDragging -and $script:warmIndex -lt $script:warmList.Count) {
                $warmPath = $script:warmList[$script:warmIndex]
                $script:warmIndex++
                if (-not $script:badPaths.ContainsKey($warmPath)) {
                    try {
                        $null = Get-DisplayBitmap $warmPath $false
                    } catch {
                        $script:badPaths[$warmPath] = $true
                    }
                }
            }

            # 9) Smooth edges: redraw the window picture when the dachshund or the bubble changed
            if ($script:smoothMode -and $script:viewDirty) {
                try {
                    Update-SmoothView
                } catch {
                    $null = Write-ErrorLog ('平滑邊緣顯示失敗，已改回一般顯示：' + $_.ToString())
                    try { Set-ViewMode $false } catch { }
                }
            }
            # 10) Power saving: fast asleep (sent to bed, or asleep for the night) = 4 updates a second instead of 16.
            $calm = $script:dogSleeping -and $script:dogActLen -eq 0 -and ($script:dogActTick - $script:dogSleepPre) -ge 30 -and
                -not $script:isDragging -and -not $script:hovering -and -not $menuOpen -and $script:bellyRubTicks -le 0
            $wantInterval = if ($calm) { 240 } else { 60 }
            if ($script:timer.Interval -ne $wantInterval) { $script:timer.Interval = $wantInterval }
            $script:tickErrors = 0
        } catch {
            $script:tickErrors++
            if ($script:tickErrors -eq 1) {
                $null = Write-ErrorLog ('動畫錯誤：' + $_.ToString() + "`r`n" + $_.ScriptStackTrace)
            }
            if (($script:tickErrors % 20) -eq 0) {
                # Something keeps failing: reset to a calm state (tried again every 20 failed ticks).
                $script:actionMode = 'idle'
                $script:actionTick = 0
                $script:dogAct = ''
                $script:dogSleeping = $false
                $script:dogNightSleep = $false
                try { Set-Bubble '發生錯誤，已自動重設' } catch { }
            }
        }
    })

    $form.Add_FormClosed({
        try { $timer.Stop() } catch { }
        try { if ($null -ne $script:jerkyForm) { $script:jerkyForm.Close(); $script:jerkyForm.Dispose() } } catch { }
        try { if ($null -ne $script:glassForm) { $script:glassForm.Close(); $script:glassForm.Dispose() } } catch { }
        try { if ($null -ne $script:glassPlayer) { $script:glassPlayer.Dispose() } } catch { }
        try { foreach ($bp in @($script:barkPlayers.Values)) { if ($null -ne $bp) { $bp.Stop(); $bp.Dispose() } } } catch { }
        try { if ($null -ne $script:trayIcon) { $script:trayIcon.Visible = $false; $script:trayIcon.Dispose() } } catch { }
        try { $script:instanceMutex.ReleaseMutex() } catch { }
    })
    $form.Add_Shown({
        try {
            if ($script:smoothMode) {
                try {
                    Update-SmoothView
                } catch {
                    $null = Write-ErrorLog ('平滑邊緣顯示失敗，已改回一般顯示：' + $_.ToString())
                    try { Set-ViewMode $false } catch { }
                }
            }
            if (-not $script:smoothMode) {
                $script:pic.BringToFront()
                $script:bubble.BringToFront()
            }
            Set-Bubble '旺旺來了！右鍵點我開啟選單'
        } catch { $null = Write-ErrorLog ('顯示錯誤：' + $_.ToString()) }
    })
    try { (Get-TrayIcon).Visible = $true } catch { $null = Write-ErrorLog ('右下角圖示錯誤：' + $_.ToString()) }
    $timer.Start()
    [System.Windows.Forms.Application]::Run($form)
}
catch {
    $msg = $_.ToString() + "`r`n`r`n" + $_.ScriptStackTrace
    $null = Write-ErrorLog $msg -Force
    try {
        $box = '旺旺（臘腸狗桌寵）無法啟動。' + "`r`n" + '請把資料夾裡最新的 DachshundPet_Error_ 開頭文字檔提供給我。' + "`r`n`r`n" + $_.Exception.Message
        [void][System.Windows.Forms.MessageBox]::Show($box, '臘腸狗桌寵 啟動錯誤', 'OK', 'Error')
    } catch { }
    exit 1
}
