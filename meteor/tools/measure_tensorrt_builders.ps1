# Measures NVIDIA's TensorRT "builder resource" files for Windows, so Meteor
# can offer the VDA (TensorRT) download on more graphics cards.
#
# Why: TensorRT needs one builder file per GPU generation (sm75 = RTX 20,
# sm86 = RTX 30, sm89 = RTX 40, sm120 = RTX 50, ...). Meteor only installs a
# file whose SHA-256 is pinned in meteor/src/download.rs, and for Windows only
# sm86 has been pinned. On any other card the tray says "No verified TensorRT
# download for this GPU".
#
# What this does: reads the same NVIDIA package Meteor downloads from
# (pypi.nvidia.com, over HTTPS, only the files asked for), unpacks each
# builder file, checks that Windows accepts NVIDIA's digital signature on it,
# and writes its name, SHA-256 and sizes as lines ready for download.rs.
# Nothing is installed and the unpacked files are deleted again.
#
# Run from PowerShell (no administrator rights needed):
#   powershell -ExecutionPolicy Bypass -File .\measure_tensorrt_builders.ps1
# Only one generation (about 250 MB instead of about 1.5 GB):
#   powershell -ExecutionPolicy Bypass -File .\measure_tensorrt_builders.ps1 -Only 120
#
# The result is written next to this script: tensorrt-builders-windows.txt

