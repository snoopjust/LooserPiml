<#
.SYNOPSIS
    Fetches the embedded libraries into Libs\ for local development and tests.

.DESCRIPTION
    Release zips get the same libraries through the .pkgmeta externals
    (BigWigsMods/packager). Keep the tags here in sync with .pkgmeta.
    Libs\ is gitignored.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\fetch-libs.ps1
#>
param(
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$libsDir = Join-Path $root 'Libs'

# Keep in sync with .pkgmeta
$sources = @(
    @{
        Repo = 'https://github.com/WoWUIDev/Ace3'
        Tag  = 'Release-r1403'
        # source subfolder -> Libs\<target>
        Dirs = [ordered]@{
            'LibStub'             = 'LibStub'
            'CallbackHandler-1.0' = 'CallbackHandler-1.0'
            'AceComm-3.0'         = 'AceComm-3.0'
            'AceSerializer-3.0'   = 'AceSerializer-3.0'
        }
    },
    @{
        Repo  = 'https://github.com/SafeteeWoW/LibDeflate'
        Tag   = '1.0.2-release'
        Dirs  = [ordered]@{ '.' = 'LibDeflate' }
        # The repo root also holds tests and docs; only ship what the addon loads.
        Files = @('LibDeflate.lua', 'lib.xml', 'LICENSE.txt')
    },
    @{
        Repo  = 'https://github.com/tekkub/libdatabroker-1-1'
        Tag   = 'v1.1.4'
        Dirs  = [ordered]@{ '.' = 'LibDataBroker-1.1' }
        Files = @('LibDataBroker-1.1.lua')
    },
    @{
        # LibDBIcon lives in the WoWAce Subversion repository. SVN serves
        # files over plain HTTPS, so no svn client is needed for local dev
        # (the release packager does a real svn checkout of the same tag).
        Url   = 'https://repos.wowace.com/wow/libdbicon-1-0/tags/v12.1.1/LibDBIcon-1.0'
        Tag   = 'v12.1.1'
        Dirs  = [ordered]@{ '.' = 'LibDBIcon-1.0' }
        Files = @('LibDBIcon-1.0.lua', 'lib.xml')
    }
)

if ((Test-Path $libsDir) -and -not $Force) {
    $missing = foreach ($src in $sources) {
        foreach ($target in $src.Dirs.Values) {
            if (-not (Test-Path (Join-Path $libsDir $target))) { $target }
        }
    }
    if (-not $missing) {
        Write-Host 'Libs already present. Use -Force to re-fetch.'
        return
    }
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("LooserPiml-libs-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
New-Item -ItemType Directory -Force -Path $libsDir | Out-Null

try {
    $i = 0
    foreach ($src in $sources) {
        $i++
        $checkout = Join-Path $tmp "src$i"
        if ($src.Url) {
            Write-Host "Downloading $($src.Url)"
            New-Item -ItemType Directory -Path $checkout | Out-Null
            foreach ($file in $src.Files) {
                Invoke-WebRequest -UseBasicParsing -Uri "$($src.Url)/$file" -OutFile (Join-Path $checkout $file)
            }
        }
        else {
            Write-Host "Cloning $($src.Repo) @ $($src.Tag)"
            git -c advice.detachedHead=false clone --quiet --depth 1 --branch $src.Tag $src.Repo $checkout
            if ($LASTEXITCODE -ne 0) { throw "git clone failed for $($src.Repo)" }
        }

        foreach ($entry in $src.Dirs.GetEnumerator()) {
            $from = if ($entry.Key -eq '.') { $checkout } else { Join-Path $checkout $entry.Key }
            $to = Join-Path $libsDir $entry.Value
            if (Test-Path $to) { Remove-Item -Recurse -Force $to }
            New-Item -ItemType Directory -Path $to | Out-Null
            if ($src.Files) {
                foreach ($file in $src.Files) { Copy-Item (Join-Path $from $file) -Destination $to }
            }
            else {
                # Copy everything except VCS metadata
                Get-ChildItem -Force $from | Where-Object { $_.Name -notin @('.git', '.github') } |
                    Copy-Item -Destination $to -Recurse -Force
            }
            Write-Host "  -> Libs\$($entry.Value)"
        }
    }
}
finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

Write-Host 'Done.'
