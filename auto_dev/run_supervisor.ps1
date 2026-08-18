# AI Dev Supervisor launcher
# Invoked by run_once.cmd from Task Scheduler.
# Logs stdout/stderr to scheduler_stdout.log in the same folder.

$py = "D:\game\auto_dev\supervisor.py"
$log = "D:\game\auto_dev\scheduler_stdout.log"

& $py 2>&1 | Out-File -FilePath $log -Append -Encoding utf8
exit $LASTEXITCODE