#Requires -Version 5.1
<#
.SYNOPSIS
    Build every atlas-seed skeleton (or palette/card) into its own subdir of
    _previews/ and serve the whole lot on http://localhost:4000/.

.EXAMPLE
    .\serve.ps1
    # builds s1..s6 previews, then serves at http://localhost:4000/

.EXAMPLE
    .\serve.ps1 -Sweep palettes

.EXAMPLE
    .\serve.ps1 -Sweep cards -Port 8080
#>
[CmdletBinding()]
param(
    [ValidateSet('skeletons', 'palettes', 'cards')]
    [string]$Sweep = 'skeletons',
    [int]$Port = 4000
)

$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot

try {
    $variants = @{
        skeletons = @('s1','s2','s3','s4','s5','s6')
        palettes  = @('rust','paper','cartography','midnight','minimal','fieldnotes','solarized','nord')
        cards     = @('v1','v2','v3','v4','v5','v6','v7')
    }
    $configKey = @{ skeletons = 'skeleton'; palettes = 'palette'; cards = 'card' }[$Sweep]
    $prefix    = @{ skeletons = '';         palettes = 'pal-';    cards = 'card-' }[$Sweep]
    $names = @{
        s1='Hero + footer'; s2='Top bar + footer'; s3='Top bar + sidenav'
        s4='Split hero';    s5='Magazine cover';   s6='Terminal frame'
        rust='Warm rust';   paper='Paper & ink';   cartography='Cartography'
        midnight='Midnight'; minimal='Minimal';    fieldnotes='Field notes'
        solarized='Solarized'; nord='Nord'
        v1='Image-top';     v2='Horizontal';       v3='Hero overlay'
        v4='Terminal';      v5='Index card';       v6='No-image'; v7='Compact row'
    }

    $configPath  = Join-Path $PSScriptRoot '_config.yml'
    $previewsDir = Join-Path $PSScriptRoot '_previews'

    $origConfig = Get-Content $configPath -Raw

    if (Test-Path $previewsDir) {
        Write-Host "Cleaning $previewsDir..."
        Remove-Item $previewsDir -Recurse -Force
    }

    try {
        foreach ($v in $variants[$Sweep]) {
            Write-Host "Building $configKey=$v ..." -ForegroundColor Cyan

            (Get-Content $configPath) | ForEach-Object {
                if ($_ -match "^$configKey\s*:") { "${configKey}: $v" } else { $_ }
            } | Set-Content $configPath

            $dest = "_previews/$prefix$v"
            $base = "/$prefix$v"
            docker run --rm -v "${pwd}:/srv/jekyll" jekyll/jekyll:4 `
                jekyll build -d $dest --baseurl $base 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "jekyll build failed for $v (exit $LASTEXITCODE)" }
            Write-Host "  done: $v"
        }

        $sb = [System.Text.StringBuilder]::new()
        [void]$sb.AppendLine('<!doctype html><meta charset=utf-8>')
        [void]$sb.AppendLine("<title>Atlas seed - $Sweep previews</title>")
        [void]$sb.AppendLine('<style>body{font-family:system-ui;padding:2rem;max-width:560px;margin:auto}h1{margin:0 0 1rem}a{display:block;padding:.5rem .75rem;border:1px solid #ddd;border-radius:6px;margin:.25rem 0;text-decoration:none;color:#222}a:hover{background:#f5f5f5}small{color:#888;margin-left:.5rem}</style>')
        [void]$sb.AppendLine("<h1>Atlas seed - $Sweep previews</h1>")
        foreach ($v in $variants[$Sweep]) {
            $label = $names[$v]
            [void]$sb.AppendLine("<a href=`"/$prefix$v/`">$v<small>$label</small></a>")
        }
        Set-Content -Path (Join-Path $previewsDir 'index.html') -Value $sb.ToString()
    }
    finally {
        Set-Content -Path $configPath -Value $origConfig -NoNewline
    }

    Write-Host ""
    Write-Host "Serving http://localhost:$Port/  (Ctrl+C to stop)" -ForegroundColor Green

    Push-Location $previewsDir
    try {
        $pythonCmd = if (Get-Command py -ErrorAction SilentlyContinue) { 'py' } else { 'python' }
        & $pythonCmd -m http.server $Port
    }
    finally {
        Pop-Location
    }
}
finally {
    Pop-Location
}
