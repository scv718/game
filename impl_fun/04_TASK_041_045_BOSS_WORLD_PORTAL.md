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

> **041 Boss/Siege → 042 Boss Aftermath → 043 Resident/NPC → 044 Animal/Hostile NPC → 045 Full Portal Memory**
>
> 목표: 대규모 위협과 사망 기억 시스템을 Village 전체 생명체 범주로 확장한다.

---

## TASK-041 Boss / Siege Vertical Slice

- 상태: QUEUED
- 선행: Enemy Archetypes, Elite, Wave Composition, Wall/Gate Upgrade, Potion, Equipment, Mercenary Classes.
- 목표: 일반 NIGHT Wave와 구분되는 warning → preparation → siege → boss → resolved 흐름.

### TASK-041-1 Siege Design/Runtime Audit

- 상태: QUEUED
- 확인:
  - Threat/Wave trigger.
  - Gate/Wall/building damage.
  - Boss candidate design.
  - Tactical Command.
  - facility damage persistence hook.
  - support NPC design hook.
- 규칙:
  - 확정 Boss 능력/시설 파괴 정책이 없으면 임의 영구 삭제/스토리 결과 발명 금지.
- 완료조건:
  - lifecycle owner와 최소 Boss vertical slice 범위 확정.

### TASK-041-2 Siege Event State

- 상태: QUEUED
- 상태:
  - WARNING.
  - PREPARATION.
  - ACTIVE.
  - RESOLVED.
  - AFTERMATH_PENDING.
- 요구사항:
  - duplicate trigger 금지.
  - state signal/UI hook.
  - reload/save hook.
  - ACTIVE 중 일반 Wave와 중복 spawn 정책 명확.
- 완료조건:
  - lifecycle PASS.

### TASK-041-3 Boss Actor / Combat

- 상태: QUEUED
- 요구사항:
  - 기존 Enemy/Combat foundation 재사용.
  - boss identity/stats.
  - 기존 설계 기반 ability 최소 1.
  - Tactical Focus 가능.
  - Player direct attack 금지.
  - lethal death → Death Ledger eligibility.
- 완료조건:
  - Boss combat PASS.

### TASK-041-4 Siege Structure Interaction

- 상태: QUEUED
- 요구사항:
  - Gate/Wall/시설 피해.
  - target freed/unreachable stall 방지.
  - 시설 damage state 누적.
  - 확정 정책 없이 building node 영구 delete 금지.
  - damaged state save hook.
- 완료조건:
  - structure interaction PASS.

### TASK-041-5 Siege Resolution / Reward Hook

- 상태: QUEUED
- 요구사항:
  - Boss death/retreat/fail 중 현재 설계에 존재하는 결과만.
  - resolved 정확히 1회.
  - reward duplicate 없음.
  - AFTERMATH_PENDING으로 연결.
- 완료조건:
  - resolution PASS.

### TASK-041-6 Siege 통합 검증

- 상태: QUEUED
- 시나리오:
  1. warning.
  2. preparation.
  3. active.
  4. mixed enemies.
  5. structure damage.
  6. tactical command.
  7. boss.
  8. lethal deaths.
  9. resolved.
  10. aftermath pending.
- HUMAN_CHECK:
  - 일반 Wave와 확실히 다른 대규모 사건처럼 느껴지는지.
- 완료조건:
  - PASS.

---

## TASK-042 Boss Aftermath

- 상태: QUEUED
- 확정 핵심:
  - 지원 NPC 1명 랜덤 사망.
  - 생존 지원 NPC는 레벨 1 초기화 후 합류 제안.
  - 시설 피해/복구.
  - 보상/후속 변화.

### TASK-042-1 Support NPC Eligibility / Outcome

- 상태: QUEUED
- 요구사항:
  - eligible support NPC pool.
  - deterministic test seed.
  - eligible pool에서 정확히 1명 death.
  - 이미 dead/ineligible 제외.
  - lethal death 의미로 처리되며 Death Ledger/Ghost eligibility 연결.
  - 동일 Siege에 outcome 중복 적용 금지.
- 완료조건:
  - NPC death 1회 정확.

### TASK-042-2 Survivor Reset / Join Offer

- 상태: QUEUED
- 요구사항:
  - survivor identity 유지.
  - level 1 reset.
  - join offer state.
  - 자동 합류가 아니라 "합류 제안" 유지.
  - 기존 skill/class identity를 초기화할 범위는 `GAME_DESIGN.md` 우선.
- 완료조건:
  - survivor state 정상.

### TASK-042-3 Facility Recovery State

- 상태: QUEUED
- 요구사항:
  - damaged facility feedback.
  - repair hook.
  - instant free full restore 금지.
  - repair cost/time 미정이면 `DESIGN_TUNING`.
  - save hook.
- 완료조건:
  - next DAY damaged state 유지.

### TASK-042-4 Aftermath Regression

- 상태: QUEUED
- 완료조건:
  - Siege → NPC outcome → survivor offer → facility recovery state → DAY continuation PASS.

---

## TASK-043 Resident / NPC Expansion

- 상태: QUEUED
- 목표: 일반 Resident/지원 NPC를 Food/Death/Ghost/Save에 연결할 persistent identity 범주로 만든다.

### TASK-043-1 Resident Runtime Audit

- 상태: QUEUED
- 확인:
  - current Worker/Resident split.
  - NPC identity.
  - Food consumption owner.
  - Death Ledger category.
  - save hooks.
