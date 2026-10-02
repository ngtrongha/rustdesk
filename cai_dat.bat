@echo off
set "CHECK_ONLY=0"
set "IS_SILENT=0"
set "FORCE_CLIENT_TYPE="
set "FORCE_RESET_GUID=0"
set "DO_CLEAN_ONLY=0"

for %%A in (%*) do (
    if /I "%%~A"=="--check" set "CHECK_ONLY=1"
    if /I "%%~A"=="--silent" set "IS_SILENT=1"
    if /I "%%~A"=="-s" set "IS_SILENT=1"
    if /I "%%~A"=="--new" set "FORCE_CLIENT_TYPE=NEW"
    if /I "%%~A"=="--old" set "FORCE_CLIENT_TYPE=OLD"
    if /I "%%~A"=="--reset-guid" set "FORCE_RESET_GUID=1"
    if /I "%%~A"=="--reset-id" set "FORCE_RESET_GUID=1"
    if /I "%%~A"=="--fix-clone" set "FORCE_RESET_GUID=1"
    if /I "%%~A"=="--clean-old" set "DO_CLEAN_ONLY=1"
    if /I "%%~A"=="--clean" set "DO_CLEAN_ONLY=1"
    if /I "%%~A"=="--migrate" set "DO_CLEAN_ONLY=1"
)

:: ==========================================================
:: Kiem tra quyen Admin (Tuong thich Windows 7, 8, 10, 11)
:: ==========================================================
if "%CHECK_ONLY%"=="1" goto START_SCRIPT

>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"
if %errorlevel% equ 0 goto START_SCRIPT

reg query "HKU\S-1-5-19" >nul 2>&1
if %errorlevel% equ 0 goto START_SCRIPT

fsutil dirty query %systemdrive% >nul 2>&1
if %errorlevel% equ 0 goto START_SCRIPT

fltmc >nul 2>&1
if %errorlevel% equ 0 goto START_SCRIPT

net session >nul 2>&1
if %errorlevel% equ 0 goto START_SCRIPT

:: Neu chua co quyen Admin, tu dong mo hop thoai UAC yeu cau cap quyen
echo [THONG BAO] Dang yeu cau quyen quan tri Administrator...
set "ELEVATE_TARGET=%~f0"
set "ELEVATE_ARGS=%*"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process cmd.exe -ArgumentList @('/k', [char]34 + $env:ELEVATE_TARGET + [char]34 + ' ' + $env:ELEVATE_ARGS) -Verb RunAs" >nul 2>&1
if %errorlevel% equ 0 exit /b 0

echo.
echo [LOI] Khong the tu dong nang quyen Administrator!
echo Vui long nhap chuot phai vao file "cai_dat.bat" va chon "Run as Administrator" (Chay voi quyen quan tri).
echo.
if "%IS_SILENT%"=="0" pause
exit /b 1

:START_SCRIPT
cd /d "%~dp0"
chcp 65001 >nul
title Cau hinh tu dong BVDKKH - Remote (BVDK Khanh Hoa)

:: [Muc 9] Thiet lap log file canh cai_dat.bat
set "LOG_FILE=%~dp0cai_dat.log"
echo. >> "%LOG_FILE%"
echo ================================================================ >> "%LOG_FILE%"
echo [%DATE% %TIME%] === BAT DAU CAI DAT === >> "%LOG_FILE%"
echo ================================================================ >> "%LOG_FILE%"

echo ==========================================================
echo       CAU HINH TU DONG BVDKKH - REMOTE (BVDK KHANH HOA)
echo ==========================================================
echo.

if "%DO_CLEAN_ONLY%"=="1" goto RUN_CLEAN_ONLY

:: Lay kien truc Windows goc. Uu tien gia tri he thong trong Registry de
:: nhan dien dung ARM64 ngay ca khi script duoc goi tu mot tien trinh gia lap.
set "NATIVE_ARCH=%PROCESSOR_ARCHITECTURE%"
if defined PROCESSOR_ARCHITEW6432 set "NATIVE_ARCH=%PROCESSOR_ARCHITEW6432%"
for /f "tokens=3" %%A in ('reg.exe query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v PROCESSOR_ARCHITECTURE 2^>nul ^| findstr /I /C:"PROCESSOR_ARCHITECTURE"') do set "NATIVE_ARCH=%%A"

set "ARCH="
if /I "%NATIVE_ARCH%"=="AMD64" set "ARCH=x64"
if /I "%NATIVE_ARCH%"=="ARM64" set "ARCH=arm64"
if /I "%NATIVE_ARCH%"=="x86" set "ARCH=x86"

if not defined ARCH (
    echo [LOI] Kien truc Windows "%NATIVE_ARCH%" chua duoc ho tro.
    echo [%DATE% %TIME%] [LOI] Kien truc "%NATIVE_ARCH%" khong ho tro >> "%LOG_FILE%"
    echo.
    pause
    exit /b 1
)

:: Windows 10/11 co CurrentMajorVersionNumber. Windows 7/8/8.1 khong co
:: gia tri nay va phai dung ban Sciter vi ban Flutter khong ho tro cac he cu.
set "OS_MODE=legacy"
reg.exe query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v CurrentMajorVersionNumber >nul 2>&1
if not errorlevel 1 set "OS_MODE=modern"

:: Tuy chon thu nhanh, khong anh huong khi cai dat binh thuong:
:: cai_dat.bat --check legacy
if "%CHECK_ONLY%"=="1" if /I "%~2"=="legacy" set "OS_MODE=legacy"
if "%CHECK_ONLY%"=="1" if /I "%~2"=="modern" set "OS_MODE=modern"

set "INSTALL_PROFILE=sciter"
if /I "%OS_MODE%"=="modern" if /I "%ARCH%"=="x64" set "INSTALL_PROFILE=x64"
if /I "%OS_MODE%"=="modern" if /I "%ARCH%"=="arm64" set "INSTALL_PROFILE=arm64"

:: Tim goi dung kien truc trong thu muc "src" hoac canh file cai_dat.bat.
:: Uu tien EXE chinh thuc; MSI chi duoc dung khi khong co EXE phu hop.
set "RUSTDESK_FILE="
set "INSTALLER_TYPE="

if /I "%INSTALL_PROFILE%"=="arm64" goto SELECT_ARM64
if /I "%INSTALL_PROFILE%"=="x64" goto SELECT_X64
goto SELECT_SCITER

:SELECT_ARM64
call :TRY_INSTALLER "src\rustdesk-1.5.11-aarch64.exe" EXE
call :TRY_INSTALLER "rustdesk-1.5.11-aarch64.exe" EXE
call :TRY_INSTALLER "src\BVDKKH-*-aarch64.exe" EXE
call :TRY_INSTALLER "BVDKKH-*-aarch64.exe" EXE
call :TRY_INSTALLER "src\rustdesk-1.5.8-aarch64.exe" EXE
call :TRY_INSTALLER "rustdesk-1.5.8-aarch64.exe" EXE
call :TRY_INSTALLER "src\rustdesk-1.5.1-aarch64.exe" EXE
call :TRY_INSTALLER "rustdesk-1.5.1-aarch64.exe" EXE
call :TRY_INSTALLER "src\rustdesk-1.5.0-aarch64.exe" EXE
call :TRY_INSTALLER "rustdesk-1.5.0-aarch64.exe" EXE
call :TRY_INSTALLER "src\rustdesk-*-aarch64.exe" EXE
call :TRY_INSTALLER "rustdesk-*-aarch64.exe" EXE
call :TRY_INSTALLER "src\rustdesk-aarch64.exe" EXE
call :TRY_INSTALLER "rustdesk-aarch64.exe" EXE
call :TRY_INSTALLER "src\rustdesk-arm64.exe" EXE
call :TRY_INSTALLER "rustdesk-arm64.exe" EXE
call :TRY_INSTALLER "src\rustdesk-1.5.11-aarch64.msi" MSI
call :TRY_INSTALLER "rustdesk-1.5.11-aarch64.msi" MSI
call :TRY_INSTALLER "src\rustdesk-1.5.8-aarch64.msi" MSI
call :TRY_INSTALLER "rustdesk-1.5.8-aarch64.msi" MSI
call :TRY_INSTALLER "src\rustdesk-1.5.1-aarch64.msi" MSI
call :TRY_INSTALLER "rustdesk-1.5.1-aarch64.msi" MSI
call :TRY_INSTALLER "src\rustdesk-1.5.0-aarch64.msi" MSI
call :TRY_INSTALLER "rustdesk-1.5.0-aarch64.msi" MSI
call :TRY_INSTALLER "src\rustdesk-*-aarch64.msi" MSI
call :TRY_INSTALLER "rustdesk-*-aarch64.msi" MSI
goto INSTALLER_SELECTED

