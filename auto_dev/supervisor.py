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
import tempfile
import time
import msvcrt

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_PATH = os.path.join(BASE_DIR, "config.json")
STATE_PATH = os.path.join(BASE_DIR, "state.json")
QUEUE_LOCK_PATH = os.path.join(BASE_DIR, ".queue_lock")
PROMPT_DIR = os.path.join(BASE_DIR, "prompts")
GROUP_ID = None  # --group 지정 시 해당 그룹 서브트리만 처리 (병렬 레인)
WORKTREE_DIR = None  # --group 에 매핑된 git worktree (에이전트 작업 디렉터리)
CONFIG = {}  # config.json 내용 (main() 에서 로드; 테스트에서 직접 주입 가능)
# commit-gate: implementer attempt 단위 artifact(attempt_delta) 판정 + source provenance 스냅샷
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

STATES = ("QUEUED", "IMPLEMENT", "REVIEW", "FIX", "DONE", "NEEDS_DESIGN", "REVIEW_PARSE_ERROR")
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
    """runtime 상태 전이. AI_TASK_QUEUE.md(spec) 는 절대 수정하지 않는다.

    V2 계약: runtime status 의 단일 source of truth 는 state_v2.json.
    큐 파일은 사람이 작성한 계획(spec)으로 read-only 유지 → canonical main clean 유지.
    상태 변경은 state_v2 에 기록하고 로그로 노출한다."""
    _v2_mark(task_id, status, feedback=feedback)


GATE_TEMP_RE = re.compile(r"^(_probe|_debug|_diag|tmp_|temp_|test_tmp)", re.IGNORECASE)
DANGER_RE = re.compile(r"^(auto_dev/(?!INTEGRATION_NOTE|runs/)|\.git|credential|.*\.key$|\.gitattributes$)", re.IGNORECASE)


def _run_cmd(cmd, cwd=None, timeout=900):
    try:
        r = subprocess.run(cmd, cwd=cwd, capture_output=True, encoding="utf-8",
                           errors="replace", timeout=timeout)
        return r.returncode, (r.stdout or ""), (r.stderr or "")
    except Exception as e:
        return -1, "", str(e)


def find_task_test_file(task, root):
    """태스크 ID에서 관례상 테스트 파일 추정 (task3dint0012_test.gd 등)."""
    tid = task["id"].replace("-", "").lower()
    candidates = glob.glob(os.path.join(root, "tests", f"*{tid}*_test.gd"))
    if not candidates:
        return None
    return max(candidates, key=os.path.getmtime)


def required_test_path(task):
    """Supervisor가 직접 계산한 필수 테스트 파일 경로 (LLM 추론 불필요)."""
    return os.path.join("tests", f"{task['id'].replace('-', '').lower()}_test.gd")


_IMPL_FAILURE_MARKERS = (
    "NO_CODE_DIFF",
    "MISSING_REQUIRED_TEST",
    "태스크 테스트 FAIL",
    "회귀(baseline 3D) FAIL",
)

_INFRA_FAILURE_MARKERS = (
    "TIMEOUT",
    "시간 초과",
    "godot_exe",
    "git",
    "bootstrap",
    "import",
    "infra",
    "provider",
    "model",
    "tool",
    "Command '",
    "exit code",
    "Process failed",
)

DESIGN_KEYWORDS = (
    "design ambiguity",
    "설계 모호",
    "설계 갈등",
    "NEEDS_DESIGN",
)


def classify_gate_failure(problems, max_rounds):
    """검증 게이트 반복 실패 원인 분류.

    목표: NEEDS_DESIGN은 오직 실제 game-design ambiguity일 때만 사용한다.
    자동화가 작업을 완료하지 못한 경우는 NeedsDesign으로 승격하지 않는다.

    분류 체계:
    - ImplementationFailure: 구현자가 코드/필수 테스트를 만들지 않음 등 deterministic 구현 실패.
    - InfraFailure: timeout, Godot/git/bootstrap 오류, provider/model/tool 장애 등 인프라 문제.
    - NeedsDesign: 명시적 design ambiguity가 확인된 경우에만.
    - NonDesignFailure: 분류 불가능한 unknown gate failure (기본값, NeedsDesign 아님).
    """
    text_blob = " ".join(problems).lower()

    if any(m in text_blob for m in _IMPL_FAILURE_MARKERS):
        return "ImplementationFailure"

    if any(m.lower() in text_blob for m in _INFRA_FAILURE_MARKERS):
        return "InfraFailure"

    if any(kw.lower() in text_blob for kw in DESIGN_KEYWORDS):
        return "NeedsDesign"

    return "NonDesignFailure"


