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

> **033 Enemy Archetypes → 034 Elite → 035 Wave Composition → 036 Wall/Gate Upgrade → 037 Core Building Upgrade → 038 Herb Automation → 039 Advanced Cooking → 040 Advanced Potion**
>
> 목표: NIGHT 전술 판단과 Village 성장/준비 루프를 콘텐츠 다양성으로 확장한다.

---

## TASK-033 Enemy Archetypes

- 상태: QUEUED
- 목표: 수치만 다른 적이 아니라 플레이어의 방어/타겟 판단을 바꾸는 최소 3개 역할을 만든다.
- 후보 역할: melee / fast / ranged / structure attacker. 실제 `GAME_DESIGN.md` 확정 내용을 우선한다.

### TASK-033-1 Enemy Runtime Audit

- 상태: QUEUED
- 확인:
  - Enemy base data/actor.
  - target preference.
  - Navigation3D.
  - Gate/Wall/building damage API.
  - Wave spawn data.
  - Ghost identity.
- 완료조건:
  - archetype을 data-driven으로 확장할 최소 hook 확정.

### TASK-033-2 Archetype Data

- 상태: QUEUED
- 필드:
  - archetype_id.
  - base stats.
  - attack profile/range.
  - target preference.
  - movement profile.
  - visual hook.
  - spawn weight hook.
  - ghost identity hook.
- 요구사항:
  - 최소 3 archetype.
  - 이름/스킬이 미정이면 역할 id 중심으로 구현하고 `DESIGN_TUNING`.
- 완료조건:
  - data validation PASS.

### TASK-033-3 Structure Attacker / Target Policy

- 상태: QUEUED
- 요구사항:
  - structure attacker만 Gate/Wall/Building preference를 가질 수 있도록 명확한 정책.
  - 일반 Enemy 기존 Gate behavior를 깨뜨리지 않음.
  - unreachable structure target permanent stall 금지.
  - target freed/breached 후 재탐색.
  - Player target 금지.
- 완료조건:
  - target selection/navigation PASS.

### TASK-033-4 Archetype Combat Regression

- 상태: QUEUED
- 검증:
  - melee/fast/ranged/structure 역할.
  - mixed navigation.
  - Gate.
  - Mercenary class/skill.
  - Ghost identity.
- HUMAN_CHECK:
  - 전장에서 적 역할을 읽을 수 있는지.
- 완료조건:
  - mixed archetype combat PASS.

---

## TASK-034 Elite Enemy

- 상태: QUEUED
- 목표: 기존 archetype identity를 유지하면서 강화된 고우선도 적을 만든다.

### TASK-034-1 Elite Modifier Data

- 상태: QUEUED
- 요구사항:
  - base archetype + elite modifier.
  - hp/damage/speed 등 modifier data.
  - 동일 modifier 중복 적용 금지.
  - elite가 별도 완전 복제 actor tree가 되지 않음.
- 완료조건:
  - elite 생성/stat PASS.

### TASK-034-2 Elite Runtime / Tactical Priority

- 상태: QUEUED
- 요구사항:
  - 기존 AI/target policy 유지.
  - Focus Target 대상으로 정상 선택 가능.
  - elite death Death Ledger/Ghost eligibility 유지.
- 완료조건:
  - combat PASS.

### TASK-034-3 Elite Visual / Reward Hook

- 상태: QUEUED
- 요구사항:
  - Quaternius compatible visual distinction.
  - reward는 기존 reward owner에 hook.
  - elite reward 정확히 1회.
  - 확정 loot table 없으면 최소 hook + `DESIGN_TUNING`.
- HUMAN_CHECK:
  - combat 중 Elite를 즉시 식별 가능한지.
- 완료조건:
  - visual/reward hook 정상.

### TASK-034-4 Elite Regression

- 상태: QUEUED
- 완료조건:
  - normal + elite mixed combat.
  - death/ghost/reward duplicate 없음.

---

## TASK-035 Wave Composition

- 상태: QUEUED
- 목표: Threat에 따라 단순 수량이 아니라 enemy composition이 변하는 Wave를 만든다.

### TASK-035-1 Wave Runtime Audit

- 상태: QUEUED
- 확인:
  - current Wave/Threat owner.
  - west main spawn / north secondary route.
  - wave completion.
  - ghost insertion.
  - deterministic seed/test hooks.
- 완료조건:
  - composition owner 확정.

### TASK-035-2 Wave Composition Data

- 상태: QUEUED
- 필드:
  - threat_band.
  - count/budget.
  - archetype weights.
  - elite weight.
  - ghost insertion hook.
  - route/spawn direction policy.
