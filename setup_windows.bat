@echo off
rem ============================================================
rem  SHIBUYA RIFT - Windows 11 セットアップ (RTX 5080 推奨)
rem  1) Poly Haven から HDRI / PBR / 樹木・岩を自動取得
rem  2) PLATEAU 渋谷区 2025 CityGML を取得し渋谷駅周辺を OBJ 変換
rem ============================================================
setlocal
cd /d "%~dp0"

where py >nul 2>nul
if errorlevel 1 (
  echo [FAIL] Python が見つかりません。https://www.python.org/downloads/ から
  echo        Python 3.11+ をインストールしてください。
  pause
  exit /b 1
)

py -3 tools\run_all.py %*

echo.
echo 完了。次の手順:
echo   1. Godot 4.4.x を https://godotengine.org/download/windows/ から入手
echo   2. game\project.godot を開く (初回インポートに数分)
echo   3. F5 で実行 / デモ動画は: py -3 tools\make_demo_mp4.py --godot ^<Godot.exeのパス^>
pause
