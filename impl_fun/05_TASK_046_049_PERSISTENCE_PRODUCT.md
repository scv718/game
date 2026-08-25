# AI Task Queue

> Post-3D Production Roadmap autonomous execution queue.
>
> 이 파일은 Ox Alpha/OpenCode가 장시간 무인 실행해도 임의 설계 확장이나 범위 이탈을 최소화하도록 작성된 실행용 Queue다.
>
> 상태: `QUEUED` / `IMPLEMENT` / `REVIEW` / `FIX` / `DONE` / `NEEDS_DESIGN`
>
> `##` = 기능 챕터/컨테이너, `###` = Supervisor가 실제 실행하는 태스크.

---

# 공통 실행 규칙

> 1. 실제 구현은 `### TASK-*` 단위로 파일 순서대로 실행한다.
> 2. 태스크 시작 시 `GAME_DESIGN.md`, `DEVELOPMENT_STATUS.md`의 **현재 태스크 관련 섹션만 우선 확인**하고, 이후 실제 Runtime 코드/Scene/Test를 확인한다.
> 3. 문서보다 Runtime 코드가 최신일 수 있으므로 reference/API/Scene ownership은 실제 코드를 우선한다.
> 4. 전체 저장소를 무작정 전수 리팩터링하지 않는다. 현재 태스크와 직접 연결된 파일부터 audit한다.
> 5. 기존 구현이 요구사항을 이미 충족하면 재작성하지 말고 재사용한다.
> 6. 현재 태스크 완료에 필요한 최소 변경만 허용한다. "나중에 필요할 것 같아서" 범용 Framework/ECS/Database를 선행 구현하지 않는다.
> 7. 수치만 미정이면 `NEEDS_DESIGN`으로 멈추지 않는다. export/config/data 값으로 두고 구현기록에 `DESIGN_TUNING`으로 남긴다.
> 8. 플레이 경험 자체가 달라지는 선택지, 서로 충돌하는 확정 규칙, 데이터 모델의 소유권을 결정할 근거가 전혀 없는 경우만 `NEEDS_DESIGN`.
> 9. `NEEDS_DESIGN`이 발생하면 추측 구현하지 않고 현재 태스크에서 중단한다. 해당 태스크에 의존하는 후속 태스크는 실행하지 않는다.
> 10. Godot headless 테스트를 실제 실행한다. 실행하지 않은 테스트를 PASS라고 보고하지 않는다.
> 11. 기존 assertion을 약화시켜 PASS시키지 않는다. 요구사항 변경으로 assertion 수정이 필요하면 이유를 구현기록에 남긴다.
> 12. flaky test가 보이면 현재 변경으로 발생했는지 기존 이슈인지 분리 확인한다.
> 13. 미감/UX/체감만 자동 검증할 수 없으면 `HUMAN_CHECK`로 남긴다. 이것만 남고 기능/회귀가 정상이면 코드상 DONE 가능하다.
> 14. 태스크 중 임시 진단 파일을 만들 수 있으나 `_diag*`, `_probe*`, `_debug*`, `_temp*`는 태스크 종료 전 제거한다.
> 15. freed reference, duplicate actor, duplicate reward, stale navigation, orphan resource, signal/timer leak를 남기지 않는다.
> 16. Runtime Actor/Node instance와 persistent identity/data를 분리한다.
> 17. lethal death와 cleanup/despawn/scene unload를 혼동하지 않는다.
> 18. 사용자 변경사항을 임의 revert하지 않는다.
> 19. `git reset --hard`, `git clean -fd`, force push 금지.
> 20. 자동 push 금지. commit 정책은 현재 Supervisor/프로젝트 설정을 그대로 따르며 태스크가 임의로 Git 정책을 변경하지 않는다.
> 21. 한 태스크가 DONE되기 전 다음 태스크 기능을 선행 구현하지 않는다.
> 22. 각 태스크 완료 후 신규 테스트 + 해당 기능 회귀 + 기존 DAY/NIGHT 핵심 회귀 subset을 실제 실행한다.
> 23. 결과 보고에는 `구현 요약 / 변경 파일 / 신규·변경 API / 테스트 결과 / 회귀 결과 / DESIGN_TUNING / HUMAN_CHECK / known issue`를 남긴다.

---

# 리뷰 규칙

