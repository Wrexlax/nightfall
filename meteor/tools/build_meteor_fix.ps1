# Builds nightfall-meteor.exe from this folder (upstream Meteor 0.9.0 plus the
# Steam Frame port's fixes) and swaps it into the Meteor installed on this PC.
# Upstream's own exe is kept next to it as nightfall-meteor.exe.bak, so it is
# easy to go back. It only swaps into a real 0.9 install: an older Meteor
# folder (0.1.x) is left alone.
#
# FIRST install upstream's own Meteor 0.9.0 for Windows (its installer brings
# the other files this exe needs: models, ncnn.dll, FFmpeg, the setup window).
# This script only replaces the one exe inside that install.
#
# Run from PowerShell, in this "meteor" folder:
#   powershell -ExecutionPolicy Bypass -File .\tools\build_meteor_fix.ps1
#
# Needs Rust 1.92 or newer (https://rustup.rs). rustup-init.exe offers to
# install the Visual Studio C++ build tools it needs; say yes.
#
# -BuildOnly builds the exe and stops there, touching nothing installed. The
# installer script (build_frame_installer.ps1) uses it.
param([switch]$BuildOnly)

$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)

# Windows' build tools stop at paths longer than 260 characters, and building
# the Opus library goes about 183 characters deep below this folder. A copy
# unpacked one folder deeper than usual failed that way on 2026-11-16, with
# "FileTracker : error FTK1011 ... The system cannot find the path specified",
# which says nothing about the cause. Say it here instead.
$here = (Get-Location).Path
if ($here.Length -gt 77) {
    throw "This folder's path is $($here.Length) characters long ($here). Windows' build tools need it to be 77 or fewer for this build. Move the folder somewhere shorter, for example C:\meteor-frame-src, and run this again from there."
}

if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
    $cargoBin = Join-Path $env:USERPROFILE '.cargo\bin'
    if (Test-Path (Join-Path $cargoBin 'cargo.exe')) { $env:Path = "$cargoBin;$env:Path" }
}
if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
    throw 'Rust is not installed. Install it from https://rustup.rs (run rustup-init.exe, accept the defaults), then open a new PowerShell window and run this again.'
}

# Upstream builds Meteor 0.9 with Rust 1.92; older compilers may refuse it.
$rustc = (& rustc --version) -join ' '
if ($rustc -match 'rustc (\d+)\.(\d+)') {
    if ([int]$Matches[1] -eq 1 -and [int]$Matches[2] -lt 92) {
        Write-Host "Rust is $rustc; Meteor 0.9 needs 1.92 or newer. Updating Rust..."
        & rustup update stable
        if ($LASTEXITCODE -ne 0) { throw "rustup update failed ($LASTEXITCODE)" }
    }
}

# What this build calls itself (tray menu, log, and what the headset sees):
# upstream's version plus the Steam Frame revision. Kept in one file, which
# the installer script reads too.
$version = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'frame-version.txt') -Raw).Trim()
if ($version -notmatch '^\d+\.\d+\.\d+-sf\d+$') { throw "tools\frame-version.txt should hold a version like 0.9.0-sf12, not '$version'" }
$env:METEOR_RELEASE_VERSION = $version

# The exe must not carry this PC's folder names. A program remembers where
# the source files it was built from lay (it prints them when something
# goes wrong), and the libraries Meteor is built from are downloaded into
# the account's own folder by default: an exe built that way held
# "C:\Users\<account name>\.cargo\..." 456 times (found 2026-11-18). So
# the downloads go to a folder with no name in it, and what the Rust
# compiler still knows of the account's folder is written as "~".
$neutral = Join-Path $env:PUBLIC 'nf-cargo'
New-Item -ItemType Directory -Path $neutral -Force | Out-Null
$env:CARGO_HOME = $neutral
$env:CARGO_ENCODED_RUSTFLAGS = "--remap-path-prefix=$($env:USERPROFILE)=~"

Write-Host 'Building Meteor (the first build downloads crates and takes several minutes)...'
& cargo build --release --locked --no-default-features
if ($LASTEXITCODE -ne 0) { throw "cargo build failed ($LASTEXITCODE)" }
$built = Join-Path (Get-Location) 'target\release\nightfall-meteor.exe'
if (-not (Test-Path $built)) { throw "Build finished but $built is missing" }

# Looked for rather than assumed: the account's folder name inside the exe.
$account = Split-Path $env:USERPROFILE -Leaf
$text = [Text.Encoding]::GetEncoding(28591).GetString([IO.File]::ReadAllBytes($built))
$named = [regex]::Matches($text, [regex]::Escape("Users\$account"), 'IgnoreCase').Count +
    [regex]::Matches($text, [regex]::Escape("Users/$account"), 'IgnoreCase').Count