:SELECT_X64
call :TRY_INSTALLER "src\rustdesk-1.5.12-x86_64.exe" EXE
call :TRY_INSTALLER "rustdesk-1.5.12-x86_64.exe" EXE
call :TRY_INSTALLER "src\rustdesk-1.5.11-x86_64.exe" EXE
call :TRY_INSTALLER "rustdesk-1.5.11-x86_64.exe" EXE
call :TRY_INSTALLER "src\BVDKKH-*-x86_64.exe" EXE
call :TRY_INSTALLER "BVDKKH-*-x86_64.exe" EXE
call :TRY_INSTALLER "src\rustdesk-1.5.8-x86_64.exe" EXE
call :TRY_INSTALLER "rustdesk-1.5.8-x86_64.exe" EXE
call :TRY_INSTALLER "src\rustdesk-1.5.1-x86_64.exe" EXE
call :TRY_INSTALLER "rustdesk-1.5.1-x86_64.exe" EXE
call :TRY_INSTALLER "src\rustdesk-1.5.0-x86_64.exe" EXE
call :TRY_INSTALLER "rustdesk-1.5.0-x86_64.exe" EXE
call :TRY_INSTALLER "src\rustdesk-*-x86_64.exe" EXE
call :TRY_INSTALLER "rustdesk-*-x86_64.exe" EXE
call :TRY_INSTALLER "src\rustdesk-x86_64.exe" EXE
call :TRY_INSTALLER "rustdesk-x86_64.exe" EXE
call :TRY_INSTALLER "src\rustdesk-x64.exe" EXE
call :TRY_INSTALLER "rustdesk-x64.exe" EXE
call :TRY_INSTALLER "src\rustdesk-1.5.11-x86_64.msi" MSI
call :TRY_INSTALLER "rustdesk-1.5.11-x86_64.msi" MSI
call :TRY_INSTALLER "src\rustdesk-1.5.8-x86_64.msi" MSI
call :TRY_INSTALLER "rustdesk-1.5.8-x86_64.msi" MSI
call :TRY_INSTALLER "src\rustdesk-1.5.1-x86_64.msi" MSI
call :TRY_INSTALLER "rustdesk-1.5.1-x86_64.msi" MSI
call :TRY_INSTALLER "src\rustdesk-1.5.0-x86_64.msi" MSI
call :TRY_INSTALLER "rustdesk-1.5.0-x86_64.msi" MSI
call :TRY_INSTALLER "src\rustdesk-*-x86_64.msi" MSI
call :TRY_INSTALLER "rustdesk-*-x86_64.msi" MSI
goto INSTALLER_SELECTED

:SELECT_SCITER
if /I "%ARCH%"=="x64" call :TRY_INSTALLER "src\rustdesk-1.5.12-win7-x86_64.exe" EXE
if /I "%ARCH%"=="x64" call :TRY_INSTALLER "rustdesk-1.5.12-win7-x86_64.exe" EXE
if /I "%ARCH%"=="x64" call :TRY_INSTALLER "src\rustdesk-*-win7-x86_64.exe" EXE
if /I "%ARCH%"=="x64" call :TRY_INSTALLER "rustdesk-*-win7-x86_64.exe" EXE
call :TRY_INSTALLER "src\rustdesk-1.5.12-x86-sciter.exe" EXE
call :TRY_INSTALLER "rustdesk-1.5.12-x86-sciter.exe" EXE
call :TRY_INSTALLER "src\rustdesk-1.5.11-x86-sciter.exe" EXE
call :TRY_INSTALLER "rustdesk-1.5.11-x86-sciter.exe" EXE
call :TRY_INSTALLER "src\BVDKKH-*-x86-sciter.exe" EXE
call :TRY_INSTALLER "BVDKKH-*-x86-sciter.exe" EXE
call :TRY_INSTALLER "src\rustdesk-1.5.8-x86-sciter.exe" EXE
call :TRY_INSTALLER "rustdesk-1.5.8-x86-sciter.exe" EXE
call :TRY_INSTALLER "src\rustdesk-1.5.1-x86-sciter.exe" EXE
call :TRY_INSTALLER "rustdesk-1.5.1-x86-sciter.exe" EXE
call :TRY_INSTALLER "src\rustdesk-1.5.0-x86-sciter.exe" EXE
call :TRY_INSTALLER "rustdesk-1.5.0-x86-sciter.exe" EXE
call :TRY_INSTALLER "src\rustdesk-*-x86-sciter.exe" EXE
call :TRY_INSTALLER "rustdesk-*-x86-sciter.exe" EXE
call :TRY_INSTALLER "src\rustdesk-x86-sciter.exe" EXE
call :TRY_INSTALLER "rustdesk-x86-sciter.exe" EXE
call :TRY_INSTALLER "src\rustdesk-x86.exe" EXE
call :TRY_INSTALLER "rustdesk-x86.exe" EXE

:INSTALLER_SELECTED
if not defined RUSTDESK_FILE (
    echo [LOI] Khong tim thay goi RustDesk phu hop voi he dieu han va kien truc may.
    echo.
    echo Hay dat file cai dat vao cung thu muc voi "cai_dat.bat" hoac thu muc "src":
    if /I "%INSTALL_PROFILE%"=="arm64" echo   rustdesk-1.5.11-aarch64.exe ^(hoac .msi^)
    if /I "%INSTALL_PROFILE%"=="x64" echo   rustdesk-1.5.11-x86_64.exe ^(hoac .msi^)
    if /I "%INSTALL_PROFILE%"=="sciter" echo   rustdesk-1.5.11-x86-sciter.exe
    echo.
    if "%IS_SILENT%"=="0" pause
    exit /b 1
)

:: [Nhan dien phien ban] Mac dinh luon cai dat ban moi (BVĐKKH - Remote)
set "CLIENT_TYPE=NEW"
if /I "%FORCE_CLIENT_TYPE%"=="OLD" set "CLIENT_TYPE=OLD"
if /I "%FORCE_CLIENT_TYPE%"=="NEW" set "CLIENT_TYPE=NEW"