> 1. Reviewer 판정은 `LGTM` / `FIX` / `HUMAN_CHECK`.
> 2. Queue의 `상태: REVIEW` 자체는 FIX 사유가 아니다.
> 3. Reviewer는 요구사항/코드/실제 테스트 문제만 FIX 사유로 사용한다.
> 4. 정확한 밸런스 수치 미정은 `DESIGN_TUNING`, 게임 규칙 자체의 공백은 `NEEDS_DESIGN`.
> 5. HUMAN_CHECK만 남으면 LGTM 가능하다.
> 6. Reviewer 판정 문자열은 일반 텍스트/Markdown bold 여부와 무관하게 동일 판정으로 취급한다.
> 7. 동일한 잘못된 리뷰 사유로 무한 FIX loop를 만들지 않는다.
> 8. 리뷰가 코드를 수정하지 않는 구조라면 수정 요구만 명확히 남기고 구현 세션이 FIX한다.

---

# 확정 게임 규칙

> 1. Main Runtime은 Stylized Top-down **3D**다.
> 2. 기존 3D Foundation의 XZ ground, `Navigation3D`, `BuildingPlacement3D`, `ResourceNode3D`, `Camera3D`, `Interaction3D`를 우선 재사용한다.
> 3. 신규 2D Gameplay Runtime 경로를 만들지 않는다.
> 4. Quaternius 기반 Stylized Top-down 3D 아트 방향을 유지한다. 외부 에셋 추가 시 출처/라이선스/스타일 호환을 기록한다.
> 5. 플레이어는 직접 필드를 돌아다니며 반복 노동하거나 직접 전투하는 Avatar가 아니다.
> 6. 기본 조작은 Camera + Mouse 관리 방식이다. 자유 회전/1인칭/3인칭 액션 조작을 추가하지 않는다.
> 7. 핵심 원칙은 **전투는 자동, 판단은 플레이어가 한다.**
> 8. Worker가 반복 생산/운반을 수행하고 Mercenary가 실제 전투를 수행한다.
> 9. Scout/Expedition은 autonomous 시스템이며 플레이어가 탐사 캐릭터를 직접 조작하지 않는다.
> 10. DAY는 건설/고용/배치/생산/준비/탐사 판단 중심, NIGHT는 자동전투 + Tactical Command 중심이다.
> 11. Food는 필수 장기/사전 준비 자원이다. raw food는 섭취 가능하나 효율이 낮고 Cooking으로 개선한다.
> 12. Potion은 Food와 별도 슬롯/체계이며 자동전투 중 조건부 위기 대응용이다. 플레이어 수동 연타 소비 구조를 만들지 않는다.
> 13. Morale은 별도 전략 상태로 유지하며 임의의 새 Morale 효과를 발명하지 않는다.
> 14. Threat는 Wave 압박과 연결되며 Dungeon clear가 Threat를 감소/지연시키는 전략 루프를 유지한다.
> 15. Death Ledger는 실제 lethal death만 기록한다. cleanup/despawn은 death가 아니다.
> 16. 기록된 존재는 이후 최대 1회 Ghost로 재등장한다.
> 17. Ghost는 원본 identity/class/성장/가능한 skill identity를 유지한다.
> 18. Ghost death는 새 DeathRecord를 만들지 않고 기존 기록을 RESOLVED 처리한다. Ghost recursion 금지.
> 19. Ghost가 등장하기 전 death record를 삭제/정화/방지하는 시스템을 만들지 않는다.
> 20. Boss/Siege는 시설에 피해를 줄 수 있으나 확정 설계 없이 시설 영구 삭제를 만들지 않는다.
> 21. 메타 진행은 자동으로 Roguelite permanent upgrade 구조를 만들지 않는다.
> 22. 신규 역할/보너스/건물을 이름만 보고 임의 확정하지 않는다. 기존 `GAME_DESIGN.md`가 우선이다.

---

# 현재 시스템 보존 규칙

> 다음 기존 기반은 특별한 이유 없이 교체/재작성하지 않는다:
>
> - Camera + Mouse management.
> - DAY/NIGHT state.
> - Worker Assignment / Workplace / Roster identity.
> - Lumberyard / Quarry / Farm 및 기존 생산 파이프라인.
> - Mercenary Roster / Auto Combat / Tactical Command priority.
> - Wall / Gate / Defense.
> - Food / Farming / Cooking foundation.
> - Potion foundation.
> - Inn / Morale / Threat foundation.
> - Death Ledger / Ghost candidate/Portal foundation이 이미 존재하면 그 ownership.
> - World Map / ExplorationRegion foundation이 존재하면 해당 state/API.
>
> 현재 태스크와 직접 충돌하지 않는 기존 회귀 테스트는 유지한다.

---

# 범위 밖 공통 금지

> - Player direct combat.
> - Player Avatar 반복 노동.
> - 신규 2D Runtime.
> - Multiplayer.
> - Procedural open world.
> - 범용 ECS 전환.
> - 대규모 전면 UI 재작성.
> - 확정되지 않은 스토리 캠페인.
> - 확정되지 않은 Roguelite meta progression.
> - 자동 Asset Migration.
> - 테스트 편의를 위한 production cheat API 추가.

