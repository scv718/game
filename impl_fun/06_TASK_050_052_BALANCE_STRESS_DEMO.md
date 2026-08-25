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

> **050 Balance → 051 Stress/Performance → 052 Demo Vertical Slice**
>
> 목표: 기능을 더 늘리지 않고 현재 시스템을 실제 Demo로 완주 가능한 수준까지 검증/튜닝한다.

---

## TASK-050 Balance Pass

- 상태: QUEUED
- 대상:
  - Wood/Stone.
  - Building cost.
  - Worker.
  - Food/Crops/Cooking.
  - Potion.
  - Inn/Morale.
  - Threat/Wave.
  - Enemy/Elite.
  - Equipment/Class/Skill.
  - Dungeon reward/difficulty.
  - Wall/Gate.
  - Boss/Siege.

### TASK-050-1 Balance Instrumentation / Metrics

- 상태: QUEUED
- 수집:
  - DAY production rates.
  - resource income/spend.
  - Food surplus/deficit.
  - worker utilization.
  - first NIGHT readiness.
  - mercenary survival/death.
  - wave duration.
  - potion use count.
  - Dungeon duration/reward.
  - Threat change.
  - Gate/facility damage.
- 요구사항:
  - debug metrics가 release gameplay를 바꾸지 않음.
  - deterministic simulation 가능한 값은 test output으로 기록.
- 완료조건:
  - 최소 플레이 세션 metrics 수집 가능.

### TASK-050-2 Economy Balance

- 상태: QUEUED
- 목표:
  - 초반 soft-lock 방지.
  - 무한 surplus 방지.
  - Worker 자동화 확장 의미.
  - Food mandatory loop가 과도한 chores가 되지 않음.
  - Equipment/Potion 제작이 모든 자원을 독점하지 않음.
- 원칙:
  - tuning은 config/data 변경 중심.
  - 새 시스템 추가로 문제를 가리지 않는다.
- 완료조건:
  - economy simulation/regression PASS.
  - 주요 수치 `DESIGN_TUNING` 기록.

### TASK-050-3 Combat / Threat / Dungeon Balance

- 상태: QUEUED
- 목표:
  - 자동승리/즉사 양극단 방지.
  - Tactical Command 가치.
  - class/equipment/potion 준비 가치.
  - Dungeon Threat control 가치.
  - Elite/Wave composition 구분.
  - Boss 준비의 의미.
- HUMAN_CHECK:
  - DAY 준비가 NIGHT 결과에 체감상 영향을 주는지.
- 완료조건:
  - combat metrics + test PASS.

### TASK-050-4 Balance Regression Snapshot

- 상태: QUEUED
- 요구사항:
  - 핵심 config/tuning 값 목록 기록.
  - 테스트용 cheat 수치와 production 값 분리.
  - regression baseline 생성.
- 완료조건:
  - tuning 변경 후 비교 가능한 baseline.

---

## TASK-051 Large Scale Stress / Performance

- 상태: QUEUED
- 원칙: 실제 병목을 측정한 뒤만 최적화한다. 추측성 대규모 최적화 금지.

### TASK-051-1 Population / Navigation Stress

- 상태: QUEUED
- 검증:
  - Worker 다수.
  - Mercenary 다수.
  - Enemy/Elite/Ghost mixed wave.
  - Buildings/resources.
  - Navigation3D rebuild/path.
  - repeated assignments.
- 측정:
  - frame time/FPS 가능한 범위.
  - node count.
  - nav stall.
- 완료조건:
  - duplicate actor/stale nav/runaway process 없음.

### TASK-051-2 Rendering Stress

- 상태: QUEUED
- 검증:
  - Trees/Rocks/Props.
  - Shadows.
  - zoom-out.
  - DAY/NIGHT.
  - VFX.
  - Characters.
- 원칙:
  - Quaternius visual 방향 훼손 금지.
  - 실제 병목 근거 없이 LOD/occlusion framework 과설계 금지.
- 완료조건:
  - 병목 기록 + 필요한 최소 개선.

### TASK-051-3 Long Session Stability

- 상태: QUEUED
- 시나리오:
  - repeated DAY/NIGHT.
  - build/remove/upgrade.
  - worker reassign.
  - Expedition.
  - Dungeon.
  - Wave/Ghost.
  - Save/Load.
  - Siege.
- 검증:
  - memory runaway.
  - orphan nodes/resources.
  - stale refs.
  - signal/timer leak.
  - duplicate reward/wave.
- 완료조건:
  - long-session PASS.

### TASK-051-4 Performance Regression Baseline

- 상태: QUEUED
- 요구사항:
  - 대표 stress scenario와 측정치 기록.
  - 개선 전/후 비교.
  - known bottleneck 분리.
- 완료조건:
  - Demo 이전 baseline 확보.

---

## TASK-052 Demo Vertical Slice

- 상태: QUEUED
- 목표: Steam Demo 후보가 될 수 있는 하나의 완결된 플레이 루프를 처음부터 끝까지 끊김 없이 실행한다.
- 신규 핵심 시스템 추가보다 blocker 수정/연결/폴리시를 우선한다.

### TASK-052-1 Demo Start State / New Game

- 상태: QUEUED
- 요구사항:
  - 정상 starting resources.
  - Tutorial start.
  - Camera + Mouse.
  - debug용 과도 자원은 별도 development option.
  - production build에는 cheat 상태 유입 금지.
- 완료조건:
  - New Game 정상.

### TASK-052-2 Early DAY Loop

