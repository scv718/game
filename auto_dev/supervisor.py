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

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_PATH = os.path.join(BASE_DIR, "config.json")
STATE_PATH = os.path.join(BASE_DIR, "state.json")
PROMPT_DIR = os.path.join(BASE_DIR, "prompts")

if sys.stdout:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if sys.stderr:
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

STATES = ("QUEUED", "IMPLEMENT", "REVIEW", "FIX", "DONE", "NEEDS_DESIGN")
SENTINEL_IDS = ("OVERNIGHT-STOP",)
TASK_ID_RE = re.compile(r"^(TASK(?:-[A-Z0-9]+){1,3}|OVERNIGHT-STOP(?:-\d+)?)$")
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
    return os.path.join(BASE_DIR, cfg("log_dir"), datetime.datetime.now().strftime("%Y%m%d") + ".log")


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
    if os.path.exists(STATE_PATH):
        with open(STATE_PATH, encoding="utf-8") as f:
            state = json.load(f)
    if state.get("running") and pid_alive(state.get("pid")):
        log(f"이전 실행(pid={state.get('pid')})이 아직 진행 중 - 이번 사이클 건너뜀")
        return False
    state["running"] = True
    state["pid"] = os.getpid()
    state["started"] = datetime.datetime.now().isoformat()
    with open(STATE_PATH, "w", encoding="utf-8") as f:
        json.dump(state, f, ensure_ascii=False, indent=2)
    return True


def release_lock():
    state = {"running": False, "pid": None, "ended": datetime.datetime.now().isoformat()}
    with open(STATE_PATH, "w", encoding="utf-8") as f:
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
    """지정 태스크의 상태/피드백 줄을 파일에서 직접 갱신 (사람 편집 보존)."""
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


def run_opencode(prompt, model, extra_args=None, timeout_sec=1800):
    exe = cfg("opencode_exe")
    args = [exe, "run", prompt, "--model", model, "--auto", "--format", "json",
            "--variant", "max",
            "--dir", cfg("project_dir")]
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
        log(f"opencode 실패 (exit={proc.returncode}): {stderr[-2000:]}")
        return None, "", stderr[-2000:] or "알 수 없는 오류"
    return parse_run_output(stdout)


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
    """free 모델의 간헐적 빈 응답(프로바이더 무응답) 방어 - 백오프 재시도."""
    sid, text, err = None, "", None
    for i in range(1, attempts + 1):
        sid, text, err = run_opencode(prompt, model, extra, timeout_sec)
        if err or (text or "").strip():
            return sid, text, err
        if i < attempts:
            wait = 20 * i
            log(f"[{task_id}] 빈 응답 ({i}/{attempts}) - {wait}초 후 재시도")
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


def run_reviewer(task, summary):
    prompt = load_prompt("reviewer.md")
    prompt += "\n\n" + format_task_context(task)
    prompt += f"\n\n[구현 결과 요약]\n{summary or '(요약 없음 - 직접 코드를 확인하세요)'}"
    queue_path = os.path.join(cfg("project_dir"), cfg("queue_file"))
    extra = ["--file", build_task_file(task, queue_path)]
    _, text, err = run_opencode_retry(prompt, cfg("reviewer_model"), extra,
                                      cfg("reviewer_timeout_sec"), task_id=task["id"])
    if err:
        return None, err
    return extract_verdict(text)


def pick_next_task(tasks):
    for t in tasks:
        if t["leaf"] and t["status"] in ("QUEUED", "IMPLEMENT", "REVIEW", "FIX"):
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
    parser.add_argument("--config", type=str, default=None, help="대체 config.json 경로")
    args = parser.parse_args()

    if args.config:
        with open(args.config, encoding="utf-8") as f:
            CONFIG = json.load(f)

    tasks, queue_path = parse_queue()

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
        if task["status"] == "REVIEW":
            log(f"[{task['id']}] REVIEW 상태에서 재개 (구현 완료분 그대로 리뷰)")
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

            verdict, reason = run_reviewer(task, summary)
            if not verdict:
                log(f"[{task['id']}] 판정 파싱 실패 (리뷰어 출력에 판정 없음) - 1회 재시도")
                verdict, reason = run_reviewer(task, summary)
            if not verdict:
                log(f"[{task['id']}] 판정 파싱 실패 재시도 후에도 실패 - 수동 개입 필요")
                update_queue(tasks, queue_path, task["id"], "NEEDS_DESIGN",
                             feedback="리뷰어가 판정 형식을 지키지 않음 - 직접 확인 필요")
                return
            log(f"[{task['id']}] 리뷰 판정: {verdict} | 사유: {reason[:300]}")

            if verdict == "LGTM":
                update_queue(tasks, queue_path, task["id"], "DONE", feedback=reason)
                log(f"[{task['id']}] DONE")
                return

            if verdict == "NEEDS_DESIGN":
                update_queue(tasks, queue_path, task["id"], "NEEDS_DESIGN", feedback=reason)
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