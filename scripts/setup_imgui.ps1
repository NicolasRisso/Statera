# Fetches and builds the Odin Dear ImGui bindings (docking branch) into vendor/imgui.
# Requires: git, python, Visual Studio 2022 C++ tools.
$ErrorActionPreference = 'Stop'

$root   = Split-Path $PSScriptRoot -Parent
$dest   = Join-Path $root 'vendor\imgui'
$commit = 'a116eb1ceaa6acde60219efdd56bf6c2e1aedf4c'  # gitlab.com/L-4/odin-imgui, imgui v1.92.8-docking

if (-not (Test-Path $dest)) {
    git clone --quiet https://gitlab.com/L-4/odin-imgui.git $dest
}
git -C $dest fetch --quiet origin
git -C $dest checkout --quiet $commit

# Only build the backends we use.
$build = Join-Path $dest 'build.py'
(Get-Content $build -Raw) -replace '(?s)wanted_backends = \[.*?\]', 'wanted_backends = ["sdl3", "opengl3"]' |
    Set-Content $build -NoNewline

$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
$vcvars = Join-Path $vs 'VC\Auxiliary\Build\vcvars64.bat'

cmd /c "`"$vcvars`" >nul && cd /d `"$dest`" && python build.py"
if ($LASTEXITCODE -ne 0) { throw "imgui build failed ($LASTEXITCODE)" }
Write-Host "imgui ready at $dest"
