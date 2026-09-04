"""완전 자율 2-lane 병렬 실행기 (AUTO-LANE).

supervisor를 leaf 단위로 드라이브한다: `--group G --task L` 조합은
전역 queue 락을 걸지 않으면서 NEEDS_DESIGN 블로커도 무시하고 해당
leaf를 강제 실행한다. 이를 이용해 서로 다른 worktree 그룹을 병렬 lane으로
돌릴 수 있다(락 경합 없음).

사용:  python auto_lane.py --groups G1,G2,... [--passes N]
동작:  그룹 목록을 순회하며, 각 그룹의 비-DONE leaf를 상태순으로
       --group G --task L 로 순차 실행. 한 그룹이 DONE이 아니면 반복.
       모든 그룹의 실행 가능한 leaf가 소진되면 종료.

동기:  30B CPU offload 환경에서는 정상 작업도 15~30분 이상 걸린다.
       따라서 supervisor를 고정 wall-clock 시간으로 강제 종료하지 않는다.
       대신 '실제 progress'를 관찰해 충분히 오래 진전이 없을 때만
       NO_PROGRESS_STALLED로 판정해 중단한다.
"""
import json
import os
import subprocess
import sys
import time
import datetime
import glob
import argparse

LOCAL = os.environ.get("LOCALAPPDATA", r"C:\Users\skfnx\AppData\Local")
PY = os.path.join(LOCAL, "Python", "pythoncore-3.14-64", "python.exe")
SUP = r"D:\game\auto_dev\supervisor.py"
BASE = r"D:\game\auto_dev"
CONFIG_PATH = os.path.join(BASE, "config.json")
LOG_DIR = os.path.join(BASE, "logs")
os.makedirs(LOG_DIR, exist_ok=True)

# leaf는 러너블 이지만 그룹 서브트리에서 확인
RUNNABLE = ("QUEUED", "IMPLEMENT", "REVIEW", "FIX", "REVIEW_PARSE_ERROR", "NEEDS_DESIGN")

KEEP = ("QUEUED", "IMPLEMENT", "REVIEW", "FIX", "REVIEW_PARSE_ERROR", "NEEDS_DESIGN")


def _cfg(key, default=None):
    try:
        with open(CONFIG_PATH, encoding="utf-8") as f:
            return json.load(f).get(key, default)
    except Exception:
        return default


def log(msg):
    line = "[%s] %s" % (time.strftime("%Y-%m-%d %H:%M:%S"), msg)
    print(line, flush=True)
    try:
        with open(os.path.join(LOG_DIR, "auto_lane.log"), "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except Exception:
        pass


def _tree_kill(pid):
    """프로세스 트리 강제 종료 (Windows taskkill /T /F)."""
    try:
        subprocess.run(["taskkill", "/PID", str(pid), "/T", "/F"],
                       capture_output=True, timeout=30)
    except Exception:
        try:
            os.kill(pid, 9)
        except Exception:
            pass


def _progress_signals(group):
    """감시 대상 progress sink (mtime, size) 목록.
    - supervisor 그룹 로그 파일
    - 하네스 runs/* 의 최신 events.jsonl/checkpoint/final.json
    - 워크트리 최신 *_test.gd / 변경 파일
    반환: 해당 sign자료의 (max_mtime, max_agg_size)"""
    best_mtime = 0.0
    best_size = 0
    # 1) supervisor 로그 캡처 (그룹 suffix)
    try:
        today = datetime.datetime.now().strftime("%Y%m%d")
        cands = glob.glob(os.path.join(BASE, "logs", today + "_" + group + ".log")) + \
                glob.glob(os.path.join(BASE, "logs", today + ".log"))
        for p in cands:
            st = os.stat(p)
            best_mtime = max(best_mtime, st.st_mtime)
            best_size += st.st_size
    except Exception:
        pass
    # 2) 하네스 runs 최신 아티팩트
    hdir = _cfg("harness_dir", r"D:\coding-harness")
    runs_dir = os.path.join(hdir, "runs")
    try:
        for p in glob.glob(os.path.join(runs_dir, "**", "events.jsonl"), recursive=True) + \
                 glob.glob(os.path.join(runs_dir, "**", "checkpoint.json"), recursive=True) + \
                 glob.glob(os.path.join(runs_dir, "**", "final.json"), recursive=True):
            st = os.stat(p)
            if st.st_mtime > best_mtime:
                best_mtime = st.st_mtime
            best_size += st.st_size
    except Exception:
        pass
    return best_mtime, best_size


def wait_no_progress(group, proc, timeout_sec=7200, no_progress_sec=1200,
                     sample_interval=20):
    """supervisor를 고정 wall-clock으로 죽이지 않고 진행을 관찰한다.
    - 지속적으로 progress(파일/로그/아티팩트 mtime, SIZE 증가)가 있으면 계속 대기.
    - no_progress_sec 동안 progress가 전혀 없으면 NO_PROGRESS_STALLED 판정.
    - 안전망으로 전체 timeout_sec 초과 시에도 중단(벡업 가드).
    반환: (exitcode, "ok" | "no_progress_stalled" | "overall_timeout")"""
    started = time.time()
    last_mtime, last_size = _progress_signals(group)
    last_change = time.time()

    while True:
        if proc.poll() is not None:
            return proc.returncode, "ok"
        cur_mtime, cur_size = _progress_signals(group)
        progressed = (cur_mtime > last_mtime + 1.0) or (cur_size > last_size)
        if progressed:
            last_mtime, last_size = cur_mtime, cur_size
            last_change = time.time()
        elapsed = time.time() - last_change
        total = time.time() - started
        if elapsed >= no_progress_sec:
            log("NO_PROGRESS_STALLED: %s초 동안 진행 없음 (%s) - 트리 종료" % (
                no_progress_sec, group))
            _tree_kill(proc.pid)
            return None, "no_progress_stalled"
        if total >= timeout_sec:
            log("OVERALL_TIMEOUT: %s초 초과 (%s) - 트리 종료" % (timeout_sec, group))
            _tree_kill(proc.pid)
            return None, "overall_timeout"
        time.sleep(sample_interval)
        try:
            if proc.poll() is not None:
                return proc.returncode, "ok"
        except Exception:
            return None, "ok"


def sup(group, args, timeout_sec=None, no_progress_sec=None):
    """supervisor 1회 호출. 고정 wall-clock timeout이 아닌 Progress Watchdog으로 진행 감시.
    args: supervisor에 넘길 리스트 (예: ['--task', 'TASK-027-5'])"""
    if timeout_sec is None:
        timeout_sec = int(_cfg("lane_overall_timeout_sec", 7200))
    if no_progress_sec is None:
        no_progress_sec = int(_cfg("lane_no_progress_sec", 1200))
    full = [PY, SUP, "--group", group] + args
    env = os.environ.copy()
    env["PYTHONIOENCODING"] = "utf-8"
    proc = subprocess.Popen(full, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True, encoding="utf-8", errors="replace", env=env,
                            creationflags=getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0))
    try:
        rc, why = wait_no_progress(group, proc, timeout_sec=timeout_sec,
                                   no_progress_sec=no_progress_sec)
        out = ""
        err = ""
        try:
            out, err = proc.communicate(timeout=30)
        except Exception:
            pass
        if why != "ok":
            log("supervisor %s: %s" % (why, args))
            return ""
        if rc is not None and rc != 0:
            log("supervisor exit=%s: %s" % (rc, args))
        return (out or "") + (err or "")
    except Exception as e:
        log("supervisor err: %s | %s" % (e, args))
        _tree_kill(proc.pid)
        return ""