param(
    [string[]]$Only = @()
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# The same package and size as WHEEL_URL / WHEEL_SIZE in meteor/src/download.rs.
$Url = 'https://pypi.nvidia.com/tensorrt-cu13-libs/tensorrt_cu13_libs-10.16.1.11-py3-none-win_amd64.whl'
$WheelSize = [long]1911173812
$Work = Join-Path $env:TEMP 'meteor-tensorrt-builders'
$Result = Join-Path $PSScriptRoot 'tensorrt-builders-windows.txt'

function New-RangeRequest([long]$From, [long]$Length) {
    $request = [Net.HttpWebRequest]::Create($Url)
    $request.AddRange($From, $From + $Length - 1)
    $request.ReadWriteTimeout = 120000
    $request.UserAgent = 'nightfall-meteor-measure-tensorrt/1'
    return $request
}

# A small piece of the package, in memory.
function Get-Range([long]$From, [long]$Length) {
    $response = (New-RangeRequest $From $Length).GetResponse()
    try {
        if ([int]$response.StatusCode -ne 206) { throw "NVIDIA's server did not answer a partial request (status $([int]$response.StatusCode))" }
        $memory = New-Object IO.MemoryStream
        $response.GetResponseStream().CopyTo($memory)
        $bytes = $memory.ToArray()
    } finally { $response.Close() }
    if ($bytes.Length -ne $Length) { throw "Expected $Length bytes from NVIDIA's server, got $($bytes.Length)" }
    return ,$bytes
}

# A large piece of the package, to a file.
function Save-Range([long]$From, [long]$Length, [string]$Path, [string]$What) {
    $response = (New-RangeRequest $From $Length).GetResponse()
    try {
        if ([int]$response.StatusCode -ne 206) { throw "NVIDIA's server did not answer a partial request (status $([int]$response.StatusCode))" }
        $source = $response.GetResponseStream()
        $target = [IO.File]::Create($Path)
        try {
            $buffer = New-Object byte[] 1048576
            $done = [long]0
            $shown = -1
            while (($read = $source.Read($buffer, 0, $buffer.Length)) -gt 0) {
                $target.Write($buffer, 0, $read)
                $done += $read
                $percent = [int](100 * $done / $Length)
                if ($percent -ne $shown) {
                    $shown = $percent
                    Write-Progress -Activity "Downloading $What" -Status "$([int]($done / 1MB)) of $([int]($Length / 1MB)) MB" -PercentComplete $percent
                }
            }
        } finally { $target.Close() }
    } finally { $response.Close() }
    Write-Progress -Activity "Downloading $What" -Completed
    if ((Get-Item -LiteralPath $Path).Length -ne $Length) { throw "The download of $What stopped early. Run the script again." }
}

function Read-U16([byte[]]$Bytes, [int]$At) { return [BitConverter]::ToUInt16($Bytes, $At) }
function Read-U32([byte[]]$Bytes, [int]$At) { return [BitConverter]::ToUInt32($Bytes, $At) }
function Read-U64([byte[]]$Bytes, [int]$At) { return [BitConverter]::ToUInt64($Bytes, $At) }

# Where the last "PK" record with these two type bytes starts, or -1.
function Find-Last([byte[]]$Bytes, [int]$Third, [int]$Fourth) {
    for ($i = $Bytes.Length - 4; $i -ge 0; $i--) {
        if ($Bytes[$i] -eq 0x50 -and $Bytes[$i + 1] -eq 0x4B -and $Bytes[$i + 2] -eq $Third -and $Bytes[$i + 3] -eq $Fourth) { return $i }
    }
    return -1
}

function Format-Rust([long]$Number) {
    return $Number.ToString('N0', [Globalization.CultureInfo]::InvariantCulture).Replace(',', '_')
}

$Max32 = [uint32]::MaxValue

Write-Host "Reading the index of NVIDIA's TensorRT package..."
$tail = Get-Range ($WheelSize - 65536) 65536
$end = Find-Last $tail 0x05 0x06
if ($end -lt 0) { throw "NVIDIA's package has an unexpected layout (no end record). It may have been replaced by a newer one." }
$directorySize = [long](Read-U32 $tail ($end + 12))
$directoryAt = [long](Read-U32 $tail ($end + 16))
if ($directorySize -eq $Max32 -or $directoryAt -eq $Max32) {
    $end64 = Find-Last $tail 0x06 0x06
    if ($end64 -lt 0) { throw "NVIDIA's package has an unexpected layout (no zip64 record)." }
    $directorySize = [long](Read-U64 $tail ($end64 + 40))
    $directoryAt = [long](Read-U64 $tail ($end64 + 48))
}
$directory = Get-Range $directoryAt $directorySize

# Every builder file in the package: name, sizes and where it starts.
$members = @()
$p = 0
while ($p + 46 -le $directory.Length -and $directory[$p] -eq 0x50 -and $directory[$p + 1] -eq 0x4B -and $directory[$p + 2] -eq 0x01 -and $directory[$p + 3] -eq 0x02) {
    $method = [int](Read-U16 $directory ($p + 10))
    $compressed = [long](Read-U32 $directory ($p + 20))
    $size = [long](Read-U32 $directory ($p + 24))
    $nameLength = [int](Read-U16 $directory ($p + 28))
    $extraLength = [int](Read-U16 $directory ($p + 30))
    $commentLength = [int](Read-U16 $directory ($p + 32))
    $offset = [long](Read-U32 $directory ($p + 42))
    $name = [Text.Encoding]::UTF8.GetString($directory, $p + 46, $nameLength)
    # The zip64 field holds, in this order, whichever of the size, the
    # compressed size and the offset did not fit in 32 bits.
    $q = $p + 46 + $nameLength
    $extraEnd = $q + $extraLength
    while ($q + 4 -le $extraEnd) {
        $tag = [int](Read-U16 $directory $q)
        $length = [int](Read-U16 $directory ($q + 2))
        if ($tag -eq 1) {
            $k = $q + 4
            if ($size -eq $Max32) { $size = [long](Read-U64 $directory $k); $k += 8 }
            if ($compressed -eq $Max32) { $compressed = [long](Read-U64 $directory $k); $k += 8 }
            if ($offset -eq $Max32) { $offset = [long](Read-U64 $directory $k); $k += 8 }
        }
        $q += 4 + $length
    }
    if ($name -match '^tensorrt_libs/(nvinfer_builder_resource_sm(\d+)_10\.dll)$') {
        $members += [pscustomobject]@{ File = $Matches[1]; Sm = [int]$Matches[2]; Method = $method; Compressed = $compressed; Size = $size; Offset = $offset }
    }
    $p += 46 + $nameLength + $extraLength + $commentLength
}
if ($members.Count -eq 0) { throw "No builder files found in NVIDIA's package." }
$members = @($members | Sort-Object Sm)
Write-Host ("Builder files in the package: " + (($members | ForEach-Object { "sm$($_.Sm)" }) -join ', '))
if ($Only.Count -gt 0) {
    $wanted = @($Only | ForEach-Object { [int]($_ -replace '[^0-9]', '') })
    $members = @($members | Where-Object { $wanted -contains $_.Sm })
    if ($members.Count -eq 0) { throw "None of the asked-for generations ($($Only -join ', ')) is in the package." }
}
$totalMb = [int](($members | Measure-Object -Property Compressed -Sum).Sum / 1MB)
Write-Host "Measuring $($members.Count) file(s), about $totalMb MB to download."

New-Item -ItemType Directory -Force -Path $Work | Out-Null
$lines = @(
    "// Windows builder resources, tensorrt_cu13_libs 10.16.1.11.",
    "// Measured $(Get-Date -Format 'yyyy-MM-dd') by meteor/tools/measure_tensorrt_builders.ps1 from",
    "// $Url",
    "// Each file's Authenticode signature (NVIDIA Corporation) was valid on this PC."
)
foreach ($member in $members) {
    $raw = Join-Path $Work ($member.File + '.raw')
    $dll = Join-Path $Work $member.File
    # The file's own header says where its data starts.
    $header = Get-Range $member.Offset 30
    if (-not ($header[0] -eq 0x50 -and $header[1] -eq 0x4B -and $header[2] -eq 0x03 -and $header[3] -eq 0x04)) { throw "NVIDIA's package has an unexpected layout at $($member.File)." }
    $dataAt = $member.Offset + 30 + [long](Read-U16 $header 26) + [long](Read-U16 $header 28)
    Save-Range $dataAt $member.Compressed $raw $member.File
    Write-Host "Unpacking and checking $($member.File)..."
    if ($member.Method -eq 0) {
        Move-Item -LiteralPath $raw -Destination $dll -Force
    } elseif ($member.Method -eq 8) {
        $source = [IO.File]::OpenRead($raw)
        try {
            $inflate = New-Object IO.Compression.DeflateStream($source, [IO.Compression.CompressionMode]::Decompress)
            $target = [IO.File]::Create($dll)
            try { $inflate.CopyTo($target) } finally { $target.Close(); $inflate.Close() }
        } finally { $source.Close() }
        Remove-Item -LiteralPath $raw -Force
    } else {
        throw "$($member.File) is packed in a way this script does not know (method $($member.Method))."
    }
    $unpacked = (Get-Item -LiteralPath $dll).Length
    if ($unpacked -ne $member.Size) { throw "$($member.File) unpacked to $unpacked bytes; the package says $($member.Size)." }
    $signature = Get-AuthenticodeSignature -LiteralPath $dll
    $signer = if ($signature.SignerCertificate) { $signature.SignerCertificate.Subject } else { '(none)' }
    if ($signature.Status -ne 'Valid' -or $signer -notmatch 'O=NVIDIA Corporation') {
        throw "$($member.File) is not validly signed by NVIDIA (status: $($signature.Status), signer: $signer). Not recording it."
    }
    $hash = (Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash.ToLower()
    Remove-Item -LiteralPath $dll -Force
    $lines += @(
        "    ($($member.Sm), WheelFile {",
        "        name: `"$($member.File)`",",
        "        sha256: `"$hash`",",
        "        size: $(Format-Rust $member.Size),",
        "        compressed: $(Format-Rust $member.Compressed),",
        "    }),"
    )
    Write-Host "  sm$($member.Sm): signed by NVIDIA, SHA-256 $hash"
}
Remove-Item -LiteralPath $Work -Recurse -Force -ErrorAction SilentlyContinue
Set-Content -LiteralPath $Result -Value $lines -Encoding UTF8
Write-Host ''
Write-Host "Done. The measurements are in:"
Write-Host "  $Result"
