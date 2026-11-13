@echo off
rem Run the app as a Windows desktop app (debug, hot reload with "r" in this console).
rem Extra arguments go to flutter, e.g.: tool\run_windows.cmd --release
setlocal
cd /d "%~dp0.."
rem Upper-case the drive letter: Flutter keys its build cache on the path, and
rem mixing "d:\" and "D:\" builds wipes windows\flutter\ephemeral.
for %%D in (A B C D E F G H I J K L M N O P Q R S T U V W X Y Z) do if /i "%CD:~0,1%"=="%%D" cd /d "%%D%CD:~1%"
where flutter >nul 2>nul || set "PATH=C:\dev\flutter\bin;%PATH%"
call flutter run -d windows %*