- 요구사항:
  - 최소 LOW/MID/HIGH 3 band.
  - exact weight/count는 `DESIGN_TUNING`.
  - EAST Royal Road/SOUTH Production을 기본 spawn으로 임의 전환하지 않는다.
- 완료조건:
  - deterministic seed로 composition 생성 PASS.

### TASK-035-3 Mixed Wave Spawn / Completion

- 상태: QUEUED
- 요구사항:
  - normal + elite + eligible ghost.
  - spawn duplicate 없음.
  - wave completion은 실제 active combatants 기준.
  - cleanup을 death로 기록하지 않음.
  - unresolved surviving ghost의 기존 return 정책 유지.
- 완료조건:
  - mixed wave lifecycle PASS.

### TASK-035-4 Wave Strategy Regression

- 상태: QUEUED
- 검증:
  - low/mid/high Threat.
  - Dungeon delay/reduction.
  - Ghost.
  - Elite.
  - Gate/Tactical.
  - repeated NIGHT.
- HUMAN_CHECK:
  - Threat가 높아질수록 "수량만 많음"이 아니라 조합이 달라지는지.
- 완료조건:
  - strategy loop PASS.

---

## TASK-036 Wall / Gate Upgrade

- 상태: QUEUED

### TASK-036-1 Defense Upgrade Contract

- 상태: QUEUED
- 필드:
  - defense identity.
  - level.
  - max_hp/durability modifier.
  - upgrade cost.
  - visual hook.
- 요구사항:
  - 기존 Wall/Gate identity 유지.
  - exact cost/stat은 `DESIGN_TUNING`.
- 완료조건:
  - data contract PASS.

### TASK-036-2 Upgrade Runtime

- 상태: QUEUED
- 요구사항:
  - upgrade cost 정확히 1회.
  - negative resource 금지.
  - collision/nav identity 유지.
  - Gate `OPEN/CLOSED/BREACHED` state를 upgrade가 임의 reset하지 않음.
  - damaged HP 정책은 기존 설계가 없으면 임의 결정하지 말고 현재 데이터 흐름에 가장 작은 일관 정책을 적용하고 구현기록에 남김.
- 완료조건:
  - upgrade 후 combat/nav 정상.

### TASK-036-3 Upgrade UI / Visual

- 상태: QUEUED
- 요구사항:
  - level/cost/stat delta 표시.
  - unavailable reason.
  - visual hook.
- HUMAN_CHECK:
  - upgrade 전후 차이가 읽히는지.
- 완료조건:
  - UI 정상.

### TASK-036-4 Defense Upgrade Regression

- 상태: QUEUED
- 검증:
  - build → damage → upgrade → gate toggle → combat → breach.
  - save hook.
- 완료조건:
  - PASS.

---

## TASK-037 Core Building Upgrade

- 상태: QUEUED
- 우선 대상: 실제 존재하는 Lumberyard / Quarry / Farm / Inn / Cooking/Potion production building.
- 확정되지 않은 새 건물을 임의 추가하지 않는다.

### TASK-037-1 Building Upgrade Audit / Contract

- 상태: QUEUED
- 확인:
  - Building identity.
  - workplace slots.
  - production rate.
  - capacity.
  - visual hooks.
- contract:
  - level.
  - cost.
  - modifier set.
- 완료조건:
  - 최소 공통 contract.

### TASK-037-2 Production / Capacity Upgrade

- 상태: QUEUED
- 요구사항:
  - 현재 건물에 의미 있는 modifier만 적용.
  - production/capacity/worker slots 중 설계 근거 있는 항목만.
  - exact 수치 `DESIGN_TUNING`.
  - upgrade 반복 duplicate multiplier 금지.
- 완료조건:
  - level 변화 → 실제 생산/용량 변화.

### TASK-037-3 Upgrade UI / Visual Hook

- 상태: QUEUED
- 요구사항:
  - current/next level.
  - cost.
  - effect delta.
  - Quaternius visual variant가 있으면 hook.
- HUMAN_CHECK:
  - 마을 성장 변화가 읽히는지.
- 완료조건:
  - UI PASS.

### TASK-037-4 Building Upgrade Regression

- 상태: QUEUED
- 완료조건:
  - build → assign → produce → upgrade → DAY/NIGHT production PASS.

---

## TASK-038 Herb Automation

- 상태: QUEUED
- 설계: 야생 약초 → 약초밭/온실 → Herbalist 자동화. 초기 직접 Player 채집을 새로 만들지 않는다.

### TASK-038-1 Herb / Potion Runtime Audit

- 상태: QUEUED
- 확인:
  - Herb resource.
  - wild source.
  - Farm/production building.
  - Worker Assignment.
  - Potion material consumption.
- 완료조건:
  - automation owner 결정.

### TASK-038-2 Automation Building