- 완료조건:
  - Worker와 Resident를 억지 통합하지 않고 owner 확정.

### TASK-043-2 Resident Identity / Lifecycle

- 상태: QUEUED
- 필드:
  - resident_id.
  - role.
  - alive/dead.
  - assignment hook.
  - food consumption hook.
  - Death Ledger category.
  - Ghost eligibility.
  - save identity.
- 요구사항:
  - Runtime Actor reference 분리.
  - cleanup death 오판정 금지.
- 완료조건:
  - lifecycle PASS.

### TASK-043-3 Support NPC Role Hook

- 상태: QUEUED
- 요구사항:
  - Boss aftermath join offer와 연결.
  - gameplay bonus가 확정되지 않았으면 임의 passive/시설 bonus 생성 금지.
  - identity/lifecycle만 안정화.
- 완료조건:
  - support NPC persistent state PASS.

### TASK-043-4 Resident Regression

- 상태: QUEUED
- 완료조건:
  - Food + Death Ledger + Ghost eligibility + save hook PASS.

---

## TASK-044 Animal / Hostile NPC Foundation

- 상태: QUEUED
- 목표: Portal Memory 대상 범주를 Animal/Hostile NPC까지 확장할 최소 Actor/data category.

### TASK-044-1 Animal Data / Actor

- 상태: QUEUED
- 요구사항:
  - stable identity.
  - category.
  - basic movement.
  - HP/death.
  - cleanup separation.
  - Death Ledger.
  - Ghost eligibility.
- 금지:
  - gameplay 목적 없는 생태계 simulation.
  - 확정되지 않은 hunting system.
- 완료조건:
  - spawn/death/ledger/cleanup PASS.

### TASK-044-2 Hostile NPC Data / Actor

- 상태: QUEUED
- 요구사항:
  - 기존 Enemy base 우선 재사용.
  - category identity는 Enemy archetype과 구분 가능.
  - lethal death/ghost.
  - Player target 금지.
- 완료조건:
  - hostile NPC death loop PASS.

### TASK-044-3 Category Visual Hook

- 상태: QUEUED
- 요구사항:
  - Quaternius-compatible visual.
  - Ghost modifier가 원본 silhouette/identity를 유지할 수 있는 hook.
- HUMAN_CHECK:
  - category가 visual로 읽히는지.
- 완료조건:
  - hook 정상.

### TASK-044-4 Category Regression

- 상태: QUEUED
- 완료조건:
  - Mercenary/Enemy/Resident/Animal/Hostile NPC identity/death 분리 PASS.

---

## TASK-045 Full Portal Memory

- 상태: QUEUED
- LOCK:
  - 실제 lethal death 대상은 최대 1회 Ghost return.
  - cleanup/despawn 제외.
  - Ghost death recursion 금지.
  - identity 유지.
  - Ghost return prevention/purification 없음.

### TASK-045-1 Eligibility Matrix / Audit

- 상태: QUEUED
- 대상:
  - Enemy.
  - Mercenary.
  - Resident.
  - Animal.
  - Hostile NPC.
  - Support NPC.
  - 실제 Dungeon entity 중 lethal identity가 있는 대상.
- 요구사항:
  - 각 category의 death source_uid/record kind/ghost factory path를 표로 구현기록에 남김.
  - category별 예외를 임의 만들지 않음.
- 완료조건:
  - eligibility 명확.

### TASK-045-2 Multi-category Ghost Factory / Identity

- 상태: QUEUED
- 요구사항:
  - 원본 class/type/stat snapshot 재사용.
  - skill identity 가능한 범위 유지.
  - original visual + common ghost modifier 구조.
  - temporary Food/Potion/Morale buff 미복제.
  - 별도 category마다 전투 코드를 복제하지 않음.
- 완료조건:
  - 각 category ghost construction PASS.

### TASK-045-3 Return Lifecycle / Resolve

- 상태: QUEUED
- 요구사항:
  - one death → max one active ghost.
  - eligible later NIGHT/Wave.
  - ACTIVE/PENDING/RESOLVED 상태 일관.
  - ghost survive cleanup → 기존 unresolved continuity 정책 유지.
  - ghost lethal death → 기존 record RESOLVED.
  - 신규 DeathRecord 생성 금지.
- 완료조건:
  - lifecycle PASS.

### TASK-045-4 Full Portal Regression

- 상태: QUEUED
- 검증:
  - category lethal death.
  - cleanup.
  - candidate.
  - return.
  - identity.
  - combat.
  - ghost death resolve.
  - repeated NIGHT.
  - Dungeon.
  - Boss aftermath.
- HUMAN_CHECK:
  - 죽은 동료/적의 원본 identity가 Ghost에서도 알아볼 수 있는지.
- 완료조건:
  - 현재 범주의 Portal Memory PASS.

---

## PHASE-STOP-4 Boss / Portal 종료 경계

- 상태: QUEUED
- 확인:
  - TASK-041~045 완료.
  - Boss/Aftermath duplicate 없음.
  - Ghost recursion 없음.
  - category identity 안정.
  - facility permanent deletion 임의 구현 없음.
  - 임시 파일 없음.
- 종료 회귀:
  - Siege.
  - Aftermath.
  - Resident/Animal.
  - Full Portal.
- 완료조건:
  - PASS.
  - 다음 파일 자동 시작 금지.
