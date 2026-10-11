<#
.SYNOPSIS
    Links this repository into the game's AddOns folder with a directory
    junction (no admin rights needed), so edits show up after /reload.

.DESCRIPTION
    Creates  <WowClient>\Interface\AddOns\LooserPiml  ->  <this repo>
    Equivalent to: mklink /J "<WowClient>\Interface\AddOns\LooserPiml" "<repo>"

    Safety: never deletes or overwrites anything. If a real LooserPiml folder
    (e.g. a WowUp install) or a junction to somewhere else is in the way, it
    stops and tells you. -Remove only ever removes the junction itself, never
    the files it points to.

    Do not also install LooserPiml via WowUp on the same client while the
    junction exists.

.PARAMETER WowClient
    The client folder (the one containing the Wow*.exe and Interface\).
    WoW: Forever beta: "<WoW>\_classic_beta_" (TODO(verify): folder name at launch).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\link-addon.ps1
    powershell -ExecutionPolicy Bypass -File tools\link-addon.ps1 -WowClient "D:\Games\World of Warcraft\_classic_beta_"
    powershell -ExecutionPolicy Bypass -File tools\link-addon.ps1 -Remove
#>
param(
    [string]$WowClient = 'C:\Program Files (x86)\World of Warcraft\_classic_beta_',
    [switch]$Remove
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Split-Path -Parent $PSScriptRoot)).Path
$addonName = 'LooserPiml'

if (-not (Test-Path (Join-Path $WowClient 'Interface'))) {
    throw "'$WowClient' does not look like a WoW client folder (no Interface\ inside)."
}
if (-not (Get-ChildItem $WowClient -Filter 'Wow*.exe' -File)) {
    throw "'$WowClient' contains no Wow*.exe - wrong folder?"
}

$addons = Join-Path $WowClient 'Interface\AddOns'
$link = Join-Path $addons $addonName

function Get-JunctionTarget([string]$path) {
    $item = Get-Item -LiteralPath $path -Force
    if ($item.LinkType -ne 'Junction') { return $null }
    return @($item.Target)[0]
}

if ($Remove) {
    if (-not (Test-Path -LiteralPath $link)) {
        Write-Host "Nothing to remove: $link does not exist."
        return
    }
    if (-not (Get-JunctionTarget $link)) {
        throw "$link is a real folder, not a junction. Not touching it."
    }
    # Directory.Delete without recursion removes only the junction, never the repo.
    [System.IO.Directory]::Delete($link, $false)
    Write-Host "Removed junction $link"
    return
}

if (-not (Test-Path -LiteralPath $addons)) {
    New-Item -ItemType Directory -Path $addons | Out-Null
    Write-Host "Created $addons"
}

if (Test-Path -LiteralPath $link) {
    $target = Get-JunctionTarget $link
    if (-not $target) {
        throw "$link already exists as a real folder (WowUp or manual install?). Remove or rename it yourself, then run this again."
    }
    if ((Resolve-Path $target).Path -eq $repo) {
        Write-Host "Already linked: $link -> $repo"
        return
    }
    throw "$link is a junction to '$target', not to this repo. Remove it with -Remove first."
}

New-Item -ItemType Junction -Path $link -Target $repo | Out-Null
Write-Host "Linked $link -> $repo"
Write-Host 'Fetch the libraries once with tools\fetch-libs.ps1, then start the game (or /reload).'