- 상태: QUEUED
- 요구사항:
  - `GAME_DESIGN.md`에 Herb Garden/Greenhouse 등이 실제 정의되어 있으면 그중 현재 단계에 맞는 1개 사용.
  - 정의가 충돌/부재하면 임의 건물 확정하지 않고 `NEEDS_DESIGN`.
  - Workplace slots/production data 기존 contract 재사용.
- 완료조건:
  - building identity 확정/구현.

### TASK-038-3 Herbalist Worker

- 상태: QUEUED
- 요구사항:
  - 기존 Worker Assignment 재사용.
  - spawn/despawn lifecycle 기존 규칙.
  - herb produce/deposit.
  - Navigation3D.
  - duplicate worker assignment 금지.
- 완료조건:
  - assign → produce → deposit PASS.

### TASK-038-4 Herb Automation Regression

- 상태: QUEUED
- 완료조건:
  - wild herb source + automated herb + Potion production 연결 PASS.

---

## TASK-039 Advanced Cooking

- 상태: QUEUED
- LOCK: Food는 필수 장기/사전 준비. raw food는 가능하지만 효율 낮음. Potion 역할과 섞지 않는다.

### TASK-039-1 Food Runtime Audit

- 상태: QUEUED
- 확인:
  - raw food.
  - recipe.
  - cooking building/worker.
  - consumption.
  - buff pipeline.
  - quality/tier 기존 데이터.
- 완료조건:
  - 확장 지점 확정.

### TASK-039-2 Food Quality

- 상태: QUEUED
- 요구사항:
  - 기존 기획의 quality grade가 있으면 유지.
  - 최소 3 tier vertical slice.
  - quality가 단순 RNG-only 결과가 되지 않음.
  - efficiency/buff strength/duration 중 현재 확정된 항목만.
- 완료조건:
  - quality data/consumption PASS.

### TASK-039-3 Recipe Expansion

- 상태: QUEUED
- 요구사항:
  - 다중 ingredient.
  - recipe data-driven.
  - raw/crop ingredient 연결.
  - negative ingredient 금지.
  - duplicate output 금지.
- 완료조건:
  - multiple recipe production PASS.

### TASK-039-4 Long-duration Food Effect

- 상태: QUEUED
- 요구사항:
  - 기존 설계에 확정 buff가 있으면 적용.
  - 없으면 modifier hook만 두고 `NEEDS_DESIGN` 또는 `DESIGN_TUNING`을 내용에 맞게 기록.
  - combat 중 Potion처럼 즉시 조건부 소비 금지.
  - DeathRecord에 temporary food effect snapshot 금지.
- 완료조건:
  - Food/Potion 역할 분리.

### TASK-039-5 Cooking Regression

- 상태: QUEUED
- 완료조건:
  - Farm → ingredient → Cook → Quality Meal → consumption → NIGHT/Dungeon PASS.

---

## TASK-040 Advanced Potion

- 상태: QUEUED
- LOCK: Potion은 별도 슬롯, 자동전투 중 조건부 위기 대응.

### TASK-040-1 Potion Runtime Audit

- 상태: QUEUED
- 확인:
  - current potion definitions.
  - slot count.
  - auto-use condition.
  - consume ownership.
  - cooldown/multi-consume guard.
- 완료조건:
  - extension owner 확정.

### TASK-040-2 Potion Definition Expansion

- 상태: QUEUED
- 요구사항:
  - 기존 설계의 Potion type 우선.
  - 최소 2 type.
  - effect/condition data-driven.
  - 새로운 고위험 effect 임의 발명 금지.
- 완료조건:
  - definition validation.

### TASK-040-3 Auto-use Conditions

- 상태: QUEUED
- 요구사항:
  - HP threshold / battle condition 등 기존 규칙.
  - cooldown.
  - one condition event → one consume.
  - empty slot/no item 안전.
  - Player manual spam button 금지.
  - Pause/1x/2x duplicate consume 금지.
- 완료조건:
  - deterministic consume PASS.

### TASK-040-4 Potion Regression

- 상태: QUEUED
- 완료조건:
  - multiple Potion conditions + Overworld/Dungeon combat + Food separation PASS.

---

## PHASE-STOP-3 Enemy / Village Progression 종료 경계

- 상태: QUEUED
- 확인:
  - TASK-033~040 완료.
  - mixed wave 정상.
  - building/defense upgrade 정상.
  - Food/Potion 역할 분리.
  - Player direct combat 없음.
  - 임시 파일 없음.
- 종료 회귀:
  - Wave strategy.
  - Village production.
  - Cooking/Potion.
  - Dungeon.
- 완료조건:
  - PASS.
  - 다음 파일 자동 시작 금지.
