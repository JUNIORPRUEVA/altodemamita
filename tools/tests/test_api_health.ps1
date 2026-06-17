$uri = "https://altodemamita.com/api/health"
Write-Host "Testing: $uri"
try {
    $response = Invoke-WebRequest -Uri $uri -TimeoutSec 15 -UseBasicParsing
    Write-Host "✅ API RESPONDING"
    Write-Host "Status: $($response.StatusCode)"
    Write-Host "Response: $($response.Content)"
} catch {
    Write-Host "❌ API NOT RESPONDING"
    Write-Host "Error: $($_.Exception.Message)"
}
