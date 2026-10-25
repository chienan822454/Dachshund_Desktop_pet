#requires -Version 5.1
# =============================================================================
# 臘腸狗桌寵 V1.12.1 - 旺旺, a dachshund desktop pet (low-risk edition)
#   Made from Fighter V24.7: only the dachshund is kept.
#   * Offline only: this program contains no network code.
#   * Writes only into its own folder, and only when something goes wrong
#     (DachshundPet_Error_*.txt, at most 5 files per run). One exception: an alarm clock
#     that is set is remembered in %APPDATA%\DachshundPet\alarm.txt (deleted when cancelled).
#   * Alarm clock and automatic barking: play sounds\wangwang_bark.wav (旺旺's real bark) with Windows' own sound player.
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
$script:appVersion = 'V1.12.1'
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
    foreach ($pn in @('tilt_00', 'tilt_01', 'sniff_00', 'sniff_01', 'lie_00', 'sleep_00', 'bow_00', 'crouch_00', 'sidesleep_00', 'belly_00', 'yawn_00', 'sit_00', 'flat_00', 'curl_00', 'bed_00', 'shake_00', 'shake_01', 'shake_02', 'shake_03', 'eat_00', 'eat_01', 'eat_02', 'drink_00', 'drink_01')) {
        $pp = Get-OutfitPicture ('dachshund_3d_' + $pn + '.png')
        if ($null -ne $pp) { $script:dogPoses[$pn] = $pp }
    }
    # Drinking only with the outfit's own pictures (the plain picture would take the clothes off for a moment).
    if (-not [string]::IsNullOrEmpty($script:outfitDir)) {
        foreach ($pn in @('drink_00', 'drink_01')) {
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

function Step-Roam {
    if ($script:roamPauseTicks -gt 0) {
        $script:roamPauseTicks--
        $script:roamMoving = $false
        return
    }
    # When chasing the mouse, aim next to the pointer and re-aim about once a second.
    $chasing = [bool]$script:dogChaseMouse
    if ($chasing -and ($script:clockTick % 15) -eq 0) { $script:roamTarget = $null }
    if ($null -eq $script:roamTarget) {
        $b = Get-RoamBounds
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
    if ($dist -le $stepLen) {
        # Arrived: rest 2.4 to 8.4 seconds, then pick a new spot.
        $script:baseLocation = $script:roamTarget
        $script:roamX = [double]$script:roamTarget.X
        $script:roamY = [double]$script:roamTarget.Y
        $script:roamTarget = $null
        $script:roamMoving = $false
        if ($chasing) {
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
    if ($size -eq $script:form.Width) { return }
    # Keep the feet and the middle of the dachshund where they were.
    $old = $script:form.Width
    $centerX = $script:baseLocation.X + [int][Math]::Floor($old / 2.0)
    $bottom = $script:baseLocation.Y + $old
    $script:form.Size = [System.Drawing.Size]::new($size, $size)
    $script:pic.Size = $script:form.ClientSize
    $script:bubble.MaximumSize = [System.Drawing.Size]::new($size - 12, 0)
    $script:baseLocation = [System.Drawing.Point]::new($centerX - [int][Math]::Floor($size / 2.0), $bottom - $size)
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
    $ni.Text = '旺旺躲起來了（點一下叫牠回來）'
    $ni.Add_MouseClick({
        param($sender, $e)
        if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
            try { Show-Dog } catch { $null = Write-ErrorLog ('叫旺旺回來錯誤：' + $_.ToString()) }
        }
    })
    $trayMenu = New-Object System.Windows.Forms.ContextMenuStrip
    $trayBack = $trayMenu.Items.Add('叫旺旺回來')
    $trayBack.Add_Click({ try { Show-Dog } catch { $null = Write-ErrorLog ('叫旺旺回來錯誤：' + $_.ToString()) } })
    $trayQuit = $trayMenu.Items.Add('關閉旺旺')
    $trayQuit.Add_Click({ $script:form.Close() })
    $ni.ContextMenuStrip = $trayMenu
    $script:trayIcon = $ni
    return $ni
}

function Hide-Dog([int]$minutes) {
    # $minutes = 0: hidden until it is called back.
    if ($script:dogHidden) { return }
    if ($script:alarmRinging) { Stop-AlarmRing '' }
    $script:hiddenUntil = if ($minutes -gt 0) { (Get-Date).AddMinutes($minutes) } else { [DateTime]::MaxValue }
    $script:dogHidden = $true
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
    try { $script:trayIcon.Visible = $false } catch { }
    $script:lastInteractTick = $script:clockTick
    $script:timer.Interval = 60
    $script:form.Location = $script:baseLocation
    $script:viewDirty = $true
    if ($script:dogSleeping) { Set-Bubble 'Zzz…' } else { Set-Bubble $say }
}

# -----------------------------------------------------------------------------
# Alarm clock: at the set time the dachshund comes out (also when hidden), wakes up and barks with
# 旺旺's real bark (sounds\wangwang_bark.wav) until it is clicked, for at most one minute.
# -----------------------------------------------------------------------------
function Get-BarkPlayer {
    if ($null -ne $script:barkPlayer) { return $script:barkPlayer }
    $wav = Join-Path $PSScriptRoot 'sounds\wangwang_bark.wav'
    if (-not (Test-Path -LiteralPath $wav)) { return $null }
    try {
        $player = New-Object System.Media.SoundPlayer($wav)
        $player.Load()
        $script:barkPlayer = $player
    } catch {
        $script:barkPlayer = $null
        $null = Write-ErrorLog ('旺旺的叫聲無法播放：' + $_.ToString())
    }
    return $script:barkPlayer
}

function Invoke-BarkSound([bool]$fallback = $true) {
    # $true when 旺旺's own bark was played; without the sound file a Windows sound is played instead
    # ($fallback = $false: then nothing is played, used for the automatic barking).
    $player = Get-BarkPlayer
    if ($null -ne $player) {
        try { $player.Play(); return $true } catch { }
    }
    if ($fallback) {
        try { [System.Media.SystemSounds]::Exclamation.Play() } catch { }
    }
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

function Save-AlarmSetting {
    # Remembered in %APPDATA%\DachshundPet\alarm.txt, so the alarm survives a restart; deleted when cancelled.
    try {
        if ([string]::IsNullOrEmpty($script:alarmFile)) { return }
        if ($null -eq $script:alarmTime) {
            if (Test-Path -LiteralPath $script:alarmFile) { Remove-Item -LiteralPath $script:alarmFile -Force }
            return
        }
        $dir = Split-Path -Parent $script:alarmFile
        if (-not (Test-Path -LiteralPath $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }
        $daily = if ($script:alarmDaily) { '1' } else { '0' }
        $when = $script:alarmTime.ToString('yyyy-MM-dd HH:mm', [System.Globalization.CultureInfo]::InvariantCulture)
        $lines = [string[]]@($script:alarmHHmm, $daily, $script:alarmNote, $when)
        [System.IO.File]::WriteAllLines($script:alarmFile, $lines, [System.Text.UTF8Encoding]::new($false))
    } catch {
        $null = Write-ErrorLog ('鬧鐘沒辦法記下來（下次開旺旺要重新設定）：' + $_.ToString())
    }
}

function Import-AlarmSetting {
    try {
        if ([string]::IsNullOrEmpty($script:alarmFile) -or -not (Test-Path -LiteralPath $script:alarmFile)) { return }
        $lines = [System.IO.File]::ReadAllLines($script:alarmFile, [System.Text.Encoding]::UTF8)
        if ($lines.Count -lt 2 -or $lines[0] -notmatch '^([01]?\d|2[0-3]):[0-5]\d$') { return }
        $daily = ($lines[1] -eq '1')
        $at = $null
        if ($daily) {
            $at = Get-NextAlarmTime ([string]$lines[0])
        } elseif ($lines.Count -ge 4) {
            $parsed = [DateTime]::MinValue
            if ([DateTime]::TryParseExact([string]$lines[3], 'yyyy-MM-dd HH:mm', [System.Globalization.CultureInfo]::InvariantCulture,
                    [System.Globalization.DateTimeStyles]::None, [ref]$parsed)) {
                if ($parsed -gt (Get-Date)) { $at = $parsed }
            }
        }
        if ($null -eq $at) {
            # A one-time alarm whose time has already passed.
            Remove-Item -LiteralPath $script:alarmFile -Force -ErrorAction SilentlyContinue
            return
        }
        $script:alarmHHmm = [string]$lines[0]
        $script:alarmDaily = $daily
        $script:alarmNote = if ($lines.Count -ge 3) { [string]$lines[2] } else { '' }
        $script:alarmTime = $at
    } catch { }
}

function Set-DogAlarm([string]$hhmm, [bool]$daily, [string]$note) {
    $script:alarmHHmm = $hhmm
    $script:alarmDaily = $daily
    $script:alarmNote = $note
    $script:alarmTime = Get-NextAlarmTime $hhmm
    Save-AlarmSetting
    $day = if ($daily) { '每天 ' } elseif ($script:alarmTime.Date -eq (Get-Date).Date) { '今天 ' } else { '明天 ' }
    Set-Bubble ('好！' + $day + $hhmm + ' 旺旺會汪汪叫你')
}

function Clear-DogAlarm {
    $script:alarmTime = $null
    $script:alarmHHmm = ''
    $script:alarmDaily = $false
    $script:alarmNote = ''
    Save-AlarmSetting
}

function Start-DogCountdown([int]$minutes) {
    if ($script:alarmRinging) { Stop-AlarmRing '' }
    $script:timerUntil = (Get-Date).AddMinutes($minutes)
    $label = if ($minutes -ge 60 -and ($minutes % 60) -eq 0) { [string]($minutes / 60) + ' 小時' } else { [string]$minutes + ' 分鐘' }
    Set-Bubble ('好！' + $label + '後（' + $script:timerUntil.ToString('HH:mm') + '）叫你')
}

function Start-AlarmRing([string]$note) {
    if ($script:dogHidden) { Show-Dog '汪汪！' }
    if ($script:dogSleeping) { Stop-DogSleep $false }
    $script:alarmRinging = $true
    $script:alarmRingNote = $note
    $script:alarmRingUntil = (Get-Date).AddSeconds(60)
    $script:alarmNextBark = [DateTime]::MinValue
    $script:lastInteractTick = $script:clockTick
}

function Stop-AlarmRing([string]$say) {
    if (-not $script:alarmRinging) { return }
    $script:alarmRinging = $false
    try { if ($null -ne $script:barkPlayer) { $script:barkPlayer.Stop() } } catch { }
    if (-not [string]::IsNullOrEmpty($say)) { Set-Bubble $say }
}

function Step-AlarmRing([DateTime]$now) {
    # Barks every 2.6 seconds with a happy hop, until clicked (at most one minute).
    if ($now -ge $script:alarmRingUntil) { Stop-AlarmRing '旺旺叫累了，鬧鐘先停囉'; return }
    if ($now -lt $script:alarmNextBark) { return }
    $script:alarmNextBark = $now.AddMilliseconds(2600)
    [void](Invoke-BarkSound)
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
    if ($null -ne $script:alarmTime -and $now -ge $script:alarmTime) {
        $lateMinutes = ($now - $script:alarmTime).TotalMinutes
        $hhmm = $script:alarmHHmm
        $note = $script:alarmNote
        if ($script:alarmDaily) { $script:alarmTime = Get-NextAlarmTime $hhmm } else { Clear-DogAlarm }
        if ([string]::IsNullOrEmpty($note)) { $note = $hhmm + ' 到囉！' }
        if ($lateMinutes -le 10) {
            Start-AlarmRing $note
        } elseif (-not $script:dogHidden) {
            # The computer was asleep at that time: no barking long afterwards, it only says so.
            Set-Bubble ('錯過了 ' + $hhmm + ' 的鬧鐘（電腦剛剛在睡覺）')
        }
    }
    if ($null -ne $script:timerUntil -and $now -ge $script:timerUntil) {
        $script:timerUntil = $null
        Start-AlarmRing '時間到囉！'
    }
    if ($script:alarmRinging) { Step-AlarmRing $now }
}

function Update-AlarmMenu {
    $now = Get-Date
    if ($null -ne $script:alarmTime) {
        $day = if ($script:alarmDaily) { '每天 ' } elseif ($script:alarmTime.Date -eq $now.Date) { '今天 ' } else { '明天 ' }
        $info = '鬧鐘：' + $day + $script:alarmHHmm
        if (-not [string]::IsNullOrEmpty($script:alarmNote)) { $info += '「' + $script:alarmNote + '」' }
        $script:miAlarmInfo.Text = $info
    } else {
        $script:miAlarmInfo.Text = '還沒有設定鬧鐘'
    }
    $script:miAlarmOff.Enabled = ($null -ne $script:alarmTime)
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

function Show-AlarmDialog {
    # A small window: the time, every day or only once, and an optional line for the bubble.
    $dlg = New-Object System.Windows.Forms.Form
    try {
        $dlg.Text = '旺旺鬧鐘'
        $dlg.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
        $dlg.MaximizeBox = $false
        $dlg.MinimizeBox = $false
        $dlg.ShowInTaskbar = $false
        $dlg.TopMost = $true
        $dlg.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
        $dlg.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
        $dlg.Font = [System.Drawing.Font]::new('Microsoft JhengHei UI', 10)
        $dlg.ClientSize = [System.Drawing.Size]::new((Get-Scaled 330), (Get-Scaled 214))

        $lblTime = New-Object System.Windows.Forms.Label
        $lblTime.Text = '幾點叫你：'
        $lblTime.AutoSize = $true
        $lblTime.Location = [System.Drawing.Point]::new((Get-Scaled 16), (Get-Scaled 20))
        $dlg.Controls.Add($lblTime)

        $picker = New-Object System.Windows.Forms.DateTimePicker
        $picker.Format = [System.Windows.Forms.DateTimePickerFormat]::Custom
        $picker.CustomFormat = 'HH:mm'
        $picker.ShowUpDown = $true
        $picker.Location = [System.Drawing.Point]::new((Get-Scaled 120), (Get-Scaled 16))
        $picker.Width = Get-Scaled 90
        if (-not [string]::IsNullOrEmpty($script:alarmHHmm)) {
            $startAt = Get-NextAlarmTime $script:alarmHHmm
        } else {
            # Half an hour from now, on a 5-minute mark.
            $soon = (Get-Date).AddMinutes(30)
            $startAt = $soon.Date.AddHours($soon.Hour).AddMinutes([Math]::Ceiling($soon.Minute / 5.0) * 5)
        }
        $picker.Value = $startAt
        $dlg.Controls.Add($picker)

        $chkDaily = New-Object System.Windows.Forms.CheckBox
        $chkDaily.Text = '每天這個時間都叫我'
        $chkDaily.AutoSize = $true
        $chkDaily.Checked = [bool]$script:alarmDaily
        $chkDaily.Location = [System.Drawing.Point]::new((Get-Scaled 16), (Get-Scaled 58))
        $dlg.Controls.Add($chkDaily)

        $lblNote = New-Object System.Windows.Forms.Label
        $lblNote.Text = '想提醒自己的話（可以空白）：'
        $lblNote.AutoSize = $true
        $lblNote.Location = [System.Drawing.Point]::new((Get-Scaled 16), (Get-Scaled 94))
        $dlg.Controls.Add($lblNote)

        $txtNote = New-Object System.Windows.Forms.TextBox
        $txtNote.MaxLength = 20
        $txtNote.Text = [string]$script:alarmNote
        $txtNote.Location = [System.Drawing.Point]::new((Get-Scaled 16), (Get-Scaled 120))
        $txtNote.Width = Get-Scaled 298
        $dlg.Controls.Add($txtNote)

        $btnOk = New-Object System.Windows.Forms.Button
        $btnOk.Text = '設定'
        $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $btnOk.Location = [System.Drawing.Point]::new((Get-Scaled 132), (Get-Scaled 166))
        $btnOk.Size = [System.Drawing.Size]::new((Get-Scaled 84), (Get-Scaled 30))
        $dlg.Controls.Add($btnOk)
        $btnCancel = New-Object System.Windows.Forms.Button
        $btnCancel.Text = '取消'
        $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $btnCancel.Location = [System.Drawing.Point]::new((Get-Scaled 230), (Get-Scaled 166))
        $btnCancel.Size = [System.Drawing.Size]::new((Get-Scaled 84), (Get-Scaled 30))
        $dlg.Controls.Add($btnCancel)
        $dlg.AcceptButton = $btnOk
        $dlg.CancelButton = $btnCancel

        $result = $dlg.ShowDialog([System.Windows.Forms.IWin32Window]$script:form)
        if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
            Set-DogAlarm ($picker.Value.ToString('HH:mm', [System.Globalization.CultureInfo]::InvariantCulture)) ([bool]$chkDaily.Checked) (([string]$txtNote.Text).Trim())
        }
    } finally {
        $dlg.Dispose()
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
    $script:dogNightSleep = $false
    $script:dogAct = $name
    $script:dogActTick = 0
    $script:dogActLen = [int]$spec.Len
    $script:dogActPose = if ($script:rng.Next(0, 2) -eq 0) { 'tilt_00' } else { 'tilt_01' }
    $script:actionMode = 'idle'
    $script:actionTick = 0
    $script:roamMoving = $false
    if ($name -eq 'look') { $script:facingLeft = -not $script:facingLeft }
    if ($say -eq '*') {
        $lines = @($spec.Say)
        $say = [string]$lines[$script:rng.Next(0, $lines.Count)]
    }
    if (-not [string]::IsNullOrEmpty($say)) { Set-Bubble $say }
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
    $script:dogNightSleep = $false
    if ($script:dogAct -eq 'sleep') { $script:dogAct = '' }
    $script:lastInteractTick = $script:clockTick
    $script:napAfterTicks = $script:rng.Next(4000, 8000)
    if ($wasSleeping -and $stretch) {
        if (Test-DogAction 'bow') { Start-DogAction 'bow' $say } else { Set-Bubble $say }
    }
}

function Invoke-DogHover {
    # The pointer touched the dachshund: a curious head tilt (at most every 10 seconds).
    if ($script:isDragging) { return }
    if (($script:clockTick - $script:hoverReactTick) -lt 160) { return }
    $script:hoverReactTick = $script:clockTick
    if ($script:dogSleeping) { Set-Bubble 'Zzz…（點我叫醒旺旺）'; return }
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
        @('lion', '小獅子裝', 'clothes\lion', 'costume')
    )
    $script:outfitId = 'none'
    $script:outfitDir = ''
    $script:outfitMenuItems = @()
    $script:dogWalkStep = 0
    Import-DogPictures

    # ----- Shared state -----
    $script:petSize = Get-Scaled 250
    $script:sizeRatio = 1.0
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
    $script:autoBarkSound = $false        # the automatic barking plays 旺旺's real bark only when switched on in the menu
    $script:roamEnabled = $true
    $script:roamSpeed = 3.0
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
    # Alarm clock (remembered across restarts in %APPDATA%\DachshundPet\alarm.txt) and countdown
    $script:alarmTime = $null
    $script:alarmHHmm = ''
    $script:alarmDaily = $false
    $script:alarmNote = ''
    $script:timerUntil = $null
    $script:alarmRinging = $false
    $script:alarmRingNote = ''
    $script:alarmRingUntil = [DateTime]::MinValue
    $script:alarmNextBark = [DateTime]::MinValue
    $script:barkPlayer = $null
    $script:alarmFile = ''
    try {
        $appData = [Environment]::GetFolderPath('ApplicationData')
        if (-not [string]::IsNullOrEmpty($appData)) { $script:alarmFile = Join-Path $appData 'DachshundPet\alarm.txt' }
    } catch { $script:alarmFile = '' }
    Import-AlarmSetting
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
    $miFeed = New-Object System.Windows.Forms.ToolStripMenuItem('餵點心')
    $miFeed.Add_Click({
        try {
            if ($script:dogSleeping) { Start-DogAction 'eat' '聞到點心的味道，旺旺醒來了！' } else { Start-DogAction 'eat' '*' }
        } catch { $null = Write-ErrorLog ('餵點心錯誤：' + $_.ToString()) }
    })
    [void]$cms.Items.Add($miFeed)
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
            try { Set-DogOutfit ([string]$sender.Tag) } catch { $null = Write-ErrorLog ('換衣服錯誤：' + $_.ToString()) }
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
    $miAlarmSet = New-Object System.Windows.Forms.ToolStripMenuItem('設定鬧鐘時間…')
    $miAlarmSet.Add_Click({ try { Show-AlarmDialog } catch { $null = Write-ErrorLog ('鬧鐘設定錯誤：' + $_.ToString()) } })
    [void]$miAlarm.DropDownItems.Add($miAlarmSet)
    $script:miAlarmOff = New-Object System.Windows.Forms.ToolStripMenuItem('取消鬧鐘')
    $script:miAlarmOff.Add_Click({ try { Clear-DogAlarm; Set-Bubble '鬧鐘取消了' } catch { $null = Write-ErrorLog ('鬧鐘錯誤：' + $_.ToString()) } })
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
    $miAlarm.Add_DropDownOpening({ try { Update-AlarmMenu } catch { } })
    [void]$cms.Items.Add($miAlarm)
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
    [void]$cms.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

    $miAuto = New-Object System.Windows.Forms.ToolStripMenuItem('自動汪汪叫')
    $miAuto.CheckOnClick = $true
    $miAuto.Checked = $script:autoBarkEnabled
    $miAuto.Add_Click({
        param($sender, $e)
        $script:autoBarkEnabled = [bool]$sender.Checked
        $script:autoBarkCountdown = $script:autoBarkIntervalTicks
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
    foreach ($seconds in @(15, 25, 40)) {
        $gapItem = New-Object System.Windows.Forms.ToolStripMenuItem(('{0} 秒' -f $seconds))
        $gapItem.Tag = [int]$seconds
        $gapItem.Checked = ($seconds -eq 25)
        $gapItem.Add_Click({
            param($sender, $e)
            $script:autoBarkIntervalTicks = [int]([int]$sender.Tag * 1000 / 60)
            $script:autoBarkCountdown = $script:autoBarkIntervalTicks
            foreach ($item in $sender.Owner.Items) { $item.Checked = ($item -eq $sender) }
            Set-Bubble ('每 {0} 秒汪一下' -f $sender.Tag)
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
                Set-Bubble ('旺旺變成' + $sender.Text + '尺寸了！')
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
                '‧左鍵拖曳：把牠抱到別的地方' + $nl +
                '‧右鍵：叫牠做動作、餵點心、餵水、睡覺、換衣服、鬧鐘和各種設定' + $nl +
                '‧鬧鐘：時間到旺旺會用真的叫聲汪汪叫，點牠一下就停' + $nl +
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
            $script:dogNightSleep = $false
            $script:dogAct = ''
            Set-Bubble '汪！放旺旺下來～'
        }
        $script:dragMoved = $true
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
        if ($moved) {
            # Put down: shakes itself, rests about 6 seconds, then walks again.
            $script:roamTarget = $null
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
            # A click on the sleeping dachshund wakes it up.
            try { Stop-DogSleep $true } catch { }
            return
        }
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
            }

            # 2) Happy hop (after a pat or a bark)
            if ($script:actionMode -ne 'idle') {
                $script:actionTick++
                $xOffset = [int]([Math]::Sin($script:actionTick / 1.0) * 4)
                $yOffset = [int]([Math]::Abs([Math]::Sin($script:actionTick / 1.1)) * -16)
                if ($script:actionTick -gt 24) { $script:actionMode = 'idle'; $script:actionTick = 0 }
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
                            Set-Bubble ([string]$yum[$script:rng.Next(0, $yum.Count)])
                        }
                    }
                    'drink' {
                        $xOffset = 0
                        $yOffset = 0
                        if ($t -ge 50) { $yOffset = [int]([Math]::Abs([Math]::Sin($t / 1.3)) * -6) }
                        if ($t -eq 50) {
                            $ahh = @('喝飽了～哈～', '好好喝！謝謝～', '咕嚕～喝飽飽了！')
                            Set-Bubble ([string]$ahh[$script:rng.Next(0, $ahh.Count)])
                        }
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
                    if ($script:dogAct -eq 'sleep') { Stop-DogSleep $true } else { $script:dogAct = '' }
                }
            } elseif (-not $script:isDragging -and -not $menuOpen -and -not $script:roamMoving -and $script:actionMode -eq 'idle') {
                $idleFor = $script:clockTick - $script:lastInteractTick
                if ($script:nightSleepEnabled -and $script:isNight -and $idleFor -gt 1000) {
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
                if ($script:hoverTicks -eq 25 -and -not $script:dogSleeping -and $script:dogAct -ne 'eat' -and $script:dogAct -ne 'drink' -and -not $script:alarmRinging) { Start-DogAction 'pet' '*' }
            }

            # 4) Barking now and then (paused while dragging, in the menu, or during an action)
            $quietNight = $script:nightSleepEnabled -and $script:isNight
            if ($script:autoBarkEnabled -and -not $quietNight -and -not $script:isDragging -and -not $menuOpen -and -not $script:alarmRinging -and $script:actionMode -eq 'idle' -and $script:dogAct -eq '') {
                $script:autoBarkCountdown--
                if ($script:autoBarkCountdown -le 0) {
                    $script:autoBarkCountdown = $script:autoBarkIntervalTicks
                    Set-Bubble ($script:dogLines[$script:rng.Next(0, $script:dogLines.Count)])
                    $script:actionMode = 'happy'
                    $script:actionTick = 0
                    # 旺旺's real bark (can be switched off in the menu; nothing is played without the sound file).
                    if ($script:autoBarkSound) {
                        try { [void](Invoke-BarkSound $false) } catch { $null = Write-ErrorLog ('叫聲錯誤：' + $_.ToString()) }
                    }
                }
            }

            # 5) Free roaming (not during an action)
            if ($script:roamEnabled -and -not $script:isDragging -and -not $menuOpen -and $script:dogAct -eq '') {
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
            if ($script:roamMoving) {
                if ($script:dogWalkFrames.Count -eq 4) {
                    # The legs do the walking; a faster walking speed means quicker steps.
                    $walkHold = [Math]::Max(1, [int][Math]::Round(6.0 / $script:roamSpeed))
                    $script:dogWalkStep = [int]([Math]::Floor($script:idleTick / $walkHold) % 6)
                    if ($script:dogChaseMouse -or $script:roamSpeed -ge 5.0) {
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
            $script:form.Location = [System.Drawing.Point]::new([int]($script:baseLocation.X + (Get-Scaled ($xOffset * $script:sizeRatio))), [int]($script:baseLocation.Y + (Get-Scaled ($yOffset * $script:sizeRatio))))
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
                -not $script:isDragging -and -not $script:hovering -and -not $menuOpen
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
        try { if ($null -ne $script:barkPlayer) { $script:barkPlayer.Stop(); $script:barkPlayer.Dispose() } } catch { }
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
