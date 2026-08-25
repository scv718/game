param([int]$MaxCycles = 200)
$py = "$env:LOCALAPPDATA\Python\pythoncore-3.14-64\python.exe"
$sup = "D:\game\auto_dev\supervisor.py"
for ($i = 1; $i -le $MaxCycles; $i++) {
    & $py $sup 2>&1 | Out-File -FilePath "D:\game\auto_dev\logs\phase_lane.log" -Append -Encoding utf8
    Start-Sleep -Seconds 10
    $status = (& $py $sup --status 2>&1) | Out-String
    if ($status -notmatch "QUEUED|IMPLEMENT|REVIEW|FIX|REVIEW_PARSE_ERROR") {
        "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] phase 큐 완료 - 레인 종료" | Out-File -FilePath "D:\game\auto_dev\logs\phase_lane.log" -Append -Encoding utf8
        break
    }
}