:: [Kiem tra ban cu de Migration sang ban moi]
set "OLD_FOUND=0"
set "OLD_DIR="
if exist "%ProgramFiles%\RustDesk" set "OLD_FOUND=1" & set "OLD_DIR=%ProgramFiles%\RustDesk"
if exist "%SystemDrive%\Program Files\RustDesk" set "OLD_FOUND=1" & set "OLD_DIR=%SystemDrive%\Program Files\RustDesk"
if exist "%SystemDrive%\Program Files (x86)\RustDesk" set "OLD_FOUND=1" & set "OLD_DIR=%SystemDrive%\Program Files (x86)\RustDesk"
if exist "%ProgramFiles%\BVDKKH - Remote" set "OLD_FOUND=1" & set "OLD_DIR=%ProgramFiles%\BVDKKH - Remote"
if exist "%SystemDrive%\Program Files\BVDKKH - Remote" set "OLD_FOUND=1" & set "OLD_DIR=%SystemDrive%\Program Files\BVDKKH - Remote"
if exist "%SystemDrive%\Program Files (x86)\BVDKKH - Remote" set "OLD_FOUND=1" & set "OLD_DIR=%SystemDrive%\Program Files (x86)\BVDKKH - Remote"
sc.exe query rustdesk >nul 2>&1
if not errorlevel 1 set "OLD_FOUND=1"
sc.exe query "RustDesk Service" >nul 2>&1
if not errorlevel 1 set "OLD_FOUND=1"
sc.exe query "BVDKKH - Remote" >nul 2>&1
if not errorlevel 1 set "OLD_FOUND=1"
reg query "HKLM\Software\Microsoft\Windows\CurrentVersion\Uninstall\RustDesk" >nul 2>&1
if not errorlevel 1 set "OLD_FOUND=1"
reg query "HKLM\Software\Microsoft\Windows\CurrentVersion\Uninstall\BVDKKH - Remote" >nul 2>&1
if not errorlevel 1 set "OLD_FOUND=1"
reg query "HKLM\Software\Microsoft\Windows\CurrentVersion\Run" /v RustDesk >nul 2>&1
if not errorlevel 1 set "OLD_FOUND=1"
reg query "HKLM\Software\Microsoft\Windows\CurrentVersion\Run" /v "BVDKKH - Remote" >nul 2>&1
if not errorlevel 1 set "OLD_FOUND=1"

if /I "%CLIENT_TYPE%"=="OLD" goto SETUP_OLD_CLIENT

:SETUP_NEW_CLIENT
set "APP_NAME=BVDKKH - Remote"
set "APP_DISPLAY=BVĐKKH - Remote"
set "MAIN_EXE=BVDKKH - Remote.exe"
set "SERVICE_NAME=BVDKKH - Remote"
set "SERVICE_DISPLAY=BVĐKKH - Remote Service"
set "TARGET_DIR=%ProgramFiles%\BVDKKH - Remote"
if /I "%ARCH%"=="x86" if defined ProgramFiles(x86) call set "TARGET_DIR=%%ProgramFiles(x86)%%\BVDKKH - Remote"
goto CLIENT_SETUP_DONE

:SETUP_OLD_CLIENT
set "APP_NAME=RustDesk"
set "APP_DISPLAY=RustDesk"
set "MAIN_EXE=rustdesk.exe"
set "SERVICE_NAME=rustdesk"
set "SERVICE_DISPLAY=RustDesk Service"
set "TARGET_DIR=%ProgramFiles%\RustDesk"
if exist "%SystemDrive%\Program Files (x86)\RustDesk\rustdesk.exe" set "TARGET_DIR=%SystemDrive%\Program Files (x86)\RustDesk"
if exist "%ProgramFiles%\RustDesk\rustdesk.exe" set "TARGET_DIR=%ProgramFiles%\RustDesk"

:CLIENT_SETUP_DONE

:CHECK_OK
echo Kien truc he thong phat hien: %ARCH%
if /I "%OS_MODE%"=="legacy" echo Nhom Windows phat hien: Windows 7/8/8.1 [dung Sciter]
if /I "%OS_MODE%"=="modern" echo Nhom Windows phat hien: Windows 10/11
if /I "%CLIENT_TYPE%"=="NEW" (
    echo Phien ban phan mem: BVDKKH - Remote [Phien ban moi - Cai dat chinh thuc]
) else (
    echo Phien ban phan mem: RustDesk goc [Phien ban cu/tieu chuan]
)
if "%OLD_FOUND%"=="1" if /I "%CLIENT_TYPE%"=="NEW" (
    echo [PHAT HIEN] He thong dang ton tai ban cai dat cu tai: "%OLD_DIR%"
    echo [MIGRATION] Script se tu dong chuyen doi toan bo sang kieu moi "BVĐKKH - Remote"!
)
echo Thu muc cai dat: %TARGET_DIR%
echo File duoc chon de cai dat: %RUSTDESK_FILE%
echo.

:: [Muc 11] Mo rong --check mode: hien thi trang thai he thong
if "%CHECK_ONLY%"=="0" goto SKIP_STATUS_CHECK

echo --- Trang thai he thong hien tai ---
powershell -NoProfile -ExecutionPolicy Bypass -Command "$svcs = @('BVDKKH - Remote', 'BVĐKKH - Remote', 'rustdesk'); $found = $false; foreach ($s in $svcs) { $svc = Get-Service -Name $s -ErrorAction SilentlyContinue; if ($svc) { Write-Host ('Dich vu ' + $s + ': ' + $svc.Status); $found = $true } }; if (-not $found) { Write-Host 'Dich vu: CHUA CAI DAT' }"

if exist "%~dp0src\install_official.ps1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\install_official.ps1" -CheckOnly -TargetDir "%TARGET_DIR%" -MainExe "%MAIN_EXE%" -AppName "%APP_NAME%"
) else if exist "src\install_official.ps1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "src\install_official.ps1" -CheckOnly -TargetDir "%TARGET_DIR%" -MainExe "%MAIN_EXE%" -AppName "%APP_NAME%"
)

powershell -NoProfile -ExecutionPolicy Bypass -Command "$found = $false; foreach ($c in @('RustDesk2.toml', 'BVDKKH - Remote2.toml', 'BVĐKKH - Remote2.toml')) { foreach ($base in @((Join-Path $env:SystemRoot 'System32\config\systemprofile\AppData\Roaming\RustDesk\config'), (Join-Path $env:ProgramData 'RustDesk\config'), (Join-Path $env:ProgramData 'BVDKKH - Remote\config'), (Join-Path $env:ProgramData 'BVĐKKH - Remote\config'))) { if (Test-Path (Join-Path $base $c) -ErrorAction SilentlyContinue) { $found = $true; break } } }; if ($found) { Write-Host 'Cau hinh Server: DA GHI' } else { Write-Host 'Cau hinh Server: CHUA GHI' }"

:: Kiem tra ket noi relay server
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $t = New-Object System.Net.Sockets.TcpClient; $t.Connect('172.16.3.28', 21116); $t.Close(); Write-Host 'Ket noi relay server: OK (port 21116)' } catch { Write-Host 'Ket noi relay server: KHONG KET NOI DUOC (port 21116)' }"

:: Hien thi RustDesk ID hien tai (neu co)
powershell -NoProfile -ExecutionPolicy Bypass -Command "$idFound = $false; $paths = @((Join-Path $env:SystemRoot 'System32\config\systemprofile\AppData\Roaming\RustDesk\config'), (Join-Path $env:ProgramData 'RustDesk\config'), (Join-Path $env:ProgramData 'BVDKKH - Remote\config'), (Join-Path $env:ProgramData 'BVĐKKH - Remote\config')); foreach ($p in $paths) { foreach ($t in @('RustDesk.toml', 'BVDKKH - Remote.toml', 'BVĐKKH - Remote.toml')) { $f = Join-Path $p $t; if (Test-Path $f -ErrorAction SilentlyContinue) { try { $c = [System.IO.File]::ReadAllText($f); if ($c -match 'id\s*=\s*''([^'']+)''') { Write-Host ('RustDesk ID: ' + $Matches[1]); $idFound = $true; break } } catch { try { $lines = Get-Content $f -ErrorAction SilentlyContinue; foreach ($l in $lines) { if ($l -match 'id\s*=\s*''([^'']+)''') { Write-Host ('RustDesk ID: ' + $Matches[1]); $idFound = $true; break } }; if ($idFound) { break } } catch {} } } }; if ($idFound) { break } }; if (-not $idFound) { Write-Host 'RustDesk ID: CHUA DANG KY' }"

echo ---
exit /b 0

:SKIP_STATUS_CHECK

