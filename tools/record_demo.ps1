<#
DIGIHARIMAN — 60秒デモを MP4 に録画するスクリプト (Windows PowerShell)

Godot の Movie Maker モードで全フレームを確実に描画・録音し（実行速度に
関係なく取りこぼしゼロ）、ffmpeg があれば H.264 MP4 へ自動変換します。

使い方:
  powershell -ExecutionPolicy Bypass -File tools\record_demo.ps1
  powershell ... -Godot "C:\path\to\Godot_v4.4.1-stable_win64.exe"
  powershell ... -Fps 60 -Width 1920 -Height 1080

ffmpeg が無い場合は AVI (Motion JPEG) のまま残します。導入は:
  winget install Gyan.FFmpeg
#>
param(
    [string]$Godot = "godot",
    [int]$Fps = 60,
    [int]$Width = 1920,
    [int]$Height = 1080,
    [string]$OutName = "digihariman_demo"
)

$ErrorActionPreference = "Stop"
$project = Split-Path -Parent $PSScriptRoot
$avi = Join-Path $project "$OutName.avi"
$mp4 = Join-Path $project "$OutName.mp4"

if (-not (Get-Command $Godot -ErrorAction SilentlyContinue)) {
    Write-Error "Godot が見つかりません。-Godot で exe のパスを指定してください。"
}

# The movie writer captures the project's base viewport, which --resolution
# cannot change — override.cfg (read by Godot at startup) is the supported way.
$override = Join-Path $project "override.cfg"
@"
[display]

window/size/viewport_width=$Width
window/size/viewport_height=$Height
window/size/mode=0
"@ | Set-Content -Encoding ASCII $override

try {
    Write-Host "Movie Maker モードで録画中... (${Width}x${Height} @ ${Fps}fps / 実時間の数倍かかります)"
    & $Godot --path $project --write-movie $avi --fixed-fps $Fps -- --demo
    if ($LASTEXITCODE -ne 0) { Write-Error "Godot の録画が失敗しました (exit $LASTEXITCODE)" }
} finally {
    Remove-Item -ErrorAction SilentlyContinue $override
}
if (-not (Test-Path $avi)) { Write-Error "録画ファイルが生成されませんでした: $avi" }

$ffmpeg = Get-Command ffmpeg -ErrorAction SilentlyContinue
if ($null -eq $ffmpeg) {
    Write-Host ""
    Write-Host "ffmpeg が無いため MP4 変換をスキップしました。録画は AVI のまま:"
    Write-Host "  $avi"
    Write-Host "MP4 が必要なら 'winget install Gyan.FFmpeg' 後に再実行するか、手動で:"
    Write-Host "  ffmpeg -i `"$avi`" -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p -c:a aac -b:a 192k `"$mp4`""
    exit 0
}

Write-Host "MP4 へ変換中..."
& ffmpeg -y -loglevel warning -i $avi `
    -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p `
    -c:a aac -b:a 192k -movflags +faststart $mp4
if ($LASTEXITCODE -ne 0) { Write-Error "ffmpeg の変換が失敗しました" }
Remove-Item $avi
Write-Host ""
Write-Host "完成: $mp4"
