# LEGACY_2D_TASKS_REMOVED.md

> Legacy 2D-only TASK 정리 기록
>
> 기준일: 2026-09-04

---

## 조사 결과

**LEGACY_2D_ONLY TASK: 0건**

AI_TASK_QUEUE.md의 현재 top-level TASK heading 48개와 supervisor parser의 전체 TASK section 235개를 분석한 결과, legacy 2D 전용 TASK는 존재하지 않는다.

### 분류 기준

| 분류 | 기준 | TASK 수 |
|------|------|---------|
| **CURRENT_3D** | TASK-3D-* (3D Foundation/Migration) | ~25 |
| **SHARED_SYSTEM** | TASK-017~052 (Food/Farm/Cooking/Potion/Inn/Morale/Threat/Ghost/Portal/Expedition/Dungeon/Equipment 등) | ~100+ |
| **POST3D** | TASK-POST3D-* (3D 완료 후 작업) | 3 |
| **LEGACY_2D_ONLY** | 2D Node2D/CharacterBody2D/TileMap 전용 | **0** |

### 제거 대상 없음

- TASK-017~052는 2D/3D 공용 gameplay system으로, 3D runtime에서도 재사용됨
- TASK-3D-*는 3D migration 자체
- CHECKPOINT/STOP 마커는 TASK가 아님
- 이전 세션에서 이미 legacy 2D TASK가 정리된 것으로 확인

### 유지한 SHARED_SYSTEM 목록

- TASK-017: Ghost Return
- TASK-018: Food Resource / Consumption
- TASK-019: Farm / Farmer / Crop
- TASK-020: Cooking / Meal
- TASK-021: Herb / Potion
- TASK-022: Inn Upgrade / Hire
- TASK-023: Mercenary Morale
- TASK-024: Threat Gauge / Wave
- TASK-025: Portal Memory / Ghost
- TASK-026: Scout / Expedition
- TASK-027: Dungeon Vertical Slice
- TASK-028: Dungeon ↔ Threat Integration
- TASK-029~052: Equipment, Classes, Skills, Boss, Siege, NPC, Save, Tutorial, Audio, Balance, Demo 등

### automation dead reference

- `auto_dev/config.json`: worktree 매핑에서 존재하지 않는 TASK ID 없음
- `auto_dev/supervisor.py`: legacy smoke_test.gd 참조 없음 (이전 commit에서 제거 완료)
- `auto_dev/night_exec.py`: `TASK-026` → `TASK-027` → `TASK-028` active phase만 참조하며 dead 2D reference 없음.

---

## 결론

Legacy 2D-only TASK 정리는 이미 완료된 상태. 추가 정리 불필요.

## 2026-09-04 cleanup audit

- 현재 queue active status: 132 (`QUEUED`, `IMPLEMENT`, `FIX`, `NEEDS_DESIGN`; 부모/자식 section 포함, `DONE` 제외)
- 이 pass의 제거 TASK: 0
- TASK-027-6/7/8 및 TASK-028-3: 보존
- `tests/baseline_3d_health_test.gd`: active regression gate
- `tests/smoke_test.gd`: historical 2D contract; automation runnable path에서 호출되지 않음
- obsolete parent/root: 없음
