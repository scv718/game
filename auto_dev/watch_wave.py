import datetime
import json
import os
import shutil
import subprocess
import time

PY = r"C:\Users\skfnx\AppData\Local\Python\pythoncore-3.14-64\python.exe"
SUP = r"D:\game\auto_dev\supervisor.py"
MAIN = r"D:\game"
WT_ROOT = r"D:\game-wt"
LOG = r"D:\game\auto_dev\logs\watch_wave.log"

WAVE_A = ["TASK-3D-BLD-001", "TASK-3D-WRK-001", "TASK-3D-CMB-001", "TASK-3D-VIS-001"]
WAVETREES = {
    "TASK-3D-BLD-001": (r"D:\game-wt\building", "ai/3d-building"),
    "TASK-3D-WRK-001": (r"D:\game-wt\worker", "ai/3d-worker"),
    "TASK-3D-CMB-001": (r"D:\game-wt\combat", "ai/3d-combat"),
    "TASK-3D-VIS-001": (r"D:\game-wt\visual", "ai/3d-visual"),
}
FEATURES = {
    "TASK-017": ("f-ghost", "ai/f-ghost"),
    "TASK-018": ("f-food", "ai/f-food"),
    "TASK-019": ("f-farm", "ai/f-farm"),
    "TASK-020": ("f-cooking", "ai/f-cooking"),
    "TASK-021": ("f-potion", "ai/f-potion"),
    "TASK-022": ("f-inn", "ai/f-inn"),
    "TASK-023": ("f-morale", "ai/f-morale"),
    "TASK-024": ("f-threat", "ai/f-threat"),
    "TASK-025": ("f-portal", "ai/f-portal"),
}
VIS2 = ("visual2", "ai/3d-visual-002")
CONFIG_JSON = r"D:\game\auto_dev\config.json"
PHASES = [
    ("impl_fun\\01_TASK_026_028_EXPEDITION_DUNGEON.md", "PHASE-1 Expedition/Dungeon"),
    ("impl_fun\\02_TASK_029_032_EQUIPMENT_MERCENARY.md", "PHASE-2 Equipment/Mercenary"),
    ("impl_fun\\03_TASK_033_040_ENEMY_VILLAGE_PROGRESSION.md", "PHASE-3 Enemy/Village"),
    ("impl_fun\\04_TASK_041_045_BOSS_WORLD_PORTAL.md", "PHASE-4 Boss/World/Portal"),
    ("impl_fun\\05_TASK_046_049_PERSISTENCE_PRODUCT.md", "PHASE-5 Persistence/Product"),
    ("impl_fun\\06_TASK_050_052_BALANCE_STRESS_DEMO.md", "PHASE-6 Balance/Stress/Demo"),
]


def set_queue_file(rel_path):
    with open(CONFIG_JSON, encoding="utf-8") as f:
        cfg = json.load(f)
    cfg["queue_file"] = rel_path
    with open(CONFIG_JSON, "w", encoding="utf-8") as f:
        json.dump(cfg, f, ensure_ascii=False, indent=2)
    log(f"queue_file 전환: {rel_path}")


def queue_has_work():
    for line in status_text().splitlines():
        parts = line.split()
        if len(parts) >= 2 and parts[1] in ("QUEUED", "IMPLEMENT", "REVIEW", "FIX", "REVIEW_PARSE_ERROR"):
            return True
    return False


def start_phase_lane():
    subprocess.run(["powershell", "-NoProfile", "-Command",
                    "Start-Process powershell -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File D:\\game\\auto_dev\\run_phase.ps1' -WindowStyle Hidden"],
                   capture_output=True, encoding="utf-8", errors="replace", timeout=60)
    log("phase 레인 시작")


def log(msg):
    line = f"[{datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] {msg}"
    print(line, flush=True)
    with open(LOG, "a", encoding="utf-8") as f:
        f.write(line + "\n")


def run(cmd, cwd=None, timeout=600):
    try:
        r = subprocess.run(cmd, cwd=cwd, capture_output=True, encoding="utf-8",
                           errors="replace", timeout=timeout)
        return r.returncode, (r.stdout or "") + (r.stderr or "")
    except Exception as e:
        return -1, str(e)


def status_text():
    r = subprocess.run([PY, SUP, "--status"], capture_output=True, encoding="utf-8",
                       errors="replace", timeout=60)
    return r.stdout or ""


def group_done(gid):
    for line in status_text().splitlines():
        parts = line.strip().split()
        if parts and parts[0] == gid:
            return "DONE" in line
    return False


def start_lane(gid):
    subprocess.run(["powershell", "-NoProfile", "-Command",
                    f"Start-Process powershell -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File D:\\game\\auto_dev\\run_lane.ps1 -Group {gid}' -WindowStyle Hidden"],
                   capture_output=True, encoding="utf-8", errors="replace", timeout=60)
    log(f"레인 시작: {gid}")


