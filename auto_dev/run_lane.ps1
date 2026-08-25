param(
    [Parameter(Mandatory=$true)][string]$Group,
    [int]$MaxCycles = 40
)
$py = "$env:LOCALAPPDATA\Python\pythoncore-3.14-64\python.exe"
$sup = "D:\game\auto_dev\supervisor.py"
for ($i = 1; $i -le $MaxCycles; $i++) {
    & $py $sup --group $Group 2>&1 | Out-File -FilePath "D:\game\auto_dev\logs\lane_$Group.log" -Append -Encoding utf8
    Start-Sleep -Seconds 10
    $status = (& $py $sup --group $Group --status 2>&1) | Out-String
    if ($status -notmatch "QUEUED|IMPLEMENT|REVIEW|FIX") {
        "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] 그룹 $Group 완료 - 레인 종료" | Out-File -FilePath "D:\game\auto_dev\logs\lane_$Group.log" -Append -Encoding utf8
        break
    }
}