def run_headless_test(godot_exe, root, script_path, timeout=900):
    rc, out, err = _run_cmd([godot_exe, "--headless", "--path", root,
                             "--script", script_path], timeout=timeout)
    text = out or ""
    if "RESULT=FAIL" in text:
        return False, text[-600:]
    if "RESULT=PASS" not in text:
        return False, ("PASS 마커 없음 (실행 실패 추정)\n" + (text or err)[-500:])
    return True, ""


# ---------------------------------------------------------------------------
# COMMIT GATE: 성공 TASK(review=SKIPPED 게이트 PASS / LGTM) 는 반드시
# 검증된 Git source commit 을 보유한 후에만 DONE 이 되어야 한다.
# invariant: status==DONE -> source_commit(basis) exists
# ---------------------------------------------------------------------------
_COMMIT_SKIP_PARTS = ("/auto_dev/", "/.git/", "/.godot/", "/.import/", "/logs/", "/.venv/", "/cache/")
_COMMIT_SKIP_EXT = (".md", ".tmp", ".log", ".import", ".bak", ".old", ".orig", ".mp4", ".png", ".jpg")


def _file_hash(path):
    try:
        with open(path, "rb") as f:
            return hashlib.md5(f.read()).hexdigest()
    except OSError:
        return None


def _iter_worktree_files(root):
    if not root or not os.path.isdir(root):
        return
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in (".git", ".godot")]
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


def attempt_delta(root):
    """마지막 baseline 대비 이번 attempt 에서 실제 새로 생성/수정된 파일 목록 (rel path).
    content-hash 차이 기반이므로 기존 파일 내용 수정도 감지한다.
    baseline 이 없으면(REVIEW 재개 등) 전체 worktree dirty(changed_paths) 로 폴백."""
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
    """implementer 시도 시작 직전 baseline 스냅샷 + attempt 시작 HEAD 저장."""
    global _WORKTREE_BASELINE, _ATTEMPT_START_HEAD
    _WORKTREE_BASELINE = snapshot_worktree(root)
    try:
        _, head, _ = _run_cmd(["git", "-C", root, "rev-parse", "HEAD"], timeout=30)
        _ATTEMPT_START_HEAD = (head or "").strip() or None
    except Exception:
        _ATTEMPT_START_HEAD = None


def capture_attempt_delta(root):
    """시도 종료 후 _LAST_ATTEMPT_DELTA 갱신. baseline 은 유지."""
    global _LAST_ATTEMPT_DELTA
    _LAST_ATTEMPT_DELTA = attempt_delta(root)
    return _LAST_ATTEMPT_DELTA


def _git_rev_parse(root, ref="HEAD"):
    rc, out, _ = _run_cmd(["git", "-C", root, "rev-parse", ref], timeout=30)
    return (out or "").strip() or None


def _rel(root, p):
    return os.path.relpath(p, root).replace("\\", "/")


_WT_ALREADY_REGISTERED = re.compile(r".*worktree.*(already.*exist|exists)", re.IGNORECASE)