---
# 실행 순서

> **046 Save/Load → 047 Meta Progression Decision → 048 Tutorial → 049 Audio/VFX**
>
> 목표: 현재까지의 복합 시스템을 안정적으로 저장/복원하고 첫 플레이 전달력을 확보한다.

---

## TASK-046 Save / Load

- 상태: QUEUED
- 저장 대상:
  - VillageResources.
  - Buildings/levels.
  - Wall/Gate state/damage.
  - Worker assignment.
  - Residents.
  - Mercenary roster.
  - Equipment/Potion.
  - Food/Crops.
  - Threat/Wave.
  - Exploration/Expedition/Dungeon.
  - Death Ledger/Ghost.
  - Morale source state.
  - damaged facility.
  - day/time.

### TASK-046-1 Persistence Audit / Ownership Map

- 상태: QUEUED
- 설명: 저장 대상별로 persistent / reconstructable / transient를 분류한다.
- 요구사항:
  - stable identity owner 기록.
  - Runtime Actor/Node를 직접 저장하지 않음.
  - current Autoload/service ownership 확인.
  - schema version 필요 영역 기록.
- 산출:
  - 구현기록에 persistence map 표 작성.
- 완료조건:
  - 각 시스템의 save owner/restore owner 명확.

### TASK-046-2 Save Schema / Versioning

- 상태: QUEUED
- 요구사항:
  - top-level schema_version.
  - stable IDs.
  - typed dictionary/JSON-compatible 구조.
  - Node/Resource instance를 그대로 serialize 금지(명시적 data export 사용).
  - missing optional field safe default.
  - unknown future field ignore 가능.
  - corrupt/invalid parse 시 기존 save 덮어쓰지 않음.
- 완료조건:
  - schema validation PASS.

### TASK-046-3 Save Write / Atomic Safety

- 상태: QUEUED
- 요구사항:
  - temp write → validation → replace 등 가능한 atomic pattern.
  - write failure 시 기존 정상 save 보존.
  - partial file safe fail.
  - user save path 기존 프로젝트 정책 준수.
- 금지:
  - 테스트 때문에 임의 절대경로.
- 완료조건:
  - save 생성/parse/write failure safe.

### TASK-046-4 Runtime Reconstruction

- 상태: QUEUED
- 요구사항:
  - World/Building 생성 순서.
  - Navigation3D rebuild.
  - Worker workplace assignment.
  - Mercenary roster/equipment.
  - Gate OPEN/CLOSED/BREACHED + damage.
  - Threat/Wave.
  - Expedition/Dungeon state.
  - Death Ledger/Ghost active/pending 정책.
  - duplicate actor 금지.
- 중요:
  - transient combat target/timer는 복원하지 않고 authoritative data에서 재구성.
- 완료조건:
  - load 후 core runtime consistency PASS.

### TASK-046-5 Active State Edge Cases

- 상태: QUEUED
- 검증:
  - NIGHT save/load.
  - active Expedition.
  - Dungeon in-progress 정책.
  - active Ghost.
  - damaged facility.
  - production timer.
- 규칙:
  - 설계상 save가 허용되지 않는 state가 있다면 임의 복원하지 말고 기존 design 확인. 근거 없으면 `NEEDS_DESIGN`.
- 완료조건:
  - supported active state 안정.

### TASK-046-6 Save / Load 통합 회귀

- 상태: QUEUED
- 시나리오:
  1. 건설.
  2. Worker assign.
  3. Food/Crop.
  4. Equipment/Potion.
  5. Expedition.
  6. Dungeon result/state.
  7. NIGHT death.
  8. Death Ledger/Ghost candidate.
  9. Threat.
  10. Gate damage/state.
  11. save.
  12. Runtime 종료/재구성.
  13. load.
  14. 상태 비교.
  15. repeated load duplicate actor 없음.
- 완료조건:
  - PASS.

---

## TASK-047 Meta Progression Decision

- 상태: QUEUED
- 중요: 자동으로 Roguelite permanent upgrade를 만들지 않는다.

### TASK-047-1 Design Audit

- 상태: QUEUED
- 확인:
  - campaign/run reset.
  - new game loop.
  - permanent unlock.
  - replay structure.
  - `GAME_DESIGN.md`.
- 판정:
  - 필요 없음/설계 없음 → `DONE - NOT REQUIRED` 근거 기록.
  - 필요하지만 핵심 설계 공백 → `NEEDS_DESIGN`.
  - 명시적 설계 존재 → 047-2 진행.
- 완료조건:
  - 임의 meta system 생성 없이 판정.

### TASK-047-2 Minimal Unlock Hook