:: [Muc 9] Ghi thong tin ban dau vao log
echo [%DATE% %TIME%] Kien truc: %ARCH%, OS: %OS_MODE%, Profile: %INSTALL_PROFILE% >> "%LOG_FILE%"
echo [%DATE% %TIME%] Installer: %RUSTDESK_FILE% (%INSTALLER_TYPE%) >> "%LOG_FILE%"

:: ==============================================================================
:: [Khac phuc trung lap do Clone / Ghost Windows]
:: Kiem tra va tai tao MachineGuid doc lap neu phat hien ma Ghost mau (6c2a494b-5097-4a52-8d10-028ec947b421)
:: ==============================================================================
echo Dang kiem tra ma dinh danh Windows (MachineGuid) chong trung lap do Clone/Ghost...
echo [%DATE% %TIME%] Buoc: Kiem tra MachineGuid chong trung lap >> "%LOG_FILE%"
set "ENV_FORCE_RESET_GUID=%FORCE_RESET_GUID%"
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$cur = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Cryptography' -ErrorAction SilentlyContinue).MachineGuid; " ^
    "$ghostGuids = @('6c2a494b-5097-4a52-8d10-028ec947b421', 'd18b2b18-0000-0000-0000-000000000000'); " ^
    "$needReset = ($env:ENV_FORCE_RESET_GUID -eq '1') -or (-not $cur) -or ($ghostGuids -contains $cur.ToLower()); " ^
    "if ($needReset) { " ^
    "    $newG = [guid]::NewGuid().ToString().ToLower(); " ^
    "    Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name 'MachineGuid' -Value $newG -Force; " ^
    "    Write-Host ('  [FIX GHOST] Phat hien GUID ban Clone: ' + $cur + ' -> Da tao MachineGuid moi: ' + $newG); " ^
    "    foreach ($bd in @((Join-Path $env:ProgramData 'RustDesk\backup'), (Join-Path $env:ProgramData 'BVĐKKH - Remote\backup'), (Join-Path $env:ProgramData 'BVDKKH - Remote\backup'))) { " ^
    "        if (Test-Path $bd) { Remove-Item $bd -Recurse -Force -ErrorAction SilentlyContinue } " ^
    "    }; " ^
    "    exit 10; " ^
    "} else { " ^
    "    Write-Host ('  [OK] MachineGuid hop le: ' + $cur); " ^
    "    exit 0; " ^
    "}"
if errorlevel 10 (
    set "FORCE_RESET_GUID=1"
    echo   [FIX GHOST] Da dat co Reset GUID/ID moi cho may tinh nay.
)

:: [Muc 6] Sao luu danh tinh RustDesk ID hien co truoc khi lam gi khac
echo Dang kiem tra va sao luu danh tinh RustDesk ID hien co (neu co)...
echo [%DATE% %TIME%] Buoc: Sao luu danh tinh RustDesk ID >> "%LOG_FILE%"
if exist "%~dp0src\write_config.ps1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\write_config.ps1" -BackupOnly
) else if exist "src\write_config.ps1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "src\write_config.ps1" -BackupOnly
) else if exist "%~dp0write_config.ps1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0write_config.ps1" -BackupOnly
)

echo Dang tat tien trinh va dich vu cu (neu co)...
echo [%DATE% %TIME%] Buoc: Tat tien trinh va dich vu cu >> "%LOG_FILE%"
taskkill /F /IM "BVĐKKH - Remote.exe" > nul 2>&1
taskkill /F /IM "BVDKKH - Remote.exe" > nul 2>&1
taskkill /F /IM rustdesk.exe > nul 2>&1
taskkill /F /IM rustdesk-x64.exe > nul 2>&1
taskkill /F /IM rustdesk-x86.exe > nul 2>&1
taskkill /F /IM RuntimeBroker_rustdesk.exe > nul 2>&1

powershell -NoProfile -ExecutionPolicy Bypass -Command "$svcs = @('BVĐKKH - Remote', 'BVDKKH - Remote', 'rustdesk'); foreach ($name in $svcs) { $s = Get-Service -Name $name -ErrorAction SilentlyContinue; if ($s -and $s.Status -ne 'Stopped') { Stop-Service -Name $name -Force -ErrorAction SilentlyContinue; $count=0; while ($count -lt 10) { $s.Refresh(); if ($s.Status -eq 'Stopped') { break }; if ($count -eq 5) { try { $w = Get-WmiObject Win32_Service -Filter ('Name=''' + $name + ''''); if ($w -and $w.ProcessId -gt 0) { Stop-Process -Id $w.ProcessId -Force -ErrorAction SilentlyContinue } } catch {} }; Start-Sleep -Milliseconds 500; $count++ } } }"
timeout /t 1 /nobreak >nul 2>&1

:: [Migration & Don dep ban cu]
:: Luon thuc hien don dep sach se dich vu va file cu truoc khi cai ban moi
if /I "%CLIENT_TYPE%"=="NEW" (
    echo   [MIGRATION] Dang thuc hien don dep toan dien ban RustDesk cu...
    echo [%DATE% %TIME%]   Migration: Goi install_official.ps1 -MigrateOld >> "%LOG_FILE%"
    if exist "%~dp0src\install_official.ps1" (
        powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\install_official.ps1" -MigrateOld -TargetDir "%TARGET_DIR%" -AppName "%APP_NAME%"
    ) else if exist "src\install_official.ps1" (
        powershell -NoProfile -ExecutionPolicy Bypass -File "src\install_official.ps1" -MigrateOld -TargetDir "%TARGET_DIR%" -AppName "%APP_NAME%"
    )
)

:: [Cai dat / Cap nhat truc tiep - khong chay --uninstall de bao toan ID va khong bi tat cmd]
echo Dang cai dat / cap nhat chinh thuc vao "%TARGET_DIR%"...
echo [%DATE% %TIME%] Buoc: Cai dat vao %TARGET_DIR% >> "%LOG_FILE%"
if /I "%INSTALLER_TYPE%"=="MSI" goto INSTALL_MSI

:: Tao thu muc cai dat (ho tro tot duong dan Unicode)
if not exist "%TARGET_DIR%" mkdir "%TARGET_DIR%" >nul 2>&1
powershell -NoProfile -ExecutionPolicy Bypass -Command "[System.IO.Directory]::CreateDirectory($env:TARGET_DIR) | Out-Null"

:: Dam bao bien LOCALAPPDATA luon ton tai (dac biet tren cac ban Windows 7 Ghost/Lite)
if not defined LOCALAPPDATA (
    if exist "%USERPROFILE%\AppData\Local" set "LOCALAPPDATA=%USERPROFILE%\AppData\Local"
)

:: Tat ca cac goi cai dat EXE (x64, arm64, Sciter Win7) deu la goi Portable Packer
:: can duoc giai nen de lay binary thuc thi goc va cac thu vien phu thuoc (sciter.dll, flutter,...)
echo   Dang giai nen bo cai dat %APP_DISPLAY%...
echo [%DATE% %TIME%]   Giai nen goi portable bang --version >> "%LOG_FILE%"
"%RUSTDESK_FILE%" --version >nul 2>&1
timeout /t 2 /nobreak >nul 2>&1
taskkill /F /IM "BVĐKKH - Remote.exe" >nul 2>&1
taskkill /F /IM rustdesk.exe >nul 2>&1
taskkill /F /IM RuntimeBroker_rustdesk.exe >nul 2>&1

:: Xac dinh thu muc chua file da duoc giai nen
set "UNPACK_DIR="
if exist "%LOCALAPPDATA%\rustdesk\rustdesk.exe" set "UNPACK_DIR=%LOCALAPPDATA%\rustdesk"
if not defined UNPACK_DIR if exist "%USERPROFILE%\AppData\Local\rustdesk\rustdesk.exe" set "UNPACK_DIR=%USERPROFILE%\AppData\Local\rustdesk"

