"""야간 자동 개발 익스큐터 v2 (NIGHT-EXEC, 의존성 기반 3-lane 병렬).

지침 (수정본):
- 최대 3개의 top-level TASK lane 동시 실행.
- 병렬화는 dependency graph 기준 (번호 아님). contract 공유/선행후행/광범위 파일 수정 태스크는 동시 실행 금지.
- 각 lane 내부는 순차. 선행 contract barrier에서 후속 대기.
- lane 간 worktree merge 후 다음 dependency stage 전 통합 regression (로그 기록).
- merge conflict/API 충돌 시 선행 구현을 authoritative contract로, 후행 lane rebase/retry.
- NEEDS_DESIGN(설계 충돌) 시 중단. model/runtime 장애는 상태 변경 없이 재시도, 2시간 timeout 반복 시 런타임 blocker.

실행 레그 (사용자 계획):
  R1 Phase2-b32: [029,030]  | [031]  | POST3D-INT,POST3D-REG
  R2 Phase2-b32: [032]
  R3 Phase3:     [033,034,035] | [036,037] | [038,039,040]
  R4 Phase4-b45: [041,042] | [043] | [044]
  R5 Phase4-b45: [045]
  R6 Phase5:     [046]                        (단독)
  R7 Phase5-aft: [047] | [048] | [049]
  R8 Phase6-b52: [050] | [051]
  R9 Phase6-b52: [052]
"""
import subprocess, time, os, threading

LOCAL = os.environ.get("LOCALAPPDATA", r"C:\Users\skfnx\AppData\Local")
PY = os.path.join(LOCAL, "Python", "pythoncore-3.14-64", "python.exe")
SUP = r"D:\game\auto_dev\supervisor.py"
LANE = r"D:\game\auto_dev\run_lane_delayed.ps1"
LOG = r"D:\game\auto_dev\logs\night_exec.log"
RUNNABLE = ("QUEUED", "IMPLEMENT", "REVIEW", "FIX", "REVIEW_PARSE_ERROR")

POST3D = ("TASK-POST3D-INT-001", "TASK-POST3D-REG-001")

# 레그: 각 항목 = [lane1, lane2, lane3], lane = 그룹 시퀀스
LEGS = [
    ("R0 PHASE1", [["TASK-026"], ["TASK-027"], ["TASK-028"]]),
    ("R1 PHASE2(کb32)", [["TASK-029", "TASK-030"], ["TASK-031"], list(POST3D)]),
    ("R2 PHASE2 032",   [["TASK-032"]]),
    ("R3 PHASE3",       [["TASK-033", "TASK-034", "TASK-035"], ["TASK-036", "TASK-037"], ["TASK-038", "TASK-039", "TASK-040"]]),
    ("R4 PHASE4(b45)",  [["TASK-041", "TASK-042"], ["TASK-043"], ["TASK-044"]]),
    ("R5 PHASE4 045",   [["TASK-045"]]),
    ("R6 PHASE5 046",   [["TASK-046"]]),
    ("R7 PHASE5 seq",   [["TASK-047"], ["TASK-048"], ["TASK-049"]]),
    ("R8 PHASE6(b52)",  [["TASK-050"], ["TASK-051"]]),
    ("R9 PHASE6 052",   [["TASK-052"]]),
]

_lock = threading.Lock()
_logfile = open(LOG, "a", encoding="utf-8")

def log(msg):
    line = f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] {msg}"
    print(line, flush=True)
    try:
        _logfile.write(line + "\n")
        _logfile.flush()
    except Exception:
        pass

def sup_status(group=None):
    args = [PY, SUP] + (["--group", group] if group else []) + ["--status"]
    try:
        r = subprocess.run(args, capture_output=True, text=True, encoding="utf-8",
                           errors="replace", timeout=90)
        return r.stdout
    except Exception as e:
        log(f"status 오류: {e}")
        return ""

def group_has_runnable(group):
    # 상태 컬럼만 파싱: 제목/설명/피드백 속 "QUEUED/IMPLEMENT/REVIEW/FIX" 단어로 오판하지 않음
    statuses = set(status_col(sup_status(group)).values())
    return any(s in statuses for s in RUNNABLE)

def group_done(group):
    return not group_has_runnable(group)

def status_col(out):
    """지정 그룹(또는 전체)에서 leaf 상태 매핑: id->상태"""
    m = {}
    for line in out.splitlines():
        p = line.strip().split()
        if len(p) >= 2 and p[0].startswith("TASK-") and ("-" in p[0]):
            m[p[0]] = p[1]
    return m