def ensure_worktree(gid, short, branch):
    wt = os.path.join(WT_ROOT, short)
    if os.path.exists(wt):
        return wt
    rc, out = run(["git", "-C", MAIN, "worktree", "add", wt, "-b", branch], timeout=300)
    if rc != 0:
        log(f"worktree 생성 실패 {short}: {out.strip()[:200]}")
        return None
    run(["git", "config", "--global", "--add", "safe.directory", wt])
    tiny = os.path.join(MAIN, "assets", "tiny_swords")
    if os.path.exists(tiny):
        shutil.copytree(tiny, os.path.join(wt, "assets", "tiny_swords"))
    log(f"worktree 생성: {wt} ({branch})")
    return wt


def commit_worktree(gid):
    wt, branch = WAVETREES.get(gid, (None, None))
    if not wt:
        return
    run(["git", "-C", wt, "add", "-A"])
    rc, out = run(["git", "-C", wt, "commit", "-m", f"{gid}: 레인 작업 커밋"], timeout=120)
    log(f"커밋 {gid}: rc={rc} {out.strip()[:100]}")


def merge_into_main(groups):
    for gid in groups:
        wt, branch = WAVETREES.get(gid) or (None, None)
        if not branch:
            continue
        rc, out = run(["git", "-C", MAIN, "merge", branch, "--no-edit"], timeout=300)
        if rc != 0:
            log(f"병합 실패 {branch}: {out.strip()[:300]} - 수동 개입 필요")
            return False
        log(f"병합 완료: {branch} -> main")
    return True


def main():
    stage = 0
    log("watch_wave 시작 (스테이지 0: Wave A 대기)")
    while True:
        time.sleep(120)
        if stage == 0 and all(group_done(g) for g in WAVE_A):
            log("Wave A 전체 DONE - 커밋/병합 후 INT-001 시작")
            for g in WAVE_A:
                commit_worktree(g)
            if merge_into_main(WAVE_A):
                start_lane("TASK-3D-INT-001")
                stage = 1
                log("스테이지 1: INT-001 대기")
        elif stage == 1 and group_done("TASK-3D-INT-001"):
            log("INT-001 DONE - VIS-002 워크트리 생성 + INT-002/VIS-002 시작")
            if ensure_worktree("TASK-3D-VIS-002", *VIS2):
                start_lane("TASK-3D-INT-002")
                start_lane("TASK-3D-VIS-002")
                stage = 2
                log("스테이지 2: INT-002/VIS-002 대기")
        elif stage == 2 and group_done("TASK-3D-INT-002") and group_done("TASK-3D-VIS-002"):
            log("INT-002/VIS-002 DONE - 기능 워크트리 9개 생성 + 병렬 시작")
            ok = all(ensure_worktree(gid, *FEATURES[gid]) for gid in FEATURES)
            if ok:
                for gid in FEATURES:
                    start_lane(gid)
                stage = 3
                log("스테이지 3: TASK-017~025 대기")
        elif stage == 3 and all(group_done(g) for g in FEATURES):
            log("TASK-017~025 DONE - 커밋/병합 후 POST3D 순차 시작")
            for g in FEATURES:
                commit_worktree(g)
            if merge_into_main(list(FEATURES)):
                start_lane("TASK-POST3D-INT-001")
                stage = 4
                log("스테이지 4: POST3D-INT-001 대기")
        elif stage == 4 and group_done("TASK-POST3D-INT-001"):
            start_lane("TASK-POST3D-VIS-001")
            stage = 5
            log("스테이지 5: POST3D-VIS-001 대기")
        elif stage == 5 and group_done("TASK-POST3D-VIS-001"):
            start_lane("TASK-POST3D-REG-001")
            stage = 6
            log("스테이지 6: 최종 회귀 진행 중")
        elif stage == 6 and group_done("TASK-POST3D-REG-001"):
            log("POST3D-REG-001 DONE - impl_fun phase 순차 실행 시작")
            set_queue_file(PHASES[0][0])
            time.sleep(30)
            start_phase_lane()
            stage = 100 + 1  # 101 = phase 1 진행
            log("스테이지 101: PHASE-1 진행 중")
        elif stage in range(101, 107):
            idx = stage - 101
            if not queue_has_work():
                log(f"{PHASES[idx][1]} 완료")
                if idx + 1 < len(PHASES):
                    set_queue_file(PHASES[idx + 1][0])
                    time.sleep(30)
                    start_phase_lane()
                    stage = 101 + idx + 1
                    log(f"스테이지 {101 + idx + 1}: {PHASES[idx + 1][1]} 진행 중")
                else:
                    log("모든 phase 완료 - 전체 자동화 종료")
                    stage = 999


if __name__ == "__main__":
    main()