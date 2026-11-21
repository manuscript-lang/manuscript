# Installs the Manuscript compiler (`ms.exe`) on Windows.
#
#   irm https://manuscript-lang.github.io/manuscript/install.ps1 | iex
#
# It downloads the release archive for this machine, checks its SHA-256, copies `ms.exe` and `ms-rust.exe`
# into a bin directory and adds that directory to your user PATH. Settings, all optional:
#   $env:MS_VERSION      a release such as 2026.11.0 (default: the latest release)
#   $env:MS_INSTALL_DIR  where `ms.exe` goes (default: $HOME\.ms\bin)
#   $env:MS_RELEASE_URL  a directory URL that holds the archives (default: GitHub releases)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$repo = 'manuscript-lang/manuscript'
$version = if ($env:MS_VERSION) { $env:MS_VERSION.TrimStart('v') } else { 'latest' }
$dir = if ($env:MS_INSTALL_DIR) { $env:MS_INSTALL_DIR } else { Join-Path $HOME '.ms\bin' }

$arch = switch ($env:PROCESSOR_ARCHITECTURE) {
    'AMD64' { 'amd64' }
    'ARM64' { 'arm64' }
    default { throw "install: unsupported processor $($env:PROCESSOR_ARCHITECTURE)" }
}

if ($env:MS_RELEASE_URL) { $base = $env:MS_RELEASE_URL }
elseif ($version -eq 'latest') { $base = "https://github.com/$repo/releases/latest/download" }
else { $base = "https://github.com/$repo/releases/download/v$version" }

$name = "manuscript-rust-windows-$arch"
$work = Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Path $work | Out-Null
try {
    Write-Host "Downloading $name"
    Invoke-WebRequest "$base/$name.zip" -OutFile "$work\$name.zip"
    Invoke-WebRequest "$base/$name.zip.sha256" -OutFile "$work\$name.zip.sha256"

    $expected = ((Get-Content "$work\$name.zip.sha256" -Raw).Trim() -split '\s+')[0].ToLower()
    $actual = (Get-FileHash "$work\$name.zip" -Algorithm SHA256).Hash.ToLower()
    if ($expected -ne $actual) { throw "install: checksum mismatch: expected $expected, got $actual" }

    Expand-Archive "$work\$name.zip" -DestinationPath $work
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    # `ms.exe` finds `ms-rust.exe`, the Rust command line it hands some stages to, in its own directory.
    Copy-Item "$work\$name\ms-rust.exe" "$dir\ms-rust.exe" -Force
    Copy-Item "$work\$name\ms.exe" "$dir\ms.exe" -Force
} finally {
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "Installed $(& "$dir\ms.exe" --version) to $dir\ms.exe"
$user = [Environment]::GetEnvironmentVariable('Path', 'User')
if (($user -split ';') -notcontains $dir) {
    [Environment]::SetEnvironmentVariable('Path', "$user;$dir", 'User')
    Write-Host "Added $dir to your user PATH. Open a new terminal to use ms."
}
