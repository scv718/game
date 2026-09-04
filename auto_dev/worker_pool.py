"""026~052 (+022) 그룹을 동시 3개 제한으로 순차 재실행하는 작업자 풀.

메모리 고갈(WebKit 크래시) 방지를 위해 동시 실행 그룹 수를 CONCURRENCY로 제한.
각 그룹은 run_lane_delayed.ps1(or run_lane.ps1)로 supervisor --group 실행.
그룹이 완료(실행 가능 서브태스크 없음)되면 다음 그룹을 시작.
"""
import subprocess, sys, time, os

LOCAL = os.environ.get("LOCALAPPDATA", r"C:\Users\skfnx\AppData\Local")
PY = os.path.join(LOCAL, "Python", "pythoncore-3.14-64", "python.exe")
SUP = r"D:\game\auto_dev\supervisor.py"
LANE = r"D:\game\auto_dev\run_lane_delayed.ps1"
LOG = r"D:\game\auto_dev\logs\worker_pool.log"
CONCURRENCY = 3
COMPLETE_STATES = ("QUEUED", "IMPLEMENT", "REVIEW", "FIX", "REVIEW_PARSE_ERROR")

def log(msg):
    line = f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] {msg}"
    print(line, flush=True)
    with open(LOG, "a", encoding="utf-8") as f:
        f.write(line + "\n")

def group_done(group):
    try:
        out = subprocess.run([PY, SUP, "--group", group, "--status"],
                             capture_output=True, text=True, encoding="utf-8",
                             errors="replace", timeout=60).stdout
    except Exception as e:
        log(f"{group} 상태확인 오류: {e}")
        return False
    return not any(s in out for s in COMPLETE_STATES)

def run_lane(group, delay=0):
    args = ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass",
            "-File", LANE, "-Group", group, "-Delay", str(delay)]
    return subprocess.Popen(args)

def main():
    groups = ["TASK-022"] + [f"TASK-{n:03d}" for n in range(26, 53)]
    todo = list(groups)
    running = {}   # pid -> (group, proc)
    log(f"작업자 풀 시작: {len(todo)}개 그룹, 동시 실행 {CONCURRENCY}개 제한")

    while todo or running:
        # 완료된 프로세스 회수
        for pid in list(running.keys()):
            group, proc = running[pid]
            if proc.poll() is not None:
                log(f"[완료] {group} (exit={proc.returncode}) -> 실행가능 남음: {not group_done(group)}")
                del running[pid]

        # 슬롯이 비면 다음 그룹 시작
        while len(running) < CONCURRENCY and todo:
            g = todo.pop(0)
            if group_done(g):
                log(f"[스킵] {g} 이미 완료됨")
                continue
            p = run_lane(g, delay=0)
            running[p.pid] = (g, p)
            log(f"[시작] {g} (pid={p.pid}), 실행중 {len(running)}/{CONCURRENCY}")

        if not running:
            break
        time.sleep(20)

    log("작업자 풀 종료: 모든 그룹 처리 완료")

if __name__ == "__main__":
    main()
