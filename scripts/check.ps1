# Runs every local check: Rojo build, StyLua, Selene, luau-lsp type analysis and Lune unit tests.
# Usage (from the repository root):  powershell -ExecutionPolicy Bypass -File scripts/check.ps1
$ErrorActionPreference = "Continue"
$env:PATH = "$env:USERPROFILE\.rokit\bin;$env:PATH"
Set-Location (Split-Path $PSScriptRoot -Parent)
$failed = @()

function Step($name, [scriptblock]$block) {
    Write-Host "== $name" -ForegroundColor Cyan
    & $block
    if ($LASTEXITCODE -ne 0) { $script:failed += $name; Write-Host "FAILED: $name" -ForegroundColor Red }
}

Step "rojo build" { New-Item -ItemType Directory -Force build | Out-Null; rojo build default.project.json -o build/Hexland.rbxl }
Step "stylua --check" { stylua --check src tests }
Step "selene" { selene src tests }
Step "luau-lsp analyze" {
    if (-not (Test-Path .luau-defs/globalTypes.d.luau)) {
        New-Item -ItemType Directory -Force .luau-defs | Out-Null
        curl.exe -sSL -o .luau-defs/globalTypes.d.luau https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.None.d.luau
    }
    rojo sourcemap default.project.json -o sourcemap.json | Out-Null
    $out = & luau-lsp analyze --platform=roblox --sourcemap=sourcemap.json --definitions=@roblox=.luau-defs/globalTypes.d.luau src 2>&1 |
        ForEach-Object { "$_" } | Where-Object { $_ -match 'Error' }
    $out | Sort-Object -Unique | ForEach-Object { Write-Host $_ }
    $global:LASTEXITCODE = if ($out) { 1 } else { 0 }
}
Step "lune unit tests" { lune run tests/run }

if ($failed.Count -gt 0) { Write-Host "`nFailed: $($failed -join ', ')" -ForegroundColor Red; exit 1 }
Write-Host "`nAll checks passed" -ForegroundColor Green
