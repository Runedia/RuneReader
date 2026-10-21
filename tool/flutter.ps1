# Runs the project-local Flutter SDK against the project-local Android SDK.
# Usage: .\tool\flutter.ps1 <flutter arguments>
#   e.g. .\tool\flutter.ps1 build apk --debug
#
# Environment changes are scoped to this invocation and restored afterwards.
#
# LOCALAPPDATA is redirected because the Flutter tool aborts when a
# %LOCALAPPDATA%\Google\AndroidStudio* folder has no `.home` file
# (flutter_tools android_studio.dart: the ToolExit raised by its
# ErrorHandlingFileSystem bypasses the FileSystemException handler).

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$flutter = Join-Path $root '.sdk\flutter\bin\flutter.bat'
$androidSdk = Join-Path $root '.sdk\android'
$localAppData = Join-Path $root '.sdk\localappdata'

if (-not (Test-Path -LiteralPath $flutter)) {
    throw "Flutter SDK not found at $flutter. See AGENTS.md (Toolchain)."
}
if (-not (Test-Path -LiteralPath (Join-Path $androidSdk 'platforms\android-36\android.jar'))) {
    throw "Android SDK platform 36 not found under $androidSdk. See AGENTS.md (Toolchain)."
}

$names = 'ANDROID_HOME', 'ANDROID_SDK_ROOT', 'LOCALAPPDATA', 'PUB_CACHE'
$saved = @{}
foreach ($n in $names) { $saved[$n] = [Environment]::GetEnvironmentVariable($n, 'Process') }

try {
    if (-not $env:PUB_CACHE) { $env:PUB_CACHE = Join-Path $env:LOCALAPPDATA 'Pub\Cache' }
    New-Item -ItemType Directory -Force -Path $localAppData | Out-Null
    $env:LOCALAPPDATA = $localAppData
    $env:ANDROID_HOME = $androidSdk
    $env:ANDROID_SDK_ROOT = $androidSdk
    & $flutter @args
    $code = $LASTEXITCODE
}
finally {
    foreach ($n in $names) { [Environment]::SetEnvironmentVariable($n, $saved[$n], 'Process') }
}
exit $code
