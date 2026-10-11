<#
.SYNOPSIS
    One-time setup of the offline test toolchain: Lua 5.1 + LuaRocks + busted.

.DESCRIPTION
    Builds Lua 5.1.5 (the language version WoW uses) and LuaRocks with hererocks,
    then installs busted. Everything lands in -Prefix (default:
    %LOCALAPPDATA%\LooserPiml\lua51), never in the repo or the game folder.

    Prerequisites (install once):
        winget install --id BrechtSanders.WinLibs.POSIX.UCRT --exact   # MinGW-w64 GCC
        python -m pip install --user hererocks

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\setup-test-env.ps1
#>
param(
    [string]$Prefix = (Join-Path $env:LOCALAPPDATA 'LooserPiml\lua51')
)

$ErrorActionPreference = 'Stop'

function Find-Gcc {
    $cmd = Get-Command gcc.exe -ErrorAction SilentlyContinue
    if ($cmd) { return Split-Path -Parent $cmd.Source }
    $wingetPackages = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
    $gcc = Get-ChildItem $wingetPackages -Recurse -Filter gcc.exe -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -like '*WinLibs*\mingw64\bin\gcc.exe' } |
        Select-Object -First 1
    if ($gcc) { return Split-Path -Parent $gcc.FullName }
    return $null
}

$gccDir = Find-Gcc
if (-not $gccDir) {
    throw 'gcc not found. Install it with: winget install --id BrechtSanders.WinLibs.POSIX.UCRT --exact'
}
# hererocks and luarocks call gcc directly, so it must be on PATH for this process.
$env:PATH = "$gccDir;$env:PATH"
# hererocks runs LuaRocks' install.bat from the current directory; some shells set
# this variable, which stops Windows from finding it there. Process scope only.
$env:NoDefaultCurrentDirectoryInExePath = $null
Write-Host "Using gcc from $gccDir"

python -m hererocks --version | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw 'hererocks not found. Install it with: python -m pip install --user hererocks'
}

Write-Host "Building Lua 5.1 + LuaRocks into $Prefix ..."
python -m hererocks $Prefix --lua 5.1 --luarocks latest --target mingw
if ($LASTEXITCODE -ne 0) { throw 'hererocks failed' }

# LuaRocks 3.8 assumes the old MSVCR80 runtime for MinGW, but WinLibs (UCRT)
# builds Lua against the Universal CRT. Mixing them makes C rocks (lfs, ...)
# fail to load with "module not found", so link C rocks against ucrt too.
$config = Join-Path $Prefix 'luarocks\config-5.1.lua'
(Get-Content $config) -replace "MSVCRT = '[^']*'", "MSVCRT = 'ucrt'" | Set-Content -Encoding ascii $config

$luarocks = Join-Path $Prefix 'bin\luarocks.bat'
Write-Host 'Installing busted ...'
& $luarocks install busted
if ($LASTEXITCODE -ne 0) { throw 'luarocks install busted failed' }
& (Join-Path $Prefix 'bin\lua.exe') -e "require('lfs'); require('system'); require('term.core')"
if ($LASTEXITCODE -ne 0) { throw 'busted C modules do not load' }

Write-Host ''
Write-Host "Done. Run the tests with: powershell -ExecutionPolicy Bypass -File tools\run-tests.ps1"
