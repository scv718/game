"""완전 자율 병렬 실행기 (AUTO-LANE) - Harness V2 production entry.

역할 분리(V2 계약):
  supervisor  : 구현 + 결정적 게이트 -> SOURCE_COMMITTED -> WAIT_INTEGRATION 까지만.
  auto_lane   : 드라이브 + Integration Coordinator 로
                WAIT_INTEGRATION -> INTEGRATING -> INTEGRATED -> REGRESSION_PASS -> DONE.
                INTEGRATED/REGRESSION_PASS 확인 후에만 큐(AI_TASK_QUEUE.md)와 결과에 DONE 을 기록.
  의존성 unlock : 큐 문자열 DONE 이 아닌 V2 persistent state 의
                  integration_status == INTEGRATED AND integrated_commit 가 기준.

시작 조건: canonical baseline(clean main) + production dry-run 전부 PASS 여야만 실행.
하나라도 FAIL 이면 AUTO_LANE_NOT_STARTED 로 종료. V1 fallback 금지.

사용:
  python auto_lane.py --groups G1,G2,... [--passes N]
"""
from __future__ import annotations

import argparse
import datetime
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import time

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
LOG_DIR = os.path.join(BASE_DIR, "logs")
CONFIG_PATH = os.path.join(BASE_DIR, "config.json")
STATE_V2_PATH = os.path.join(BASE_DIR, "state_v2.json")
INTEGRATION_WT = r"D:\game-wt\integration-v2"
INTEGRATION_BRANCH = "codex/integration-v2"
os.makedirs(LOG_DIR, exist_ok=True)

try:
    sys.path.insert(0, BASE_DIR)
    from harness_v2.core import (IntegrationCoordinator, Lifecycle, TaskState,
                                 V2StateStore, git, git_required)
    from harness_v2.adapter import canonical_baseline, production_dry_run
    V2 = True
except Exception as _e:  # pragma: no cover - fail-loud
    V2 = False


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
    try:
        subprocess.run(["taskkill", "/PID", str(pid), "/T", "/F"],
                       capture_output=True, timeout=30)
    except Exception:
        try:
            os.kill(pid, 9)
        except Exception:
            pass


def _progress_signals(group):
    best_mtime = 0.0
    best_size = 0
    try:
        today = datetime.datetime.now().strftime("%Y%m%d")
        cands = glob.glob(os.path.join(BASE_DIR, "logs", today + "_" + group + ".log")) + \
                glob.glob(os.path.join(BASE_DIR, "logs", today + ".log"))
        for p in cands:
            st = os.stat(p)
            best_mtime = max(best_mtime, st.st_mtime)
            best_size += st.st_size
    except Exception:
        pass
    return best_mtime, best_size


def wait_no_progress(group, proc, timeout_sec=7200, no_progress_sec=1200,
                     sample_interval=20):
    """supervisor 이 진행 중인 동안 대기. no_progress_sec 동안 진행 없으면 중단."""
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
            log("NO_PROGRESS_STALLED: %s초 동안 진행 없음 (%s) - 트리 종료" % (no_progress_sec, group))
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
    """supervisor 1회 호출 (구현 로드). Progress Watchdog 로 진행 감시."""
    py = _cfg("python_exe",
              r"C:\Users\skfnx\AppData\Local\Python\pythoncore-3.14-64\python.exe")
    if timeout_sec is None:
        timeout_sec = int(_cfg("lane_overall_timeout_sec", 7200))
    if no_progress_sec is None:
        no_progress_sec = int(_cfg("lane_no_progress_sec", 1200))
    full = [py, os.path.join(BASE_DIR, "supervisor.py"), "--group", group] + args
    env = os.environ.copy()
    env["PYTHONIOENCODING"] = "utf-8"
    proc = subprocess.Popen(full, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True, encoding="utf-8", errors="replace", env=env,
                            creationflags=getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0))
    try:
        rc, why = wait_no_progress(group, proc, timeout_sec=timeout_sec,
                                   no_progress_sec=no_progress_sec)
        out = err = ""
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


