# Makes one Setup file for the Steam Frame port's Meteor:
#   target\frame-installer\Nightfall-Meteor-<version>-SteamFrame-Setup-x64.exe
#
# It is upstream's own installer (tools\windows-release\Meteor.iss, Inno
# Setup) with this port's nightfall-meteor.exe in it. It installs to the same
# place under the same name as upstream's Meteor, so either one installs over
# the other and a PC only ever has one: they use the same ports and settings.
#
# Everything but the exe is taken from the Meteor 0.9 installed on this PC:
# the FFmpeg and ncnn libraries, the depth model, the bundled host and the
# PCVR runtime, which this port doesn't change and which upstream's release
# build makes from inputs this PC doesn't have.
#
# NOTHING PERSONAL GOES IN. The installed folder also holds this PC's own
# host settings, pairing keys, session history and logs (runtime\host\config).
# So nothing is copied by folder: the bundled host and runtime are copied
# file by file from upstream's own list (runtime\manifest.json), each checked
# against the size and SHA-256 that list gives; the rest is a fixed list of
# names. Before the installer is made, the staged copy is searched once more
# for anything that looks like settings, keys or logs, and the script stops
# if it finds any.
#
# Needs: upstream's Nightfall Meteor 0.9.0 installed, Rust (as for
# build_meteor_fix.ps1), and Inno Setup 7:
#   winget install --id JRSoftware.InnoSetup.7 -e -s winget
#
# Run from PowerShell, in this "meteor" folder:
#   powershell -ExecutionPolicy Bypass -File .\tools\build_frame_installer.ps1
#
# It installs nothing and replaces nothing on this PC.

$ErrorActionPreference = 'Stop'
$meteor = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$repo = (Resolve-Path (Join-Path $meteor '..')).Path
$version = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'frame-version.txt') -Raw).Trim()
$out = Join-Path $meteor 'target\frame-installer'
$stage = Join-Path $out 'stage'
$name = "Nightfall-Meteor-$version-SteamFrame-Setup-x64"

# 1. What is needed, checked before the long part.
$compiler = Get-Command ISCC.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1
if (-not $compiler) {
    foreach ($candidate in @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 7\ISCC.exe'),
        (Join-Path $env:ProgramFiles 'Inno Setup 7\ISCC.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 7\ISCC.exe')
    )) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { $compiler = $candidate; break }
    }
}
if (-not $compiler) {
    throw "Inno Setup 7 is not installed. Install it with this line, then run this script again:`n  winget install --id JRSoftware.InnoSetup.7 -e -s winget"
}
$installed = Join-Path $env:LOCALAPPDATA 'Programs\Nightfall Meteor'
$manifestFile = Join-Path $installed 'runtime\manifest.json'
if (-not (Test-Path -LiteralPath $manifestFile -PathType Leaf)) {
    throw "Upstream's Nightfall Meteor 0.9 is not installed in $installed (no runtime\manifest.json). Install it with its own installer first."
}
$licence = Join-Path $repo 'LICENSE'
if (-not (Test-Path -LiteralPath $licence -PathType Leaf)) { throw "Missing $licence (Nightfall's licence, shown by the installer)" }

# 2. The exe, built the same way as always.
& (Join-Path $PSScriptRoot 'build_meteor_fix.ps1') -BuildOnly
if ($LASTEXITCODE -ne 0) { throw "The build did not finish ($LASTEXITCODE)" }
$built = Join-Path $meteor 'target\release\nightfall-meteor.exe'
if (-not (Test-Path -LiteralPath $built -PathType Leaf)) { throw "Missing $built" }

# 3. A clean copy to make the installer from.
if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
New-Item -ItemType Directory -Path $stage -Force | Out-Null
Copy-Item -LiteralPath $built -Destination $stage

# Libraries the installer put beside the exe: fixed names, as Meteor.iss
# lists them.
$libraries = @('ncnn.dll', 'avcodec-62.dll', 'avutil-60.dll', 'swscale-9.dll', 'swresample-6.dll', 'meteor_vda_vulkan.dll')
foreach ($file in $libraries) {
    $source = Join-Path $installed $file
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "The installed Meteor is missing $file" }
    Copy-Item -LiteralPath $source -Destination $stage
}
foreach ($pattern in @('msvcp*.dll', 'vcruntime*.dll', 'vccorlib*.dll', 'concrt*.dll', 'vcomp*.dll')) {
    $found = @(Get-ChildItem -Path (Join-Path $installed $pattern) -File)
    if (-not $found.Count) { throw "The installed Meteor has no $pattern" }
    $found | Copy-Item -Destination $stage
}
# The helper scripts and the readme come from this source, not the install.
$scripts = @('README.txt', 'Setup-Meteor.ps1', 'Meteor-Cli.ps1', 'Pair-Headset.ps1', 'Install-SteamVR.ps1', 'SteamVR-Driver.ps1', 'Install-VirtualDisplay.ps1', 'Firewall-Meteor.ps1')
foreach ($file in $scripts) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot "windows-release\$file") -Destination $stage
}
# Licence texts and the depth model. Meteor writes nothing below "share":
# what it downloads or learns goes to its own folder in AppData.
$doc = Join-Path $installed 'share\doc\nightfall-meteor'
foreach ($file in @('LICENSE', 'FFmpeg-LICENSE.txt', 'THIRD_PARTY_NOTICES.txt')) {
    if (-not (Test-Path -LiteralPath (Join-Path $doc $file) -PathType Leaf)) { throw "The installed Meteor is missing share\doc\nightfall-meteor\$file" }
}
New-Item -ItemType Directory -Path (Join-Path $stage 'share\doc') -Force | Out-Null
Copy-Item -LiteralPath $doc -Destination (Join-Path $stage 'share\doc') -Recurse
$models = Join-Path $stage 'share\nightfall-meteor\models'
New-Item -ItemType Directory -Path $models -Force | Out-Null
$modelFiles = @(Get-ChildItem -Path (Join-Path $installed 'share\nightfall-meteor\models') -File | Where-Object { $_.Name -match '\.ncnn\.(param|bin)$' })
if (-not $modelFiles.Count) { throw 'The installed Meteor has no depth model in share\nightfall-meteor\models' }
$modelFiles | Copy-Item -Destination $models

