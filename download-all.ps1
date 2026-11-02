# Interactive Moodle course-archiver downloader.
# Downloads the .mbz files listed on the list page you currently have open in Brave.
# Run it again on each page you want.

$ErrorActionPreference = "Stop"
$site    = "https://cegepth.moodle.decclic.qc.ca"
$listUrl = "$site/admin/tool/coursearchiver/archivelist.php"
$outDir  = $PSScriptRoot
$links   = Join-Path $PSScriptRoot "links.txt"

function Step($n, $text) { Write-Host "`n=== STEP $n : $text ===" -ForegroundColor Cyan }

# ---------------------------------------------------------------- STEP 1: links of THIS page
Step 1 "Get the links of the page you have open"
$snippet = @'
(() => {
  const urls = [...new Set([...document.querySelectorAll('a[href]')]
    .map(a => a.href).filter(h => /restorefile\.php.*download=1/.test(h)))];
  const a = document.createElement('a');
  a.href = URL.createObjectURL(new Blob([urls.join('\n')], {type: 'text/plain'}));
  a.download = 'links.txt'; a.click();
  console.log('LINKS ON THIS PAGE: ' + urls.length);
})();
'@
Set-Clipboard -Value $snippet
Write-Host "The console snippet has been COPIED to your clipboard."
Write-Host "  1. In Brave, go to the list page you want ($listUrl), e.g. page 3."
Write-Host "  2. Press F12 > 'Console' tab > paste (Ctrl+V) > Enter."
Write-Host "     (If Brave blocks pasting: type  allow pasting  + Enter, then paste again.)"
Write-Host "  3. The console shows 'LINKS ON THIS PAGE: N' and saves links.txt."
[void](Read-Host "Press Enter here when done")

if (-not (Test-Path $links)) {
    Write-Host "links.txt not found next to the script ($links)." -ForegroundColor Red
    exit
}
Write-Host "Using $links (last modified $((Get-Item $links).LastWriteTime))"

$urls = @(Get-Content $links | Where-Object { $_ -match 'restorefile\.php\?.*download=1' } | Select-Object -Unique)
if ($urls.Count -eq 0) { Write-Host "No download links in links.txt." -ForegroundColor Red; exit }
Write-Host "`nThis page: $($urls.Count) files." -ForegroundColor Green

# ---------------------------------------------------------------- STEP 2: cookie
function Get-Cookie {
    Step 2 "MoodleSession cookie"
    Write-Host "  1. In Brave, on the Moodle site, press F12 > 'Application' tab."
    Write-Host "  2. Left side: Storage > Cookies > $site"
    Write-Host "  3. Find the row MoodleSessioncegepth : copy its Value."
    $name = "MoodleSessioncegepth"
    while ($true) {
        $v = (Read-Host "Paste the VALUE of $name").Trim().Trim('"')
        if (-not $v) { continue }
        $c = "$name=$v"
        $res = & curl.exe -L -s -o NUL -w "%{http_code} %{url_effective}" -b $c $listUrl
        if ($res -match '^200 ' -and $res -notmatch 'login') {
            Write-Host "Cookie works." -ForegroundColor Green
            return $c
        }
        Write-Host "Cookie rejected (got: $res). Copy it again - make sure you are still logged in." -ForegroundColor Yellow
    }
}
$cookie = Get-Cookie

# ---------------------------------------------------------------- STEP 3: download
Step 3 "Downloading $($urls.Count) files into $outDir"
$failed = New-Object System.Collections.ArrayList
$consecutive = 0
$i = 0
foreach ($url in $urls) {
    $i++
    $fn = ([System.Uri]$url).Query.TrimStart('?') -split '&' | Where-Object { $_ -like 'filename=*' }
    $name = [System.Uri]::UnescapeDataString(($fn -replace '^filename=', ''))
    $name = $name -replace '[\\/:*?"<>|]', '_'
    $dest = Join-Path $outDir $name
    if (Test-Path $dest) { Write-Host "[$i/$($urls.Count)] skip (exists) $name"; $consecutive = 0; continue }
    Write-Host "[$i/$($urls.Count)] $name"

    $ok = $false
    for ($try = 1; $try -le 2 -and -not $ok; $try++) {
        & curl.exe -L -sS --fail --retry 5 --retry-delay 5 -b $cookie -o "$dest.part" $url
        if ($LASTEXITCODE -eq 0 -and (Test-Path "$dest.part") -and (Get-Item "$dest.part").Length -gt 0) {
            # a real .mbz is gzip (1F 8B); an HTML login page means the session expired
            $b = [System.IO.File]::OpenRead("$dest.part"); $h1 = $b.ReadByte(); $h2 = $b.ReadByte(); $b.Close()
            if ($h1 -eq 0x1F -and $h2 -eq 0x8B) { Move-Item "$dest.part" $dest; $ok = $true }
        }
        if (-not $ok) { Remove-Item "$dest.part" -ErrorAction SilentlyContinue }
    }
    if ($ok) { $consecutive = 0; continue }

    Write-Host "   FAILED" -ForegroundColor Red
    [void]$failed.Add($url)
    $consecutive++
    if ($consecutive -ge 3) {
        Write-Host "`n3 failures in a row - your session probably expired." -ForegroundColor Yellow
        $cookie = Get-Cookie
        $consecutive = 0
    }
}

# ---------------------------------------------------------------- summary
$onDisk = 0
foreach ($url in $urls) {
    $fn = ([System.Uri]$url).Query.TrimStart('?') -split '&' | Where-Object { $_ -like 'filename=*' }
    $n = ([System.Uri]::UnescapeDataString(($fn -replace '^filename=', ''))) -replace '[\\/:*?"<>|]', '_'
    if (Test-Path (Join-Path $outDir $n)) { $onDisk++ }
}
Write-Host "`nThis page: expected $($urls.Count), on disk $onDisk, failed $($failed.Count)" -ForegroundColor Cyan
if ($failed.Count) {
    $failed | Set-Content (Join-Path $outDir "failed.txt")
    Write-Host "Failed URLs saved to failed.txt. Re-run on this same page: files already downloaded are skipped."
}
