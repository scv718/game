#!/usr/bin/env python3
"""AI Dev Supervisor - AI_TASK_QUEUE.md 기반 자동 구현/리뷰 사이클 (Windows)"""

import argparse
import datetime
import glob
import hashlib
import json
import os
import re
import subprocess
import sys
import threading
import time
import msvcrt

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_PATH = os.path.join(BASE_DIR, "config.json")
STATE_PATH = os.path.join(BASE_DIR, "state.json")
QUEUE_LOCK_PATH = os.path.join(BASE_DIR, ".queue_lock")
PROMPT_DIR = os.path.join(BASE_DIR, "prompts")
GROUP_ID = None  # --group 지정 시 해당 그룹 서브트리만 처리 (병렬 레인)
WORKTREE_DIR = None  # --group 에 매핑된 git worktree (에이전트 작업 디렉터리)
# implementer attempt 단위 artifact(attempt_delta) 판정용 스냅샷
_WORKTREE_BASELINE = None  # 시도 시작 시점의 전체 파일 content-hash 스냅샷
_LAST_ATTEMPT_DELTA = None  # 마지막 시도에서 실제 새로 생성/수정된 파일 목록 (rel path)
_ATTEMPT_START_HEAD = None  # 시도 시작 시점의 git HEAD (agent 가 이미 commit 한 경우 대비)
FALLBACK_STATE_PATH = os.path.join(BASE_DIR, "fallback_state.json")
IMPL_FALLBACK_STATE_PATH = os.path.join(BASE_DIR, "impl_fallback_state.json")
QUOTA_RE = re.compile(r"insufficient|quota|balance|credit|usage limit|limit reached|exhausted|402|429",
                      re.IGNORECASE)

if sys.stdout:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if sys.stderr:
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

STATES = ("QUEUED", "IMPLEMENT", "REVIEW", "FIX", "DONE", "NEEDS_DESIGN", "REVIEW_PARSE_ERROR",
          "BLOCKED_STALLED", "BLOCKED_AGENT", "BLOCKED_INFRA")
RETRYABLE = ("QUEUED", "IMPLEMENT", "REVIEW", "FIX", "REVIEW_PARSE_ERROR")
SENTINEL_IDS = ("OVERNIGHT-STOP",)
TASK_ID_RE = re.compile(r"^(TASK(?:-[A-Z0-9]+){1,5}|OVERNIGHT-STOP(?:-\d+)?)$")
STATUS_RE = re.compile(r"^-\s*상태\s*[:：]\s*(.+?)\s*$")
FEEDBACK_RE = re.compile(r"^-\s*피드백\s*[:：]\s*(.*?)\s*$")
HEADING_RE = re.compile(r"^(#{2,3})\s+(.+?)\s*$")
VERDICT_RE = re.compile(r"판정\s*[:：]\s*(?:\*\*|\*)?\s*(LGTM|FIX|NEEDS_DESIGN)", re.IGNORECASE)

INFRA_ERR_RE = re.compile(
    r"Model not found|UnknownError|Unexpected server error|no such model|"
    r"ECONNREFUSED|ECONNRESET|ENOTFOUND|ETIMEDOUT|PROTOCOL_ERROR|"
    r"connection|connect|timeout|ollama|provider|no such host|"
    r"unauthorized|invalid api|401|403|429|rate.?limit|"
    r"spawn\s|ENOENT|load failed", re.IGNORECASE)

def is_infra_error(err):
    """모델/프로바이더/네트워크 등 인프라 오류는 설계 충돌(NEEDS_DESIGN)이 아니다.
    상태를 유지하고 다음 사이클에서 재시도해야 한다."""
    if not err:
        return False
    if err in ("알 수 없는 오류", "빈 응답"):
        return True
    return bool(INFRA_ERR_RE.search(err))
REASON_RE = re.compile(r"사유\s*[:：]\s*(.+)", re.IGNORECASE)
SUMMARY_RE = re.compile(r"구현\s*요약\s*[:：]\s*(.+)", re.IGNORECASE)


def log(msg):
    ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = f"[{ts}] {msg}"
    print(line, flush=True)
    with open(log_path(), "a", encoding="utf-8") as f:
        f.write(line + "\n")


def log_path():
    os.makedirs(os.path.join(BASE_DIR, cfg("log_dir")), exist_ok=True)
    suffix = f"_{GROUP_ID}" if GROUP_ID else ""
    return os.path.join(BASE_DIR, cfg("log_dir"), datetime.datetime.now().strftime("%Y%m%d") + suffix + ".log")


def state_path():
    if GROUP_ID:
        return os.path.join(BASE_DIR, f"state_{GROUP_ID}.json")
    return STATE_PATH


class queue_lock:
    """큐 파일 동시 수정 방지 (여러 supervisor 레인이 같은 AI_TASK_QUEUE.md 공유)."""

    def __enter__(self):
        self.f = open(QUEUE_LOCK_PATH, "a+")
        for _ in range(600):
            try:
                msvcrt.locking(self.f.fileno(), msvcrt.LK_LOCK, 1)
                break
            except OSError:
                time.sleep(1)
        return self

    def __exit__(self, *exc):
        try:
            self.f.seek(0)
            msvcrt.locking(self.f.fileno(), msvcrt.LK_UNLCK, 1)
        except OSError:
            pass
        self.f.close()
        return False


def cfg(key):
    return CONFIG[key]


def load_config():
    with open(CONFIG_PATH, encoding="utf-8") as f:
        return json.load(f)


def pid_alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except (OSError, PermissionError):
        return False


def acquire_lock():
    state = {"running": False, "pid": None}
    if os.path.exists(state_path()):
        with open(state_path(), encoding="utf-8") as f:
            state = json.load(f)
    if state.get("running") and pid_alive(state.get("pid")):
        log(f"이전 실행(pid={state.get('pid')})이 아직 진행 중 - 이번 사이클 건너뜀")
        return False
    state["running"] = True
    state["pid"] = os.getpid()
    state["started"] = datetime.datetime.now().isoformat()
    with open(state_path(), "w", encoding="utf-8") as f:
        json.dump(state, f, ensure_ascii=False, indent=2)
    return True


def release_lock():
    state = {"running": False, "pid": None, "ended": datetime.datetime.now().isoformat()}
    with open(state_path(), "w", encoding="utf-8") as f:
        json.dump(state, f, ensure_ascii=False, indent=2)


def parse_queue():
    """AI_TASK_QUEUE.md를 파싱. 태스크 = 2단계(##) 또는 3단계(###) 섹션."""
    path = os.path.join(cfg("project_dir"), cfg("queue_file"))
    with open(path, encoding="utf-8") as f:
        lines = f.readlines()

    tasks = []
    stack = []  # (level, task)
    current = None

    for raw in lines:
        line = raw.rstrip("\n")
        m = HEADING_RE.match(line)
        if m:
            level = len(m.group(1))
            tid = m.group(2).strip().split()[0] if m.group(2).strip() else ""
            if not TASK_ID_RE.match(tid):
                # 비-태스크 헤딩(예: ## PHASE-STOP-...)은 태스크 섹션 경계다.
                # 스킵만 하면 이후 행들이 이전 태스크로 흘러들어 상태를 덮어쓴다.
                current = None
                stack = []
                continue
            if level == 3:
                parent = stack[-1][1] if stack else None
                current = {
                    "id": None, "title": m.group(2), "status": "QUEUED",
                    "feedback": "", "level": 3, "parent": parent, "children": [],
                }
                if parent is not None:
                    parent["children"].append(current)
                tasks.append(current)
            elif level == 2:
                current = {
                    "id": None, "title": m.group(2), "status": "QUEUED",
                    "feedback": "", "level": 2, "parent": None, "children": [],
                }
                tasks.append(current)
                stack = [(2, current)]
            continue
        if current is None:
            continue
        sm = STATUS_RE.match(line)
        if sm:
            current["status"] = sm.group(1).upper()
            continue
        fm = FEEDBACK_RE.match(line)
        if fm:
            current["feedback"] = fm.group(1)
            continue

    for t in tasks:
        t["id"] = t["title"].strip().split()[0] if t["title"].strip() else "?"

    def finalize(t):
        t["leaf"] = len(t["children"]) == 0
        if not t["leaf"]:
            child_states = [c["status"] for c in t["children"]]
            if any(s == "NEEDS_DESIGN" for s in child_states):
                t["status"] = "NEEDS_DESIGN"
            elif all(s == "DONE" for s in child_states):
                t["status"] = "DONE"
            elif any(s in ("IMPLEMENT", "REVIEW", "FIX") for s in child_states):
                t["status"] = "IMPLEMENT"
            else:
                t["status"] = "QUEUED"
        for c in t["children"]:
            finalize(c)

    for t in tasks:
        finalize(t)
    return tasks, path


def update_queue(tasks, path, task_id, status, feedback=None):
    """지정 태스크의 상태/피드백 줄을 파일에서 직접 갱신 (사람 편집 보존, 레인 간 동시 쓰기 방지)."""
    with queue_lock():
        _update_queue_locked(tasks, path, task_id, status, feedback)


def _update_queue_locked(tasks, path, task_id, status, feedback=None):
    with open(path, encoding="utf-8") as f:
        lines = f.readlines()

    target = next((t for t in tasks if t["id"] == task_id), None)
    if target is None:
        return
    in_target = False
    depth = 0
    out = []
    status_written = False
    feedback_written = False
    for raw in lines:
        line = raw.rstrip("\n")
        m = HEADING_RE.match(line)
        if m:
            hlevel = len(m.group(1))
            tid = m.group(2).strip().split()[0] if m.group(2).strip() else ""
            if tid == task_id:
                in_target = True
                depth = hlevel
            elif in_target and hlevel <= depth:
                in_target = False
        if in_target:
            sm = STATUS_RE.match(line)
            if sm and not status_written:
                out.append(f"- 상태: {status}\n")
                status_written = True
                if feedback is not None:
                    out.append(f"- 피드백: {feedback}\n")
                    feedback_written = True
                continue
            if FEEDBACK_RE.match(line) and feedback is not None and not feedback_written:
                out.append(f"- 피드백: {feedback}\n")
                feedback_written = True
                continue
        out.append(raw)
    with open(path, "w", encoding="utf-8") as f:
        f.writelines(out)


GATE_TEMP_RE = re.compile(r"^(_probe|_debug|_diag|tmp_|temp_|test_tmp)", re.IGNORECASE)
DANGER_RE = re.compile(r"^(auto_dev/(?!INTEGRATION_NOTE|runs/)|\.git|credential|.*\.key$|\.gitattributes$)", re.IGNORECASE)


def _run_cmd(cmd, cwd=None, timeout=900):
    try:
        r = subprocess.run(cmd, cwd=cwd, capture_output=True, encoding="utf-8",
                           errors="replace", timeout=timeout)
        return r.returncode, (r.stdout or ""), (r.stderr or "")
    except Exception as e:
        return -1, "", str(e)


def task_tid(task):
    """태스크 ID → 결정적 파일명용 축약 id (TASK-027-5 → task0275)."""
    return task["id"].replace("-", "").lower()


def required_test_path(task):
    """Supervisor가 직접 계산한 필수 테스트 파일 경로 (LLM 추론 불필요)."""
    return os.path.join("tests", f"{task_tid(task)}_test.gd")


def possible_test_candidates(root):
    """정확한 task 패턴과 무관하게 최근 생성된 *_test.gd 후보들을 찾는다.
    잘못된 위치/이름으로 만들어진 테스트를 진단 메시지에 표시하는 용도."""
    cands = []
    for p in glob.glob(os.path.join(root, "**", "*_test.gd"), recursive=True):
        rel = os.path.relpath(p, root).replace("\\", "/")
        name = os.path.basename(p)
        if GATE_TEMP_RE.match(name):
            continue
        cands.append((os.path.getmtime(p), rel))
    cands.sort(key=lambda x: x[0], reverse=True)
    return [rel for _, rel in cands[:6]]