if defined UNPACK_DIR (
    echo   Dang dong bo toan bo tep chuong trinh vao "%TARGET_DIR%"...
    echo [%DATE% %TIME%]   XCOPY: "%UNPACK_DIR%" -> "%TARGET_DIR%" >> "%LOG_FILE%"
    xcopy "%UNPACK_DIR%\*" "%TARGET_DIR%\" /E /H /C /I /Y /Q /R >nul 2>&1
    copy /Y "%UNPACK_DIR%\rustdesk.exe" "%TARGET_DIR%\rustdesk.exe" >nul 2>&1
    if exist "%UNPACK_DIR%\sciter.dll" copy /Y "%UNPACK_DIR%\sciter.dll" "%TARGET_DIR%\sciter.dll" >nul 2>&1
    
    :: Kiem tra dam bao file trong TARGET_DIR khop hoan toan dung luong voi file goc da giai nen
    powershell -NoProfile -ExecutionPolicy Bypass -Command "$u = $env:UNPACK_DIR; if (-not $u) { $u = Join-Path $env:LOCALAPPDATA 'rustdesk' }; $ue = Join-Path $u 'rustdesk.exe'; $te = Join-Path $env:TARGET_DIR 'rustdesk.exe'; if ((Test-Path $ue) -and (Test-Path $te)) { if ((Get-Item $te).Length -ne (Get-Item $ue).Length) { Copy-Item $ue $te -Force } }"

    :: Tao ca 'BVDKKH - Remote.exe', 'BVĐKKH - Remote.exe' va 'rustdesk.exe' de dam bao ca is_installed() va script deu chay dung
    if /I "%CLIENT_TYPE%"=="NEW" (
        copy /Y "%TARGET_DIR%\rustdesk.exe" "%TARGET_DIR%\%MAIN_EXE%" >nul 2>&1
        copy /Y "%TARGET_DIR%\rustdesk.exe" "%TARGET_DIR%\BVDKKH - Remote.exe" >nul 2>&1
        copy /Y "%TARGET_DIR%\rustdesk.exe" "%TARGET_DIR%\BVĐKKH - Remote.exe" >nul 2>&1
    )
) else (
    echo   [CANH BAO] Khong tim thay thu muc giai nen, thu chep truc tiep file...
    echo [%DATE% %TIME%]   Fallback direct copy >> "%LOG_FILE%"
    copy /Y "%RUSTDESK_FILE%" "%TARGET_DIR%\rustdesk.exe" >nul 2>&1
    if /I "%CLIENT_TYPE%"=="NEW" (
        copy /Y "%RUSTDESK_FILE%" "%TARGET_DIR%\%MAIN_EXE%" >nul 2>&1
        copy /Y "%RUSTDESK_FILE%" "%TARGET_DIR%\BVDKKH - Remote.exe" >nul 2>&1
        copy /Y "%RUSTDESK_FILE%" "%TARGET_DIR%\BVĐKKH - Remote.exe" >nul 2>&1
    )
)

:: Dong bo truc tiep cac cong cu ho tro Bao Su Co IT vao thu muc cai dat
echo   Dang dong bo cac cong cu ho tro Bao Su Co IT...
echo [%DATE% %TIME%]   Dong bo cong cu ho tro Bao Su Co IT >> "%LOG_FILE%"
if exist "%~dp0src\BaoSuCoIT.exe" (
    copy /Y "%~dp0src\BaoSuCoIT.exe" "%TARGET_DIR%\" >nul 2>&1
    copy /Y "%~dp0src\support_dialog.ps1" "%TARGET_DIR%\" >nul 2>&1
    copy /Y "%~dp0src\ticket_watcher.ps1" "%TARGET_DIR%\" >nul 2>&1
    copy /Y "%~dp0src\support_launcher.vbs" "%TARGET_DIR%\" >nul 2>&1
    copy /Y "%~dp0src\icon.ico" "%TARGET_DIR%\" >nul 2>&1
)
if exist "src\BaoSuCoIT.exe" (
    copy /Y "src\BaoSuCoIT.exe" "%TARGET_DIR%\" >nul 2>&1
    copy /Y "src\support_dialog.ps1" "%TARGET_DIR%\" >nul 2>&1
    copy /Y "src\ticket_watcher.ps1" "%TARGET_DIR%\" >nul 2>&1
    copy /Y "src\support_launcher.vbs" "%TARGET_DIR%\" >nul 2>&1
    copy /Y "src\icon.ico" "%TARGET_DIR%\" >nul 2>&1
)
if exist "%~dp0BaoSuCoIT.exe" (
    copy /Y "%~dp0BaoSuCoIT.exe" "%TARGET_DIR%\" >nul 2>&1
    copy /Y "%~dp0support_dialog.ps1" "%TARGET_DIR%\" >nul 2>&1
    copy /Y "%~dp0ticket_watcher.ps1" "%TARGET_DIR%\" >nul 2>&1
    copy /Y "%~dp0support_launcher.vbs" "%TARGET_DIR%\" >nul 2>&1
    copy /Y "%~dp0icon.ico" "%TARGET_DIR%\" >nul 2>&1
)
powershell -NoProfile -ExecutionPolicy Bypass -Command "$td = $env:TARGET_DIR; if ($td) { $td = $td.Trim().TrimEnd('\'); foreach ($sd in @('%~dp0src', 'src', '%~dp0')) { if (Test-Path $sd) { foreach ($fn in @('BaoSuCoIT.exe', 'support_dialog.ps1', 'ticket_watcher.ps1', 'support_launcher.vbs', 'icon.ico')) { $sf = Join-Path $sd $fn; $df = Join-Path $td $fn; if (Test-Path $sf) { Copy-Item $sf $df -Force -ErrorAction SilentlyContinue } } } } }"

set "RD_PATH=%TARGET_DIR%\%MAIN_EXE%"
if not exist "%RD_PATH%" if exist "%TARGET_DIR%\rustdesk.exe" set "RD_PATH=%TARGET_DIR%\rustdesk.exe"

if not exist "%RD_PATH%" (
    echo [LOI] Khong the ghi de file thuc thi vao "%TARGET_DIR%".
    echo [%DATE% %TIME%] [LOI] Khong ghi de duoc %MAIN_EXE% >> "%LOG_FILE%"
    if "%IS_SILENT%"=="0" pause
    exit /b 1
)

:: [Dang ky Ban cai dat chinh thuc vao Registry (is_installed = TRUE)]
echo   Dang dang ky ban cai dat chinh thuc vao Registry he thong...
echo [%DATE% %TIME%]   Dang ky cai dat chinh thuc bang install_official.ps1 >> "%LOG_FILE%"
if exist "%~dp0src\install_official.ps1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\install_official.ps1" -TargetDir "%TARGET_DIR%" -MainExe "%MAIN_EXE%" -AppName "%APP_NAME%"
) else if exist "src\install_official.ps1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "src\install_official.ps1" -TargetDir "%TARGET_DIR%" -MainExe "%MAIN_EXE%" -AppName "%APP_NAME%"
)

:: Dang ky / cap nhat Windows Service truc tiep
echo   Dang cau hinh va dang ky dich vu he thong (%SERVICE_DISPLAY%)...
echo [%DATE% %TIME%]   Dang ky Service %SERVICE_NAME% >> "%LOG_FILE%"

:: Neu cai ban moi ma may da co service rustdesk hoac BVĐKKH - Remote cu, dung va xoa tranh xung dot
if /I "%CLIENT_TYPE%"=="NEW" (
    call :WAIT_SERVICE_STATUS Stopped "rustdesk"
    sc.exe delete rustdesk >nul 2>&1
    call :WAIT_SERVICE_STATUS Stopped "BVĐKKH - Remote"
    sc.exe delete "BVĐKKH - Remote" >nul 2>&1
)

