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

> **029 Equipment → 030 Equipment Production → 031 Mercenary Classes → 032 Mercenary Skills**
>
> 목표: 용병의 성장/준비 선택지를 만들되 자동전투 원칙을 유지한다.

---

## TASK-029 Equipment Progression

- 상태: QUEUED
- 목표: Weapon/Armor 최소 장비 체계와 Mercenary stat modifier pipeline을 구축한다.

### TASK-029-1 Equipment Runtime Audit

- 상태: QUEUED
- 확인:
  - Equipment Shop 기존 역할.
  - Inventory/resource/item data.
  - Mercenary base stat 계산 위치.
  - Potion slot과 UI ownership.
  - save hook 존재 여부.
- 규칙:
  - 이미 item/equipment 구조가 있으면 재사용.
  - Equipment Shop은 완제품 구매/관리 성격을 유지하고 primary crafting owner로 임의 변경하지 않는다.
- 완료조건:
  - item owner/stat owner/UI owner 확정.

### TASK-029-2 Equipment Definition

- 상태: QUEUED
- 최소 필드:
  - equipment_id.
  - display_name.
  - slot: WEAPON / ARMOR.
  - tier/quality.
  - stat_modifiers.
  - compatible_class/tag.
  - visual_hook.
  - metadata.
- 첫 범위:
  - Weapon 1종.
  - Armor 1종.
- 금지:
  - durability.
  - 강화 확률.
  - 거대 random affix framework.
  - 확정되지 않은 rarity loot casino.
- 완료조건:
  - data validation PASS.

### TASK-029-3 Mercenary Equipment Slots / Modifier Pipeline

- 상태: QUEUED
- 요구사항:
  - Weapon/Armor equip/unequip.
  - slot compatibility.
  - same item duplicate equip 방지.
  - base stat object 영구 변조 금지.
  - `effective_stat = base + equipment + existing allowed modifiers` 형태의 단일 계산 경로.
  - equip/unequip 반복에도 modifier 누적 금지.
  - Potion slot과 완전 분리.
- 자동검증:
  - equip → stat 변화.
  - unequip → 원복.
  - repeated equip no duplicate modifier.
  - invalid slot 거부.
- 완료조건:
  - modifier pipeline 안정.

### TASK-029-4 Equipment UI / Combat Regression

- 상태: QUEUED
- 요구사항:
  - Roster detail에서 현재 장비/변경 가능.
  - combat actor spawn 시 effective stats 반영.
  - Dungeon/Overworld 모두 동일 stat source 사용.
  - dead Mercenary 장비 정책은 기존 design/data ownership에 따르며 임의 삭제 금지.
- HUMAN_CHECK:
  - 비교/교체 정보가 이해 가능한지.
- 완료조건:
  - equip → NIGHT/Dungeon combat 반영 PASS.

---

## TASK-030 Equipment Production

- 상태: QUEUED
- 목표: 재료 → 제작 → Equipment → 장착의 최소 생산 루프를 연결한다.

### TASK-030-1 Production Building Audit

- 상태: QUEUED
- 확인:
  - Blacksmith/Smithy/Equipment Shop/production building 실제 존재 여부.
  - Worker assignment/workplace contract.
  - recipe/crafting foundation.
  - VillageResources/material ownership.
- 원칙:
  - 기존 생산 건물이 있으면 재사용.
  - 이름만 보고 Equipment Shop을 제작 건물로 임의 변경 금지.
  - owner 근거가 없으면 `NEEDS_DESIGN`.
- 완료조건:
  - production owner 결정.

### TASK-030-2 Equipment Recipe Data

- 상태: QUEUED
- 최소 필드:
  - recipe_id.
  - material costs.
  - output equipment_id.
  - craft duration.
  - required building.
  - worker requirement hook.
- 요구사항:
  - exact cost/time은 `DESIGN_TUNING` 가능.
  - negative material 금지.
  - recipe completion 중복 지급 금지.
- 완료조건:
  - recipe validation PASS.

### TASK-030-3 Craft Runtime / Output

- 상태: QUEUED
- 요구사항:
  - material validation.
  - start craft.
  - GameTime/production tick 기존 정책과 일치.
  - craft 완료 정확히 1회.
  - output이 equipment inventory/storage owner로 전달.
  - worker unassign/building invalid 시 안전 처리.
- 완료조건:
  - material → craft → output PASS.

### TASK-030-4 Production Regression

- 상태: QUEUED
- 시나리오:
  1. material 확보.
  2. production building.
  3. worker 조건 충족.
  4. craft.
  5. output.
  6. equip.
  7. NIGHT combat.
  8. repeated completion duplicate 없음.
- 완료조건:
  - 전체 production/equip loop PASS.

---

## TASK-031 Mercenary Classes

- 상태: QUEUED
- 목표: 자동전투에서 역할이 실제로 다른 Mercenary class 기반을 만든다.
- 원칙: `GAME_DESIGN.md`의 확정 class가 있으면 사용. 없으면 이름/서사/스킬을 발명하지 말고 최소 역할 archetype만 구현한다.

