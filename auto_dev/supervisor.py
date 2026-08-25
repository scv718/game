#!/usr/bin/env python3
"""AI Dev Supervisor - AI_TASK_QUEUE.md 기반 자동 구현/리뷰 사이클 (Windows)"""

import argparse
import datetime
import json
import os
import re
import subprocess
import sys
import time
import msvcrt

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_PATH = os.path.join(BASE_DIR, "config.json")
STATE_PATH = os.path.join(BASE_DIR, "state.json")
QUEUE_LOCK_PATH = os.path.join(BASE_DIR, ".queue_lock")
PROMPT_DIR = os.path.join(BASE_DIR, "prompts")
GROUP_ID = None  # --group 지정 시 해당 그룹 서브트리만 처리 (병렬 레인)
WORKTREE_DIR = None  # --group 에 매핑된 git worktree (에이전트 작업 디렉터리)
FALLBACK_STATE_PATH = os.path.join(BASE_DIR, "fallback_state.json")
QUOTA_RE = re.compile(r"insufficient|quota|balance|credit|usage limit|limit reached|exhausted|402|429",
                      re.IGNORECASE)

if sys.stdout:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if sys.stderr:
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

STATES = ("QUEUED", "IMPLEMENT", "REVIEW", "FIX", "DONE", "NEEDS_DESIGN", "REVIEW_PARSE_ERROR")
RETRYABLE = ("QUEUED", "IMPLEMENT", "REVIEW", "FIX", "REVIEW_PARSE_ERROR")
SENTINEL_IDS = ("OVERNIGHT-STOP",)
TASK_ID_RE = re.compile(r"^(TASK(?:-[A-Z0-9]+){1,5}|OVERNIGHT-STOP(?:-\d+)?)$")
STATUS_RE = re.compile(r"^-\s*상태\s*[:：]\s*(.+?)\s*$")
FEEDBACK_RE = re.compile(r"^-\s*피드백\s*[:：]\s*(.*?)\s*$")
HEADING_RE = re.compile(r"^(#{2,3})\s+(.+?)\s*$")
VERDICT_RE = re.compile(r"판정\s*[:：]\s*(?:\*\*|\*)?\s*(LGTM|FIX|NEEDS_DESIGN)", re.IGNORECASE)
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


def write_result(task, verdict, reason):
    """레인별 결과 보고 (auto_dev/runs/<GROUP>/RESULT.md) - Integration Agent 가 읽음."""
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