def _ensure_group_worktree(main, wt):
    """COMMIT-GATE WORKTREE INVARIANT: a new task's worktree must be a descendant
    of (or equal to) the current canonical main HEAD.

    Allowed:
    - missing wt            -> create it at the current canonical main HEAD
                              (git worktree add -b <branch> <wt> <main_head>).
    - exists && wt HEAD == main HEAD            -> reuse (fresh).
    - exists && main HEAD is ancestor of wt HEAD
             && worktree branch == expected group branch
                                                 -> reuse (legitimate accumulated
                                                    commits on this group's branch).
    Refused (old/stale/diverged; preserved but never run on):
    - exists && main HEAD is NOT an ancestor of wt HEAD.
    Returns the expected worktree HEAD on success; exits non-zero on refusal."""
    head = _git_rev_parse(main, "HEAD")
    if not head:
        log(f"[WT-ERR] canonical main HEAD 조회 실패 ({main}) - 워크트리 확보 중단")
        sys.exit(1)
    branch = "ai/" + os.path.basename(os.path.normpath(wt))
    if not os.path.isdir(wt) or not os.path.exists(os.path.join(wt, ".git")):
        rc, out, err = _run_cmd(["git", "-C", main, "worktree", "add", "-b", branch, wt, head], timeout=120)
        if rc != 0:
            if _WT_ALREADY_REGISTERED.match(err or "") or _WT_ALREADY_REGISTERED.match(out or ""):
                pass
            else:
                rc2, out2, err2 = _run_cmd(["git", "-C", main, "worktree", "add", "--detach", wt, head], timeout=120)
                if rc2 != 0:
                    log(f"[WT-ERR] 워크트리 생성 실패 {wt}: {err} / {err2}")
                    sys.exit(1)
        actual = _git_rev_parse(wt, "HEAD")
        if actual != head:
            log(f"[WT-ERR] 생성된 워크트리 HEAD 불일치: {actual} != {head}")
            sys.exit(1)
        log(f"[WT] 신규 워크트리 생성: {wt} @ {head} (branch={branch})")
        return head
    actual = _git_rev_parse(wt, "HEAD")
    if actual == head:
        log(f"[WT] 워크트리 재사용(HEAD 일치): {wt} @ {head}")
        return head
    # wt HEAD != main HEAD. 허용하려면 main HEAD가 wt HEAD의 ancestor여야 하고,
    # 해당 worktree가 이 그룹의 expected branch여야 한다(동일 그룹 branch에
    # TASK commit이 정상 누적된 legitimate descendant).
    actual_branch = (_run_cmd(["git", "-C", wt, "branch", "--show-current"], timeout=30)[1] or "").strip()
    if actual_branch == branch:
        rc, _, _ = _run_cmd(["git", "-C", main, "merge-base", "--is-ancestor", head, actual], timeout=30)
        if rc == 0:
            log(f"[WT] 워크트리 재사용(descendant, 동일 그룹 branch {branch}): {wt} @ {actual}")
            return head
    log(f"[WT-ERR] 기존 워크트리가 STALE: {wt} HEAD={actual}, canonical main HEAD={head} "
        f"(branch={actual_branch}, expected={branch}). 재사용 금지(보존은 유지). "
        f"old/stale/diverged 워크트리에 작업 실행 중단.")
    sys.exit(1)


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
    """전체 worktree stage 금지 - 명시 경로만 stage (untracked 신규 포함)."""
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
    """DONE 이전 commit gate. 성공 TASK invariant 강제.
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

        # whole-worktree stage 금지 - 명시 경로만 stage (untracked 신규 포함).
        # 이미 committed 인 target 은 제외하고, 여전히 uncommitted 인 target 만 specific stage 한다.
        to_stage = {t for t in targets if _is_uncommitted(root, t)}
        if not to_stage:
            return False, None, None, "commit 대상 없음 - 남은 uncommitted 대상 없음"
        ok, serr = _stage_specific(root, sorted(to_stage))
        if not ok:
            return False, None, None, f"stage 실패: {serr.strip()[:200]}"

        # stage 검증: 대상이 전부 staged 되고 unrelated 는 섞이지 않았는지
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

    계약(중요): 향후 integration 단계에서는 source_commit 단일 hash 만을 cherry-pick 해서
    TASK 전체 integration 으로 간주하면 안 된다. agent 가 하나 이상의 partial commit 을
    만들 수 있으므로, TASK 의 정확한 provenance 는 (source_base_commit, source_commit] 범위,
    즉 `source_base_commit..source_commit` 범위 전체의 commit 들을 모두 포함해야 한다.
    """
    if not commit:
        return
    runs_dir = os.path.join(BASE_DIR, "runs", GROUP_ID) if GROUP_ID else os.path.join(BASE_DIR, "runs", "_default")
    os.makedirs(runs_dir, exist_ok=True)
    p = os.path.join(runs_dir, f"result_{task['id']}.json")
    rng = f"{base}..{commit}" if (base and base != commit) else (commit or "")
    data = {
        "task": task["id"],
        "status": "WAIT_INTEGRATION",
        "source_base_commit": base,
        "source_commit": commit,
        "source_provenance_range": rng,
        "source_branch": (WORKTREE_DIR or cfg("project_dir")),
        "source_commit_created_at": datetime.datetime.now().isoformat(),
        "integrator_contract": (
            "TASK 전체 integration 은 source_base_commit..source_commit 범위 전체의 commit 들을 "
            "모두 포함해야 한다. source_commit 단일 cherry-pick 으로 TASK 전체를 integration "
            "했다고 간주하지 말 것 (partial agent commit 이 존재할 수 있다). "
            "DONE 은 Integration Coordinator 가 INTEGRATED + REGRESSION_PASS 확인 후에만 기록한다."
        ),
        "note": reason,
    }
    try:
        with open(p, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
    except OSError:
        pass


def _v2_state_path():
    """Harness V2 persistent state 경로 (supervisor/auto_lane 공용). gitignore 대상(자동 커밋 금지)."""
    return os.path.join(BASE_DIR, "state_v2.json")


def _v2_store():
    """V2 TaskState 저장소 로드 (없으면 빈 스토어 자동 생성)."""
    try:
        from harness_v2.core import V2StateStore
    except Exception as e:
        log(f"[V2] harness_v2.core 로드 불가 - DONE 보류: {e}")
        return None
    return V2StateStore(_v2_state_path())


# ── AI_TASK_QUEUE.md spec-only 정책 ──────────────────────────────────────
# production runtime 동안 canonical main 의 AI_TASK_QUEUE.md 는 read-only spec 이다.
# runtime status(IMPLEMENT/FIX/REVIEW/WAIT_INTEGRATION/DONE/...) 는 절대 이 파일에
# 쓰지 않고 state_v2.json 을 단일 source of truth 로 사용한다. 큐 파일의 QUEUED/DONE
# 등은 state_v2 에 task record 가 없을 때의 bootstrap/spec 값으로만 사용한다.
_V1_TO_V2 = {
    "QUEUED": "IMPLEMENT",                     # 설계 해결 재큐 -> retryable attempt
    "IMPLEMENT": "IMPLEMENT",
    "REVIEW": "IMPLEMENT",
    "REVIEW_PARSE_ERROR": "IMPLEMENT",
    "FIX": "IMPLEMENT",
    "NEEDS_DESIGN": "CANONICAL_REVIEW_REQUIRED",
    "WAIT_INTEGRATION": "WAIT_INTEGRATION",
    "DONE": "DONE",
}
V2_RUNTIME = {
    "WORKTREE_CREATED": "QUEUED",
    "ENV_BOOTSTRAPPED": "QUEUED",
    "BASELINE_HEALTHY": "IMPLEMENT",
    "IMPLEMENT": "IMPLEMENT",
    "SOURCE_VALIDATED": "IMPLEMENT",
    "SOURCE_COMMITTED": "IMPLEMENT",
    "WAIT_INTEGRATION": "WAIT_INTEGRATION",
    "INTEGRATING": "WAIT_INTEGRATION",
    "INTEGRATED": "WAIT_INTEGRATION",
    "REGRESSION_PASS": "WAIT_INTEGRATION",
    "DONE": "DONE",
    "INTEGRATION_CONFLICT": "NEEDS_DESIGN",
    "CANONICAL_REVIEW_REQUIRED": "NEEDS_DESIGN",
}


def _v2_mark(task_id, status, feedback=None):
    """runtime status 결정을 state_v2 에만 기록 (큐 파일 미수정). 비차단."""
    store = _v2_store()
    if store is None:
        return
    try:
        from harness_v2.core import Lifecycle, LifecycleController, TaskState
        v2 = store.get_task(task_id)
        if v2 is None:
            v2 = TaskState(task_id)
        target = _V1_TO_V2.get(status)
        fields = {}
        if feedback:
            fields["last_error"] = str(feedback)[:400]
        if status == "FIX":
            fields.setdefault("failure_class", "GATE_FAILED")
        if target == Lifecycle.CANONICAL_REVIEW_REQUIRED.value:
            fields.setdefault("failure_class", "NEEDS_DESIGN")
        if target:
            LifecycleController(store).record(
                v2, Lifecycle(target) if target in Lifecycle.__members__ else target, **fields)
        else:
            store.put_task(v2)
        log(f"[V2][{task_id}] runtime status {status} -> {target or '(keep)'} (state_v2)")
    except Exception as e:
        log(f"[V2][{task_id}] 상태 기록 실패(비차단): {str(e)[:120]}")


def runtime_status(task_spec):
    """runtime 판정용 status. state_v2 record 우선, 없으면 큐 spec(bootstrap) 사용."""
    store = _v2_store()
    if store is None:
        return task_spec["status"]
    v2 = store.get_task(task_spec["id"])
    if v2 is None:
        return task_spec["status"]
    return V2_RUNTIME.get(v2.status, task_spec["status"])


def finalize_done(task, tasks, queue_path, reason):
    """DONE 전 commit gate. 성공 TASK 는 반드시 source commit 보유.

    V2 계약: 여기서는 절대 DONE 을 기록하지 않는다.
    SOURCE_VALIDATED -> SOURCE_COMMITTED -> WAIT_INTEGRATION 까지만 소유하고,
    INTEGRATED/REGRESSION_PASS -> DONE 전이는 Integration Coordinator 가 수행한다.
    반환: source 단계 완료(WAIT_INTEGRATION 기록)했으면 True, commit 실패로 보류했으면 False."""
    root = WORKTREE_DIR or cfg("project_dir")
    ok, base, commit, creason = ensure_source_commit(task, root)
    if ok and commit:
        if not base:
            base = _git_rev_parse(root, commit + "^") or commit
        _record_source_commit(task, base, commit, creason)

        store = _v2_store()
        if store is None:
            update_queue(tasks, queue_path, task["id"], "FIX",
                         feedback="V2 상태 스토어 초기화 실패 - DONE 보류")
            return False
        try:
            from harness_v2.core import Lifecycle, LifecycleController
            tid = task["id"]
            v2 = store.get_task(tid)
            if v2 is None:
                from harness_v2.core import TaskState
                dep_ids = [d.strip().upper() for d in str(task.get("depends_on") or "").split(",") if d.strip()]
                v2 = TaskState(tid, depends_on=dep_ids,
                               source_branch=(WORKTREE_DIR or cfg("project_dir")))
            ctl = LifecycleController(store)
            ctl.source_validated(v2)
            v2.source_commit = commit
            v2.source_validation_result = "PASS"
            ctl.record(v2, Lifecycle.SOURCE_COMMITTED, source_commit=commit)
            ctl.wait_integration(v2)
            store.put_task(v2)
        except Exception as e:
            update_queue(tasks, queue_path, task["id"], "FIX",
                         feedback=f"V2 상태 기록 실패 - DONE 보류: {str(e)[:150]}")
            return False

        fb = (reason or "") + f" | source_base={base[:12]}..source={commit[:12]} | WAIT_INTEGRATION"
        update_queue(tasks, queue_path, task["id"], "WAIT_INTEGRATION", feedback=fb)
        write_result(task, "WAIT_INTEGRATION",
                     fb + f"\n- source_base_commit: {base}\n- source_commit: {commit}\n- source_provenance_range: {base}..{commit}\n- worktree: {root}")
        log(f"[{task['id']}] SOURCE_COMMITTED -> WAIT_INTEGRATION (provenance {base[:12]}..{commit[:12]})")
        return True
    # commit 실패 → DONE 금지. implementation/test PASS 상태는 로그에 보존하고 non-success 로 남김.
    update_queue(tasks, queue_path, task["id"], "FIX",
                 feedback=f"PASS 후 source commit 생성 실패 (COMMIT_FAILED) - 변경 보존, 재시도 필요: {creason[:150]}")
    write_result(task, "COMMIT_FAILED",
                 f"implementation/test PASS 유지, provenance 생성 실패: {creason}\n- 작업 파일은 보존됨(삭제 안 함)")
    log(f"[{task['id']}] DONE 보류: COMMIT_FAILED - {creason}")
    return False


def verification_gate(task):
    """LLM 리뷰 대체 결정적 게이트. 반환: (통과 여부, 문제 목록)."""
    root = WORKTREE_DIR or cfg("project_dir")
    ver = CONFIG.get("verification", {})
    problems = []

    rc, st, _ = _run_cmd(["git", "-C", root, "status", "--porcelain"], timeout=60)
    lines = [l for l in (st or "").splitlines() if l.strip()]
    if not lines:
        return False, ["NO_CODE_DIFF: 변경된 파일이 없음 - 구현 자체가 이루어지지 않았을 가능성"]

    # 위험 파일 변경 → FAIL (자동 되돌림 없이 사람 확인 대상으로)
    for l in lines:
        path = l[3:].strip().strip('"').replace("\\", "/")
        if DANGER_RE.match(path):
            problems.append(f"위험 파일 변경(FAIL): {path}")

    # 임시/debug 파일 (신규 생성된 것)
    for l in lines:
        if l.startswith("??"):
            name = os.path.basename(l[3:].strip().strip('"'))
            if GATE_TEMP_RE.match(name):
                problems.append(f"임시/debug 파일 잔존: {name}")

    # 테스트 삭제 / SUSPICIOUS_TEST_CHANGE
    if ver.get("suspicious_test_change", True):
        for l in lines:
            x, y, path = l[0], l[1], l[3:].strip().strip('"').replace("\\", "/")
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

    # 태스크 자체 테스트 (cheap fail-first: required test 없으면 즉시 FAIL, regression 미실행)
    if ver.get("task_test", True):
        required = required_test_path(task)
        tf = find_task_test_file(task, root)
        godot = CONFIG.get("godot_exe")
        if not godot:
            problems.append("config에 godot_exe 미설정 - 게이트 테스트 불가")
        elif tf is None:
            problems.append(f"MISSING_REQUIRED_TEST: 필수 테스트 존재 안 함 {required}")
            # NO REQUIRED TEST: expensive baseline 회귀를 실행하지 않고 즉시 실패한다.
            return False, problems
        else:
            ok, tailtxt = run_headless_test(godot, root, tf)
            if not ok:
                problems.append(f"태스크 테스트 FAIL: {os.path.basename(tf)}\n{tailtxt}")

    # 회귀(baseline): canonical 3D health test. legacy smoke_test.gd 는 자동 regression gate 에서 제외.
    if ver.get("regression", True):
        baseline = os.path.join(root, "tests", "baseline_3d_health_test.gd")
        godot = CONFIG.get("godot_exe")
        base_timeout = int(ver.get("regression_timeout", 600))
        if godot and os.path.exists(baseline):
            ok, tailtxt = run_headless_test(godot, root, baseline, timeout=base_timeout)
            if not ok:
                problems.append(f"회귀(baseline 3D) FAIL\n{tailtxt}")

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
    log(f"opencode 실행: model={model} args={extra_args or []} cwd={agent_dir}")
    proc = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True, encoding="utf-8", errors="replace", env=env,
                            cwd=agent_dir,
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
    # WORKTREE_ISOLATION: task context 는 canonical main(D:\game)이 아닌 작업 워크트리
    # 내부에 둔다. opencode --file attach 경로가 main 을 노출하면 에이전트가 main 을
    # 프로젝트 루트로 오인해 absolute-path write 를 수행할 수 있다(WORKTREE_ISOLATION_FAILURE).
    # per-task 안정 파일명으로 매 시도 덮어쓰기(시도 간 누적 방지). .md 는 commit
    # 대상(_COMMIT_SKIP_EXT)에서 제외되므로 source commit 에 포함되지 않는다.
    if WORKTREE_DIR:
        runtime_dir = os.path.join(WORKTREE_DIR, ".auto_dev_runtime")
    else:
        runtime_dir = os.path.join(tempfile.gettempdir(), "auto_dev_runtime")
    os.makedirs(runtime_dir, exist_ok=True)
    out_path = os.path.join(runtime_dir, f"task_context_{task['id']}.md")
    with open(out_path, "w", encoding="utf-8") as f:
        if block:
            f.writelines(block)
        else:
            f.write(format_task_context(task))

    return out_path


def _v2_record_implement_start(task):
    """IMPLEMENT 시작부터 V2 persistent store 에 TaskState 를 기록 (early lifecycle).

    기존에는 SOURCE_COMMITTED 단계(finalize_done)에서만 TaskState 가 생성되어,
    구현 진행 중인 TASK 는 state_v2.tasks 에 존재하지 않았다(tasks={} 관찰).
    구현 시작 즉시 기록하면 진행 상태/프로비넌스 anchor 를 런타임에 확인할 수 있다.
    실패해도 구현 자체는 차단하지 않는다 (비차단, 로그만)."""
    store = _v2_store()
    if store is None:
        return
    try:
        from harness_v2.core import LifecycleController, TaskState
        tid = task["id"]
        v2 = store.get_task(tid)
        if v2 is None:
            dep_ids = [d.strip().upper() for d in str(task.get("depends_on") or "").split(",")
                       if d.strip()]
            v2 = TaskState(tid, depends_on=dep_ids)
        attempt = _ATTEMPT_START_HEAD or datetime.datetime.now().strftime("%Y%m%dT%H%M%S")
        LifecycleController(store).implementation_started(v2, attempt_id=attempt)
        log(f"[V2][{tid}] state_v2 에 IMPLEMENT 기록 (attempt={attempt})")
    except Exception as e:
        log(f"[V2][{task['id']}] IMPLEMENT 기록 실패(비차단): {str(e)[:150]}")


def run_implementer(task, session_id=None, review_feedback=None):
    prompt = load_prompt("implementer.md")
    prompt += "\n\n" + format_task_context(task)
    if review_feedback:
        prompt += f"\n\n[리뷰어 피드백 - 반드시 반영하고 수정하세요]\n{review_feedback}"
    queue_path = os.path.join(cfg("project_dir"), cfg("queue_file"))
    extra = ["--file", build_task_file(task, queue_path)]
    if session_id:
        extra += ["--session", session_id]
    root = WORKTREE_DIR or cfg("project_dir")
    set_attempt_baseline(root)  # commit-gate: 시도 시작 baseline + attempt 시작 HEAD 스냅샷
    _v2_record_implement_start(task)
    sid, text, err = run_opencode_retry(prompt, cfg("implementer_model"), extra,
                                        cfg("implementer_timeout_sec"), task_id=task["id"])
    capture_attempt_delta(root)  # commit-gate: 이번 attempt 실제 변경 파일(delta) 기록
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
    sid, text, err = run_opencode_retry(prompt, model, extra, cfg("thinker_timeout_sec"),
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


def pick_next_task(tasks):
    for t in tasks:
        if t["leaf"] and runtime_status(t) in RETRYABLE:
            if t["id"] in SENTINEL_IDS:
                continue
            return t
    sentinel = next((t for t in tasks if t["leaf"] and runtime_status(t) == "QUEUED"
                     and t["id"] in SENTINEL_IDS), None)
    if sentinel is not None:
        return sentinel
    return None


def print_status(tasks):
    for t in tasks:
        prefix = "  " if t["level"] == 3 else ""
        mark = " [LEAF]" if t["leaf"] else " [GROUP]"
        st = runtime_status(t)
        line = f"{prefix}{t['id']:<14} {st:<12} {t['title']}"
        if t.get("feedback") and st in ("FIX", "NEEDS_DESIGN", "DONE"):
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
            _ensure_group_worktree(cfg("project_dir"), WORKTREE_DIR)
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
        blocked = [t for t in tasks if runtime_status(t) == "NEEDS_DESIGN"]
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
        rt = runtime_status(task)
        skip_review = bool(CONFIG.get("skip_review"))
        if skip_review and rt in ("REVIEW", "REVIEW_PARSE_ERROR"):
            log(f"[{task['id']}] {rt} 상태 재개 - 리뷰 스킵 모드이므로 게이트로 바로 진행")
        elif rt in ("REVIEW", "REVIEW_PARSE_ERROR"):
            log(f"[{task['id']}] {rt} 상태에서 재개 (구현 완료분 그대로 리뷰)")
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
                    if err == "알 수 없는 오류" or is_infra_error(err):
                        update_queue(tasks, queue_path, task["id"], "IMPLEMENT",
                                     feedback=f"구현자 인프라 오류 재시도: {err[:120]} - 다음 사이클 재시도")
                    else:
                        if maybe_design_resolve(task, tasks, queue_path, f"구현 실행 오류: {err}"):
                            return
                        update_queue(tasks, queue_path, task["id"], "NEEDS_DESIGN",
                                     feedback=f"구현 실행 오류: {err[:300]}")
                return
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
                    session_id, summary, err = run_implementer(task, session_id=session_id,
                                                               review_feedback=feedback)
                    if err:
                        if err.startswith("실행 시간 초과"):
                            update_queue(tasks, queue_path, task["id"], "FIX",
                                         feedback=f"게이트 수정 중 시간 초과: {err}")
                        elif err == "알 수 없는 오류" or is_infra_error(err):
                            update_queue(tasks, queue_path, task["id"], "FIX",
                                         feedback=f"수정 중 인프라 오류 재시도: {err[:120]} - 다음 사이클 재시도")
                        else:
                            if maybe_design_resolve(task, tasks, queue_path, f"게이트 수정 실행 오류: {err}"):
                                return
                            update_queue(tasks, queue_path, task["id"], "NEEDS_DESIGN",
                                         feedback=f"게이트 수정 실행 오류: {err[:300]}")
                        return
                else:
                    cls = classify_gate_failure(problems, max_rounds)
                    if cls == "ImplementationFailure":
                        # 구현 실패 - NEEDS_DESIGN 으로 승격하지 않고 FIX 유지.
                        # auto_lane 은 재시작하지 않고, 다음 사이클/사람 개입에서 구현 수정 우선.
                        update_queue(tasks, queue_path, task["id"], "FIX",
                                     feedback=f"검증 게이트 {max_rounds}회 실패 (구현 실패 분류, 수동 확인): "
                                              + "; ".join(p[:150] for p in problems[:5]))
                        write_result(task, "FIX", "auto-gate 반복 실패 (review=SKIPPED 모드) - 구현 실패 분류")
                        return
                    if maybe_design_resolve(task, tasks, queue_path, "검증 게이트 반복 실패: " + "; ".join(p[:150] for p in problems[:5])):
                        return
                    update_queue(tasks, queue_path, task["id"], "NEEDS_DESIGN",
                                 feedback=f"검증 게이트 {max_rounds}회 실패 - 수동 확인 필요: "
                                          + "; ".join(p[:150] for p in problems[:5]))
                    write_result(task, "NEEDS_DESIGN", "auto-gate 반복 실패 (review=SKIPPED 모드)")
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
                session_id, summary, err = run_implementer(task, session_id=session_id, review_feedback=reason)
                if err:
                    if err.startswith("실행 시간 초과"):
                        log(f"[{task['id']}] 재구현 시간 초과 - FIX 상태 유지, 다음 사이클에서 재시도")
                        update_queue(tasks, queue_path, task["id"], "FIX",
                                     feedback=f"재구현 시간 초과: {err}\n리뷰 피드백: {reason[:300]}")
                    else:
                        log(f"[{task['id']}] 재구현 실패: {err}")
                        if err == "알 수 없는 오류" or is_infra_error(err):
                            update_queue(tasks, queue_path, task["id"], "FIX",
                                         feedback=f"재구현 인프라 오류 재시도: {err[:120]} - 다음 사이클 재시도")
                        else:
                            if maybe_design_resolve(task, tasks, queue_path, f"재구현 실행 오류: {err}"):
                                return
                            update_queue(tasks, queue_path, task["id"], "NEEDS_DESIGN",
                                         feedback=f"재구현 실행 오류: {err[:300]}")
                    return
                log(f"[{task['id']}] 재구현 완료: {summary[:200]}")
            else:
                if maybe_design_resolve(task, tasks, queue_path, f"FIX {cfg('max_fix_rounds')}회 초과: {reason}"):
                    return
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