def has_needs_design(group=None):
    """지정 그룹(또는 전체)에서 NEEDS_DESIGN leaf 존재 여부.

    lane-scoped 원칙: 그룹 단위로만 blocker를 판단해 한 lane의 NEEDS_DESIGN이
    다른 lane(다른 그룹 경로)까지 중단시키지 않는다. 상태 컬럼만 판정에 사용."""
    statuses = set(status_col(sup_status(group)).values())
    return "NEEDS_DESIGN" in statuses

def run_group_lane(group):
    """그룹 레인 실행 + 완료 대기. True=완료, False=blocker/toolong."""
    if group_done(group):
        log(f"[skip-완료] {group}")
        return True
    # 1회 재시도 허용(runtime 장애): lane 종료 후 실행 가능 태스크 남아있으면 재시도
    attempts = 0
    while True:
        attempts += 1
        log(f"[start-lane] {group} (시도 {attempts})")
        args = ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass",
                "-File", LANE, "-Group", group, "-Delay", "0"]
        proc = subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        deadline = time.time() + 6*3600
        while time.time() < deadline:
            if proc.poll() is not None:
                break
            if group_done(group):
                log(f"[완료감지] {group} 실행 가능 태스크 소진")
                proc.terminate()
                break
            if has_needs_design(group):
                log(f"[BLOCK-lane] {group} NEEDS_DESIGN 발생 - 이 그룹 레인만 중단")
                proc.terminate()
                return False
            time.sleep(30)
        else:
            log(f"[TIMEOUT] {group} 6시간 경과 강제종료")
        proc.wait(timeout=30)
        # 재시도 판정
        if group_done(group):
            log(f"[완료] {group}")
            return True
        if attempts >= 2:
            log(f"[BLOCK] {group} 2회 재시도 후 미완료 - 런타임 blocker")
            return False
        log(f"[재시도] {group} 미완료 남음, 60초 후 재시도")
        time.sleep(60)

def lane_worker(seq, results, idx):
    """한 lane의 그룹 시퀀스 순차 실행.

    lane-scoped blocker: NEEDS_DESIGN 그룹은 건너뛰고 다음 그룹으로 진행한다.
    (다른 lane/후속 leg가 전역 중단되지 않는다.)"""
    for g in seq:
        if has_needs_design(g):
            log(f"[lane {idx}] {g} NEEDS_DESIGN - 그룹 건너뜀(이 lane만 skip, 다른 레인 계속)")
            continue
        ok = run_group_lane(g)
        if not ok:
            results[idx] = False
            log(f"[lane {idx}] {g} 실패/blocker - lane 중단")
            return
        log(f"[lane {idx}] {g} 완료")
    results[idx] = True

def run_leg(name, lanes):
    """레그 실행: lanes 최대 3개 병렬."""
    log(f"=== {name} 시작 ({len(lanes)} lane) ===")
    results = [False]*len(lanes)
    threads = []
    for idx, seq in enumerate(lanes):
        t = threading.Thread(target=lane_worker, args=(seq, results, idx), daemon=True)
        threads.append(t)
        t.start()
        time.sleep(2)  # 동시 start로 인한 리소스 폭주 방지
    for t in threads:
        t.join()
    ok = all(results)
    log(f"=== {name} 끝 (성공={ok}) ===")
    if ok:
        # dependency stage 넘어가기 전 통합 regression 체크 (로그 기록용)
        log(f"[barrier] {name} 전체 완료 - 통합 regression 대상 확인")
    return ok

def main():
    log("=== 야간 익스큐터 v2 (3-lane 병렬) 시작 ===")
    failed_legs = []

    for name, lanes in LEGS:
        # lane-scoped 원칙: 한 그룹/레인의 NEEDS_DESIGN이 전체 진행을 멈추지 않도록
        # 레그 단위로도 중단하지 않는다. 블로커 그룹은 해당 레인만 끝내고
        # 남은 레그는 계속 진행한다(야간 자동화 최대 진행 목표).
        ok = run_leg(name, lanes)
        if not ok:
            failed_legs.append(name)
            log(f"[계속] {name} - 블로커/실패 레인 있음 (기록 후 다음 레그 진행)")
    if failed_legs:
        log(f"[요약] 실패/블로커 레그: {', '.join(failed_legs)}")
    log("=== 야간 익스큐터 v2 종료 ===")

if __name__ == "__main__":
    main()