- 상태: QUEUED
- 검증:
  - basic resources.
  - Lumberyard/Quarry/Farm.
  - Worker.
  - Food/Cooking.
  - Inn/Mercenary.
  - Equipment/Potion 준비.
- 완료조건:
  - first NIGHT 준비까지 soft-lock 없음.

### TASK-052-3 First NIGHT → Threat → Expedition/Dungeon Loop

- 상태: QUEUED
- 검증:
  - NIGHT Wave.
  - Tactical Command.
  - Threat.
  - Scout dispatch.
  - Dungeon discovery.
  - preparation.
  - Dungeon encounter.
  - clear.
  - Threat delay/reduction.
- 완료조건:
  - 전략 루프 연결 PASS.

### TASK-052-4 Advanced Wave / Death / Ghost / Defense

- 상태: QUEUED
- 검증:
  - stronger mixed Wave.
  - lethal death.
  - Death Ledger.
  - Ghost Return.
  - equipment/class/skill.
  - defense upgrade.
- 완료조건:
  - Ghost 핵심 hook 체감 가능한 상태.

### TASK-052-5 Siege / Aftermath / Save-Load

- 상태: QUEUED
- 검증:
  - Siege warning/preparation.
  - Boss.
  - facility damage.
  - support NPC outcome.
  - aftermath.
  - save.
  - reload.
  - next DAY continuity.
- 완료조건:
  - Demo 장기 loop 완결.

### TASK-052-6 Demo UX / Visual Acceptance + Final Regression

- 상태: QUEUED
- 필수 Screenshot/검토:
  - DAY village.
  - Worker production.
  - Farm/Food.
  - Mercenary equipment/class.
  - NIGHT tactical.
  - mixed Wave/Elite.
  - Ghost.
  - Dungeon preparation.
  - Dungeon encounter.
  - upgraded defense.
  - Siege/Boss.
  - Aftermath.
- HUMAN_CHECK:
  - 첫 10분 안에 목적이 이해되는지.
  - 3D 비주얼이 실제 출시 방향으로 느껴지는지.
  - 마을 성장 변화가 보이는지.
  - DAY/NIGHT 감각이 명확히 다른지.
  - 직접 전투하지 않아도 판단할 것이 충분한지.
  - Dungeon이 기존 시스템에 목적을 부여하는지.
  - Food/Potion/Equipment가 서로 다른 준비 요소인지.
  - Ghost Return이 고유한 핵심 경험인지.
  - Siege/Boss가 장기 준비의 결과처럼 느껴지는지.
- 자동검증:
  - Camera.
  - Resource.
  - Building/Upgrade.
  - Worker.
  - Food/Farm/Cooking.
  - Potion.
  - Inn/Morale.
  - Mercenary/Equipment/Class/Skill.
  - Enemy/Elite/Wave/Threat.
  - Tactical/Gate.
  - Death Ledger/Ghost.
  - Scout/Expedition/Dungeon.
  - Boss/Siege/Aftermath.
  - Resident/NPC/Animal category.
  - Save/Load.
  - Tutorial.
  - Audio event safety.
  - repeated DAY/NIGHT.
  - no duplicate actor.
  - no freed reference.
  - no stale navigation.
  - no duplicate reward.
  - no ghost recursion.
  - no negative resource.
  - no duplicate wave.
  - no potion multi-consume.
- 완료조건:
  - 실행 가능한 전체 regression PASS.
  - 미실행 테스트/known blocker 명시.
  - 기능 blocker/치명적 visual blocker 없음.

---

# POST-DEMO DEFERRED LOCK

> Demo Vertical Slice 이후 별도 Queue에서만 검토:
>
> - 추가 Dungeon biome/content.
> - 추가 Boss.
> - 추가 Mercenary classes.
> - 추가 Equipment rarity/content.
> - 추가 Recipe/Potion.
> - 추가 Enemy faction.
> - Story/Narrative campaign.
> - Achievements.
> - Steam integration.
> - Localization.
> - Accessibility.
> - Controller support.
> - Full settings/graphics options.
> - Workshop/Mod support.
> - Multiplayer.
>
> 실제 Demo 플레이 피드백 전 자동 구현 금지.

---

## PRODUCTION-ROADMAP-STOP Final 종료 경계

- 상태: QUEUED
- 필수 확인:
  - TASK-026~052 실행 가능한 항목 처리.
  - `NEEDS_DESIGN` / `DESIGN_TUNING` / `HUMAN_CHECK` 목록 정리.
  - Main Runtime 3D.
  - Camera + Mouse management.
  - Player direct combat/반복 노동 없음.
  - DAY/NIGHT 정상.
  - duplicate actor/DeathRecord/Ghost/Wave/reward 없음.
  - Ghost recursion 없음.
  - negative resource 없음.
  - Potion multi-consume 없음.
  - freed reference/stale navigation/orphan resource 없음.
  - parser/import/save corruption 없음.
  - 임시 파일 없음.
- 최종 보고:
  - DONE.
  - FIX.
  - NEEDS_DESIGN.
  - DESIGN_TUNING.
  - HUMAN_CHECK.
  - 미실행 테스트.
  - known blocker.
  - performance findings.
  - asset/license additions.
  - Demo run 결과.
- 종료조건:
  - Demo Final Regression 수행.
  - 결과 보고 작성.
  - POST-DEMO DEFERRED 기능 미시작 확인.
  - **이 TASK 이후 신규 기능 자동 시작 금지.**