def group_leaf_statuses(group):
    out = sup(group, ["--status"], timeout_sec=600, no_progress_sec=300)
    m = {}
    for line in out.splitlines():
        p = line.strip().split()
        if len(p) >= 2 and (p[0].startswith("TASK-") or p[0].startswith("V3-")):
            m[p[0]] = p[1]
    return m


def group_remaining(group):
    keep = ("QUEUED", "IMPLEMENT", "REVIEW", "FIX", "REVIEW_PARSE_ERROR", "NEEDS_DESIGN")
    st = group_leaf_statuses(group)
    ids = [k for k, v in st.items() if v in keep]
    if group in st:
        children = [k for k in ids if k != group and k.startswith(group)]
        if not children:
            return ids
        return [k for k in ids if k != group]
    return ids


def run_one(group, leaf, timeout_sec=None, no_progress_sec=None):
    log(">> %s @ %s" % (leaf, group))
    return sup(group, ["--task", leaf], timeout_sec=timeout_sec,
               no_progress_sec=no_progress_sec)


# ---------------------------------------------------------------------------
# V2 integration
# ---------------------------------------------------------------------------

def _load_or_create_task(task_id):
    store = V2StateStore(STATE_V2_PATH)
    task = store.get_task(task_id)
    if task is None:
        task = TaskState(task_id)
    return store, task


def _regression_ok(repo):
    """통합 target 에서 canonical 3D baseline 회귀 실행. PASS 여부 반환."""
    godot = _cfg("godot_exe")
    if not godot:
        log("[V2] godot_exe 미설정 - 회귀 불가")
        return False
    baseline = os.path.join(repo, "tests", "baseline_3d_health_test.gd")
    if not os.path.exists(baseline):
        log("[V2] baseline 스크립트 없음: %s" % baseline)
        return False
    try:
        proc = subprocess.run([godot, "--headless", "--path", repo, "-s", baseline],
                              cwd=repo, text=True, capture_output=True, encoding="utf-8",
                              errors="replace",
                              timeout=int(_cfg("verification", {}).get("regression_timeout", 300)))
    except subprocess.TimeoutExpired:
        log("[V2] 회귀 타임아웃")
        return False
    combined = (proc.stdout or "") + (proc.stderr or "")
    ok = proc.returncode == 0 and "BASELINE_3D_RESULT=PASS" in combined
    log("[V2] 회귀(%s) exit=%d PASS=%s" % (os.path.basename(baseline), proc.returncode, ok))
    return ok