def find_task_test_file(task, root):
    """태스크 ID에서 관례상 테스트 파일 추정 (task3dint0012_test.gd 등)."""
    tid = task_tid(task)
    candidates = glob.glob(os.path.join(root, "tests", f"*{tid}*_test.gd"))
    if not candidates:
        return None
    return max(candidates, key=os.path.getmtime)


def classify_no_diff(task):
    """git diff가 0인 경우 근본 원인 분류.
    - TOOL_LOOP_STALLED: 모델이 tool_calls를 내지 않아 하네스가 분석 텍스트만으로 완료한 경우
    - NO_CODE_DIFF: 도구는 실행됐으나 코드 변경이 없는 경우
    하네스 최신 final.json의 tool_events/turns 로 판별."""
    hdir = CONFIG.get("harness_dir", "D:\\coding-harness")
    runs_dir = os.path.join(hdir, "runs")
    if not os.path.isdir(runs_dir):
        return "NO_CODE_DIFF"
    cands = []
    for f in glob.glob(os.path.join(runs_dir, "*", "final.json")):
        try:
            mtime = os.path.getmtime(f)
        except OSError:
            continue
        cands.append((mtime, f))
    cands.sort(reverse=True)
    recent = cands[:8]
    for _, f in recent:
        try:
            with open(f, encoding="utf-8") as fh:
                data = json.load(fh)
        except (OSError, ValueError):
            continue
        text = json.dumps(data, ensure_ascii=False)
        if task_tid(task) not in text.lower():
            continue
        tool_events = data.get("tool_events", 0)
        turns = data.get("turns", 0)
        if tool_events == 0:
            return f"TOOL_LOOP_STALLED (tool_events=0, turns={turns}) - 모델이 실제 도구를 실행하지 않음"
        return f"NO_CODE_DIFF (tool_events={tool_events}) - 도구는 실행됐으나 작업 트리에 변경 없음"
    return "NO_CODE_DIFF"


FAILURE_TYPES = ("ANALYSIS_ONLY", "TOOL_LOOP_STALLED", "NO_PROGRESS_STALLED",
                 "AGENT_MAX_TURNS", "NO_CODE_DIFF", "NO_MEANINGFUL_ARTIFACT",
                 "MISSING_REQUIRED_TEST", "TEST_FAILED", "TEST_TIMEOUT",
                 "REGRESSION_FAILED", "WRONG_TEST_PATH",
                 "COMMIT_FAILED",
                 "PROVIDER_ERROR", "HARNESS_CRASH", "PROCESS_ERROR")
# 실패 유형별 최대 재시도 횟수 (초과 시 해당 TASK를 영구 차단)
# 시도 예산은 TASK 단위로 영속 유지되며, fresh session 생성으로 초기화되지 않는다.
RETRY_LIMITS = {
    "ANALYSIS_ONLY": 2,
    "TOOL_LOOP_STALLED": 2,
    "NO_PROGRESS_STALLED": 2,
    "AGENT_MAX_TURNS": 2,
    "NO_CODE_DIFF": 2,
    "NO_MEANINGFUL_ARTIFACT": 2,
    "MISSING_REQUIRED_TEST": 2,
    "TEST_FAILED": 3,
    "TEST_TIMEOUT": 3,
    "REGRESSION_FAILED": 3,
    "WRONG_TEST_PATH": 2,
    "COMMIT_FAILED": 3,
    "PROVIDER_ERROR": 3,
    "HARNESS_CRASH": 3,
    "PROCESS_ERROR": 3,
}
TASK_ATTEMPT_BUDGET = 6

# 모델/에이전트 행동 문제 (세션 행동 자체가 잘못됨) → BLOCKED_AGENT
AGENT_FAILURES = {"ANALYSIS_ONLY", "TOOL_LOOP_STALLED", "AGENT_MAX_TURNS"}
# 진행 없음 → BLOCKED_STALLED
STALLED_FAILURES = {"NO_PROGRESS_STALLED"}
# 인프라 문제 → BLOCKED_INFRA
INFRA_FAILURES = {"PROVIDER_ERROR", "HARNESS_CRASH", "PROCESS_ERROR"}

# verification / implementation failure (모델 stall 아님) - gate 처리용
VERIFY_FAILURES = {"TEST_FAILED", "TEST_TIMEOUT", "REGRESSION_FAILED", "WRONG_TEST_PATH",
                   "MISSING_REQUIRED_TEST", "NO_CODE_DIFF", "NO_MEANINGFUL_ARTIFACT"}

# fresh session이 필요한 실패: 기존 checkpoint/session 재사용 금지.
# session 만료/행동 붕괴 계열 → fresh. TEST_FAILED 등 구현을 이어갈 가치가 있는 경우 → same session 우선.
FRESH_SESSION_TYPES = ("ANALYSIS_ONLY", "TOOL_LOOP_STALLED", "NO_PROGRESS_STALLED",
                       "AGENT_MAX_TURNS", "PROVIDER_ERROR", "HARNESS_CRASH", "PROCESS_ERROR")


def _failure_path(task):
    runs_dir = os.path.join(BASE_DIR, "runs", GROUP_ID) if GROUP_ID else os.path.join(BASE_DIR, "runs", "_default")
    os.makedirs(runs_dir, exist_ok=True)
    return os.path.join(runs_dir, f"failure_{task['id']}.json")


def get_failure_state(task):
    p = _failure_path(task)
    if not os.path.exists(p):
        return {"counts": {}, "fingerprints": {}, "attempts": 0, "sessions": []}
    try:
        with open(p, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return {"counts": {}, "fingerprints": {}, "attempts": 0, "sessions": []}


def _save_failure_state(task, st):
    with open(_failure_path(task), "w", encoding="utf-8") as f:
        json.dump(st, f, ensure_ascii=False)


def _normalize_reason(reason):
    """동일 실패 fingerprint용 정규화: 소문자, 공백/개행/줄임 정리 후 앞부분."""
    if not reason:
        return ""
    s = re.sub(r"\s+", " ", str(reason)).strip().lower()
    return s[:160]


def record_failure(task, failure_type, reason, session_id=None, fresh=False):
    """TASK 단위 영속 실패 기록. session_id 변경(기록/폐기)은 attempts 초기화하지 않는다.
    반환: (exceeded, failure_type, counts, attempts)"""
    st = get_failure_state(task)
    st.setdefault("counts", {})
    st.setdefault("fingerprints", {})
    st["attempts"] = st.get("attempts", 0) + 1
    st["counts"][failure_type] = st["counts"].get(failure_type, 0) + 1
    fp = _normalize_reason(reason)
    if fp:
        key = f"{failure_type}|{fp}"
        st["fingerprints"][key] = st["fingerprints"].get(key, 0) + 1
    # session 추적 (fresh session 이벤트 포함)
    sessions = st.setdefault("sessions", [])
    if session_id:
        sessions.append({"id": session_id, "type": failure_type, "fresh": fresh,
                         "at": datetime.datetime.now().isoformat()})
        sessions[:] = sessions[-20:]
    _save_failure_state(task, st)
    limit = RETRY_LIMITS.get(failure_type, 3)
    exceeded_by_type = st["counts"].get(failure_type, 0) >= limit
    exceeded_budget = st["attempts"] >= TASK_ATTEMPT_BUDGET
    return (exceeded_by_type or exceeded_budget), failure_type, st["counts"], st["attempts"]


def clear_failure_state(task):
    p = _failure_path(task)
    if os.path.exists(p):
        try:
            os.remove(p)
        except OSError:
            pass


def decision_message(failure_type, counts, attempts):
    return (f"{failure_type} (시도 {counts.get(failure_type, 0)}/{RETRY_LIMITS.get(failure_type, 3)} "
            f"· 총 {attempts}/{TASK_ATTEMPT_BUDGET})")


def _harness_status_classify(task, hstatus):
    """하네스 status → 실패 유형 라벨. harness/세션 행동 스톨만 분류."""
    hs = (hstatus or "").lower()
    if hs == "analysis_only":
        return "ANALYSIS_ONLY"
    if hs == "tool_loop_stalled":
        return "TOOL_LOOP_STALLED"
    if hs == "max_turns":
        return "AGENT_MAX_TURNS"
    if hs in ("timeout", "no_progress_stalled"):
        return "NO_PROGRESS_STALLED"
    return None


def infra_failure_type(err):
    """인프라 오류 → 실패 유형 (handle_retryable_failure 용)."""
    if not err:
        return None
    msg = str(err).lower()
    if msg.startswith("실행 시간 초과"):
        return "NO_PROGRESS_STALLED"
    if any(k in msg for k in ("provider", "model", "네트워크", "api", "요청 실패")):
        return "PROVIDER_ERROR"
    if any(k in msg for k in ("harness", "세그먼트", "crash", "segfault")):
        return "HARNESS_CRASH"
    if any(k in msg for k in ("프로세스", "exec", "spawn", "os error")):
        return "PROCESS_ERROR"
    if any(k in msg for k in ("할당량", "quota", "rate", "429", "409")):
        return "PROVIDER_ERROR"
    if is_infra_error(msg):
        return "PROCESS_ERROR"
    return None


def terminal_for_failure(failure_type):
    """실패 유형 → 최종 차단 상태. NEEDS_DESIGN은 여기서 절대 나오지 않는다."""
    if failure_type in AGENT_FAILURES:
        return "BLOCKED_AGENT"
    if failure_type in STALLED_FAILURES:
        return "BLOCKED_STALLED"
    if failure_type in INFRA_FAILURES:
        return "BLOCKED_INFRA"
    return None


def handle_retryable_failure(task, failure_type, reason, session_id=None):
    """harness/세션 스톨 또는 인프라 오류에 대한 재시도 정책 판단.
    side effect 없음: queue 상태/result/session_id 변경은 caller가 수행한다.

    반환 dict:
      terminal       : 최종 차단 상태 or None(재시도)
      fresh_session  : 다음 구현에 새 session이 필요한지
      failure_type   : 분류된 실패 유형
      attempts       : TASK 누적 시도 수 (영속)
      type_attempts  : 해당 유형 누적 시도 수
      exceeded       : 예산/한도 초과 여부
    """
    ftype = failure_type if failure_type in FAILURE_TYPES else "HARNESS_CRASH"
    exceeded, ftype, counts, attempts = record_failure(task, ftype, reason, session_id=session_id)
    fresh = ftype in FRESH_SESSION_TYPES
    result = {
        "terminal": terminal_for_failure(ftype) if exceeded else None,
        "fresh_session": fresh,
        "failure_type": ftype,
        "attempts": attempts,
        "type_attempts": counts.get(ftype, 0),
        "exceeded": exceeded,
    }
    return result


def classification_for_gate_problems(problems):
    """verification gate 문제 목록 → 검증 실패 유형.
    gate 실패는 harness/세션 스톨과 별개 의미: verification/implementation failure.
    """
    if not problems:
        return "TEST_FAILED"
    joined = "\n".join(p.lower() for p in problems)
    if "scope_drift" in joined:
        return "NO_MEANINGFUL_ARTIFACT"
    if "no_meaningful_artifact" in joined:
        return "NO_MEANINGFUL_ARTIFACT"
    if "분류: no_code_diff" in joined or "분류: tool_loop_stalled" in joined or "분류: no_meaningful_artifact" in joined:
        return "NO_CODE_DIFF" if "분류: no_code_diff" in joined else "NO_MEANINGFUL_ARTIFACT"
    if "timeout" in joined and ("task test" in joined or "smoke" in joined or "회귀(smoke)" in joined or "태스크 테스트" in joined):
        return "TEST_TIMEOUT"
    if "required test file" in joined or "요구하는 경로" in joined or "게이트가 요구하는 경로" in joined:
        if "found possible test files" in joined:
            return "WRONG_TEST_PATH"
        return "MISSING_REQUIRED_TEST"
    if "회귀(smoke) fail" in joined:
        return "REGRESSION_FAILED"
    if "변경된 파일이 없음" in joined:
        return "NO_CODE_DIFF"
    if "태스크 테스트 fail" in joined or "task test" in joined:
        return "TEST_FAILED"
    return "TEST_FAILED"


def handle_verification_failure(task, problems, reason, session_id=None):
    """게이트(verification) 반복 실패에 대한 재시도 정책 판단. side effect 없음.
    모델/세션 문제가 아니라 검증 실패지만, 무한 회귀 방지를 위해 동일 예산을 사용한다.
    반환 dict: terminal / fresh_session / failure_type / attempts / type_attempts / exceeded
    """
    ftype = classification_for_gate_problems(problems)
    exceeded, ftype, counts, attempts = record_failure(task, ftype, reason, session_id=session_id)
    fresh = ftype in FRESH_SESSION_TYPES
    # 검증 실패는 세션을 이어서 수정하는 게 우선 (same session), 예산 초과 시 BLOCKED_AGENT
    result = {
        "terminal": "BLOCKED_AGENT" if exceeded else None,
        "fresh_session": fresh,
        "failure_type": ftype,
        "attempts": attempts,
        "type_attempts": counts.get(ftype, 0),
        "exceeded": exceeded,
    }
    return result


def _kill_process_tree(pid):
    """Windows 대상 지정 PID 의 process tree 만 종료.
    graceful terminate 시도 후 짧게 대기, 그래도 살아 있으면 taskkill /T /F.
    다른 Godot Editor / 다른 lane / 사용자 실행 프로세스는 건드리지 않는다 (PID 기반)."""
    try:
        p = subprocess.Popen(["taskkill", "/PID", str(pid), "/T", "/F"],
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                             creationflags=subprocess.CREATE_NO_WINDOW)
        p.communicate(timeout=15)
    except Exception as e:
        try:
            os.system(f'taskkill /PID {pid} /T /F >nul 2>&1')
        except Exception:
            pass


def run_headless_test(godot_exe, root, script_path, timeout=120):
    """Godot headless 테스트 실행. timeout 초과는 TEST_FAILED 와 구분해 timed_out 을 반환 (TEST_TIMEOUT).
    새 process group 으로 생성해, timeout/interrupt 시 해당 process tree 만 정리한다.
    반환: (통과 여부, tail 텍스트, timed_out 여부)"""
    timed_out = False
    creationflags = 0
    if os.name == "nt":
        creationflags |= (subprocess.CREATE_NEW_PROCESS_GROUP
                          | subprocess.CREATE_NO_WINDOW)
    try:
        proc = subprocess.Popen([godot_exe, "--headless", "--path", root,
                                 "--script", script_path], cwd=root,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                encoding="utf-8", errors="replace",
                                creationflags=creationflags)
    except Exception as e:
        return False, f"Godot spawn 실패: {str(e)[-300:]}", False
    try:
        out, _err = proc.communicate(timeout=timeout)
        text = out or ""
    except subprocess.TimeoutExpired:
        timed_out = True
        # graceful terminate 시도 → 대기 → 그래도 살아 있으면 process tree 강제 종료
        try:
            proc.terminate()
        except Exception:
            pass
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            _kill_process_tree(proc.pid)
            try:
                proc.kill()
            except Exception:
                pass
        # 남은 child 가 있는지 process tree 로 한 번 더 정리
        _kill_process_tree(proc.pid)
        return False, f"태스크 테스트 TIMEOUT: {timeout}초 초과", True

    # 정상 종료 후에도 잔류 child 확인 겸 안전 정리 (test 가 자식 GUI 를 남겼을 수 있음)
    if proc.returncode != 0 or "RESULT=FAIL" in text or "RESULT=PASS" not in text:
        _kill_process_tree(proc.pid)
    if "RESULT=FAIL" in text:
        return False, text[-600:], False
    if "RESULT=PASS" not in text:
        return False, ("PASS 마커 없음 (실행 실패 추정)\n" + (text or "")[-500:]), False
    return True, "", False


def changed_paths(root):
    """git status --porcelain 기준 변경/신규 파일 목록 (rel path, 정규화)."""
    _, st, _ = _run_cmd(["git", "-C", root, "status", "--porcelain"], timeout=60)
    paths = []
    for l in (st or "").splitlines():
        l = l.rstrip()
        if not l:
            continue
        path = l[3:].strip().strip('"').replace("\\", "/")
        if path:
            paths.append(path)
    return paths


def is_unrelated_change(path, task):
    """TASK 관련성 없는 변경인지. 테스트/작업트리 실패 분석 등 예외 경로는 제외."""
    tid = task_tid(task)
    p = path.lower()
    if tid in p:
        return False
    if p.startswith("tests/"):
        return False
    if "auto_dev" in p or p.startswith("docs/") or p.endswith(".md"):
        return False
    return True


def _file_hash(path):
    """파일 content-hash (md5). 읽기 오류/디렉터리면 None."""
    try:
        h = hashlib.md5()
        with open(path, "rb") as f:
            for chunk in iter(lambda: f.read(65536), b""):
                h.update(chunk)
        return h.hexdigest()
    except Exception:
        return None


def _iter_worktree_files(root):
    """worktree 의 모든 일반 파일 경로 (rel,  `/` 정규화). .git 제외."""
    root = os.path.abspath(root)
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d != ".git"]
        for fn in filenames:
            full = os.path.join(dirpath, fn)
            try:
                if os.path.isfile(full) and not os.path.islink(full):
                    rel = os.path.relpath(full, root).replace("\\", "/")
                    yield rel, full
            except Exception:
                continue


