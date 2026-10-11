<#
.SYNOPSIS
    Runs the offline busted suite (spec\) under Lua 5.1.

.DESCRIPTION
    Needs the toolchain from tools\setup-test-env.ps1 and the libraries from
    tools\fetch-libs.ps1 (fetched automatically if missing).
    Extra arguments are passed to busted, e.g.:
        tools\run-tests.ps1 --filter="Comm"
        tools\run-tests.ps1 spec\ticker_spec.lua

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\run-tests.ps1
#>
# PositionalBinding off: positional arguments (spec files) go to busted,
# not into -Prefix.
[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$Prefix = (Join-Path $env:LOCALAPPDATA 'LooserPiml\lua51'),
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$BustedArgs
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

$busted = Join-Path $Prefix 'bin\busted.bat'
if (-not (Test-Path $busted)) {
    throw "busted not found in $Prefix. Run tools\setup-test-env.ps1 first."
}

if (-not (Test-Path (Join-Path $root 'Libs\AceComm-3.0'))) {
    Write-Host 'Libs missing, fetching them first ...'
    & (Join-Path $PSScriptRoot 'fetch-libs.ps1')
}

Push-Location $root
try {
    & $busted @BustedArgs
    $code = $LASTEXITCODE
}
finally {
    Pop-Location
}
exit $code
