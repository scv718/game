# AI Dev Supervisor - Task Scheduler register/unregister
# Usage: powershell -ExecutionPolicy Bypass -File install_schedule.ps1 [-Uninstall]

param(
    [switch]$Uninstall
)

$taskName = "AI_Dev_Supervisor"
$runOnce = "D:\game\auto_dev\run_once.cmd"

if ($Uninstall) {
    schtasks /Delete /TN $taskName /F
    Write-Host "Scheduled task removed: $taskName"
    exit
}

schtasks /Create /TN $taskName /TR "`"$runOnce`"" /SC HOURLY /MO 1 /ST 09:00 /F

if ($LASTEXITCODE -eq 0) {
    Write-Host "Scheduled task created: $taskName (hourly from 09:00)"
    schtasks /Query /TN $taskName
} else {
    Write-Host "Failed to create scheduled task (exit=$LASTEXITCODE)"
}