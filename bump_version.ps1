param(
    [Parameter(Mandatory=$true)]
    [string]$NewVersion
)

$ErrorActionPreference = "Stop"

# Normalize version string (e.g., trim leading 'v')
$cleanVersion = $NewVersion.TrimStart('v', 'V')
$nowDate = Get-Date -Format "yyyy-MM-dd HH:mm"

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host " Bumping RustDesk Version to: $cleanVersion" -ForegroundColor Green
Write-Host " Build Date: $nowDate" -ForegroundColor Yellow
Write-Host "=========================================" -ForegroundColor Cyan

$rootDir = $PSScriptRoot

# 1. Update src/version.rs
$versionRsPath = Join-Path $rootDir "src\version.rs"
if (Test-Path $versionRsPath) {
    $content = Get-Content $versionRsPath -Raw
    $content = $content -replace 'pub const VERSION: &str = "[^"]+";', "pub const VERSION: &str = `"$cleanVersion`";"
    $content = $content -replace 'pub const BUILD_DATE: &str = "[^"]+";', "pub const BUILD_DATE: &str = `"$nowDate`";"
    Set-Content -Path $versionRsPath -Value $content -NoNewline
    Write-Host "[SUCCESS] Updated src/version.rs" -ForegroundColor Green
}

# 2. Update Cargo.toml
$cargoPath = Join-Path $rootDir "Cargo.toml"
if (Test-Path $cargoPath) {
    $content = Get-Content $cargoPath -Raw
    $content = $content -replace '(?m)^version = "[^"]+"', "version = `"$cleanVersion`""
    Set-Content -Path $cargoPath -Value $content -NoNewline
    Write-Host "[SUCCESS] Updated Cargo.toml" -ForegroundColor Green
}

# 3. Update Cargo.lock
$cargoLockPath = Join-Path $rootDir "Cargo.lock"
if (Test-Path $cargoLockPath) {
    $lines = Get-Content $cargoLockPath
    $modified = $false
    for ($i = 0; $i -lt $lines.Length; $i++) {
        if ($lines[$i] -eq 'name = "rustdesk"' -or $lines[$i] -eq 'name = "rustdesk-portable-packer"') {
            if ($i + 1 -lt $lines.Length -and $lines[$i+1] -match '^version = "[^"]+"') {
                $lines[$i+1] = "version = `"$cleanVersion`""
                $modified = $true
            }
        }
    }
    if ($modified) {
        $lines | Set-Content -Path $cargoLockPath
        Write-Host "[SUCCESS] Updated Cargo.lock" -ForegroundColor Green
    }
}

# 4. Update flutter/pubspec.yaml
$pubspecPath = Join-Path $rootDir "flutter\pubspec.yaml"
if (Test-Path $pubspecPath) {
    $content = Get-Content $pubspecPath -Raw
    $content = $content -replace '(?m)^version: [0-9\.\-\+a-zA-Z]+', "version: $cleanVersion+68"
    Set-Content -Path $pubspecPath -Value $content -NoNewline
    Write-Host "[SUCCESS] Updated flutter/pubspec.yaml" -ForegroundColor Green
}

# 5. Update libs/portable/Cargo.toml
$portableCargoPath = Join-Path $rootDir "libs\portable\Cargo.toml"
if (Test-Path $portableCargoPath) {
    $content = Get-Content $portableCargoPath -Raw
    $content = $content -replace '(?m)^version = "[^"]+"', "version = `"$cleanVersion`""
    Set-Content -Path $portableCargoPath -Value $content -NoNewline
    Write-Host "[SUCCESS] Updated libs/portable/Cargo.toml" -ForegroundColor Green
}

# 6. Update .github/workflows/flutter-build.yml
$flutterBuildYml = Join-Path $rootDir ".github\workflows\flutter-build.yml"
if (Test-Path $flutterBuildYml) {
    $content = Get-Content $flutterBuildYml -Raw
    $content = $content -replace '(?m)^\s*VERSION: "[^"]+"', "  VERSION: `"$cleanVersion`""
    Set-Content -Path $flutterBuildYml -Value $content -NoNewline
    Write-Host "[SUCCESS] Updated .github/workflows/flutter-build.yml" -ForegroundColor Green
}

# 7. Update packaging specifications (res/*.spec, res/PKGBUILD, appimage/*.yml)
$specFiles = @(
    "res\PKGBUILD",
    "res\rpm.spec",
    "res\rpm-flutter.spec",
    "res\rpm-flutter-suse.spec",
    "appimage\AppImageBuilder-aarch64.yml",
    "appimage\AppImageBuilder-x86_64.yml"
)
foreach ($rel in $specFiles) {
    $p = Join-Path $rootDir $rel
    if (Test-Path $p) {
        $content = Get-Content $p -Raw
        $content = $content -replace '(?m)^pkgver=[0-9\.]+', "pkgver=$cleanVersion"
        $content = $content -replace '(?m)^Version:\s+[0-9\.]+', "Version:    $cleanVersion"
        $content = $content -replace '(?m)^\s*version:\s+[0-9\.]+', "    version: $cleanVersion"
        Set-Content -Path $p -Value $content -NoNewline
        Write-Host "[SUCCESS] Updated $rel" -ForegroundColor Green
    }
}

Write-Host "`nVersion successfully bumped to $cleanVersion!" -ForegroundColor Green