def snapshot_worktree(root):
    """시작 시 baseline: {rel path: content-hash}. 기존 dirty/untracked 도 모두 포함해 보존."""
    snap = {}
    for rel, full in _iter_worktree_files(root):
        h = _file_hash(full)
        if h is not None:
            snap[rel] = h
    return snap


def attempt_delta(root):
    """마지막 baseline 대비 이번 attempt 에서 실제 새로 생성/수정된 파일 목록 (rel path).
    content-hash 차이 기반이므로 기존 파일 내용 수정도 감지한다.
    baseline 이 없으면(REVIEW 재개 등) 전체 worktree dirty(changed_paths) 로 폴백."""
    global _WORKTREE_BASELINE
    if _WORKTREE_BASELINE is None:
        return changed_paths(root)
    delta = []
    current = {}
    for rel, full in _iter_worktree_files(root):
        h = _file_hash(full)
        if h is not None:
            current[rel] = h
    for rel, h in current.items():
        if _WORKTREE_BASELINE.get(rel) != h:
            delta.append(rel)
    for rel in list(_WORKTREE_BASELINE.keys()):
        if rel not in current:
            delta.append(rel)
    return delta


def set_attempt_baseline(root):
    """implementer 시도 시작 직전 baseline 스냅샷 저장."""
    global _WORKTREE_BASELINE, _ATTEMPT_START_HEAD
    _WORKTREE_BASELINE = snapshot_worktree(root)
    try:
        _, head, _ = _run_cmd(["git", "-C", root, "rev-parse", "HEAD"], timeout=30)
        _ATTEMPT_START_HEAD = (head or "").strip() or None
    except Exception:
        _ATTEMPT_START_HEAD = None


def capture_attempt_delta(root):
    """시도 종료 후 post snapshot 과 대조해 _LAST_ATTEMPT_DELTA 갱신. baseline 은 유지."""
    global _LAST_ATTEMPT_DELTA
    _LAST_ATTEMPT_DELTA = attempt_delta(root)
    return _LAST_ATTEMPT_DELTA


# ---------------------------------------------------------------------------
# COMMIT GATE: 성공 TASK 는 반드시 검증된 Git source commit 보유 후에만 DONE.
# invariant: status==DONE -> source_commit must exist
# ---------------------------------------------------------------------------
_COMMIT_SKIP_PARTS = ("/auto_dev/", "/.git/", "/.godot/", "/.import/", "/logs/", "/.venv/", "/cache/")
_COMMIT_SKIP_EXT = (".md", ".tmp", ".log", ".import", ".bak", ".old", ".orig", ".mp4", ".png", ".jpg")


def _git_rev_parse(root, ref="HEAD"):
    rc, out, _ = _run_cmd(["git", "-C", root, "rev-parse", ref], timeout=30)
    return (out or "").strip() or None


def _rel(root, p):
    return os.path.relpath(p, root).replace("\\", "/")


def _is_commitable(rel):
    r = (rel or "").lower().replace("\\", "/")
    if any(p in r for p in _COMMIT_SKIP_PARTS):
        return False
    ext = os.path.splitext(r)[1]
    if ext in _COMMIT_SKIP_EXT:
        return False
    return True


def _is_uncommitted(root, rel):
    rc, out, _ = _run_cmd(["git", "-C", root, "status", "--porcelain", "--", rel], timeout=30)
    return bool((out or "").strip())


def _is_committed_clean(root, rel):
    rc, out, _ = _run_cmd(["git", "-C", root, "ls-files", "--error-unmatch", "--", rel], timeout=30)
    if rc != 0:
        return False
    rc2, out2, _ = _run_cmd(["git", "-C", root, "status", "--porcelain", "--", rel], timeout=30)
    return (out2 or "").strip() == ""


def _all_committed_clean(root, rels):
    """모든 target 이 tracked 이고 working tree 에 modified/untracked 로 남은 것이 없어야 한다."""
    if not rels:
        return False
    return all(_is_committed_clean(root, rel) for rel in rels)


def _all_in_range(root, rels, start, end):
    """모든 target 이 start..end commit range 에 실제 포함되어 있는지."""
    if not rels:
        return False
    rc, out, _ = _run_cmd(["git", "-C", root, "diff", "--name-only", start, end], timeout=60)
    changed = {l.strip() for l in (out or "").splitlines() if l.strip()}
    return rels <= changed


def _stage_specific(root, rels):
    rc, out, err = _run_cmd(["git", "-C", root, "add", "--"] + rels, timeout=60)
    return rc == 0, (err or out)


def _cached_names(root):
    rc, out, _ = _run_cmd(["git", "-C", root, "diff", "--cached", "--name-only"], timeout=30)
    return {l.strip() for l in (out or "").splitlines() if l.strip()}


def _commit_message(task):
    title = (task.get("title") or "").strip()
    return f"auto: {task['id']} {title} (gate PASS + source commit)"


def _compute_commit_targets(task, root):
    """이번 attempt_delta 중 committable 파일 + 아직 commit 안 된 required test.
    기존 dirty/untracked(attempt delta 아님)와 unrelated 는 절대 포함하지 않는다."""
    targets = set()
    for rel in (_LAST_ATTEMPT_DELTA or []):
        if not os.path.isfile(os.path.join(root, rel)):
            continue
        if _is_commitable(rel):
            targets.add(rel)
    tf = find_task_test_file(task, root)
    if tf:
        trel = _rel(root, tf)
        if _is_commitable(trel) and _is_uncommitted(root, trel):
            targets.add(trel)
    return {t for t in targets if t}


