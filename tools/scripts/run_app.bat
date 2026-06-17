@echo off
cd /d "C:\Users\pc\DEV\PROYECTOS\CLIENTES\SISTEMA_SOLARES\app_local"
C:\src\flutter\bin\flutter.bat run -d windows --dart-define=SYNC_API_BASE_URL=http://localhost:3000
