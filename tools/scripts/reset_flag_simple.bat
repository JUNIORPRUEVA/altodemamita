@echo off
echo Resetting initial_cloud_upload flag from SharedPreferences...
cd /d "C:\Users\pc\DEV\PROYECTOS\CLIENTES\SISTEMA_SOLARES\app_local"
C:\src\flutter\bin\flutter.bat pub global run shared_preferences:clear 2>nul
echo.
echo Also deleting the SharedPreferences file directly...
del /f /q "%USERPROFILE%\AppData\Local\SistemaSolares\shared_preferences\*.xml" 2>nul
echo.
echo Done. Flag reset.
