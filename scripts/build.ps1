# Builds the Statera desktop app into build/. Usage: scripts/build.ps1 [-Release] [-Version v0.1.0]
param([switch]$Release, [string]$Version = 'dev')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root
New-Item -ItemType Directory -Force build | Out-Null

$flags = @('-vet', '-strict-style', '-out:build/statera.exe', "-define:STATERA_VERSION=$Version",
    '-resource:assets/icon/statera.rc')
if ($Release) { $flags += @('-o:speed', '-subsystem:windows') } else { $flags += '-debug' }
odin build src/app @flags
if ($LASTEXITCODE -ne 0) { throw "build failed ($LASTEXITCODE)" }

$odinRoot = (odin root).Trim()
Copy-Item (Join-Path $odinRoot 'vendor/sdl3/SDL3.dll') build -Force
Write-Host 'built build/statera.exe'
