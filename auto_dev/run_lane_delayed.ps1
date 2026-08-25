param(
    [Parameter(Mandatory=$true)][string]$Group,
    [int]$Delay = 0
)
if ($Delay -gt 0) { Start-Sleep -Seconds $Delay }
& "D:\game\auto_dev\run_lane.ps1" -Group $Group