def ensure_source_commit(task, root):
    """DONE 이전 commit gate. TODO scope 내 단일 invariant 강제.
    반환: (ok, source_base_commit, source_commit, reason)
    - source_base_commit = attempt 시작 HEAD (provenance 범위 lower bound)
    - source_commit       = 최종 HEAD (provenance 범위 upper bound)
    TASK 의 정확한 provenance 는 (source_base_commit, source_commit] 범위 전체이다."""
    try:
        required = required_test_path(task)
        tf = find_task_test_file(task, root)
        if tf is None:
            return False, None, None, f"required test 존재 안 함: {required}"

        cur_head = _git_rev_parse(root)
        start_head = _ATTEMPT_START_HEAD

        targets = _compute_commit_targets(task, root)

        # [ADOPT] 유효한 agent/외부 commit 만 채택. 다음을 반드시 모두 만족해야 한다:
        #   1) attempt 시작 HEAD != current HEAD (실제 advance)
        #   2) 이번 attempt 의 committable target 전체가 working tree 에 modified/untracked 로
        #      남아있지 않음 (= 전부 committed+clean)
        #   3) target 전체가 attempt 시작..current HEAD commit range 에 실제 포함
        #   4) required test 역시 committed
        # 어느 하나라도 실패하면 adopt 하지 않고, 남은 target 만 specific stage 하여 새 commit 생성.
        # unrelated HEAD advance 만으로는 valid source commit 으로 인정하지 않는다.
        if (start_head and cur_head and cur_head != start_head
                and targets
                and _all_committed_clean(root, targets)
                and _all_in_range(root, targets, start_head, cur_head)):
            return True, start_head, cur_head, f"기존 source commit 채택 (agent/외부): {cur_head[:12]}"

        # 이미 commit 되어 이번 attempt 의 추가 변경이 필요 없는 경우에도
        # 검증된 source commit 은 있어야 한다 (required test 가 실제 HEAD 에 committed).
        if not targets:
            trel = _rel(root, tf)
            if cur_head and _is_committed_clean(root, trel):
                return True, start_head, cur_head, f"이미 통합된 required test 존재(추가 변경 불필요): {cur_head[:12]}"
            return False, None, None, "commit 대상 없음 - 유효 source 변경/테스트 없음"

        # [item 3/4] 전체 worktree stage 금지 - 명시 경로만 stage (untracked 신규 포함).
        # 이미 committed 인 target 은 제외하고, 여전히 uncommitted 인 target 만 specific stage 한다.
        to_stage = {t for t in targets if _is_uncommitted(root, t)}
        if not to_stage:
            return False, None, None, "commit 대상 없음 - 남은 uncommitted 대상 없음"
        ok, serr = _stage_specific(root, sorted(to_stage))
        if not ok:
            return False, None, None, f"stage 실패: {serr.strip()[:200]}"

        # [item 5] stage 검증: 대상이 전부 staged 되고 unrelated 는 섞이지 않았는지
        staged = _cached_names(root)
        if to_stage != staged:
            return False, None, None, (f"stage 검증 실패 - 의도 대상과 불일치 "
                                       f"(대상={sorted(to_stage)[:5]}, staged={sorted(staged)[:5]})")

        msg = _commit_message(task)
        rc, com, cerr = _run_cmd(["git", "-C", root, "commit", "-m", msg], timeout=120)
        if rc != 0:
            return False, None, None, f"commit 실패: {((cerr or com) or '').strip()[:200]}"
        new_head = _git_rev_parse(root)
        if not new_head:
            return False, None, None, "commit 후 hash 조회 실패"
        return True, start_head, new_head, f"source commit 생성: {new_head[:12]}"
    except Exception as e:
        return False, None, None, f"commit gate 예외: {str(e)[:200]}"


