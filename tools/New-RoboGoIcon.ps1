# Draws RoboGo.ico: a dark tile with two amber chevrons, in the sizes Windows asks for.
# The icon is committed; run this only to change the drawing.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tools\New-RoboGoIcon.ps1
param([string]$Path = (Join-Path $PSScriptRoot '..\RoboGo.ico'))
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

function New-IconBitmap {
    param([int]$Size)
    $bitmap = New-Object System.Drawing.Bitmap ($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $g.Clear([System.Drawing.Color]::Transparent)
        # tile with rounded corners
        $inset = [single][math]::Max(0.5, $Size * 0.03)
        $side = [single]($Size - 2 * $inset)
        $corner = [single]($Size * 0.22)
        $tile = New-Object System.Drawing.Drawing2D.GraphicsPath
        $tile.AddArc($inset, $inset, $corner * 2, $corner * 2, 180, 90)
        $tile.AddArc($inset + $side - $corner * 2, $inset, $corner * 2, $corner * 2, 270, 90)
        $tile.AddArc($inset + $side - $corner * 2, $inset + $side - $corner * 2, $corner * 2, $corner * 2, 0, 90)
        $tile.AddArc($inset, $inset + $side - $corner * 2, $corner * 2, $corner * 2, 90, 90)
        $tile.CloseFigure()
        $fill = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 19, 21, 24))
        $g.FillPath($fill, $tile)
        if ($Size -ge 32) {
            $edge = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 58, 63, 71)), ([single][math]::Max(1.0, $Size / 64.0))
            $g.DrawPath($edge, $tile)
            $edge.Dispose()
        }
        $fill.Dispose()
        $tile.Dispose()
        # two chevrons: the first dimmer, the second in full amber, so the pair reads as motion
        $width = [single][math]::Max(1.8, $Size * 0.13)
        $chevrons = @(
            @{ X = 0.23; Color = [System.Drawing.Color]::FromArgb(255, 150, 104, 0) },
            @{ X = 0.51; Color = [System.Drawing.Color]::FromArgb(255, 255, 176, 0) }
        )
        foreach ($chevron in $chevrons) {
            $pen = New-Object System.Drawing.Pen $chevron.Color, $width
            $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
            $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
            $pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
            $points = [System.Drawing.PointF[]]@(
                (New-Object System.Drawing.PointF ([single]($Size * $chevron.X), [single]($Size * 0.27))),
                (New-Object System.Drawing.PointF ([single]($Size * ($chevron.X + 0.23)), [single]($Size * 0.5))),
                (New-Object System.Drawing.PointF ([single]($Size * $chevron.X), [single]($Size * 0.73)))
            )
            $g.DrawLines($pen, $points)
            $pen.Dispose()
        }
    }
    finally {
        $g.Dispose()
    }
    return $bitmap
}

function ConvertTo-IconImage {
    # The bytes of one picture inside an .ico file. 256 pixels is stored as PNG, smaller
    # sizes as a classic 32-bit bitmap (rows bottom-up, followed by an empty 1-bit mask),
    # which every part of Windows reads.
    param([System.Drawing.Bitmap]$Bitmap)
    $size = $Bitmap.Width
    $stream = New-Object System.IO.MemoryStream
    if ($size -ge 256) {
        $Bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
        return , $stream.ToArray()
    }
    $writer = New-Object System.IO.BinaryWriter $stream
    $maskRow = [int]([math]::Ceiling($size / 32.0) * 4)
    $writer.Write([int]40)
    $writer.Write([int]$size)
    $writer.Write([int]($size * 2))
    $writer.Write([int16]1)
    $writer.Write([int16]32)
    $writer.Write([int]0)
    $writer.Write([int]($size * $size * 4 + $maskRow * $size))
    $writer.Write([int]0)
    $writer.Write([int]0)
    $writer.Write([int]0)
    $writer.Write([int]0)
    $area = New-Object System.Drawing.Rectangle (0, 0, $size, $size)
    $data = $Bitmap.LockBits($area, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        $row = New-Object byte[] ($size * 4)
        for ($y = $size - 1; $y -ge 0; $y--) {
            $from = [IntPtr]::Add($data.Scan0, $y * $data.Stride)
            [System.Runtime.InteropServices.Marshal]::Copy($from, $row, 0, $row.Length)
            $writer.Write($row)
        }
    }
    finally {
        $Bitmap.UnlockBits($data)
    }
    $writer.Write((New-Object byte[] ($maskRow * $size)))
    $writer.Flush()
    return , $stream.ToArray()
}

$sizes = @(16, 20, 24, 32, 40, 48, 64, 256)
$images = New-Object System.Collections.Generic.List[object]
foreach ($size in $sizes) {
    $bitmap = New-IconBitmap $size
    $images.Add((ConvertTo-IconImage $bitmap))
    $bitmap.Dispose()
}
$file = New-Object System.IO.MemoryStream
$out = New-Object System.IO.BinaryWriter $file
$out.Write([int16]0)
$out.Write([int16]1)
$out.Write([int16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $edge = $sizes[$i]
    if ($edge -ge 256) { $edge = 0 }
    $out.Write([byte]$edge)
    $out.Write([byte]$edge)
    $out.Write([byte]0)
    $out.Write([byte]0)
    $out.Write([int16]1)
    $out.Write([int16]32)
    $out.Write([int]$images[$i].Length)
    $out.Write([int]$offset)
    $offset += $images[$i].Length
}
foreach ($image in $images) { $out.Write([byte[]]$image) }
$out.Flush()
$target = [System.IO.Path]::GetFullPath($Path)
[System.IO.File]::WriteAllBytes($target, $file.ToArray())
Write-Host ('[OK] ' + $target + ': ' + $sizes.Count + ' sizes, ' + $file.Length + ' bytes')
