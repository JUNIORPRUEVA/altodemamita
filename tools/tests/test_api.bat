@echo off
REM Test API health endpoint
echo Testing API at https://altodemamita.com/api/health
echo.

REM Use PowerShell with .NET for HTTP request (no security warnings)
powershell -NoProfile -Command ^
  "[Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}; " ^
  "try { " ^
  "  $client = New-Object System.Net.HttpClient; " ^
  "  $task = $client.GetAsync('https://altodemamita.com/api/health'); " ^
  "  $task.Wait(15000); " ^
  "  if ($task.Result.IsSuccessStatusCode) { " ^
  "    Write-Host '✅ API OK - Status:' $task.Result.StatusCode; " ^
  "    $content = $task.Result.Content.ReadAsStringAsync().Result; " ^
  "    Write-Host $content; " ^
  "  } else { " ^
  "    Write-Host '⚠️ API Responded - Status:' $task.Result.StatusCode; " ^
  "  } " ^
  "} catch { " ^
  "  Write-Host '❌ API NOT RESPONDING'; " ^
  "  Write-Host 'Error:' $_.Exception.Message; " ^
  "}"
