#requires -Version 5.1
# =============================================================================
# 臘腸狗桌寵 V1.7 - 旺旺, a dachshund desktop pet (low-risk edition)
#   Made from Fighter V24.7: only the dachshund is kept.
#   * Offline only: this program contains no network code.
#   * Writes only into its own folder, and only when something goes wrong
#     (DachshundPet_Error_*.txt, at most 5 files per run).
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
$script:appTitle = '臘腸狗桌寵 V1.7（旺旺）'
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
    } catch {
        $script:smoothError = $_.Exception.Message
        try { Write-Host ('Smooth edges are not available on this PC, the normal view is used: ' + $script:smoothError) } catch { }
    }
}
$script:smoothMode = $false
[System.Windows.Forms.Application]::EnableVisualStyles()

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
    $maxText = [Math]::Max(40, $width - 24)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $measured = $g.MeasureString($text, $script:bubbleFont, [int]$maxText)
    $tw = [int][Math]::Ceiling($measured.Width)
    $th = [int][Math]::Ceiling($measured.Height)
    $bx = 6
    $by = 6
    $bw = $tw + 10
    $bh = $th + 8
    $r = 6
    $path = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $fill = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::White)
    $pen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(110, 110, 110), 1)
    $ink = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(20, 100, 45))
    try {
        $path.AddArc($bx, $by, 2 * $r, 2 * $r, 180, 90)
        $path.AddArc($bx + $bw - 2 * $r, $by, 2 * $r, 2 * $r, 270, 90)
        $path.AddArc($bx + $bw - 2 * $r, $by + $bh - 2 * $r, 2 * $r, 2 * $r, 0, 90)
        $path.AddArc($bx, $by + $bh - 2 * $r, 2 * $r, 2 * $r, 90, 90)
        $path.CloseFigure()
        $g.FillPath($fill, $path)
        $g.DrawPath($pen, $path)
        $textBox = [System.Drawing.RectangleF]::new([single]($bx + 5), [single]($by + 4), [single]($tw + 1), [single]($th + 1))
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
    foreach ($pn in @('tilt_00', 'tilt_01', 'sniff_00', 'sniff_01', 'lie_00', 'sleep_00', 'bow_00', 'crouch_00', 'sidesleep_00', 'belly_00', 'yawn_00', 'sit_00', 'flat_00', 'curl_00', 'bed_00', 'shake_00', 'shake_01', 'shake_02', 'shake_03')) {
        $pp = Get-OutfitPicture ('dachshund_3d_' + $pn + '.png')
        if ($null -ne $pp) { $script:dogPoses[$pn] = $pp }
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

function Test-OutfitReady([string]$folder) {
    if ([string]::IsNullOrEmpty($folder)) { return $true }
    return [bool](Test-Path -LiteralPath (Join-Path (Join-Path $PSScriptRoot $folder) 'dachshund_3d_00.png'))
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
    foreach ($item in $script:outfitMenuItems) { $item.Checked = ([string]$item.Tag -eq $id) }
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
    if ($dist -le $script:roamSpeed) {
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
    $script:roamX = $script:roamX + $dx / $dist * $script:roamSpeed
    $script:roamY = $script:roamY + $dy / $dist * $script:roamSpeed
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
    Reset-ImageCache $size
    Set-DisplayImage (Get-WagFramePath 'idle' 0)
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
    if ($night) { Set-Bubble '晚安～旺旺要睡覺了' }
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
            # Head shake: the head swings from the neck from side to side (a little motion blur), then settles.
            $shakeSeq = @('', 'shake_00', 'shake_01', 'shake_00', 'shake_02', 'shake_03', 'shake_02', 'shake_00', 'shake_01',
                'shake_00', 'shake_02', 'shake_03', 'shake_02', 'shake_00', 'shake_02', '', '')
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
        $msg = '旺旺已經在桌面上了。' + "`r`n" + '如果看不到旺旺，請關閉工作列上的「旺旺（臘腸狗桌寵）」視窗後再重新啟動。'
        [void][System.Windows.Forms.MessageBox]::Show($msg, '臘腸狗桌寵', 'OK', 'Information')
        exit 0
    }

    # ----- Pictures -----
    # Outfits: a folder under clothes\ with the same picture names. 'none' = no clothes.
    $script:outfitList = @(
        @('none', '不穿衣服', ''),
        @('blue_bear', '藍色小熊衣', 'clothes\blue_bear'),
        @('happy_dino', 'HAPPY 恐龍衣', 'clothes\happy_dino'),
        @('red_vest', '紅色鋪棉背心', 'clothes\red_vest'),
        @('camo_jacket', '迷彩鋪棉外套', 'clothes\camo_jacket'),
        @('olive_vest', '軍綠鋪棉背心', 'clothes\olive_vest'),
        @('knit_red', '學院風針織背心（酒紅）', 'clothes\knit_red'),
        @('knit_green', '學院風針織背心（墨綠）', 'clothes\knit_green'),
        @('knit_grey', '學院風針織背心（淺灰）', 'clothes\knit_grey'),
        @('knit_camel', '學院風針織背心（焦糖）', 'clothes\knit_camel')
    )
    $script:outfitId = 'none'
    $script:outfitDir = ''
    $script:outfitMenuItems = @()
    $script:dogWalkStep = 0
    Import-DogPictures

    # ----- Shared state -----
    $script:petSize = 250
    $script:displaySize = 250
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
    $script:bubbleFont = [System.Drawing.Font]::new('Microsoft JhengHei', 9, [System.Drawing.FontStyle]::Bold)

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
    $bubble.Padding = [System.Windows.Forms.Padding]::new(4, 3, 4, 3)
    $bubble.Left = 6
    $bubble.Top = 6
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
    foreach ($oi in $script:outfitList) {
        $outfitItem = New-Object System.Windows.Forms.ToolStripMenuItem([string]$oi[1])
        $outfitItem.Tag = [string]$oi[0]
        $outfitItem.Checked = ([string]$oi[0] -eq $script:outfitId)
        $outfitItem.Enabled = (Test-OutfitReady ([string]$oi[2]))
        $outfitItem.Add_Click({
            param($sender, $e)
            try { Set-DogOutfit ([string]$sender.Tag) } catch { $null = Write-ErrorLog ('換衣服錯誤：' + $_.ToString()) }
        })
        [void]$miOutfit.DropDownItems.Add($outfitItem)
        $script:outfitMenuItems += $outfitItem
    }
    [void]$cms.Items.Add($miOutfit)
    [void]$cms.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

    $miRoam = New-Object System.Windows.Forms.ToolStripMenuItem('自由走動（在桌面到處走）')
    $miRoam.CheckOnClick = $true
    $miRoam.Checked = $script:roamEnabled
    $miRoam.Add_Click({
        param($sender, $e)
        $script:roamEnabled = [bool]$sender.Checked
        $script:roamTarget = $null
        $script:roamPauseTicks = 0
        if ($script:roamEnabled) { Set-Bubble '開始走動' } else { Set-Bubble '停下來了' }
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
    [void]$cms.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

    $miAuto = New-Object System.Windows.Forms.ToolStripMenuItem('自動汪汪叫')
    $miAuto.CheckOnClick = $true
    $miAuto.Checked = $script:autoBarkEnabled
    $miAuto.Add_Click({
        param($sender, $e)
        $script:autoBarkEnabled = [bool]$sender.Checked
        $script:autoBarkCountdown = $script:autoBarkIntervalTicks
        if ($script:autoBarkEnabled) { Set-Bubble '汪！我會常常叫你' } else { Set-Bubble '好，我安靜一點' }
    })
    [void]$cms.Items.Add($miAuto)

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
        if ($script:dogNapEnabled) { Set-Bubble '想睡就睡～' } else { Set-Bubble '不睡午覺了' }
    })
    [void]$cms.Items.Add($miNap)
    $miNight = New-Object System.Windows.Forms.ToolStripMenuItem('晚上自動睡覺（晚上10點～早上7點）')
    $miNight.CheckOnClick = $true
    $miNight.Checked = $script:nightSleepEnabled
    $miNight.Add_Click({
        param($sender, $e)
        $script:nightSleepEnabled = [bool]$sender.Checked
        $script:lastInteractTick = $script:clockTick
        if ($script:nightSleepEnabled) { Set-Bubble '晚上會乖乖睡覺～' } else { Set-Bubble '晚上也陪你！' }
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

    foreach ($sizeInfo in @(@('小尺寸', 180), @('一般尺寸', 250), @('大尺寸', 320))) {
        $sizeItem = New-Object System.Windows.Forms.ToolStripMenuItem([string]$sizeInfo[0])
        $sizeItem.Tag = [int]$sizeInfo[1]
        $sizeItem.Checked = ([int]$sizeInfo[1] -eq $script:petSize)
        $sizeItem.Add_Click({
            param($sender, $e)
            try { Set-PetSize ([int]$sender.Tag) } catch { $null = Write-ErrorLog ('尺寸調整錯誤：' + $_.ToString()) }
        })
        [void]$cms.Items.Add($sizeItem)
        $script:sizeMenuItems += $sizeItem
    }
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
        if ($moved) {
            # Put down: shakes itself, rests about 6 seconds, then walks again.
            $script:roamTarget = $null
            $script:roamPauseTicks = 100
            try { Start-DogAction 'shake' '甩甩～' } catch { }
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
    $timer.Add_Tick({
        try {
            $script:idleTick++
            $script:clockTick++
            if ($script:bubbleTicks -gt 0) {
                $script:bubbleTicks--
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
            if (($script:clockTick % 50) -eq 1) {
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
                if ($script:hoverTicks -eq 25 -and -not $script:dogSleeping) { Start-DogAction 'pet' '*' }
            }

            # 4) Barking now and then (paused while dragging, in the menu, or during an action)
            $quietNight = $script:nightSleepEnabled -and $script:isNight
            if ($script:autoBarkEnabled -and -not $quietNight -and -not $script:isDragging -and -not $menuOpen -and $script:actionMode -eq 'idle' -and $script:dogAct -eq '') {
                $script:autoBarkCountdown--
                if ($script:autoBarkCountdown -le 0) {
                    $script:autoBarkCountdown = $script:autoBarkIntervalTicks
                    Set-Bubble ($script:dogLines[$script:rng.Next(0, $script:dogLines.Count)])
                    $script:actionMode = 'happy'
                    $script:actionTick = 0
                }
            }

            # 5) Free roaming (not during an action)
            if ($script:roamEnabled -and -not $script:isDragging -and -not $menuOpen -and $script:dogAct -eq '') {
                try {
                    Step-Roam
                } catch {
                    $script:roamEnabled = $false
                    $script:roamMoving = $false
                    try { $script:miRoam.Checked = $false } catch { }
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
                    $walkBob = @(-2, 0, -2, -2, 0, -2)
                    $yOffset += $walkBob[$script:dogWalkStep]
                } else {
                    $yOffset += [int]([Math]::Abs([Math]::Sin($script:idleTick / 1.1)) * -4)
                }
            }

            # 6) Bring the dachshund back if it is off every screen (checked every 3 seconds)
            if (($script:idleTick % 50) -eq 0 -and -not $script:isDragging) { Assert-OnScreen }

            # 7) Position and picture
            $script:form.Location = [System.Drawing.Point]::new([int]($script:baseLocation.X + $xOffset), [int]($script:baseLocation.Y + $yOffset))
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
            $script:tickErrors = 0
        } catch {
            $script:tickErrors++
            if ($script:tickErrors -eq 1) {
                $null = Write-ErrorLog ('動畫錯誤：' + $_.ToString() + "`r`n" + $_.ScriptStackTrace)
            }
            if ($script:tickErrors -eq 20) {
                # Something keeps failing: reset to a calm state.
                $script:actionMode = 'idle'
                $script:actionTick = 0
                $script:dogAct = ''
                $script:dogSleeping = $false
                try { Set-Bubble '發生錯誤，已自動重設' } catch { }
            }
        }
    })

    $form.Add_FormClosed({
        try { $timer.Stop() } catch { }
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