:: Neu cai ban cu ma may da co service BVDKKH / BVĐKKH, dung va xoa service do
if /I "%CLIENT_TYPE%"=="OLD" (
    call :WAIT_SERVICE_STATUS Stopped "BVDKKH - Remote"
    sc.exe delete "BVDKKH - Remote" >nul 2>&1
    call :WAIT_SERVICE_STATUS Stopped "BVĐKKH - Remote"
    sc.exe delete "BVĐKKH - Remote" >nul 2>&1
)

sc.exe query "%SERVICE_NAME%" >nul 2>&1
if errorlevel 1 (
    sc.exe create "%SERVICE_NAME%" binpath= "\"%RD_PATH%\" --service" start= auto DisplayName= "%SERVICE_DISPLAY%" >nul 2>&1
) else (
    sc.exe config "%SERVICE_NAME%" binpath= "\"%RD_PATH%\" --service" start= auto DisplayName= "%SERVICE_DISPLAY%" >nul 2>&1
)
sc.exe failure "%SERVICE_NAME%" reset= 86400 actions= restart/5000/restart/15000/restart/60000 >nul 2>&1

set "INSTALL_EXIT=0"
goto CHECK_INSTALL_RESULT

:INSTALL_MSI
msiexec.exe /i "%RUSTDESK_FILE%" /qn /norestart
set "INSTALL_EXIT=%ERRORLEVEL%"
echo [%DATE% %TIME%] MSI exit code: %INSTALL_EXIT% >> "%LOG_FILE%"

:CHECK_INSTALL_RESULT
if "%INSTALL_EXIT%"=="0" goto INSTALL_OK
if "%INSTALL_EXIT%"=="1641" goto INSTALL_OK
if "%INSTALL_EXIT%"=="3010" goto INSTALL_OK

echo [LOI] Trinh cai dat RustDesk ket thuc voi ma loi %INSTALL_EXIT%.
echo [%DATE% %TIME%] [LOI] Installer exit code: %INSTALL_EXIT% >> "%LOG_FILE%"
echo.
pause
exit /b %INSTALL_EXIT%

:INSTALL_OK

:WRITE_CONFIG
:: Luc nay dich vu chua khoi chay; tat tiep cac tien trinh con sot lai truoc khi nap config
taskkill /F /IM "BVĐKKH - Remote.exe" > nul 2>&1
taskkill /F /IM "BVDKKH - Remote.exe" > nul 2>&1
taskkill /F /IM rustdesk.exe > nul 2>&1
taskkill /F /IM rustdesk-x64.exe > nul 2>&1
taskkill /F /IM rustdesk-x86.exe > nul 2>&1
taskkill /F /IM RuntimeBroker_rustdesk.exe > nul 2>&1

:: [Muc 5] Khoi tao thu muc cau hinh chuan truoc khi khoi dong service
echo Dang thiet lap thu muc cau hinh he thong chuan...
echo [%DATE% %TIME%] Buoc: Khoi tao thu muc cau hinh + bao toan ID >> "%LOG_FILE%"
if exist "%~dp0src\write_config.ps1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\write_config.ps1"
) else if exist "src\write_config.ps1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "src\write_config.ps1"
) else if exist "%~dp0write_config.ps1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0write_config.ps1"
)
if errorlevel 1 (
    echo [LOI] Khong ghi duoc cau hinh RustDesk.
    echo [%DATE% %TIME%] [LOI] write_config.ps1 fail >> "%LOG_FILE%"
    echo.
    pause
    exit /b 1
)

echo Dang khoi dong dich vu %SERVICE_DISPLAY% voi day du cau hinh...
echo [%DATE% %TIME%] Buoc: Khoi dong dich vu %SERVICE_NAME% >> "%LOG_FILE%"
call :WAIT_SERVICE_STATUS Running "%SERVICE_NAME%"
if errorlevel 1 (
    echo [LOI] Khong khoi dong duoc dich vu %SERVICE_DISPLAY%.
    echo [%DATE% %TIME%] [LOI] Service khong the chay >> "%LOG_FILE%"
    sc query "%SERVICE_NAME%"
    echo.
    if "%IS_SILENT%"=="0" pause
    exit /b 1
)

:SET_PASSWORD
echo Dang thiet lap mat khau mac dinh va khoa cai dat bao mat...
echo [%DATE% %TIME%] Buoc: Thiet lap mat khau va bao mat >> "%LOG_FILE%"
if not defined RD_PATH set "RD_PATH=%TARGET_DIR%\%MAIN_EXE%"
if not exist "%RD_PATH%" if exist "%TARGET_DIR%\rustdesk.exe" set "RD_PATH=%TARGET_DIR%\rustdesk.exe"
if not exist "%RD_PATH%" if exist "%ProgramFiles%\BVDKKH - Remote\BVDKKH - Remote.exe" set "RD_PATH=%ProgramFiles%\BVDKKH - Remote\BVDKKH - Remote.exe"
if not exist "%RD_PATH%" if exist "%ProgramFiles%\BVĐKKH - Remote\BVĐKKH - Remote.exe" set "RD_PATH=%ProgramFiles%\BVĐKKH - Remote\BVĐKKH - Remote.exe"
if not exist "%RD_PATH%" if exist "%ProgramFiles%\RustDesk\rustdesk.exe" set "RD_PATH=%ProgramFiles%\RustDesk\rustdesk.exe"
if not exist "%RD_PATH%" if exist "%SystemDrive%\Program Files\RustDesk\rustdesk.exe" set "RD_PATH=%SystemDrive%\Program Files\RustDesk\rustdesk.exe"
if not exist "%RD_PATH%" if exist "%SystemDrive%\Program Files (x86)\RustDesk\rustdesk.exe" set "RD_PATH=%SystemDrive%\Program Files (x86)\RustDesk\rustdesk.exe"

:: Neu chua tim thay, truy van truc tiep tu ImagePath cua Service trong Registry
if not exist "%RD_PATH%" (
    for /f "tokens=2*" %%A in ('reg query "HKLM\SYSTEM\CurrentControlSet\Services\%SERVICE_NAME%" /v ImagePath 2^>nul ^| findstr /i "ImagePath"') do (
        for %%I in (%%B) do (
            if exist "%%~I" set "RD_PATH=%%~fI"
        )
    )
)
if not exist "%RD_PATH%" (
    for /f "tokens=2*" %%A in ('reg query "HKLM\SYSTEM\CurrentControlSet\Services\rustdesk" /v ImagePath 2^>nul ^| findstr /i "ImagePath"') do (
        for %%I in (%%B) do (
            if exist "%%~I" set "RD_PATH=%%~fI"
        )
    )
)
if not exist "%RD_PATH%" if /I "%INSTALLER_TYPE%"=="EXE" set "RD_PATH=%RUSTDESK_FILE%"

:RD_PATH_OK
if exist "%RD_PATH%" goto SET_SECURITY_NOW

echo [LOI] Da chay bo cai nhung khong tim thay file thuc thi sau khi cai dat.
echo [%DATE% %TIME%] [LOI] Khong tim thay file thuc thi >> "%LOG_FILE%"
echo Vui long kiem tra lai goi "%RUSTDESK_FILE%".
echo.
if "%IS_SILENT%"=="0" pause
exit /b 1

:SET_SECURITY_NOW
echo [%DATE% %TIME%] RD_PATH: %RD_PATH% >> "%LOG_FILE%"

:: 1. Dat mat khau co dinh
"%RD_PATH%" --password Bvdkkh@2026
if errorlevel 1 (
    echo [LOI] Khong thiet lap duoc mat khau %APP_DISPLAY%.
    echo [%DATE% %TIME%] [LOI] --password fail >> "%LOG_FILE%"
    echo.
    if "%IS_SILENT%"=="0" pause
    exit /b 1
)