def run_opencode(prompt, model, extra_args=None, timeout_sec=1800):
    exe = cfg("opencode_exe")
    agent_dir = WORKTREE_DIR or cfg("project_dir")
    args = [exe, "run", prompt, "--model", model, "--auto", "--format", "json",
            "--dir", agent_dir]
    variant = cfg("variant") if "variant" in CONFIG else ""
    if variant:
        args += ["--variant", variant]
    args += extra_args or []
    env = os.environ.copy()
    env["PYTHONIOENCODING"] = "utf-8"
    env["OPENCODE_DISABLE_AUTOUPDATE"] = "1"
    log(f"opencode 실행: model={model} args={extra_args or []}")
    proc = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True, encoding="utf-8", errors="replace", env=env,
                            creationflags=subprocess.CREATE_NEW_PROCESS_GROUP)
    try:
        stdout, stderr = proc.communicate(timeout=timeout_sec)
    except subprocess.TimeoutExpired:
        log(f"TIMEOUT: {timeout_sec}초 초과 - 프로세스 트리 강제 종료 (pid={proc.pid})")
        os.system(f'taskkill /PID {proc.pid} /T /F >nul 2>&1')
        try:
            stdout, stderr = proc.communicate(timeout=30)
        except subprocess.TimeoutExpired:
            stdout, stderr = "", ""
        return None, "", f"실행 시간 초과 ({timeout_sec}초)"
    if proc.returncode != 0:
        err_msg = extract_error_event(stdout) or stderr[-2000:] or "알 수 없는 오류"
        log(f"opencode 실패 (exit={proc.returncode}): {err_msg[:200]}")
        return None, "", err_msg
    return parse_run_output(stdout)


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
    """free 모델의 간헐적 빈 응답/exit=1 무응답(프로바이더 불안정) 방어 - 백오프 재시도."""
    sid, text, err = None, "", None
    for i in range(1, attempts + 1):
        sid, text, err = run_opencode(prompt, model, extra, timeout_sec)
        if not err and (text or "").strip():
            return sid, text, err
        if err and "실행 시간 초과" in (err or ""):
            return sid, text, err
        if i < attempts:
            wait = 120 * i
            log(f"[{task_id}] 실패({(err or '빈 응답')[:60]}) ({i}/{attempts}) - {wait}초 후 재시도")
            time.sleep(wait)
    return sid, text, err


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
    prompt = load_prompt("implementer.md")
    prompt += "\n\n" + format_task_context(task)
    if review_feedback:
        prompt += f"\n\n[리뷰어 피드백 - 반드시 반영하고 수정하세요]\n{review_feedback}"
    queue_path = os.path.join(cfg("project_dir"), cfg("queue_file"))
    extra = ["--file", build_task_file(task, queue_path)]
    if session_id:
        extra += ["--session", session_id]
    sid, text, err = run_opencode_retry(prompt, cfg("implementer_model"), extra,
                                        cfg("implementer_timeout_sec"), task_id=task["id"])
    summary = extract_summary(text)
    if not summary:
        summary = (text or "").strip()[-800:]
    return sid, summary, err


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
    _, text, err = run_opencode_retry(prompt, reviewer_model(), extra,
                                      cfg("reviewer_timeout_sec"), task_id=task["id"])
    if err and QUOTA_RE.search(err or ""):
        mark_reviewer_fallback(err)
        _, text, err = run_opencode_retry(prompt, reviewer_model(), extra,
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


def reset_parse_attempts(task):
    p = parse_attempts_path(task)
    if os.path.exists(p):
        os.remove(p)


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

    log(f"=== 사이클 시작: {task['id']} ({task['title']}) ===")

    try:
        if task["id"] in SENTINEL_IDS:
            log(f"[{task['id']}] 종료 경계 도달 - 오늘 자동화 종료")
            update_queue(tasks, queue_path, task["id"], "DONE", feedback="오늘 계획 태스크 모두 처리됨. 자동화 종료.")
            return
        session_id = None
        summary = ""
        if task["status"] in ("REVIEW", "REVIEW_PARSE_ERROR"):
            log(f"[{task['id']}] {task['status']} 상태에서 재개 (구현 완료분 그대로 리뷰)")
        else:
            update_queue(tasks, queue_path, task["id"], "IMPLEMENT")
            log(f"[{task['id']}] IMPLEMENT 시작")
            session_id, summary, err = run_implementer(task)
            if err:
                if err.startswith("실행 시간 초과"):
                    log(f"[{task['id']}] 구현 시간 초과 - 상태 유지, 다음 사이클에서 재시도")
                    update_queue(tasks, queue_path, task["id"], "IMPLEMENT",
                                 feedback=f"이전 시도 시간 초과: {err}")
                else:
                    log(f"[{task['id']}] 구현 실패: {err}")
                    if err == "알 수 없는 오류":
                        update_queue(tasks, queue_path, task["id"], "IMPLEMENT",
                                     feedback=f"구현자 프로바이더 무응답: {err} - 다음 사이클 재시도")
                    else:
                        update_queue(tasks, queue_path, task["id"], "NEEDS_DESIGN",
                                     feedback=f"구현 실행 오류: {err[:300]}")
                return
            log(f"[{task['id']}] 구현 완료 (session={session_id})")
            log(f"[{task['id']}] 구현 요약: {summary[:300]}")

        verdict = None
        reason = ""
        for round_no in range(1, cfg("max_fix_rounds") + 1):
            update_queue(tasks, queue_path, task["id"], "REVIEW")
            log(f"[{task['id']}] REVIEW 라운드 {round_no}/{cfg('max_fix_rounds')} 시작")

            text, err = run_reviewer(task, summary)
            if err:
                if err == "알 수 없는 오류":
                    log(f"[{task['id']}] 리뷰어 무응답(provider) - REVIEW 유지, 다음 사이클 재시도")
                    update_queue(tasks, queue_path, task["id"], "REVIEW",
                                 feedback=f"리뷰어 프로바이더 무응답: {err}")
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
                update_queue(tasks, queue_path, task["id"], "DONE", feedback=reason)
                write_result(task, verdict, reason)
                log(f"[{task['id']}] DONE")
                return

            if verdict == "NEEDS_DESIGN":
                update_queue(tasks, queue_path, task["id"], "NEEDS_DESIGN", feedback=reason)
                write_result(task, verdict, reason)
                log(f"[{task['id']}] NEEDS_DESIGN - 자동화 정지, 사람 개입 대기")
                return

            if round_no < cfg("max_fix_rounds"):
                update_queue(tasks, queue_path, task["id"], "FIX", feedback=reason)
                log(f"[{task['id']}] FIX -> 재구현 (같은 세션 {session_id})")
                session_id, summary, err = run_implementer(task, session_id=session_id, review_feedback=reason)
                if err:
                    if err.startswith("실행 시간 초과"):
                        log(f"[{task['id']}] 재구현 시간 초과 - FIX 상태 유지, 다음 사이클에서 재시도")
                        update_queue(tasks, queue_path, task["id"], "FIX",
                                     feedback=f"재구현 시간 초과: {err}\n리뷰 피드백: {reason[:300]}")
                    else:
                        log(f"[{task['id']}] 재구현 실패: {err}")
                        if err == "알 수 없는 오류":
                            update_queue(tasks, queue_path, task["id"], "FIX",
                                         feedback=f"재구현 프로바이더 무응답: {err} - 다음 사이클 재시도")
                        else:
                            update_queue(tasks, queue_path, task["id"], "NEEDS_DESIGN",
                                         feedback=f"재구현 실행 오류: {err[:300]}")
                    return
                log(f"[{task['id']}] 재구현 완료: {summary[:200]}")
            else:
                update_queue(tasks, queue_path, task["id"], "NEEDS_DESIGN",
                             feedback=f"FIX {cfg('max_fix_rounds')}회 초과 - 자동화 정지: {reason[:300]}")
                log(f"[{task['id']}] FIX {cfg('max_fix_rounds')}회 초과 - NEEDS_DESIGN")
                return

    finally:
        if not args.task:
            release_lock()
        log(f"=== 사이클 종료: {task['id']} ===")


if __name__ == "__main__":
    main()