def _record_source_commit(task, base, commit, reason=""):
    """TASK source provenance 를 기록한다.

    계약(중요): 향후 integration 단계(non-이번-작업) 에서는 source_commit 단일 hash 만을
    cherry-pick 해서 TASK 전체 integration 으로 간주하면 안 된다. agent 가 하나 이상의
    partial commit 을 만들 수 있으므로, TASK 의 정확한 provenance 는
    (source_base_commit, source_commit] 범위, 즉 `source_base_commit..source_commit` 범위
    전체의 commit 들을 모두 포함해야 한다.
    """
    if not commit:
        return
    runs_dir = os.path.join(BASE_DIR, "runs", GROUP_ID) if GROUP_ID else os.path.join(BASE_DIR, "runs", "_default")
    os.makedirs(runs_dir, exist_ok=True)
    p = os.path.join(runs_dir, f"result_{task['id']}.json")
    rng = f"{base}..{commit}" if (base and base != commit) else (commit or "")
    data = {
        "task": task["id"],
        "status": "DONE",
        "source_base_commit": base,
        "source_commit": commit,
        "source_provenance_range": rng,
        "source_branch": (WORKTREE_DIR or cfg("project_dir")),
        "source_commit_created_at": datetime.datetime.now().isoformat(),
        "integrator_contract": (
            "TASK 전체 integration 은 source_base_commit..source_commit 범위 전체의 commit 들을 "
            "모두 포함해야 한다. source_commit 단일 cherry-pick 으로 TASK 전체를 integration "
            "했다고 간주하지 말 것 (partial agent commit 이 존재할 수 있다)."
        ),
        "note": reason,
    }
    try:
        with open(p, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
    except OSError:
        pass


def finalize_done(task, tasks, queue_path, reason):
    """DONE 전 commit gate. 성공 TASK 는 반드시 source commit 보유해야 DONE.
    반환: DONE 처리했으면 True, commit 실패로 보류했으면 False."""
    root = WORKTREE_DIR or cfg("project_dir")
    ok, base, commit, creason = ensure_source_commit(task, root)
    if ok and commit:
        if not base:
            base = _git_rev_parse(root, commit + "^") or commit
        _record_source_commit(task, base, commit, creason)
        fb = (reason or "") + f" | source_base={base[:12]}..source={commit[:12]}"
        update_queue(tasks, queue_path, task["id"], "DONE", feedback=fb)
        write_result(task, "DONE", fb + f"\n- source_base_commit: {base}\n- source_commit: {commit}\n- source_provenance_range: {base}..{commit}\n- worktree: {root}")
        log(f"[{task['id']}] DONE (provenance {base[:12]}..{commit[:12]})")
        return True
    # commit 실패 → DONE 금지. implementation/test PASS 상태는 로그에 보존하고 non-success 로 남김.
    record_failure(task, "COMMIT_FAILED", creason)
    update_queue(tasks, queue_path, task["id"], "FIX",
                 feedback=f"PASS 후 source commit 생성 실패 (COMMIT_FAILED) - 변경 보존, 재시도 필요: {creason[:150]}")
    write_result(task, "COMMIT_FAILED",
                 f"implementation/test PASS 유지, provenance 생성 실패: {creason}\n- 작업 파일은 보존됨(삭제 안 함)")
    log(f"[{task['id']}] DONE 보류: COMMIT_FAILED - {creason}")
    return False


def pre_gate(task, root):
    """Expensive Godot gate 이전의 cheap pre-gate.
    - required test 존재
    - 실제 git diff/artifact 존재
    - TASK 관련 변경 존재
    - 명백한 scope drift 없음
    구현 태스크인데 유효 artifact(비-테스트 구현 변경)가 없으면
    NO_CODE_DIFF / NO_MEANINGFUL_ARTIFACT 로 즉시 실패하고 Godot 을 실행하지 않는다.
    반환: (즉시 차단할 problems  목록, 전체 변경 경로 목록)"""
    blocking = []
    ver = CONFIG.get("verification", {})
    # attempt_delta: 이번 implementer attempt 에서 실제 새로 생성/수정된 파일 (content-hash 기준)
    # 기존 worktree 의 dirty/untracked 파일은 이번 artifact 로 계산하지 않는다.
    delta = list(_LAST_ATTEMPT_DELTA or [])
    if not delta:
        delta = changed_paths(root)
    paths = delta or changed_paths(root)

    # 1) 실제 diff/artifact 존재 (attempt 단위 기준)
    if not delta:
        return [f"변경된 파일이 없음 - 구현 자체가 이루어지지 않았을 가능성. "
                f"분류: {classify_no_diff(task)}"], paths

    # 2) required test 존재 (cheap - Godot 불필요)
    if ver.get("task_test", True) and find_task_test_file(task, root) is None:
        required = required_test_path(task)
        cands = possible_test_candidates(root)
        msg = (f"REQUIRED TEST FILE:\n"
               f"  {required}  (tests/*{task_tid(task)}*_test.gd 패턴)\n"
               f"게이트가 요구하는 경로에 태스크 테스트 파일이 없습니다.")
        if cands:
            msg += "\nFOUND POSSIBLE TEST FILES (경로/이름 불일치로 거부됨):\n  " + "\n  ".join(cands)
            msg += (f"\n원인이면 기존 테스트 내용을 {required} 로 이동/적용하세요. "
                    "다른 파일명이나 경로에 만든 테스트는 검증 게이트를 충족하지 못합니다.")
        blocking.append(msg)

    # 3) 유효 artifact: 구현(비-테스트) 변경 OR 의미 있는 테스트 변경 (attempt 단위 기준)
    #    (기존 production 코드가 요구사항을 이미 충족하면 테스트 신규/수정만으로도 유효)
    has_impl_change = any(not p.startswith("tests/") for p in delta)
    meaningful_test = False
    tf = find_task_test_file(task, root)
    if tf:
        try:
            with open(tf, encoding="utf-8", errors="replace") as f:
                meaningful_test = len(f.read().strip()) > 100
        except Exception:
            meaningful_test = False
    if not has_impl_change and not meaningful_test:
        blocking.append(
            f"NO_MEANINGFUL_ARTIFACT: 관련 구현 변경도 의미 있는 테스트 변경도 없음 "
            f"(분석/설명만 추정). 분류: NO_MEANINGFUL_ARTIFACT | 변경: {paths[:6]}")

    # 4) 명백한 scope drift 없음 (non-test 변경이 존재하되 전부 TASK 와 무관하면 드리프트)
    if has_impl_change and all(is_unrelated_change(p, task) for p in delta):
        blocking.append(
            f"명백한 SCOPE_DRIFT: 변경 파일이 전부 TASK({task['id']})와 무관. "
            f"분류: SCOPE_DRIFT | 변경: {paths[:6]}")

    return blocking, paths


def verification_gate(task):
    """LLM 리뷰 대체 결정적 게이트. 반환: (통과 여부, 문제 목록).
    cheap pre-gate 로 Godot 실행 여부를 먼저 판정한다."""
    root = WORKTREE_DIR or cfg("project_dir")
    ver = CONFIG.get("verification", {})
    problems = []

    # ---------- CHEAP PRE-GATE (Godot 실행 전) ----------
    blocking, _ = pre_gate(task, root)
    if blocking:
        problems.extend(blocking)
        # 의미 있는 코드/테스트 artifact 없음 → Godot 불필요, 즉시 실패 (TEST 실행 안 함)
        # (NO_CODE_DIFF = 변경 0 / NO_MEANINGFUL_ARTIFACT = 테스트 파일뿐. SCOPE_DRIFT 는 여기 해당 안 됨)
        if any(("NO_MEANINGFUL_ARTIFACT" in p or "변경된 파일이 없음" in p)
               and "SCOPE_DRIFT" not in p for p in blocking):
            return False, problems
        # required test 누락: 태스크 테스트 Godot 은 실행하지 않되(아래 elif), smoke 회귀는 계속 수행

    # ---------- 위험 파일 / 임시 파일 / 테스트 변조 (diff 기반, cheap) ----------
    lines = (subprocess.run(["git", "-C", root, "status", "--porcelain"],
                            capture_output=True, encoding="utf-8", errors="replace",
                            timeout=60).stdout or "").splitlines()
    for l in lines:
        pl = l.rstrip()
        if not pl:
            continue
        path = pl[3:].strip().strip('"').replace("\\", "/")
        if DANGER_RE.match(path):
            problems.append(f"위험 파일 변경(FAIL): {path}")

    for l in lines:
        pl = l.rstrip()
        if pl.startswith("??"):
            name = os.path.basename(pl[3:].strip().strip('"'))
            if GATE_TEMP_RE.match(name):
                problems.append(f"임시/debug 파일 잔존: {name}")

    if ver.get("suspicious_test_change", True):
        for l in lines:
            pl = l.rstrip()
            if not pl:
                continue
            x, y, path = pl[0], pl[1], pl[3:].strip().strip('"').replace("\\", "/")
            if not path.startswith("tests/"):
                continue
            if x == "D" or y == "D":
                problems.append(f"SUSPICIOUS_TEST_CHANGE: 테스트 파일 삭제 {path}")
                continue
            if x in ("M", "A") or y == "M":
                try:
                    _, old, _ = _run_cmd(["git", "-C", root, "show", f"HEAD:{path}"], timeout=60)
                    with open(os.path.join(root, path), encoding="utf-8", errors="replace") as f:
                        new = f.read()
                    oc, nc = old.count("_check("), new.count("_check(")
                    if nc < oc:
                        problems.append(f"SUSPICIOUS_TEST_CHANGE: {path} assertion {oc}→{nc} 감소")
                except Exception as e:
                    problems.append(f"테스트 diff 검사 실패: {path} ({e})")

    # ---------- 태스크 자체 테스트 (Godot) - timeout 단축 ----------
    if ver.get("task_test", True):
        tf = find_task_test_file(task, root)
        godot = CONFIG.get("godot_exe")
        if not godot:
            problems.append("config에 godot_exe 미설정 - 게이트 테스트 불가")
        elif tf is not None:
            tmo = int(CONFIG.get("test_timeout_sec", 120))
            ok, tailtxt, timed_out = run_headless_test(godot, root, tf, timeout=tmo)
            if not ok:
                if timed_out:
                    problems.append(f"태스크 테스트 TIMEOUT: {os.path.basename(tf)}\n{tailtxt}")
                else:
                    problems.append(f"태스크 테스트 FAIL: {os.path.basename(tf)}\n{tailtxt}")
        # (pre-gate 가 REQUIRED TEST FILE 누락을 blocking 으로 이미 추가했으므로 여기선 미실행)

    # ---------- 회귀(smoke) (Godot) - timeout 단축 ----------
    if ver.get("regression", True):
        smoke = os.path.join(root, "tests", "smoke_test.gd")
        godot = CONFIG.get("godot_exe")
        if godot and os.path.exists(smoke):
            tmo = int(CONFIG.get("smoke_timeout_sec", 300))
            ok, tailtxt, timed_out = run_headless_test(godot, root, smoke, timeout=tmo)
            if not ok:
                if timed_out:
                    problems.append(f"회귀(smoke) TIMEOUT\n{tailtxt}")
                else:
                    problems.append(f"회귀(smoke) FAIL\n{tailtxt}")

    return len(problems) == 0, problems


def write_result(task, verdict, reason):
    if not GROUP_ID:
        return
    runs_dir = os.path.join(BASE_DIR, "runs", GROUP_ID)
    os.makedirs(runs_dir, exist_ok=True)
    with open(os.path.join(runs_dir, "RESULT.md"), "a", encoding="utf-8") as f:
        f.write(f"## {task['id']} {task['title']}\n\n"
                f"- 판정: {verdict}\n- 사유: {(reason or '')[:600]}\n"
                f"- 브랜치/워크트리: {(WORKTREE_DIR or cfg('project_dir'))}\n"
                f"- 완료 시각: {datetime.datetime.now().isoformat()}\n\n")


def reviewer_model():
    """유료 리뷰어. 할당량 소진 시 C(무료)로 자동 폴백."""
    if os.path.exists(FALLBACK_STATE_PATH):
        try:
            with open(FALLBACK_STATE_PATH, encoding="utf-8") as f:
                if json.load(f).get("fallback"):
                    return cfg("reviewer_fallback_model")
        except (OSError, json.JSONDecodeError):
            pass
    return cfg("reviewer_model")


def mark_reviewer_fallback(reason):
    with open(FALLBACK_STATE_PATH, "w", encoding="utf-8") as f:
        json.dump({"fallback": True, "reason": reason[:200],
                   "when": datetime.datetime.now().isoformat()}, f, ensure_ascii=False, indent=2)
    log(f"리뷰어 유료 할당량 소진 감지 - 폴백 모델로 전환: {reason[:100]}")


def implementer_model():
    """구현자 모델. 'Model not found'(무료 모델 종료 등) 시 유료 폴백으로 전환."""
    if os.path.exists(IMPL_FALLBACK_STATE_PATH):
        try:
            with open(IMPL_FALLBACK_STATE_PATH, encoding="utf-8") as f:
                if json.load(f).get("fallback"):
                    return cfg("implementer_fallback_model")
        except (OSError, json.JSONDecodeError):
            pass
    return cfg("implementer_model")


def mark_implementer_fallback(reason):
    with open(IMPL_FALLBACK_STATE_PATH, "w", encoding="utf-8") as f:
        json.dump({"fallback": True, "reason": reason[:200],
                   "when": datetime.datetime.now().isoformat()}, f, ensure_ascii=False, indent=2)
    log(f"구현자 모델 문제 감지 - 유료 폴백 전환: {reason[:100]}")


HARNESS_BASE = "http://localhost:11434/v1"
HARNESS_API_KEY = "ollama"


def harness_py():
    d = CONFIG.get("harness_dir", "D:\\coding-harness")
    p = os.path.join(d, "agent.py")
    if os.path.exists(p):
        return p
    log(f"! coding-harness agent.py 를 찾지 못함: {p}")
    return p


def strip_model_prefix(model):
    return model.split("/")[-1] if "/" in model else model


def _extract_flag(extra_args, flag):
    """extra_args 목록에서 --flag 다음 값을 반환 (없으면 None)."""
    val, i = None, 0
    while i < len(extra_args or []):
        if extra_args[i] == flag and i + 1 < len(extra_args):
            val = extra_args[i + 1]
            i += 2
            continue
        i += 1
    return val


def _harness_progress_signal():
    """하네스 runs 아티팩트(events.jsonl/checkpoint/final.json)의 최신 mtime과 총 크기.
    진행 감시의 progress sink로 사용."""
    hdir = CONFIG.get("harness_dir", "D:\\coding-harness")
    runs_dir = os.path.join(hdir, "runs")
    best = 0.0
    size = 0
    if not os.path.isdir(runs_dir):
        return best, size
    try:
        for p in glob.glob(os.path.join(runs_dir, "**", "events.jsonl"), recursive=True) + \
                 glob.glob(os.path.join(runs_dir, "**", "checkpoint.json"), recursive=True) + \
                 glob.glob(os.path.join(runs_dir, "**", "final.json"), recursive=True):
            st = os.stat(p)
            if st.st_mtime > best:
                best = st.st_mtime
            size += st.st_size
    except Exception:
        pass
    return best, size


class NoProgressGuard:
    """하네스 에이전트 실행 중 '충분히 오래 진전이 없음'을 감지해 트리를 종료.
    고정 wall-clock timeout이 아니라 progress 기반으로 동작.
    속성: fired (bool), reason (str)"""

    def __init__(self, proc, no_progress_sec, overall_timeout_sec, name=""):
        self.proc = proc
        self.no_progress_sec = no_progress_sec
        self.overall_timeout_sec = overall_timeout_sec
        self.name = name
        self.fired = False
        self.reason = ""
        self.stop = threading.Event()
        self._t = None

    def start(self):
        self._t = threading.Thread(target=self._run, daemon=True)
        self._t.start()
        return self

    def _kill(self):
        try:
            os.system(f'taskkill /PID {self.proc.pid} /T /F >nul 2>&1')
        except Exception:
            try:
                self.proc.kill()
            except Exception:
                pass

    def _run(self):
        start = time.time()
        last_m, last_s = _harness_progress_signal()
        last_change = time.time()
        while not self.stop.is_set():
            time.sleep(20)
            if self.stop.is_set():
                return
            cur_m, cur_s = _harness_progress_signal()
            if cur_m > last_m + 1.0 or cur_s > last_s:
                last_m, last_s = cur_m, cur_s
                last_change = time.time()
                continue
            stalled_sec = time.time() - last_change
            total = time.time() - start
            if stalled_sec >= self.no_progress_sec:
                self.fired = True
                self.reason = f"NO_PROGRESS_STALLED ({int(stalled_sec)}s 진행 없음)"
                log(f"[{self.name}] {self.reason} - 트리 종료")
                self._kill()
                return
            if total >= self.overall_timeout_sec:
                self.fired = True
                self.reason = f"OVERALL_TIMEOUT ({int(total)}s)"
                log(f"[{self.name}] {self.reason} - 트리 종료")
                self._kill()
                return

    def close(self):
        self.stop.set()
        if self._t:
            self._t.join(timeout=5)


def build_harness_task_file(prompt, task_file):
    """하네스 --task-file 용 임시 파일 생성: 지시문(prompt) + 태스크 블록(task_file) 병합.
    task_file 이 없으면 prompt 만 사용. content 가 너무 길면 도구 컨텍스트 절약을 위해 흐름대로 유지."""
    content = prompt or ""
    if task_file and os.path.exists(task_file):
        try:
            with open(task_file, encoding="utf-8") as f:
                block = f.read()
            if block.strip():
                content += "\n\n[태스크 상세]\n" + block
        except OSError:
            pass
    if not content.strip():
        content = "태스크를 수행하세요."
    path = os.path.join(BASE_DIR, "harness_task.md")
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    return path


def run_opencode(prompt, model, extra_args=None, timeout_sec=1800):
    """coding-harness(agent.py) 기반 실행기로 opencode 대체 (tool-call 실행 결함 우회).
    인터페이스 (sid, text, err) 유지. sid = harness run-id (재개 시 --resume checkpoint).
    297: print(f\"  - 브랜치/워크트리: ...\") 원래 흐름 참고."""
    agent_dir = WORKTREE_DIR or cfg("project_dir")
    task_file = _extract_flag(extra_args, "--file")
    session = _extract_flag(extra_args, "--session")
    task_md = build_harness_task_file(prompt, task_file)

    args = [sys.executable, harness_py(),
            "--workdir", agent_dir,
            "--provider", "openrouter",
            "--base-url", HARNESS_BASE,
            "--api-key", HARNESS_API_KEY,
            "--model", strip_model_prefix(model),
            "--task-file", task_md,
            "--policy", "yolo",
            "--max-turns", str(CONFIG.get("harness_max_turns", 24)),
            "--timeout", str(timeout_sec)]
    if session:
        resume_cp = os.path.join(CONFIG.get("harness_dir", "D:\\coding-harness"),
                                 "runs", session, "checkpoint.json")
        if os.path.exists(resume_cp):
            args += ["--resume", resume_cp]
    env = os.environ.copy()
    env["PYTHONIOENCODING"] = "utf-8"
    log(f"harness 실행: model={strip_model_prefix(model)} wd={agent_dir}")
    proc = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True, encoding="utf-8", errors="replace", env=env,
                            creationflags=subprocess.CREATE_NEW_PROCESS_GROUP)
    no_progress_sec = int(CONFIG.get("lane_no_progress_sec", 1500))
    overall_timeout_sec = int(CONFIG.get("lane_overall_timeout_sec", 10800))
    guard = NoProgressGuard(proc, no_progress_sec, overall_timeout_sec,
                            name=f"harness {strip_model_prefix(model)}").start()
    try:
        stdout, stderr = proc.communicate(timeout=overall_timeout_sec + 30)
    except subprocess.TimeoutExpired:
        log(f"TIMEOUT: {overall_timeout_sec}초 초과 - 프로세스 트리 강제 종료 (pid={proc.pid})")
        os.system(f'taskkill /PID {proc.pid} /T /F >nul 2>&1')
        try:
            stdout, stderr = proc.communicate(timeout=30)
        except subprocess.TimeoutExpired:
            stdout, stderr = "", ""
        guard.close()
        return None, "", f"실행 시간 초과 ({overall_timeout_sec}초)", "timeout"
    finally:
        guard.close()
    if proc.returncode != 0:
        err_msg = extract_harness_error(stdout, stderr)
        log(f"harness 실패 (exit={proc.returncode}): {err_msg[:200]}")
        hstatus = "error"
        if guard.fired:
            hstatus = "timeout"
        elif proc.returncode == 2:
            hstatus = "max_turns"
        elif proc.returncode == 5:
            hstatus = "tool_loop_stalled"
        elif proc.returncode == 6:
            hstatus = "analysis_only"
        elif proc.returncode == 3:
            hstatus = "timeout"
        return None, "", (guard.reason if guard.fired else err_msg), hstatus
    sid, text, _ = parse_harness_output(stdout)
    return sid, text, "", "completed"