### TASK-031-1 Existing Class / Asset Audit

- 상태: QUEUED
- 확인:
  - 현재 Mercenary class id.
  - stat data.
  - attack range/movement.
  - equipment compatibility.
  - Quaternius character/outfit/weapon variation.
  - Tactical AI에서 class dependency 존재 여부.
- 완료조건:
  - 재사용 경계와 최소 추가 class 역할 확정.

### TASK-031-2 Class Definition

- 상태: QUEUED
- 최소 역할:
  - frontline/melee.
  - ranged.
  - defensive/support 확장점.
- 최소 필드:
  - class_id.
  - base stat profile.
  - attack profile/range.
  - equipment compatibility.
  - skill hook.
  - visual outfit hook.
- 금지:
  - 확정되지 않은 복잡한 class tree.
  - Player-controlled abilities.
- 완료조건:
  - 최소 2 class가 data로 구분.

### TASK-031-3 Class Combat Identity

- 상태: QUEUED
- 요구사항:
  - range/movement/stat 차이가 실제 AI behavior에 반영.
  - ranged가 melee range까지 불필요하게 붙지 않도록 기존 AI를 최소 확장.
  - defensive/support 역할이 아직 설계되지 않았으면 hook만 두고 효과 발명 금지.
  - Equipment modifier와 합성.
  - Tactical command priority 유지.
- 자동검증:
  - class별 target/attack range.
  - equip modifier.
  - retreat/regroup/focus.
- 완료조건:
  - 최소 2 class 역할 차이 실제 combat PASS.

### TASK-031-4 Class Visual / Roster Regression

- 상태: QUEUED
- 요구사항:
  - Quaternius existing variation 우선.
  - roster에서 class 표시.
  - Ghost identity snapshot에 class id 유지.
- HUMAN_CHECK:
  - 전장에서 class가 구분되는지.
- 완료조건:
  - class regression PASS.

---

## TASK-032 Mercenary Skill System

- 상태: QUEUED
- LOCK: Skill은 Mercenary AI가 조건에 따라 자동 사용한다. Player가 action bar에서 직접 난사하지 않는다.

### TASK-032-1 Skill Runtime Audit / Contract

- 상태: QUEUED
- 확인:
  - combat tick.
  - target selection.
  - cooldown/time scale.
  - existing effect/damage APIs.
  - Ghost snapshot.
- 완료조건:
  - skill evaluation owner/execute hook 확정.

### TASK-032-2 Skill Definition

- 상태: QUEUED
- 필드:
  - skill_id.
  - owner_class/tag.
  - trigger condition.
  - cooldown.
  - target rule.
  - effect.
  - range.
  - visual/audio hook.
  - metadata.
- 첫 범위:
  - 실제 설계가 있으면 그중 1~2종.
  - 없으면 검증용 최소 deterministic skill만 구현하되 새로운 class fantasy를 발명하지 않는다.
- 완료조건:
  - definition validation PASS.

### TASK-032-3 Auto Skill Execution

- 상태: QUEUED
- 요구사항:
  - AI condition false → 사용 안 함.
  - condition true + cooldown ready → 정확히 1회.
  - invalid/freed target 안전.
  - Pause/1x/2x에서 duplicate cast 없음.
  - skill 사용이 basic attack timer를 깨뜨리지 않음.
  - direct Player cast API/UI 금지.
- 완료조건:
  - deterministic auto skill PASS.

### TASK-032-4 Ghost Skill Preservation

- 상태: QUEUED
- 요구사항:
  - DeathRecord/Ghost source에 skill identity snapshot 유지 가능한 범위 연결.
  - temporary cooldown/current target은 snapshot 대상 아님.
  - Ghost가 원본 class/skill logic을 재사용하고 별도 복제 skill tree를 만들지 않음.
  - Ghost death recursion 없음.
- 완료조건:
  - skill identity persistence PASS.

### TASK-032-5 Skill 통합 회귀

- 상태: QUEUED
- 검증:
  - Class.
  - Equipment.
  - Potion.
  - Tactical commands.
  - Overworld.
  - Dungeon.
  - Ghost identity hook.
  - Pause/1x/2x.
- HUMAN_CHECK:
  - Skill이 자동전투를 풍부하게 하되 플레이어가 직접 액션 캐릭터를 조작하는 느낌이 아닌지.
- 완료조건:
  - 통합 PASS.

---

## PHASE-STOP-2 Equipment / Mercenary 종료 경계

- 상태: QUEUED
- 확인:
  - TASK-029~032 완료.
  - Player direct skill 없음.
  - modifier duplicate 없음.
  - Potion/Equipment slot 분리.
  - Ghost skill identity hook 정상.
  - 임시 파일 없음.
- 종료 회귀:
  - Equipment.
  - Production.
  - Class.
  - Skill.
  - NIGHT/Dungeon combat.
- 완료조건:
  - 회귀 PASS.
  - 다음 파일 자동 시작 금지.