def _write_done_report(task_id, feedback, integrated_commit=""):
    """Integration Coordinator 가 INTEGRATED+REGRESSION_PASS 를 확정한 후 호출.

    V2 계약: DONE 결과는 canonical main(AI_TASK_QUEUE.md)에 쓰지 않고
    runtime report 로만 export 한다 (main 은 runtime 동안 항상 clean)."""
    runs_dir = os.path.join(BASE_DIR, "runs")
    os.makedirs(runs_dir, exist_ok=True)
    p = os.path.join(runs_dir, "integration_done.log")
    line = "[%s] %s DONE commit=%s | %s" % (time.strftime("%Y-%m-%d %H:%M:%S"),
                                            task_id, (integrated_commit or "")[:12], feedback)
    try:
        with open(p, "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except Exception as e:
        log("[%s] DONE 리포트 기록 실패: %s" % (task_id, e))
    log(line)
    return True


def _ensure_integration_worktree(main_repo):
    """integration-v2 워크트리 보장. 없으면 canonical baseline 에서 생성."""
    store = V2StateStore(STATE_V2_PATH)
    baseline = canonical_baseline(main_repo, store)
    if os.path.isdir(INTEGRATION_WT):
        _ensure_godot_cache(main_repo)
        return baseline
    git_required(main_repo, "worktree", "add", "-b", INTEGRATION_BRANCH, INTEGRATION_WT, baseline)
    log("[V2] integration 워크트리 생성 @ %s (baseline=%s)" % (INTEGRATION_WT, baseline[:12]))
    _ensure_godot_cache(main_repo)
    return baseline


def _ensure_godot_cache(main_repo):
    """integration 워크트리의 .godot 캐시 부트스트랩.

    .godot(글로벌 클래스 캐시 + imported 리소스)는 git 에 포함되지 않아 워크트리 생성 시
    복제되지 않는다. 캐시 없는 신선 환경에서는 class_name 해석이 실패해
    (예: PotionData) autoload 체인이 깨져 baseline 회귀가 항상 FAIL 로 나온다.
    canonical 의 .godot 캐시를 복사해 동일 클로저로 만든다(소스 워크트리도 이 방식으로 동작).
    """
    cache = os.path.join(INTEGRATION_WT, ".godot", "global_script_class_cache.cfg")
    if os.path.exists(cache):
        return
    src = os.path.join(main_repo, ".godot")
    if not os.path.isdir(src):
        log("[V2] canonical .godot 캐시 없음 - bootstrap 불가")
        return
    shutil.copytree(src, os.path.join(INTEGRATION_WT, ".godot"), dirs_exist_ok=True)
    log("[V2] integration .godot 캐시 bootstrap %s" % ("완료" if os.path.exists(cache) else "실패"))


def _expectation_ok(main_repo, expected_baseline_commit):
    """optimistic concurrency guard: 통합 시작 시점의 expected baseline 과 main HEAD 일치 검증.

    외부 GPT/manual modification 이 없었다면 main HEAD 는 expected 와 동일해야 한다.
    다르면 BASELINE_MOVED 판정 (reset/force/merge 금지).
    """
    code, out, err = git(main_repo, "rev-parse", "HEAD")
    if code:
        log("[V2] main HEAD 조회 실패")
        return False, "INFRA_ERROR"
    cur = out.strip()
    if cur != expected_baseline_commit:
        log("[V2] BASELINE_MOVED: expected=%s actual=%s - 외부 main 수정 감지." % (
            expected_baseline_commit[:12], cur[:12]))
        log("[V2]   reset/force/auto-merge 금지. 기존 통합/source provenance 보존. 수동 CANONICAL_REVIEW_REQUIRED.")
        return False, "BASELINE_MOVED"
    return True, ""


def _safe_fast_forward_main(main_repo, expected_baseline_commit, integrated_commit, store,
                            task_id):
    """main 을 통합 HEAD 로 fast-forward 하기 직전 4-항 guard 검증 후 갱신.

    순서: 1) clean  2) main HEAD==expected  3) integration HEAD 는 current main descendant
         4) merge --ff-only 가능. 모두 통과 후에만 main 갱신 -> persistent baseline 갱신.
    하나라도 어기면 reset/force/merge 없이 중단 (BASELINE_MOVED / CANONICAL_REVIEW_REQUIRED).
    """
    def _is_ancestor(ancestor, descendant):
        return git(main_repo, "merge-base", "--is-ancestor", ancestor, descendant)[0] == 0

    # 1) working tree clean
    code, out, err = git(main_repo, "status", "--porcelain")
    if code or (out or "").strip():
        log("[V2] main fast-forward 보류: working tree dirty (code=%s)" % code)
        return False, "INFRA_ERROR"
    # 2) main HEAD == expected
    code, out, err = git(main_repo, "rev-parse", "HEAD")
    if code or out.strip() != expected_baseline_commit:
        log("[V2] BASELINE_MOVED: expected=%s actual=%s - 수정 금지, 중단" % (
            expected_baseline_commit[:12], (out or "").strip()[:12]))
        return False, "BASELINE_MOVED"
    # 3) integration HEAD 는 current main 의 descendant
    if not _is_ancestor(git_required(main_repo, "rev-parse", "HEAD"), integrated_commit):
        log("[V2] main fast-forward 보류: integration HEAD 가 current main 의 descendant 아님")
        return False, "INFRA_ERROR"
    # 4) merge --ff-only 가능해야
    rc, o, e = git(main_repo, "merge", "--ff-only", integrated_commit)
    if rc != 0:
        log("[V2] main fast-forward 실패(ff-only): %s" % (e or o).strip()[:300])
        return False, "INFRA_ERROR"
    new_head = git_required(main_repo, "rev-parse", "HEAD")
    if new_head != integrated_commit:
        log("[V2] main fast-forward 헤드 불일치: %s != %s" % (new_head[:12], integrated_commit[:12]))
        return False, "INFRA_ERROR"
    # 5) persistent baseline 을 fast-forward 성공 확인 후에만 갱신 (먼저 갱신 금지)
    store.set_baseline(new_head)
    log("[V2] %s main fast-forward -> %s (baseline 갱신)" % (task_id, new_head[:12]))
    return True, ""


def integrate_ready_tasks(main_repo, store=None):
    """모든 WAIT_INTEGRATION & deps ready 인 task 를 통합해 DONE 까지 진행한다.

    V2 계약 순서 (strict):
      expected_baseline 기록 -> cherry-pick(INTEGRATED) -> 회귀 PASS ->
      4-항 optimistic guard(clean / main==expected / descendant / ff-only) ->
      main fast-forward 성공 -> persistent baseline 갱신 ->
      REGRESSION_PASS -> DONE -> 큐 반영.
    회귀 FAIL 또는 guard 실패 시: DONE/큐 반영/main 갱신/baseline 이동 없이 중단.
    """
    if store is None:
        store = V2StateStore(STATE_V2_PATH)
    state = store.load()
    tasks = state.get("tasks", {})
    _ensure_integration_worktree(main_repo)
    from harness_v2.core import changed_status_paths
    progressed = False
    for task_id, raw in list(tasks.items()):
        task = TaskState(**raw)
        st = task.status
        if st == Lifecycle.DONE.value:
            continue
        if st not in (Lifecycle.WAIT_INTEGRATION.value, Lifecycle.INTEGRATING.value):
            continue
        if not task.source_commit:
            continue
        # 통합 시작 시점 expected baseline 기록
        exp_code, exp_out, exp_err = git(main_repo, "rev-parse", "HEAD")
        if exp_code:
            log("[V2] %s main HEAD 조회 실패 - 중단" % task_id)
            return progressed, "INFRA_ERROR"
        expected = exp_out.strip()

        # 의존성 unlock 은 V2 persistent state 기준 (integration_status==INTEGRATED + integrated_commit)
        if changed_status_paths(INTEGRATION_WT):
            log("[V2] %s integration 워크트리 dirty - 통합 보류" % task_id)
            return progressed, "INFRA_ERROR"
        state_now = store.load()
        deps_blocked = []
        for dep in task.depends_on:
            dep_raw = state_now.get("tasks", {}).get(dep, {})
            if dep_raw.get("integration_status") != Lifecycle.INTEGRATED.value:
                deps_blocked.append("%s:not-INTEGRATED" % dep)
            elif not dep_raw.get("integrated_commit"):
                deps_blocked.append("%s:no-commit" % dep)
        if deps_blocked:
            task.set(Lifecycle.WAIT_INTEGRATION, integration_status="BLOCKED_DEPENDENCY")
            store.put_task(task)
            log("[V2] %s 통합 대기(의존성): %s" % (task_id, ", ".join(deps_blocked)))
            continue
        task.set(Lifecycle.INTEGRATING, integration_status="INTEGRATING")
        store.put_task(task)
        cherry = git(INTEGRATION_WT, "cherry-pick", task.source_commit, timeout=300)
        if cherry[0]:
            git(INTEGRATION_WT, "cherry-pick", "--abort", timeout=60)
            task.set(Lifecycle.INTEGRATION_CONFLICT, integration_status="INTEGRATION_CONFLICT",
                     last_error=(cherry[2] or cherry[1]).strip(), failure_class="INTEGRATION_CONFLICT")
            store.put_task(task)
            log("[V2] %s INTEGRATION_CONFLICT - 자동화 정지" % task_id)
            return progressed, "INTEGRATION_CONFLICT"
        integrated = git_required(INTEGRATION_WT, "rev-parse", "HEAD")
        task.integrated_commit = integrated
        task.integration_status = Lifecycle.INTEGRATED.value
        task.set(Lifecycle.INTEGRATED)
        store.put_task(task)
        reg_ok = _regression_ok(INTEGRATION_WT)
        if not reg_ok:
            task.set(Lifecycle.INTEGRATED, integration_validation_result="FAIL",
                     failure_class="INTEGRATION_TEST_FAILED")
            store.put_task(task)
            log("[V2] %s 회귀 FAIL - DONE 금지, main/baseline 미갱신" % task_id)
            continue

        # 회귀 PASS 후에만 main 반영 (4-항 optimistic guard)
        ok, stop = _safe_fast_forward_main(main_repo, expected, integrated, store, task_id)
        if not ok:
            log("[V2] %s main 반영 중단: %s - DONE 금지" % (task_id, stop))
            return progressed, stop

        # main 반영 + baseline 갱신 이후에만 REGRESSION_PASS -> DONE
        task.set(Lifecycle.REGRESSION_PASS, integration_validation_result="PASS")
        task.set(Lifecycle.DONE)
        store.put_task(task)
        _write_done_report(task_id, "통합 완료(Integration Coordinator): INTEGRATED + REGRESSION_PASS + main 반영",
                           integrated_commit=integrated)
        progressed = True
        log("[V2] %s INTEGRATED->DONE (commit=%s)" % (task_id, integrated[:12]))
    return progressed, ""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--groups", required=True, help="콤마 구분 그룹 목록")
    ap.add_argument("--passes", type=int, default=6, help="그룹당 최대 순회 횟수")
    ap.add_argument("--retry-needs-design", action="store_true",
                    help="NEEDS_DESIGN leaf 도 재시도")
    args = ap.parse_args()
    groups = [g.strip() for g in args.groups.split(",") if g.strip()]

    main_repo = _cfg("project_dir", r"D:\game")
    queue_path = os.path.join(main_repo, _cfg("queue_file", "AI_TASK_QUEUE.md"))

    # ---- 시작 조건 (전체 PASS 여야 실행, 하나라도 FAIL 이면 AUTO_LANE_NOT_STARTED) ----
    if not V2:
        log("=== AUTO_LANE_NOT_STARTED: harness_v2 로드 실패 (V1 fallback 금지) ===")
        return 2
    store = V2StateStore(STATE_V2_PATH)
    try:
        baseline = canonical_baseline(main_repo, store)
    except RuntimeError as e:
        log("=== AUTO_LANE_NOT_STARTED: baseline FAIL - %s ===" % e)
        return 2
    result = production_dry_run(main_repo, queue_path, store)
    if not (result.baseline_ok and result.queue_ok and result.coordinator_enabled):
        log("=== AUTO_LANE_NOT_STARTED: dry-run FAIL (baseline=%s queue=%s coord=%s) ===" % (
            result.baseline_ok, result.queue_ok, result.coordinator_enabled))
        return 2
    log("=== AUTO_LANE_v2 시작 baseline=%s groups=%s passes=%s (HARNESS_V2_DRY_RUN=PASS) ===" % (
        baseline[:12], groups, args.passes))

    for group in groups:
        log("--- 그룹 %s 시작 ---" % group)
        for p in range(1, args.passes + 1):
            rem = group_remaining(group)
            marked_nd = []
            if not args.retry_needs_design:
                st = group_leaf_statuses(group)
                marked_nd = [k for k in rem if st.get(k) == "NEEDS_DESIGN"]
            active = [k for k in rem if k not in marked_nd]
            if not active:
                log("[%s] 실행 가능 leaf 없음 (pass %d) - 그룹 종료" % (group, p))
                break
            log("[%s] pass %d 실행 leaf: %s" % (group, p, active))
            for leaf in active:
                run_one(group, leaf, timeout_sec=int(_cfg("lane_overall_timeout_sec", 7200)),
                        no_progress_sec=int(_cfg("lane_no_progress_sec", 1200)))
            progressed, stop = integrate_ready_tasks(main_repo)
            if stop:
                log("=== AUTO_LANE 종료: %s ===" % stop)
                return 1
    log("=== AUTO_LANE_v2 종료 ===")
    return 0


if __name__ == "__main__":
    sys.exit(main())
