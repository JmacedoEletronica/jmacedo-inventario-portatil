@echo off
setlocal
title J. MACEDO - Inventario do computador
color 0B
if not exist "%~dp0Inventario-Jmacedo.ps1" (
  echo Nao foi encontrado o arquivo Inventario-Jmacedo.ps1.
  echo Extraia ou copie a pasta completa antes de executar.
  pause
  exit /b 1
)
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Inventario-Jmacedo.ps1" %*
set "jm_exit=%errorlevel%"
if not "%jm_exit%"=="0" (
  echo.
  echo Nao foi possivel concluir. Confira a mensagem acima.
  echo Se houver bloqueio da empresa, solicite a liberacao ao TI.
  pause
)
exit /b %jm_exit%
