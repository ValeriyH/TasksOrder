@echo off
rem Start the Android emulator in its own window.
rem Default AVD is TasksOrder_API36; pass another name to override.
rem   tool\start_emulator.cmd                 start and return at once
rem   tool\start_emulator.cmd --wait          start and wait until Android has booted
rem   tool\start_emulator.cmd Pixel_8_API35   start another AVD
rem   tool\start_emulator.cmd --list          list AVDs
rem VS Code runs it with --wait before the "TasksOrder (Android)" launch.
setlocal EnableDelayedExpansion
set "SDK=%ANDROID_HOME%"
if not defined SDK set "SDK=%ANDROID_SDK_ROOT%"
if not defined SDK set "SDK=%LOCALAPPDATA%\Android\Sdk"
set "EMU=%SDK%\emulator\emulator.exe"
set "ADB=%SDK%\platform-tools\adb.exe"
if not exist "%EMU%" (
  echo Emulator not found: "%EMU%"
  exit /b 1
)

set "AVD="
set "WAIT="
:args
if "%~1"=="" goto args_done
if /i "%~1"=="--list" (
  "%EMU%" -list-avds
  exit /b 0
)
if /i "%~1"=="--wait" (set "WAIT=1") else (set "AVD=%~1")
shift
goto args
:args_done
if not defined AVD set "AVD=TasksOrder_API36"

rem Do not start a second copy if an emulator is already up.
set "RUNNING="
if exist "%ADB%" (
  "%ADB%" devices | findstr /b "emulator-" >nul && set "RUNNING=1"
)
if defined RUNNING (
  echo An emulator is already running.
) else (
  echo Starting %AVD% ...
  start "Android Emulator - %AVD%" "%EMU%" -avd %AVD%
)

if not defined WAIT exit /b 0
if not exist "%ADB%" (
  echo adb not found: "%ADB%"
  exit /b 1
)

rem Wait for the device, then for Android to finish booting (up to ~3 minutes).
echo Waiting for the emulator to boot ...
"%ADB%" -e wait-for-device
for /l %%i in (1,1,90) do (
  set "BOOTED="
  for /f "delims=" %%b in ('"%ADB%" -e shell getprop sys.boot_completed 2^>nul') do set "BOOTED=%%b"
  if "!BOOTED!"=="1" (
    echo Emulator is ready.
    "%ADB%" devices
    exit /b 0
  )
  rem "timeout" refuses to run without a console (VS Code tasks); ping is the pause.
  ping -n 3 127.0.0.1 >nul
)
echo Emulator did not finish booting in time.
exit /b 1
