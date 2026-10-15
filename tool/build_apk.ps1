# Builds the smallest release APKs for this project.
#
# Why this script exists
# ----------------------
# `flutter build apk --release` packs libflutter.so + libapp.so for THREE ABIs
# (armeabi-v7a, arm64-v8a, x86_64). Those native libraries are ~48 MB of the
# ~52 MiB .apk and they are the only real reason the file is that big.
# x86_64 is emulator-only, so dropping it and emitting one .apk per phone ABI
# cuts a single download roughly in half.
#
# Usage
# -----
#   .\tool\build_apk.ps1                        # arm64-v8a + armeabi-v7a APKs
#   .\tool\build_apk.ps1 -CompressNativeLibs    # even smaller .apk (see below)
#
# -CompressNativeLibs stores the .so files compressed inside the .apk instead
# of leaving them uncompressed/mmap-able. The .apk gets much smaller, but the
# installer has to extract the libraries, so the on-device footprint grows.
#
# Release builds are currently signed with the debug keystore (see
# android/app/build.gradle.kts), so these APKs are for testing/distribution
# only -- add a real signing config before publishing to a store.

param(
    [switch]$CompressNativeLibs
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$apkDir = Join-Path $repoRoot 'build\app\outputs\flutter-apk'

Push-Location $repoRoot
try {
    $flutterArgs = @(
        'build', 'apk',
        '--release',
        '--split-per-abi',
        '--target-platform', 'android-arm,android-arm64'
    )
    if ($CompressNativeLibs) {
        $flutterArgs += '-PcompressNativeLibs=true'
    }

    Write-Host "> flutter $($flutterArgs -join ' ')" -ForegroundColor Cyan
    & flutter @flutterArgs
    if ($LASTEXITCODE -ne 0) {
        throw "flutter build apk failed with exit code $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}

Write-Host ''
Write-Host 'Release APKs:' -ForegroundColor Green
Get-ChildItem (Join-Path $apkDir '*.apk') |
    Sort-Object Length |
    Format-Table @{ n = 'Size'; e = { '{0,7:N1} MiB' -f ($_.Length / 1MB) } }, Name -AutoSize
