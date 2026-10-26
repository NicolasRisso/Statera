# Push gate: run before every push. Exits non-zero on failure. See AGENTS.md §1.
$ErrorActionPreference = 'Continue'
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root
$failed = $false
New-Item -ItemType Directory -Force build | Out-Null

# 1-2. Check and test every Odin package under src/.
$packages = Get-ChildItem src -Recurse -Filter *.odin | ForEach-Object { $_.DirectoryName } | Sort-Object -Unique
foreach ($pkg in $packages) {
    $rel = Resolve-Path -Relative $pkg
    $hasMain = Select-String -Path "$pkg\*.odin" -Pattern '^main\s*::' -Quiet
    if ($hasMain) { odin check $rel -vet -strict-style } else { odin check $rel -no-entry-point -vet -strict-style }
    if ($LASTEXITCODE -ne 0) { Write-Host "FAIL check $rel"; $failed = $true; continue }
    if (Get-ChildItem $pkg -Filter *_test.odin) {
        $name = ($rel -replace '[\\/.]+', '_').Trim('_')
        odin test $rel -vet -strict-style "-out:build/test_$name.exe"
        if ($LASTEXITCODE -ne 0) { Write-Host "FAIL test $rel"; $failed = $true }
    }
}

# 4. Clean-room lint: tracked or staged files must not contain IBM material.
$files = git ls-files --cached
$forbidden = $files | Where-Object { $_ -match '\.(dll|jar|exe|so|dylib|xsd)$' -or $_ -match '(^|/)syntax_xml/' }
$ibmHeaders = git grep -l -I -e 'Licensed Materials - Property of IBM' -e '(C) Copyright IBM Corp' -- . ':!scripts/gate.*'
foreach ($f in @($forbidden) + @($ibmHeaders)) {
    if ($f) { Write-Host "FAIL clean-room: $f"; $failed = $true }
}

if ($failed) { Write-Host 'GATE FAILED'; exit 1 }
Write-Host 'GATE PASSED'
exit 0