:: 2. Thiet lap Unlock PIN & day cac tuy chon khoa cai dat qua CLI (neu duoc ho tro)
"%RD_PATH%" --set-unlock-pin Bvdkkh@2026 >nul 2>&1
"%RD_PATH%" --config verification-method use-permanent-password >nul 2>&1
"%RD_PATH%" --config approve-mode password >nul 2>&1
"%RD_PATH%" --config allow-remote-config-modification N >nul 2>&1
"%RD_PATH%" --config hide-server-settings Y >nul 2>&1
"%RD_PATH%" --config hide-security-settings Y >nul 2>&1
"%RD_PATH%" --config hide-proxy-settings Y >nul 2>&1
"%RD_PATH%" --config hide-websocket-settings Y >nul 2>&1
"%RD_PATH%" --config hide-stop-service Y >nul 2>&1
"%RD_PATH%" --config disable-change-permanent-password Y >nul 2>&1
"%RD_PATH%" --config disable-change-id Y >nul 2>&1
"%RD_PATH%" --config allow-remove-wallpaper N >nul 2>&1
"%RD_PATH%" --config allow-auto-update Y >nul 2>&1

:CONFIG_SERVICE_AUTOSTART
echo Dang cau hinh chay ngam, tu phuc hoi va tu khoi dong cho dich vu...
echo [%DATE% %TIME%] Buoc: Cau hinh service autostart va failure recovery >> "%LOG_FILE%"
sc config "%SERVICE_NAME%" start= auto >nul 2>&1

:: [Muc 8] Delay tang dan (5s -> 15s -> 60s), reset counter sau 24h thay vi 60s
sc failure "%SERVICE_NAME%" reset= 86400 actions= restart/5000/restart/15000/restart/60000 >nul 2>&1

:: Dang ky Registry de he thong va client nhan dien DA CAI DAT (NGAN CHAN THONG BAO UAC)
echo   Cap nhat dang ky he thong cho ban cai dat chinh thuc...
echo [%DATE% %TIME%]   Goi install_official.ps1 de dang ky Uninstall, InstallState, Run >> "%LOG_FILE%"
if exist "%~dp0src\install_official.ps1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\install_official.ps1" -TargetDir "%TARGET_DIR%" -MainExe "%MAIN_EXE%" -AppName "%APP_NAME%"
) else if exist "src\install_official.ps1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "src\install_official.ps1" -TargetDir "%TARGET_DIR%" -MainExe "%MAIN_EXE%" -AppName "%APP_NAME%"
)

:: Mo Firewall cho Service
netsh advfirewall firewall add rule name="%SERVICE_DISPLAY%" dir=in action=allow program="%RD_PATH%" enable=yes >nul 2>&1
netsh advfirewall firewall add rule name="%SERVICE_DISPLAY%" dir=out action=allow program="%RD_PATH%" enable=yes >nul 2>&1

echo Dang restart dich vu de ap dung toan bo cau hinh...
echo [%DATE% %TIME%] Buoc: Restart service sau config >> "%LOG_FILE%"
call :WAIT_SERVICE_STATUS Stopped "%SERVICE_NAME%"
if errorlevel 1 (
    echo [LOI] Khong dung duoc dich vu %SERVICE_DISPLAY% de ap dung cau hinh.
    echo [%DATE% %TIME%] [LOI] Khong stop duoc service >> "%LOG_FILE%"
    sc query "%SERVICE_NAME%"
    echo.
    if "%IS_SILENT%"=="0" pause
    exit /b 1
)
timeout /t 1 /nobreak >nul 2>&1
call :WAIT_SERVICE_STATUS Running "%SERVICE_NAME%"
if errorlevel 1 (
    echo [LOI] Khong khoi dong lai duoc dich vu %SERVICE_DISPLAY%.
    echo [%DATE% %TIME%] [LOI] Service khong start lai duoc >> "%LOG_FILE%"
    sc query "%SERVICE_NAME%"
    echo.
    if "%IS_SILENT%"=="0" pause
    exit /b 1
)

:APPLY_WALLPAPER
echo Dang tao hinh nen mac dinh theo ten may (%COMPUTERNAME%) va khoa doi hinh nen...
if exist "%~dp0src\set_wallpaper.ps1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\set_wallpaper.ps1"
) else if exist "src\set_wallpaper.ps1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "src\set_wallpaper.ps1"
) else if exist "%~dp0set_wallpaper.ps1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0set_wallpaper.ps1"
) else if exist "set_wallpaper.ps1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "set_wallpaper.ps1"
)

:ENABLE_WOL
echo Dang bat tinh nang Wake-on-LAN (WOL) cho cac card mang...
if exist "%~dp0src\enable_wol.ps1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\enable_wol.ps1"
) else if exist "src\enable_wol.ps1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "src\enable_wol.ps1"
) else if exist "%~dp0enable_wol.ps1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0enable_wol.ps1"
) else if exist "enable_wol.ps1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "enable_wol.ps1"
)

:CREATE_SHORTCUT
echo Dang kiem tra va xu ly shortcut "BVDKKH - Remote"...
echo [%DATE% %TIME%] Buoc: Tao shortcut >> "%LOG_FILE%"
set "RD_DIR=%TARGET_DIR%"
if "%RD_DIR:~-1%"=="\" set "RD_DIR=%RD_DIR:~0,-1%"
if "%RD_PATH:~-1%"=="\" set "RD_PATH=%RD_PATH:~0,-1%"

set "CUSTOM_ICON="
if exist "%~dp0src\icon.ico" set "CUSTOM_ICON=%~dp0src\icon.ico"
if not defined CUSTOM_ICON if exist "src\icon.ico" set "CUSTOM_ICON=%cd%\src\icon.ico"
if not defined CUSTOM_ICON if exist "%~dp0icon.ico" set "CUSTOM_ICON=%~dp0icon.ico"

set "TARGET_ICON="
if defined CUSTOM_ICON (
    if not exist "%ProgramData%\BVDKH" mkdir "%ProgramData%\BVDKH" >nul 2>&1
    copy /y "%CUSTOM_ICON%" "%ProgramData%\BVDKH\icon.ico" >nul 2>&1
    if exist "%ProgramData%\BVDKH\icon.ico" set "TARGET_ICON=%ProgramData%\BVDKH\icon.ico"
)
if not defined TARGET_ICON if defined RD_DIR (
    if defined CUSTOM_ICON copy /y "%CUSTOM_ICON%" "%RD_DIR%\icon.ico" >nul 2>&1
    if exist "%RD_DIR%\icon.ico" set "TARGET_ICON=%RD_DIR%\icon.ico"
)

:: [Muc 7] Goi script tao shortcut rieng (de bao tri, tuong thich Win 7-11)
if exist "%~dp0src\create_shortcut.ps1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\create_shortcut.ps1" -RdPath "%RD_PATH%" -RdDir "%RD_DIR%" -IconFile "%TARGET_ICON%"
) else if exist "src\create_shortcut.ps1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "src\create_shortcut.ps1" -RdPath "%RD_PATH%" -RdDir "%RD_DIR%" -IconFile "%TARGET_ICON%"
) else if exist "%~dp0create_shortcut.ps1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0create_shortcut.ps1" -RdPath "%RD_PATH%" -RdDir "%RD_DIR%" -IconFile "%TARGET_ICON%"
)

:LAUNCH_UI
echo Dang khoi chay giao dien %APP_DISPLAY%...
cd /d "%RD_DIR%"
start "" /d "%RD_DIR%" "%RD_PATH%"

:: Cho 1 giay va dam bao dich vu he thong luon o trang thai Running trong background
timeout /t 1 /nobreak >nul 2>&1