- 상태: QUEUED
- 선행: 047-1에서 실제 필요/설계 있음 판정일 때만.
- 요구사항:
  - unlock_id.
  - persistent flag.
  - content availability.
  - save/load.
  - stat power creep를 임의 추가하지 않음.
- 완료조건:
  - minimal unlock PASS.

### TASK-047-3 Meta Regression

- 상태: QUEUED
- 선행 조건이 없으면 `DONE - NOT REQUIRED`.
- 완료조건:
  - new game/load/unlock availability PASS.

---

## TASK-048 Tutorial / Onboarding

- 상태: QUEUED
- 첫 안내 후보:
  - Camera.
  - Resource.
  - Building.
  - Worker.
  - Food.
  - Mercenary.
  - Potion/Equipment.
  - First NIGHT.
  - Tactical Command.
  - Threat.
  - Expedition/Dungeon.

### TASK-048-1 Tutorial Flow Audit / State

- 상태: QUEUED
- 요구사항:
  - tutorial_step_id.
  - trigger.
  - completion.
  - skip.
  - save persistence.
  - already completed step 재실행 금지.
- 원칙:
  - 시스템을 새로 만들기 위한 튜토리얼이 아니라 실제 구현된 흐름을 설명.
- 완료조건:
  - deterministic progression.

### TASK-048-2 Contextual Highlight / Input Safety

- 상태: QUEUED
- 요구사항:
  - relevant UI/world target highlight.
  - 짧은 설명.
  - modal 여부 명확.
  - UI click-through/input leakage 없음.
  - Camera+Mouse 조작 유지.
- HUMAN_CHECK:
  - 과도하게 손을 잡지 않는지.
- 완료조건:
  - highlight/input PASS.

### TASK-048-3 First DAY → First NIGHT Onboarding

- 상태: QUEUED
- 흐름:
  - 기본 resource 이해.
  - building/worker.
  - Mercenary 준비.
  - Food/Potion/Equipment 최소 설명.
  - NIGHT warning.
  - Tactical Command.
  - Threat 소개.
- 규칙:
  - 플레이어 직접 전투를 튜토리얼로 요구하지 않음.
- 완료조건:
  - first NIGHT onboarding PASS.

### TASK-048-4 Tutorial Regression

- 상태: QUEUED
- 검증:
  - new game.
  - skip.
  - save/load tutorial state.
  - completed step no duplicate.
  - DAY/NIGHT.
- 완료조건:
  - PASS.

---

## TASK-049 Audio / VFX

- 상태: QUEUED
- 범위: Worker, Building, UI, Combat, Death, Ghost, Potion, Gate, DAY/NIGHT ambience, Siege/Boss.

### TASK-049-1 Asset / License Audit + Audio Bus

- 상태: QUEUED
- 요구사항:
  - 기존 audio/vfx asset 확인.
  - 신규 asset은 출처/라이선스 기록.
  - Bus: Master / Music / SFX / Ambient / UI.
  - volume setting hook.
- 완료조건:
  - bus/playback foundation PASS.

### TASK-049-2 Gameplay SFX

- 상태: QUEUED
- 요구사항:
  - event-driven.
  - per-frame playback 금지.
  - repeated hit/worker event audio spam throttling 필요 시 최소 정책.
  - UI/Combat/Gate/Ghost/Potion 핵심 이벤트.
- 완료조건:
  - duplicate playback 없음.

### TASK-049-3 Gameplay VFX

- 상태: QUEUED
- 후보:
  - hit.
  - heal/potion.
  - Ghost.
  - placement.
  - siege warning.
- 요구사항:
  - Quaternius stylized 3D 방향.
  - selection outline/전투 유닛 가독성 방해 금지.
  - effect pooling은 실제 성능 문제 없으면 과설계 금지.
- HUMAN_CHECK:
  - VFX가 전투 가독성을 해치지 않는지.
- 완료조건:
  - vertical slice PASS.

### TASK-049-4 Audio / VFX Regression

- 상태: QUEUED
- 검증:
  - repeated DAY/NIGHT.
  - large wave.
  - pause/1x/2x.
  - no audio spam.
  - freed emitter safety.
- 완료조건:
  - PASS.

---

## PHASE-STOP-5 Persistence / Product 종료 경계

- 상태: QUEUED
- 확인:
  - TASK-046~049 완료/해당 없음 판정.
  - save corruption 없음.
  - duplicate reconstruction 없음.
  - tutorial input leakage 없음.
  - audio/vfx event leak 없음.
  - 임시 파일 없음.
- 종료 회귀:
  - Save/Load.
  - Tutorial.
  - DAY/NIGHT.
  - Dungeon/Wave/Ghost.
- 완료조건:
  - PASS.
  - 다음 파일 자동 시작 금지.