$text = $null
if ($named -gt 0) {
    Write-Host "NOTE: this exe holds this PC's account folder name $named times. Fine for your own use; it must not be published." -ForegroundColor Yellow
    if ($BuildOnly) { throw "Stopped: the exe holds the account folder's name ($named times), so no installer is made from it. Tell the port's maintainer what this says." }
} else {
    Write-Host "Checked: the exe does not hold this PC's account folder name."
}
if ($BuildOnly) {
    Write-Host "Built Meteor ${version}: $built"
    exit 0
}

# Find upstream's Meteor 0.9 install. Its installer puts it in
# %LOCALAPPDATA%\Programs\Nightfall Meteor; a 0.9 folder is recognised by the
# FFmpeg library the installer ships next to the exe (0.1.x has none).
function Test-Meteor09([string]$exe) {
    return [bool]($exe -and (Test-Path $exe) -and (Test-Path (Join-Path (Split-Path $exe -Parent) 'avcodec-62.dll')))
}
$target = $null
$official = Join-Path $env:LOCALAPPDATA 'Programs\Nightfall Meteor\nightfall-meteor.exe'
$running = Get-Process -Name 'nightfall-meteor' -ErrorAction SilentlyContinue | Select-Object -First 1
$candidates = @($official)
if ($running -and $running.Path) { $candidates += $running.Path }
$candidates += @("$env:ProgramFiles\Nightfall Meteor\nightfall-meteor.exe", "$env:LOCALAPPDATA\Nightfall Meteor\nightfall-meteor.exe")
foreach ($candidate in $candidates) {
    if (Test-Meteor09 $candidate) { $target = $candidate; break }
}
if (-not $target) {
    Write-Host ''
    Write-Host "Built: $built"
    Write-Host ''
    Write-Host 'Nothing was replaced: upstream Meteor 0.9.0 is not installed on this PC.'
    if ($running -and $running.Path) {
        Write-Host "The Meteor running now is an older one: $($running.Path)"
        Write-Host 'Its folder does not have the files the 0.9 exe needs (FFmpeg, the 0.9 models, the setup window).'
    }
    Write-Host 'Install Nightfall Meteor 0.9.0 with its own installer (Nightfall-Meteor-0.9.0-Setup-x64.exe'
    Write-Host 'from the Nightfall releases page), then run this script again. It will not need to rebuild.'
    exit 0
}

Write-Host "Meteor 0.9 install found: $target"
if ($running -and $running.Path -and ($running.Path -ne $target)) {
    Write-Host "Note: a different Meteor is running now ($($running.Path)). It will be closed, and the 0.9 one started."
}
Write-Host ''
Write-Host '================================================================'
Write-Host ' The build worked. ONE STEP IS LEFT: putting the new Meteor in place.'
Write-Host '================================================================'
$answer = (Read-Host 'Replace the installed nightfall-meteor.exe with the one just built? Type YES and press Enter').Trim()
# "yes" and "y" count too: on 2026-11-17 this step was passed by, the old
# Meteor stayed installed, and the new exe was then started from the build
# folder, where it has no depth files and no host beside it.
if ($answer -notin @('YES', 'Y')) {
    Write-Host ''
    Write-Host 'NOTHING WAS REPLACED: the Meteor installed on this PC is still the old one.' -ForegroundColor Yellow
    Write-Host 'Run this script again and answer YES to put the new one in place (it will not rebuild).'
    Write-Host "Please do not start the new exe from its build folder ($built):"
    Write-Host 'there it has no depth files and no host beside it, so depth and the microphone do not work.'
    exit 0
}
# Close the running Meteor. One started by the installer can have administrator
# rights, and then this window is not allowed to close it.
$open = Get-Process -Name 'nightfall-meteor' -ErrorAction SilentlyContinue
if ($open) {
    try {
        $open | Stop-Process -Force -ErrorAction Stop
    } catch {
        Write-Host ''
        Write-Host 'Windows would not let this window close Meteor.'
        Write-Host "Please quit it yourself: right-click Meteor's icon by the clock and choose Quit."
        Read-Host 'Then press Enter here' | Out-Null
    }
    for ($i = 0; $i -lt 20 -and (Get-Process -Name 'nightfall-meteor' -ErrorAction SilentlyContinue); $i++) {
        Start-Sleep -Milliseconds 500
    }
    if (Get-Process -Name 'nightfall-meteor' -ErrorAction SilentlyContinue) {
        Write-Host 'Meteor is still running, so nothing was replaced. Quit Meteor and run this script again.'
        Write-Host "The new exe is here: $built"
        exit 1
    }
}
# Keep upstream's own exe as .bak; a second run must not overwrite it with ours.
if (-not (Test-Path "$target.bak")) { Copy-Item $target "$target.bak" }
Copy-Item $built $target -Force
Write-Host 'Replaced (the original is kept as nightfall-meteor.exe.bak). Starting Meteor...'
Start-Process $target
Write-Host "Done. The tray icon should come back; its menu title now says Nightfall Meteor $version."