def extract_harness_error(stdout, stderr):
    # 하네스 오류: exit code 매핑 + stderr 마지막 라인
    if stdout and ("STATUS" in stdout or "STATUS :" in stdout):
        for line in stdout.splitlines():
            if "STATUS :" in line or "STATUS:" in line:
                return line.strip()
    if stdout:
        # 2/3/4/5 종료코드용 메시지가 stdout에 있는 경우
        for line in stdout.splitlines():
            if line.strip().startswith(("ERROR", "TIMEOUT", "max turns", "provider",
                                        "tool_loop_stalled")):
                return line.strip()[:300]
    return (stderr or "").strip()[-2000:] or "알 수 없는 오류"


def parse_harness_output(stdout):
    """하네스 출력에서 run-id 와 최종 텍스트 추출.
    - run-id: '[harness] artifacts: <dir>/runs/<run-id>' 에서 추출
    - text: 하네스 아티팩트 final.json 의 final_text (완료 요약/판정 포함).
            final.json 을 못 읽으면 stdout 의 SUMMARY 본문으로 폴백.
    - hstatus: final.json 의 status (completed/tool_loop_stalled/max_turns/... 등)"""
    run_id = None
    for line in (stdout or "").splitlines():
        ls = line.strip()
        if ls.startswith("[harness] artifacts:"):
            m = re.search(r"runs[/\\]([A-Za-z0-9_\-]+)", ls)
            if m:
                run_id = m.group(1)
    text = ""
    hstatus = ""
    if run_id:
        final_json = os.path.join(CONFIG.get("harness_dir", "D:\\coding-harness"),
                                  "runs", run_id, "final.json")
        if os.path.exists(final_json):
            try:
                with open(final_json, encoding="utf-8") as f:
                    data = json.load(f)
                text = (data.get("final_text") or "").strip()
                hstatus = str(data.get("status") or "").strip()
                if not hstatus:
                    hstatus = "max_turns" if data.get("turns", 0) and \
                        data.get("tool_events", 0) == 0 else ""
            except (OSError, ValueError):
                text = ""
    if not hstatus:
        for line in (stdout or "").splitlines():
            if "STATUS :" in line:
                hstatus = line.split(":", 1)[1].strip().split()[0] if len(line.split(":", 1)) > 1 else ""
                break
    if not text:
        # 폴백: stdout 에서 STATUS 블록 이후 마지막 비-메타 텍스트 라인들
        lines = (stdout or "").splitlines()
        buff = []
        in_block = False
        for ln in lines:
            s = ln.strip()
            if not s:
                continue
            if s.startswith("STATUS :"):
                in_block = True
                continue
            if s.startswith(("[", "===", "---", "TURNS", "TIME", "TOKENS", "tool")):
                continue
            if in_block and not s.startswith(("turn", "[harness]")):
                buff.append(s)
        text = "\n".join(buff).strip()
    return run_id, text, ""


def extract_error_event(stdout):
    """stdout의 JSON error 이벤트에서 메시지 추출 (빈 stderr + 오류 마스킹 방지)."""
    for line in (stdout or "").splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            ev = json.loads(line)
        except json.JSONDecodeError:
            continue
        err = ev.get("error")
        if isinstance(err, dict):
            msg = err.get("message") or ""
            status = err.get("statusCode") or ""
            name = err.get("name") or ""
            detail = ""
            data = err.get("data")
            if isinstance(data, dict) and isinstance(data.get("message"), str):
                detail = data["message"]
            return f"{name} [{status}] {msg} {detail}".strip()
    return None


def parse_run_output(raw):
    """--format json 출력에서 sessionID와 전체 텍스트 추출."""
    session_id = None
    texts = []
    for line in raw.splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            ev = json.loads(line)
        except json.JSONDecodeError:
            continue
        if session_id is None and isinstance(ev.get("sessionID"), str):
            session_id = ev["sessionID"]
        part = ev.get("part")
        if isinstance(part, dict):
            if part.get("type") == "text" and isinstance(part.get("text"), str):
                if part["text"].strip():
                    texts.append(part["text"])
            if session_id is None and isinstance(part.get("sessionID"), str):
                session_id = part["sessionID"]
    return session_id, "\n".join(texts), ""


def extract_verdict(text):
    matches = list(VERDICT_RE.finditer(text))
    if not matches:
        kw = re.finditer(r"(?<![A-Za-z0-9_-])(LGTM|FIX|NEEDS_DESIGN)(?![A-Za-z0-9_-])", text or "", re.IGNORECASE)
        kw = list(kw)
        if not kw:
            return None, ""
        last = kw[-1]
        verdict = last.group(1).upper()
        reason = text[max(0, last.start() - 300):].strip()
        if len(reason) > 400:
            reason = reason[-400:]
        return verdict, reason
    verdict = matches[-1].group(1).upper()
    reasons = list(REASON_RE.finditer(text))
    reason = reasons[-1].group(1).strip() if reasons else ""
    if not reason:
        reason = text[matches[-1].end():].strip().splitlines()[0] if matches[-1].end() < len(text) else ""
    return verdict, reason


def extract_summary(text):
    matches = list(SUMMARY_RE.finditer(text))
    if not matches:
        return ""
    return text[matches[-1].end():].strip()[:800]


def load_prompt(name):
    with open(os.path.join(PROMPT_DIR, name), encoding="utf-8") as f:
        return f.read().strip()


def format_task_context(task):
    parts = [f"태스크 ID: {task['id']}", f"태스크: {task['title']}"]
    if task.get("feedback"):
        parts.append(f"참고(이전 피드백): {task['feedback']}")
    return "\n".join(parts)


def run_opencode_retry(prompt, model, extra, timeout_sec, task_id="", attempts=4):
    """모델 실행 재시도 정책.
    - 성공: 즉시 반환
    - task-level 실패(ANALYSIS_ONLY / TOOL_LOOP_STALLED / NO_PROGRESS_STALLED /
      AGENT_MAX_TURNS / timeout 등) → 내부 재시도 없이 상위 TASK 예산으로 즉시 전달
    - transient infra(provider/network/transport 일시 오류) → 백오프 내부 재시도만 사용
    반환: (sid, text, err, hstatus)"""
    sid, text, err, hstatus = None, "", None, ""
    task_level = {"analysis_only", "tool_loop_stalled", "max_turns",
                  "timeout", "no_progress_stalled"}
    for i in range(1, attempts + 1):
        sid, text, err, hstatus = run_opencode(prompt, model, extra, timeout_sec)
        if not err and (text or "").strip():
            return sid, text, err, hstatus
        hs = (hstatus or "").lower()
        # task-level 스톨/실패는 재시도로 해결할 문제가 아님 - 상위 budget 으로 즉시 전달
        if hs in task_level:
            return sid, text, err, hstatus
        if err and "실행 시간 초과" in (err or ""):
            return sid, text, err, "timeout"
        # 그 외 = transient infra 오류만 내부에서 백오프 재시도
        if i < attempts:
            wait = 120 * i
            log(f"[{task_id}] transient infra 실패({(err or '빈 응답')[:60]}) ({i}/{attempts}) - {wait}초 후 재시도")
            time.sleep(wait)
    return sid, text, err, hstatus


def build_task_file(task, queue_path):
    """큐에서 해당 태스크 블록만 추출해 축소 컨텍스트 파일로 저장 (대형 모델 컨텍스트 절약)."""
    with open(queue_path, encoding="utf-8") as f:
        lines = f.readlines()
    header = f"### {task['id']}"
    capture = False
    block = []
    for line in lines:
        if line.startswith(header):
            capture = True
            block.append(line)
            continue
        if capture:
            if line.startswith("### ") or line.startswith("## "):
                break
            block.append(line)
    out_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "task_context.md")
    with open(out_path, "w", encoding="utf-8") as f:
        if block:
            f.writelines(block)
        else:
            f.write(format_task_context(task))
    return out_path


def run_implementer(task, session_id=None, review_feedback=None):
    # esta attempt 의 baseline snapshot (기존 dirty/untracked 포함 보존, 차이는 attempt_delta 로만 판정)
    _root = WORKTREE_DIR or cfg("project_dir")
    try:
        set_attempt_baseline(_root)
    except Exception:
        pass
    prompt = load_prompt("implementer.md")
    prompt += "\n\n" + format_task_context(task)
    req = required_test_path(task)
    prompt += (f"\n\nMANDATORY TEST FILE:\n"
               f"  {req}\n\n"
               f"You MUST create exactly this test file at this path.\n"
               f"The verification gate only accepts a test matching "
               f"tests/*{task_tid(task)}*_test.gd. "
               f"A test created under any other filename or directory does not satisfy the gate.\n"
               f"Use Write/Edit to create {req} (e.g. extend SceneTree headless GDScript "
               f"with _check() assertions printing RESULT=PASS/FAIL).")
    if review_feedback:
        prompt += f"\n\n[리뷰어 피드백 - 반드시 반영하고 수정하세요]\n{review_feedback}"
    queue_path = os.path.join(cfg("project_dir"), cfg("queue_file"))
    extra = ["--file", build_task_file(task, queue_path)]
    if session_id:
        extra += ["--session", session_id]
    sid, text, err, hstatus = run_opencode_retry(prompt, cfg("implementer_model"), extra,
                                                 cfg("implementer_timeout_sec"), task_id=task["id"])
    summary = extract_summary(text)
    if not summary:
        summary = (text or "").strip()[-800:]
    try:
        capture_attempt_delta(_root)
    except Exception:
        pass
    return sid, summary, err, hstatus


def run_reviewer(task, summary, recovery_file=None):
    """리뷰어 호출. recovery_file 지정 시 이전 리뷰 출력만으로 판정만 다시 받는다.
    반환: (원문 텍스트, err)"""
    if recovery_file:
        prompt = ("아래는 이전 리뷰어의 출력입니다. 이 출력만 보고 판정을 추론해 "
                  "마지막 줄에 정확히 `판정: LGTM | FIX | NEEDS_DESIGN` 형식으로 "
                  "판정 한 줄만 다시 남기세요. 그 외 어떤 내용도 작성하지 마세요.")
        extra = ["--file", recovery_file]
    else:
        prompt = load_prompt("reviewer.md")
        prompt += "\n\n" + format_task_context(task)
        prompt += f"\n\n[구현 결과 요약]\n{summary or '(요약 없음 - 직접 코드를 확인하세요)'}"
        queue_path = os.path.join(cfg("project_dir"), cfg("queue_file"))
        extra = ["--file", build_task_file(task, queue_path)]
    _, text, err, _ = run_opencode_retry(prompt, reviewer_model(), extra,
                                         cfg("reviewer_timeout_sec"), task_id=task["id"])
    if err and QUOTA_RE.search(err or ""):
        mark_reviewer_fallback(err)
        _, text, err, _ = run_opencode_retry(prompt, reviewer_model(), extra,
                                             cfg("reviewer_timeout_sec"), task_id=task["id"])
    return text, err


def parse_attempts_path(task):
    runs_dir = os.path.join(BASE_DIR, "runs", GROUP_ID) if GROUP_ID else os.path.join(BASE_DIR, "runs", "_default")
    os.makedirs(runs_dir, exist_ok=True)
    return os.path.join(runs_dir, f"parse_attempts_{task['id']}.json")


def get_parse_attempts(task):
    p = parse_attempts_path(task)
    if os.path.exists(p):
        with open(p, encoding="utf-8") as f:
            return json.load(f).get("count", 0)
    return 0


def bump_parse_attempts(task):
    p = parse_attempts_path(task)
    n = get_parse_attempts(task) + 1
    with open(p, "w", encoding="utf-8") as f:
        json.dump({"count": n, "updated": datetime.datetime.now().isoformat()}, f, ensure_ascii=False)
    return n


