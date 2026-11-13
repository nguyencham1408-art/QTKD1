# Khoi chay server AI Agent Dai Thanh tren Localhost
Write-Host "Dang khoi chay AI Agent Localhost tren http://localhost:5000 ..." -ForegroundColor Cyan
Start-Process "http://localhost:5000"
& "$PSScriptRoot\server.ps1" -Port 5000