:: [Muc 2] Kiem tra service cuoi cung truoc khi bao thanh cong
echo [%DATE% %TIME%] Buoc: Kiem tra service lan cuoi >> "%LOG_FILE%"
call :WAIT_SERVICE_STATUS Running "%SERVICE_NAME%"
if errorlevel 1 (
    echo [CANH BAO] Dich vu %SERVICE_DISPLAY% dang khong chay. Dang khoi dong lai...
    echo [%DATE% %TIME%] [CANH BAO] Service khong Running o cuoi, dang retry >> "%LOG_FILE%"
    call :WAIT_SERVICE_STATUS Stopped "%SERVICE_NAME%"
    timeout /t 1 /nobreak >nul 2>&1
    call :WAIT_SERVICE_STATUS Running "%SERVICE_NAME%"
    if errorlevel 1 (
        echo [LOI] Khong dam bao duoc dich vu %SERVICE_DISPLAY% chay on dinh.
        echo [%DATE% %TIME%] [LOI] Service FAIL o cuoi script >> "%LOG_FILE%"
        sc query "%SERVICE_NAME%"
        echo.
        if "%IS_SILENT%"=="0" pause
        exit /b 1
    )
)

:: [Muc 10] Kiem tra ket noi toi relay server
echo Dang kiem tra ket noi toi may chu relay...
echo [%DATE% %TIME%] Buoc: Kiem tra ket noi relay server >> "%LOG_FILE%"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ok = $false; foreach ($port in @(21116, 21117)) { try { $t = New-Object System.Net.Sockets.TcpClient; $t.Connect('172.16.3.28', $port); $t.Close(); $ok = $true; Write-Host ('  [OK] Port ' + $port + ': ket noi thanh cong') } catch { Write-Host ('  [X] Port ' + $port + ': khong ket noi duoc') } }; if (-not $ok) { Write-Host '[CANH BAO] Khong ket noi duoc relay server 172.16.3.28. Kiem tra mang hoac firewall.' }"

:: Chuyen Working Directory cua CMD ve thu muc he thong de giai phong hoan toan handle toi thu muc CaiDat
cd /d "%SystemRoot%"

echo.
echo ==========================================================
echo [THANH CONG] Da cau hinh %APP_DISPLAY%, tao shortcut duy nhat,
echo             khoa bao mat, chay nen, hinh nen va bat WOL!
echo ==========================================================
echo.
echo [%DATE% %TIME%] === HOAN TAT THANH CONG === >> "%LOG_FILE%"
if "%IS_SILENT%"=="1" exit /b 0
pause
exit /b 0

:: ====================================================================
:: CHE DO CHI DON DEP BAN CU (--clean-old / --clean / --migrate)
:: ====================================================================
:RUN_CLEAN_ONLY
echo ==========================================================
echo        DON DEP TOAN DIEN CAC BAN CAI DAT CU
echo ==========================================================
echo.
echo Dang tien hanh tat tien trinh, go bo dich vu cu, xoa registry va shortcut cu...
echo [%DATE% %TIME%] Che do: Chi don dep ban cu (--clean-old) >> "%LOG_FILE%"
if exist "%~dp0src\install_official.ps1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\install_official.ps1" -MigrateOld -TargetDir "%ProgramFiles%\BVDKKH - Remote" -AppName "BVDKKH - Remote"
) else if exist "src\install_official.ps1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "src\install_official.ps1" -MigrateOld -TargetDir "%ProgramFiles%\BVDKKH - Remote" -AppName "BVDKKH - Remote"
)
echo.
echo ==========================================================
echo [THANH CONG] Da don dep toan bo cac ban RustDesk cu, service cu,
echo             shortcut va registry thua tren he thong!
echo ==========================================================
echo.
if "%IS_SILENT%"=="0" pause
exit /b 0

:: ====================================================================
:: HAM PHU TRO
:: ====================================================================

:: Dat RUSTDESK_FILE va INSTALLER_TYPE theo mau dau tien ton tai.
:TRY_INSTALLER
if defined RUSTDESK_FILE goto :EOF
for %%F in ("%~1") do (
    if exist "%%~fF" (
        set "RUSTDESK_FILE=%%~fF"
        set "INSTALLER_TYPE=%~2"
    )
)
goto :EOF

:: [Muc 4] Cho den khi service dat trang thai yeu cau (Stopped / Running).
:: Ho tro Unicode service name (BVĐKKH - Remote) tuyet doi, tu dong dung Stop-Service / Start-Service,
:: va tu dong force-kill tien trinh neu service bi treo qua 3s khi can Stop.
:WAIT_SERVICE_STATUS
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$target = '%~1'; " ^
    "$paramSvc = '%~2'; " ^
    "$svcName = $env:SERVICE_NAME; " ^
    "if ($paramSvc -and $paramSvc -ne '%%SERVICE_NAME%%' -and $paramSvc -ne $svcName) { $svcName = $paramSvc }; " ^
    "if (-not $svcName) { $svcName = 'rustdesk' }; " ^
    "if ($target -eq 'Stopped') { " ^
    "    $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue; " ^
    "    if (-not $svc -or $svc.Status -eq 'Stopped') { exit 0 }; " ^
    "    Stop-Service -Name $svcName -Force -ErrorAction SilentlyContinue; " ^
    "    & sc.exe stop $svcName | Out-Null; " ^
    "    $maxWait = 30; $count = 0; $killed = $false; " ^
    "    while ($count -lt $maxWait) { " ^
    "        try { " ^
    "            $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue; " ^
    "            if (-not $svc) { exit 0 }; " ^
    "            $svc.Refresh(); " ^
    "            if ($svc.Status -eq 'Stopped') { exit 0 }; " ^
    "        } catch {}; " ^
    "        if ($count -ge 6 -and -not $killed) { " ^
    "            $killed = $true; " ^
    "            try { " ^
    "                $wmi = Get-WmiObject Win32_Service -Filter ('Name=''' + $svcName + '''') -ErrorAction SilentlyContinue; " ^
    "                if ($wmi -and $wmi.ProcessId -gt 0) { " ^
    "                    Stop-Process -Id $wmi.ProcessId -Force -ErrorAction SilentlyContinue; " ^
    "                }; " ^
    "            } catch {}; " ^
    "            Get-Process | Where-Object { $_.ProcessName -match '(?i)(bvdkkh|rustdesk)' } | Stop-Process -Force -ErrorAction SilentlyContinue; " ^
    "        }; " ^
    "        Start-Sleep -Milliseconds 500; " ^
    "        $count++; " ^
    "    }; " ^
    "    Write-Host ('[TIMEOUT] Service khong dat trang thai: Stopped sau ' + ($maxWait / 2) + ' giay'); " ^
    "    exit 1; " ^
    "} else { " ^
    "    $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue; " ^
    "    if ($svc) { $svc.Refresh(); if ($svc.Status -eq 'Running') { exit 0 } }; " ^
    "    Start-Service -Name $svcName -ErrorAction SilentlyContinue; " ^
    "    & sc.exe start $svcName | Out-Null; " ^
    "    $maxWait = 30; $count = 0; $retryCount = 0; $maxRetry = 3; $lastRetry = 0; " ^
    "    while ($count -lt $maxWait) { " ^
    "        try { " ^
    "            $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue; " ^
    "            if ($svc) { " ^
    "                $svc.Refresh(); " ^
    "                if ($svc.Status -eq 'Running') { exit 0 }; " ^
    "                if ($svc.Status -eq 'Stopped' -and ($count - $lastRetry) -ge 6 -and $retryCount -lt $maxRetry) { " ^
    "                    $retryCount++; $lastRetry = $count; " ^
    "                    Write-Host ('  [Retry ' + $retryCount + '/' + $maxRetry + '] Dang khoi dong lai service...'); " ^
    "                    Start-Service -Name $svcName -ErrorAction SilentlyContinue; " ^
    "                    & sc.exe start $svcName | Out-Null; " ^
    "                }; " ^
    "            }; " ^
    "        } catch {}; " ^
    "        Start-Sleep -Milliseconds 500; " ^
    "        $count++; " ^
    "    }; " ^
    "    Write-Host ('[TIMEOUT] Service khong dat trang thai: Running sau ' + ($maxWait / 2) + ' giay'); " ^
    "    exit 1; " ^
    "}"
if errorlevel 1 exit /b 1
exit /b 0