# The bundled host and the PCVR runtime: only what upstream's list names,
# and only if it is byte for byte what upstream shipped.
Write-Host 'Checking the bundled host and runtime against upstream''s list...'
$manifest = Get-Content -LiteralPath $manifestFile -Raw | ConvertFrom-Json
$runtime = Join-Path $installed 'runtime'
$stageRuntime = Join-Path $stage 'runtime'
New-Item -ItemType Directory -Path $stageRuntime -Force | Out-Null
Copy-Item -LiteralPath $manifestFile -Destination $stageRuntime
$count = 0
foreach ($entry in $manifest.files) {
    $relative = ([string]$entry.path) -replace '/', '\'
    if ($relative -match '(^|\\)\.\.(\\|$)' -or [IO.Path]::IsPathRooted($relative)) { throw "Unexpected path in the list: $($entry.path)" }
    $source = Join-Path $runtime $relative
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "The installed Meteor is missing runtime\$relative" }
    $item = Get-Item -LiteralPath $source
    if ($item.Length -ne [int64]$entry.bytes) { throw "runtime\$relative is not the file upstream shipped (its size differs). Reinstall upstream's Meteor 0.9.0 and run this again." }
    $hash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($hash -ne ([string]$entry.sha256).ToLowerInvariant()) { throw "runtime\$relative is not the file upstream shipped (its SHA-256 differs). Reinstall upstream's Meteor 0.9.0 and run this again." }
    $target = Join-Path $stageRuntime $relative
    New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $target
    $count++
}
Write-Host "  $count files, all as upstream shipped them."

# 4. The last look: nothing of this PC's own in the copy.
$personal = @(Get-ChildItem -LiteralPath $stage -Recurse -File | Where-Object {
    $_.FullName.Substring($stage.Length) -match '\\config\\|credentials|\.pem$|\.key$|\.log(\.\d+)?$|\.db(-wal|-shm)?$|\.bak$|\.sf\d+$|\\unins'
})
if ($personal.Count) {
    $personal | ForEach-Object { Write-Host "  $($_.FullName.Substring($stage.Length))" }
    throw 'Stopped: the files above look like settings, keys or logs and must not go into an installer. Nothing was made.'
}
$staged = @(Get-ChildItem -LiteralPath $stage -Recurse -File)
Write-Host "Staged $($staged.Count) files, $([math]::Round(($staged | Measure-Object Length -Sum).Sum / 1MB)) MB."

# The account's folder name in none of the files that are this port's own
# (the exe was checked when it was built; this covers the scripts and the
# readme beside it). Upstream's files were checked byte for byte above.
$account = Split-Path $env:USERPROFILE -Leaf
foreach ($file in @(Get-ChildItem -LiteralPath $stage -File)) {
    if ($file.Length -gt 64MB) { continue }
    $text = [Text.Encoding]::GetEncoding(28591).GetString([IO.File]::ReadAllBytes($file.FullName))
    if ($text -match [regex]::Escape("Users\$account") -or $text -match [regex]::Escape("Users/$account")) {
        throw "Stopped: $($file.Name) holds this PC's account folder name. Nothing was made."
    }
}

# 5. The installer.
Write-Host 'Compiling the installer (a few minutes)...'
# The port's own page, so that questions about it don't go to upstream's.
& $compiler "/DAppVersion=$version" "/DStage=$stage" "/DRepoRoot=$repo" "/DOutput=$out" "/DOutputName=$name" `
    '/DPublisher=Nightfall for Steam Frame (unofficial port)' `
    '/DPublisherURL=https://github.com/Wrexlax/nightfall' `
    '/DSupportURL=https://github.com/Wrexlax/nightfall/issues' `
    (Join-Path $PSScriptRoot 'windows-release\Meteor.iss')
if ($LASTEXITCODE -ne 0) { throw "Inno Setup failed ($LASTEXITCODE)" }
$installer = Join-Path $out "$name.exe"
if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) { throw "Missing $installer" }
$hash = (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Host ''
Write-Host "Made: $installer ($([math]::Round((Get-Item -LiteralPath $installer).Length / 1MB, 1)) MB)"
Write-Host "SHA-256 $hash"
# The same line as a file beside it, in the form SHA256SUMS.txt takes.
Set-Content -LiteralPath (Join-Path $out "$name.sha256.txt") -Value "$hash  $name.exe" -Encoding ascii
Write-Host 'Nothing on this PC was installed or replaced.'