def design_resolution_path(task):
    runs_dir = os.path.join(BASE_DIR, "runs", GROUP_ID) if GROUP_ID else os.path.join(BASE_DIR, "runs", "_default")
    os.makedirs(runs_dir, exist_ok=True)
    return os.path.join(runs_dir, f"design_resolution_{task['id']}.md")


def maybe_design_resolve(task, tasks, queue_path, reason):
    """설계 갈등(NEEDS_DESIGN) 시 1회만 Thinker(qwen3.6)로 해결안을 만들어 자동 재시작.

    - 해결안 문서가 이미 존재하면 자동 재시도를 멈추고 사람 개입으로 넘긴다(반복 루프 방지).
    - Thinker가 해결안을 산출하면 태스크를 QUEUED로 재큐 → 다음 사이클에서
      qwen3-coder:30b 구현자가 해결안을 참고해 재실행한다.
    - 실패하면 False → 호출부가 그대로 NEEDS_DESIGN으로 기록한다."""
    model = cfg("design_thinker_model")
    if not model:
        return False
    rpath = design_resolution_path(task)
    if os.path.exists(rpath):
        log(f"[{task['id']}] 설계 해결 시도 기록 존재 - 자동 재시도 중단, 사람 개입 대기")
        return False
    prompt = load_prompt("thinker.md")
    prompt += "\n\n" + format_task_context(task)
    prompt += f"\n\n[실패/설계 갈등 사유]\n{str(reason)[:1500]}"
    extra = ["--file", build_task_file(task, queue_path)]
    sid, text, err, _ = run_opencode_retry(prompt, model, extra, cfg("thinker_timeout_sec"),
                                           task_id=task["id"])
    if err:
        log(f"[{task['id']}] 설계 Thinker 오류 - NEEDS_DESIGN 유지(사람 개입): {err[:200]}")
        return False
    content = (text or "").strip()
    if not content:
        log(f"[{task['id']}] 설계 Thinker 빈 응답 - NEEDS_DESIGN 유지")
        return False
    with open(rpath, "w", encoding="utf-8") as f:
        f.write(content)
    rel = os.path.relpath(rpath, BASE_DIR)
    update_queue(tasks, queue_path, task["id"], "QUEUED",
                 feedback=f"설계 해결안 자동 생성됨 ({rel} 참고): {str(reason)[:200]}")
    log(f"[{task['id']}] 설계 해결안 생성 -> QUEUED 재큐 ({model})")
    return True


def reset_parse_attempts(task):
    p = parse_attempts_path(task)
    if os.path.exists(p):
        os.remove(p)


def _active_supervisor_for(task_id):
    """동일 태스크를 실제로 실행 중인 supervisor/agent python 프로세스 존재 여부.
    상태가 IMPLEMENT 인데 실행 프로세스가 없으면 orphan(죽은 감독자 잔재)로 판단."""
    if os.name != "nt":
        return None
    try:
        for p in subprocess.run(
                ["powershell", "-NoProfile", "-Command",
                 "Get-CimInstance Win32_Process -Filter \"Name='python.exe'\" | "
                 "Where-Object { $_.CommandLine -match 'supervisor.py' } | "
                 "Select-Object -ExpandProperty ProcessId"],
                capture_output=True, encoding="utf-8", errors="replace",
                creationflags=subprocess.CREATE_NO_WINDOW, timeout=20).stdout.split():
            p = p.strip()
            if not p.isdigit():
                continue
            try:
                cmd = subprocess.run(
                    ["powershell", "-NoProfile", "-Command",
                     f"(Get-CimInstance Win32_Process -Filter \"ProcessId={p}\").CommandLine"],
                    capture_output=True, encoding="utf-8", errors="replace",
                    creationflags=subprocess.CREATE_NO_WINDOW, timeout=20).stdout or ""
            except Exception:
                continue
            if task_id in cmd and "supervisor.py" in cmd:
                return p
    except Exception:
        return None
    return None


def recover_orphan_implement(task, tasks, queue_path):
    """죽은 supervisor 가 남긴 IMPLEMENT/REVIEW 상태를 복구한다.
    상태가 유지되는데 실제 감독 프로세스가 없으면 영구 잔류 방지를 위해 재실행(FIX) 처리로 되돌린다.
    반환: 복구했으면 True (상위에서 해당 태스크를 새로 진행)"""
    if task["status"] not in ("IMPLEMENT", "REVIEW", "REVIEW_PARSE_ERROR"):
        return False
    act = _active_supervisor_for(task["id"])
    if act is None:
        log(f"[{task['id']}] orphan IMPLEMENT/REVIEW 감지 - 실행 감독자 없음 → 재실행으로 복구")
        update_queue(tasks, queue_path, task["id"], "IMPLEMENT",
                     feedback="이전 supervisor 종료로 상태만 남음 - 자동 재실행 복구")
        return True
    return False


def pick_next_task(tasks):
    for t in tasks:
        if t["leaf"] and t["status"] in RETRYABLE:
            if t["id"] in SENTINEL_IDS:
                continue
            return t
    sentinel = next((t for t in tasks if t["leaf"] and t["status"] == "QUEUED"
                     and t["id"] in SENTINEL_IDS), None)
    if sentinel is not None:
        return sentinel
    return None


def print_status(tasks):
    for t in tasks:
        prefix = "  " if t["level"] == 3 else ""
        mark = " [LEAF]" if t["leaf"] else " [GROUP]"
        line = f"{prefix}{t['id']:<14} {t['status']:<12} {t['title']}"
        if t.get("feedback") and t["status"] in ("FIX", "NEEDS_DESIGN", "DONE"):
            line += f"  | {t['feedback'][:60]}"
        print(line)