def group_leaf_ids(group):
    """그룹의 모든 leaf(id) 목록을 --status 출력에서 발견."""
    out = sup(group, ["--status"], timeout_sec=600, no_progress_sec=300)
    ids = []
    for line in out.splitlines():
        p = line.strip().split()
        if len(p) >= 2 and p[0].startswith("TASK-") and p[0] != "TASK-":
            ids.append(p[0])
    return ids


def group_leaf_statuses(group):
    out = sup(group, ["--status"], timeout_sec=600, no_progress_sec=300)
    m = {}
    for line in out.splitlines():
        p = line.strip().split()
        if len(p) >= 2 and p[0].startswith("TASK-"):
            m[p[0]] = p[1]
    return m


def run_one(group, leaf, timeout_sec=None, no_progress_sec=None):
    log(">> %s @ %s" % (leaf, group))
    out = sup(group, ["--task", leaf], timeout_sec=timeout_sec, no_progress_sec=no_progress_sec)
    # 구현 타임아웃/에러가 있어도 상태는 queue에 반영됨
    return out


def group_remaining(group):
    """그룹의 미완료 leaf 목록. root가 단일 leaf(POST3D-VIS-001 등)이면
    root 자신도 포함한다."""
    st = group_leaf_statuses(group)
    ids = [k for k, v in st.items() if v in KEEP]
    # root 자신이 leaf인 경우(root가 children 없고 QUEUED 등) 포함
    if group in st:
        # root가 leaf보다 children이 있으면 이미 children이 별도 잡힘
        children = [k for k in ids if k != group and k.startswith(group)]
        if not children:
            return ids  # root 단일 leaf면 끝
        return [k for k in ids if k != group]
    return ids


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--groups", required=True, help="콤마 구분 그룹 목록")
    ap.add_argument("--passes", type=int, default=6, help="그룹당 최대 순회 횟수")
    ap.add_argument("--retry-needs-design", action="store_true",
                    help="NEEDS_DESIGN leaf도 재시도 (기본은 건너뜀)")
    args = ap.parse_args()
    groups = [g.strip() for g in args.groups.split(",") if g.strip()]
    overall_timeout = int(_cfg("lane_overall_timeout_sec", 7200))
    no_progress = int(_cfg("lane_no_progress_sec", 1200))
    log("=== AUTO-LANE 시작 groups=%s passes=%s (overall=%s no-progress=%s) ===" % (
        groups, args.passes, overall_timeout, no_progress))

    for group in groups:
        log("--- 그룹 %s 시작 ---" % group)
        for p in range(1, args.passes + 1):
            rem = group_remaining(group)
            marked_nd = []
            # NEEDS_DESIGN leaf는 재시도하려면 명시; 아닐 경우 제외
            if not args.retry_needs_design:
                nd = [k for k in rem if group_leaf_statuses(group).get(k) == "NEEDS_DESIGN"]
                marked_nd = nd
            active = [k for k in rem if k not in marked_nd]
            if not active:
                log("[%s] 실행 가능 leaf 없음 (pass %d) - 그룹 종료" % (group, p))
                break
            log("[%s] pass %d 실행 leaf: %s" % (group, p, active))
            for leaf in active:
                run_one(group, leaf, timeout_sec=overall_timeout,
                        no_progress_sec=no_progress)
            # 상태 갱신 후 다시 검사
            st = group_leaf_statuses(group)
            done_count = sum(1 for k, v in st.items() if v == "DONE" and k != group)
            log("[%s] pass %d 완료, 그룹 DONE=%d/%d" % (
                group, p, done_count, max(1, len(st) - 1)))
        log("--- 그룹 %s 종료 ---" % group)

    log("=== AUTO-LANE 종료 ===")


if __name__ == "__main__":
    main()