def main():
    global CONFIG
    CONFIG = load_config()

    parser = argparse.ArgumentParser(description="AI Dev Supervisor")
    parser.add_argument("--status", action="store_true", help="현재 큐 상태 출력")
    parser.add_argument("--task", type=str, default=None, help="특정 태스크 ID 강제 실행")
    parser.add_argument("--group", type=str, default=None,
                        help="그룹(##) ID 지정 시 해당 서브트리만 처리 - 병렬 레인용")
    parser.add_argument("--config", type=str, default=None, help="대체 config.json 경로")
    args = parser.parse_args()

    if args.config:
        with open(args.config, encoding="utf-8") as f:
            CONFIG = json.load(f)

    if args.group:
        global GROUP_ID
        GROUP_ID = args.group

    tasks, queue_path = parse_queue()

    if GROUP_ID:
        wt_map = cfg("worktrees") if "worktrees" in CONFIG else {}
        if GROUP_ID in wt_map:
            global WORKTREE_DIR
            WORKTREE_DIR = wt_map[GROUP_ID]
            log(f"레인 워크트리: {WORKTREE_DIR}")
        root = next((t for t in tasks if t["id"] == GROUP_ID), None)
        if root is None:
            print(f"그룹 {GROUP_ID} 없음")
            sys.exit(1)
        keep = {GROUP_ID}
        changed = True
        while changed:
            changed = False
            for t in tasks:
                parent = t.get("parent")
                pid = parent["id"] if isinstance(parent, dict) else None
                if pid in keep and t["id"] not in keep:
                    keep.add(t["id"])
                    changed = True
        tasks = [t for t in tasks if t["id"] in keep]

    if args.status:
        print_status(tasks)
        return

    if args.task:
        task = next((t for t in tasks if t["id"] == args.task and t["leaf"]), None)
        if task is None:
            print(f"태스크 {args.task} 없음")
            sys.exit(1)
    else:
        if not acquire_lock():
            return
        blocked = [t for t in tasks if t["status"] == "NEEDS_DESIGN"]
        if blocked:
            log(f"NEEDS_DESIGN 태스크 존재 ({blocked[0]['id']}) - 자동화 완전 정지, 사람 개입 대기")
            release_lock()
            return
        task = pick_next_task(tasks)
        if task is None:
            log("실행할 QUEUED 태스크 없음 - 종료")
            release_lock()
            return

    # orphan IMPLEMENT/REVIEW 복구: 상태만 남고 실행 감독자가 없으면 잔류 방지
    recover_orphan_implement(task, tasks, queue_path)

    log(f"=== 사이클 시작: {task['id']} ({task['title']}) ===")

    try:
        if task["id"] in SENTINEL_IDS:
            log(f"[{task['id']}] 종료 경계 도달 - 오늘 자동화 종료")
            update_queue(tasks, queue_path, task["id"], "DONE", feedback="오늘 계획 태스크 모두 처리됨. 자동화 종료.")
            return
        session_id = None
        summary = ""
        skip_review = bool(CONFIG.get("skip_review"))
        if skip_review and task["status"] in ("REVIEW", "REVIEW_PARSE_ERROR"):
            log(f"[{task['id']}] {task['status']} 상태 재개 - 리뷰 스킵 모드이므로 게이트로 바로 진행")
        elif task["status"] in ("REVIEW", "REVIEW_PARSE_ERROR"):
            log(f"[{task['id']}] {task['status']} 상태에서 재개 (구현 완료분 그대로 리뷰)")
        else:
            update_queue(tasks, queue_path, task["id"], "IMPLEMENT")
            log(f"[{task['id']}] IMPLEMENT 시작")
            session_id, summary, err, hstatus = run_implementer(task)
            if err:
                # --- harness/세션/인프라 실패 분류 ---
                cause = _harness_status_classify(task, hstatus)
                if hstatus == "timeout" or (not cause and err.startswith("실행 시간 초과")):
                    cause = "NO_PROGRESS_STALLED"
                if cause in ("ANALYSIS_ONLY", "TOOL_LOOP_STALLED", "AGENT_MAX_TURNS", "NO_PROGRESS_STALLED"):
                    h = handle_retryable_failure(task, cause, err, session_id=session_id)
                    log(f"[{task['id']}] 구현 {h['failure_type']} ({h['type_attempts']}/{RETRY_LIMITS.get(h['failure_type'], 3)} · 총 {h['attempts']}/{TASK_ATTEMPT_BUDGET})")
                    if h["terminal"]:
                        update_queue(tasks, queue_path, task["id"], h["terminal"],
                                     feedback=f"{h['failure_type']} 한도 초과 - 자동 중단, 독립 태스크 계속 진행")
                        write_result(task, h["terminal"],
                                     f"{h['failure_type']} 반복 (하네스 {hstatus}, 시도 {h['type_attempts']})")
                        return
                    if h["fresh_session"]:
                        session_id = None
                    update_queue(tasks, queue_path, task["id"], "FIX",
                                 feedback=f"{h['failure_type']} ({h['type_attempts']}/{RETRY_LIMITS.get(h['failure_type'], 3)}): {err[:150]}")
                    return
                # 인프라/기타 실행 오류 - NEEDS_DESIGN 아님, 재시도 가능 오류로 처리
                iftype = infra_failure_type(err) or "PROCESS_ERROR"
                h = handle_retryable_failure(task, iftype, err, session_id=session_id)
                log(f"[{task['id']}] 구현 실행 오류 분류: {h['failure_type']} ({h['type_attempts']}/{RETRY_LIMITS.get(h['failure_type'], 3)} · 총 {h['attempts']}/{TASK_ATTEMPT_BUDGET})")
                if h["terminal"]:
                    update_queue(tasks, queue_path, task["id"], h["terminal"],
                                 feedback=f"{h['failure_type']} 한도 초과 - 자동 중단, 독립 태스크 계속 진행")
                    write_result(task, h["terminal"], f"{h['failure_type']} 반복: {err[:200]}")
                    return
                if h["fresh_session"]:
                    session_id = None
                update_queue(tasks, queue_path, task["id"], "FIX",
                             feedback=f"구현 실행 오류 재시도: {err[:120]} - 다음 사이클 재시도")
                return
            clear_failure_state(task)
            log(f"[{task['id']}] 구현 완료 (session={session_id})")
            log(f"[{task['id']}] 구현 요약: {summary[:300]}")

        if skip_review:
            max_rounds = cfg("max_fix_rounds")
            for attempt in range(1, max_rounds + 1):
                log(f"[{task['id']}] 검증 게이트 {attempt}/{max_rounds} 실행")
                ok, problems = verification_gate(task)
                if ok:
                    fb = "auto-gate PASS (review=SKIPPED): 태스크 테스트/회귀/diff/임시파일/위험파일 검증 통과"
                    finalize_done(task, tasks, queue_path, fb)
                    return
                log(f"[{task['id']}] 게이트 실패: {'; '.join(p[:120] for p in problems[:4])}")
                if attempt < max_rounds:
                    feedback = "자동 검증 게이트 실패 - 아래 항목을 수정하세요:\n- " + "\n- ".join(problems[:10])
                    update_queue(tasks, queue_path, task["id"], "FIX",
                                 feedback=f"게이트 실패 ({attempt}/{max_rounds}): {'; '.join(p[:100] for p in problems[:4])}")
                    session_id, summary, err, hstatus = run_implementer(task, session_id=session_id,
                                                                        review_feedback=feedback)
                    if err:
                        cause = _harness_status_classify(task, hstatus)
                        if hstatus == "timeout" or (not cause and err.startswith("실행 시간 초과")):
                            cause = "NO_PROGRESS_STALLED"
                        if cause in ("ANALYSIS_ONLY", "TOOL_LOOP_STALLED", "AGENT_MAX_TURNS", "NO_PROGRESS_STALLED"):
                            h = handle_retryable_failure(task, cause, err, session_id=session_id)
                            log(f"[{task['id']}] 게이트 수정 {h['failure_type']} ({h['type_attempts']}/{RETRY_LIMITS.get(h['failure_type'], 3)} · 총 {h['attempts']}/{TASK_ATTEMPT_BUDGET})")
                            if h["terminal"]:
                                update_queue(tasks, queue_path, task["id"], h["terminal"],
                                             feedback=f"{h['failure_type']} 한도 초과 - 자동 중단, 독립 태스크 계속 진행")
                                write_result(task, h["terminal"], f"{h['failure_type']} 반복 (하네스 {hstatus})")
                                return
                            if h["fresh_session"]:
                                session_id = None
                            update_queue(tasks, queue_path, task["id"], "FIX",
                                         feedback=f"게이트 수정 {h['failure_type']} ({h['type_attempts']}/{RETRY_LIMITS.get(h['failure_type'], 3)}): {err[:150]}")
                            return
                        iftype = infra_failure_type(err) or "PROCESS_ERROR"
                        h = handle_retryable_failure(task, iftype, err, session_id=session_id)
                        log(f"[{task['id']}] 게이트 수정 실행 오류 분류: {h['failure_type']} ({h['type_attempts']}/{RETRY_LIMITS.get(h['failure_type'], 3)} · 총 {h['attempts']}/{TASK_ATTEMPT_BUDGET})")
                        if h["terminal"]:
                            update_queue(tasks, queue_path, task["id"], h["terminal"],
                                         feedback=f"{h['failure_type']} 한도 초과 - 자동 중단")
                            write_result(task, h["terminal"], f"{h['failure_type']} 반복: {err[:200]}")
                            return
                        if h["fresh_session"]:
                            session_id = None
                        update_queue(tasks, queue_path, task["id"], "FIX",
                                     feedback=f"게이트 수정 실행 오류 재시도: {err[:120]}")
                        return
                else:
                    cause = classify_no_diff(task)
                    vtype = classification_for_gate_problems(problems)
                    vtype = vtype if vtype else ("NO_CODE_DIFF" if "분류: " in (cause or "") and "no_code_diff" in cause.lower() else "TEST_FAILED")
                    h = handle_verification_failure(task, problems, "게이트 반복 실패: " + cause,
                                                    session_id=session_id)
                    log(f"[{task['id']}] 게이트 {max_rounds}회 실패 분류: {h['failure_type']} ({h['type_attempts']}/{RETRY_LIMITS.get(h['failure_type'], 3)} · 총 {h['attempts']}/{TASK_ATTEMPT_BUDGET})")
                    if h["terminal"]:
                        update_queue(tasks, queue_path, task["id"], h["terminal"],
                                     feedback=f"게이트 {h['failure_type']} 한도 초과 - 자동 중단, 독립 태스크 계속 진행")
                        write_result(task, h["terminal"], f"게이트 반복 {h['failure_type']}: {cause}")
                    else:
                        update_queue(tasks, queue_path, task["id"], "FIX",
                                     feedback=f"게이트 반복 실패 분류: {h['failure_type']} - 수정 재시도: "
                                              + "; ".join(p[:100] for p in problems[:4]))
                    return
            return

        verdict = None
        reason = ""
        for round_no in range(1, cfg("max_fix_rounds") + 1):
            update_queue(tasks, queue_path, task["id"], "REVIEW")
            log(f"[{task['id']}] REVIEW 라운드 {round_no}/{cfg('max_fix_rounds')} 시작")

            text, err = run_reviewer(task, summary)
            if err:
                if err == "알 수 없는 오류" or is_infra_error(err):
                    log(f"[{task['id']}] 리뷰어 무응답/infra 오류 - REVIEW 유지, 다음 사이클 재시도")
                    update_queue(tasks, queue_path, task["id"], "REVIEW",
                                 feedback=f"리뷰어 인프라 오류 재시도: {err[:120]}")
                    return
                log(f"[{task['id']}] 리뷰어 실행 오류: {err}")
                update_queue(tasks, queue_path, task["id"], "REVIEW",
                             feedback=f"리뷰어 실행 오류: {err[:300]}")
                return
            verdict, reason = extract_verdict(text)
            if not verdict:
                recovery_file = os.path.join(BASE_DIR, "runs", "recovery",
                                             f"review_output_{task['id']}.md")
                os.makedirs(os.path.dirname(recovery_file), exist_ok=True)
                with open(recovery_file, "w", encoding="utf-8") as f:
                    f.write(text or "(빈 출력)")
                log(f"[{task['id']}] 판정 파싱 실패 - 판정 복구 호출 시도")
                text2, err2 = run_reviewer(task, summary, recovery_file=recovery_file)
                if err2:
                    verdict, reason = None, ""
                else:
                    verdict, reason = extract_verdict(text2)
            if not verdict:
                n = bump_parse_attempts(task)
                if n >= 3:
                    log(f"[{task['id']}] 판정 파싱 3회 이상 실패 - 수동 개입 필요")
                    if maybe_design_resolve(task, tasks, queue_path, f"리뷰 판정 파싱 {n}회 실패"):
                        return
                    update_queue(tasks, queue_path, task["id"], "NEEDS_DESIGN",
                                 feedback=f"리뷰어가 판정 형식을 3회 이상 미준수 - 직접 확인 필요 (시도 {n}회)")
                    return
                log(f"[{task['id']}] 판정 파싱 실패 ({n}회) - REVIEW_PARSE_ERROR, 다음 사이클 재시도")
                update_queue(tasks, queue_path, task["id"], "REVIEW_PARSE_ERROR",
                             feedback=f"리뷰어 판정 파싱 실패 ({n}/3회) - 자동 재시도 대기")
                return
            reset_parse_attempts(task)
            log(f"[{task['id']}] 리뷰 판정: {verdict} | 사유: {reason[:300]}")

            if verdict == "LGTM":
                finalize_done(task, tasks, queue_path, reason or "LGTM")
                return

            if verdict == "NEEDS_DESIGN":
                if maybe_design_resolve(task, tasks, queue_path, f"리뷰(NEEDS_DESIGN): {reason}"):
                    return
                update_queue(tasks, queue_path, task["id"], "NEEDS_DESIGN", feedback=reason)
                write_result(task, verdict, reason)
                log(f"[{task['id']}] NEEDS_DESIGN - 자동화 정지, 사람 개입 대기")
                return

            if round_no < cfg("max_fix_rounds"):
                update_queue(tasks, queue_path, task["id"], "FIX", feedback=reason)
                log(f"[{task['id']}] FIX -> 재구현 (같은 세션 {session_id})")
                session_id, summary, err, hstatus = run_implementer(task, session_id=session_id, review_feedback=reason)
                if err:
                    cause = _harness_status_classify(task, hstatus)
                    if hstatus == "timeout" or (not cause and err.startswith("실행 시간 초과")):
                        cause = "NO_PROGRESS_STALLED"
                    if cause in ("ANALYSIS_ONLY", "TOOL_LOOP_STALLED", "AGENT_MAX_TURNS", "NO_PROGRESS_STALLED"):
                        h = handle_retryable_failure(task, cause, err, session_id=session_id)
                        log(f"[{task['id']}] 재구현 STALL: {h['failure_type']} ({h['type_attempts']}/{RETRY_LIMITS.get(h['failure_type'], 3)} · 총 {h['attempts']}/{TASK_ATTEMPT_BUDGET})")
                        if h["terminal"]:
                            update_queue(tasks, queue_path, task["id"], h["terminal"],
                                         feedback=f"{h['failure_type']} 한도 초과 - 자동 중단, 독립 태스크 계속 진행")
                            write_result(task, h["terminal"], f"{h['failure_type']} 반복 (하네스 {hstatus})")
                            return
                        if h["fresh_session"]:
                            session_id = None
                        update_queue(tasks, queue_path, task["id"], "FIX",
                                     feedback=f"재구현 {h['failure_type']} ({h['type_attempts']}/{RETRY_LIMITS.get(h['failure_type'], 3)}): {err[:150]}\n리뷰 피드백: {reason[:200]}")
                        return
                    iftype = infra_failure_type(err) or "PROCESS_ERROR"
                    h = handle_retryable_failure(task, iftype, err, session_id=session_id)
                    log(f"[{task['id']}] 재구현 실행 오류 분류: {h['failure_type']} ({h['type_attempts']}/{RETRY_LIMITS.get(h['failure_type'], 3)} · 총 {h['attempts']}/{TASK_ATTEMPT_BUDGET})")
                    if h["terminal"]:
                        update_queue(tasks, queue_path, task["id"], h["terminal"],
                                     feedback=f"{h['failure_type']} 한도 초과 - 자동 중단")
                        write_result(task, h["terminal"], f"{h['failure_type']} 반복: {err[:200]}")
                        return
                    if h["fresh_session"]:
                        session_id = None
                    update_queue(tasks, queue_path, task["id"], "FIX",
                                 feedback=f"재구현 실행 오류 재시도: {err[:120]}\n리뷰 피드백: {reason[:200]}")
                    return
                log(f"[{task['id']}] 재구현 완료: {summary[:200]}")
            else:
                # 리뷰어가 max_fix_rounds 회 거부 - 설계 결정이 아니라 반복 실패이므로 BLOCKED_AGENT
                h = handle_retryable_failure(task, "AGENT_MAX_TURNS", f"리뷰 FIX {cfg('max_fix_rounds')}회 초과: {reason}",
                                             session_id=session_id)
                log(f"[{task['id']}] FIX {cfg('max_fix_rounds')}회 초과 - 분류: {h['failure_type']} (총 {h['attempts']}/{TASK_ATTEMPT_BUDGET})")
                update_queue(tasks, queue_path, task["id"], "BLOCKED_AGENT",
                             feedback=f"리뷰 FIX {cfg('max_fix_rounds')}회 초과 - 자동 중단: {reason[:200]}")
                write_result(task, "BLOCKED_AGENT", f"리뷰 FIX {cfg('max_fix_rounds')}회 초과: {reason[:200]}")
                log(f"[{task['id']}] FIX {cfg('max_fix_rounds')}회 초과 - BLOCKED_AGENT")
                return

    finally:
        if not args.task:
            release_lock()
        log(f"=== 사이클 종료: {task['id']} ===")


if __name__ == "__main__":
    main()