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

> **026 Scout/Expedition → 027 Dungeon → 028 Dungeon↔Threat**
>
> 목표: 직접 탐험 없는 관리형 탐사와 Dungeon 자동전투를 실제 전략 루프로 연결한다.

---

## TASK-026 Scout / Expedition Foundation

- 상태: QUEUED
- 목표: World Map에서 탐사 지역을 선택하고 persistent identity 기반 Expedition을 파견하여 시간 경과 후 발견/결과/귀환까지 처리한다.
- 핵심 흐름: `UNKNOWN → EXPLORING → DISCOVERED`, `READY → OUTBOUND → EXPLORING → RETURNING → COMPLETED`.
- Player가 Scout/Party Actor를 직접 조작하는 기능은 금지.

### TASK-026-1 Exploration Runtime Audit

- 상태: QUEUED
- 설명: 신규 구현 전에 현재 Exploration/WorldMap/Region/Threat/Roster 구조를 조사하고 재사용 경계를 확정한다.
- 확인 대상:
  - `ExplorationRegion` 또는 동등한 region data.
  - `UNKNOWN/EXPLORING/DISCOVERED` state.
  - World Map marker/region click flow.
  - 기존 Scout/Expedition placeholder.
  - GameTime/day progression API.
  - Dungeon candidate/POI marker.
  - Threat 조회/변경 API.
  - Mercenary/Resident/Worker stable identity API.
- 규칙:
  - 이 태스크는 audit 중심이다. 기존 구조가 명백히 잘못된 경우가 아니면 대규모 수정하지 않는다.
  - 실제 파일명/class/API를 구현기록에 적는다.
  - 서로 중복되는 Region state가 여러 군데 있으면 authoritative owner를 결정하되 근거가 없으면 `NEEDS_DESIGN`.
- 자동검증:
  - 기존 exploration/map 관련 테스트가 있으면 실제 실행.
  - 관련 test가 없으면 최소 smoke/import parse를 실행.
- 완료조건:
  - 재사용할 데이터 owner/API/Scene이 명확하다.
  - 구현해야 할 최소 gap 목록이 작성된다.
  - Player direct exploration 경로가 새로 필요하지 않음을 확인한다.

### TASK-026-2 Expedition Party Data

- 상태: QUEUED
- 설명: Runtime Actor와 분리된 Expedition persistent data를 구현한다.
- 최소 필드:
  - expedition_id.
  - destination_region_id.
  - member_identity_ids.
  - status.
  - departure_day/time.
  - outbound_duration.
  - exploration_duration.
  - return_duration.
  - progress/phase_started_at.
  - result.
  - discovered_feature_ids.
  - metadata.
- 상태 최소값:
  - READY.
  - OUTBOUND.
  - EXPLORING.
  - RETURNING.
  - COMPLETED.
  - CANCELED는 실제 요구가 없으면 구현하지 않는다.
- 요구사항:
  - Node/Actor reference 저장 금지.
  - 동일 Mercenary identity가 동시에 둘 이상의 active Expedition에 편성되지 않게 한다.
  - dead/unavailable member는 출발 validation 실패.
  - member list 순서는 deterministic하게 유지.
  - Expedition 완료/귀환 후 roster availability가 복구되어야 한다.
- 금지:
  - 범용 Party Framework.
  - Dungeon combat 선행 구현.
  - Food/Supply 상세 소비 선행 구현.
- 자동검증:
  - create.
  - duplicate expedition_id 차단.
  - duplicate member 차단.
  - unavailable/dead member 거부.
  - serialize 가능한 순수 data 확인.
- 완료조건:
  - create/start/progress/complete data lifecycle이 Actor 없이 안정적으로 동작.

### TASK-026-3 Expedition Runtime / Time Progression

- 상태: QUEUED
- 설명: Expedition 상태를 GameTime에 따라 진행시키는 최소 runtime owner를 구현한다.
- 요구사항:
  - GameTime 기반으로 OUTBOUND → EXPLORING → RETURNING → COMPLETED 전환.
  - frame-rate 독립.
  - Pause/1x/2x 등 기존 time policy와 충돌하지 않음.
  - DAY/NIGHT phase 전환 때문에 progress가 중복 적용되지 않음.
  - 동일 expedition에 timer/signal 중복 연결 금지.
  - reload/reconstruction을 고려해 절대 Node timer reference를 persistent data에 저장하지 않음.
- Edge Case:
  - member가 파견 중 death 처리될 수 있는 구조가 아직 없다면 임의 death event를 만들지 않고 hook만 둔다.
  - destination이 invalid/freed marker여도 region_id data로 안전 처리.
- 자동검증:
  - 동일 elapsed에서 1x/2x 정책이 기존 GameTime 정의와 일치.
  - repeated DAY/NIGHT에서 duplicate transition 없음.
- 완료조건:
  - deterministic time progression PASS.
  - active expedition query 가능.

### TASK-026-4 Scout Dispatch / Region Discovery

- 상태: QUEUED
- 설명: World Map의 UNKNOWN Region에서 Expedition을 시작하고 탐사 완료 시 Region/POI를 DISCOVERED 처리한다.
- 요구사항:
  - UNKNOWN만 신규 explore 시작 가능.
  - active EXPLORING Region에 duplicate dispatch 금지.
  - 완료 시 Region `DISCOVERED`.
  - 발견 결과는 첫 vertical slice에서 deterministic 고정 결과 사용 가능.
  - NE Dungeon Candidate 또는 현재 실제 Dungeon candidate를 발견 결과에 연결.
  - World Map marker/label이 발견 상태를 즉시 반영.
  - Player가 해당 위치로 직접 이동하지 않음.
- 금지:
  - random event framework.
  - Dungeon instance 실행.
  - Scout Actor 직접 조작.
- 자동검증:
  - UNKNOWN → EXPLORING → DISCOVERED.
  - duplicate dispatch 차단.
  - Map marker update.
- 완료조건:
  - 최소 1개 Region discovery loop PASS.

### TASK-026-5 Expedition Return / Roster Availability

- 상태: QUEUED
- 설명: Expedition 완료 후 참여 member의 availability와 결과를 안전하게 복귀시킨다.
- 요구사항:
  - 파견 중 member는 Tavern/Inn/다른 Expedition에서 중복 편성되지 않음.
  - RETURNING 완료 후 roster에서 다시 사용 가능.
  - member identity가 사라졌거나 dead라면 freed reference 없이 결과 처리.
  - reward는 이 태스크에서 구현하지 않고 result hook만 제공.
- 자동검증:
  - dispatch 중 unavailable.
  - return 후 available.
  - repeated complete 호출로 duplicate return 없음.
- 완료조건:
  - roster identity/reference 안정.

### TASK-026-6 Scout / Expedition 통합 검증

- 상태: QUEUED
- 시나리오:
  1. UNKNOWN Region 확인.
  2. Mercenary/Scout 역할에 사용할 현재 허용 member identity 준비.
  3. Expedition 생성.
  4. duplicate member/duplicate dispatch 거부.
  5. 출발.
  6. OUTBOUND progress.
  7. EXPLORING.
  8. Region DISCOVERED.
  9. Dungeon/POI hook 생성.
  10. RETURNING.
  11. COMPLETED.
  12. member availability 복구.
  13. DAY/NIGHT 반복.
  14. World Map 상태 유지.
- 회귀:
  - Camera/Mouse.
  - Worker.
  - Mercenary Roster.
  - DAY/NIGHT.
  - Threat read API.
  - Death Ledger.
- HUMAN_CHECK:
  - 직접 이동 없이도 "지역을 탐사한다"는 의도가 UI에서 이해되는지.
- 완료조건:
  - 전체 loop 자동검증 PASS.
  - HUMAN_CHECK만 남으면 DONE.

---

## TASK-027 Dungeon Vertical Slice

- 상태: QUEUED
- 목표: 발견된 Dungeon을 준비하고 Mercenary Party를 보내 자동전투 Encounter를 수행한 뒤 clear/retreat/fail 결과와 보상을 받고 귀환한다.
- LOCK:
  - Player 직접 전투 없음.
  - Player는 Party/Food/Potion/Equipment/위험/Retreat 판단 담당.
  - Mercenary Combat AI와 Tactical Command는 기존 시스템을 재사용한다.

### TASK-027-1 Dungeon Definition / Persistent Instance Data

- 상태: QUEUED
- 최소 필드:
  - dungeon_id.
  - region_id.
  - display_name.
  - state: DISCOVERED / READY / IN_PROGRESS / CLEARED / FAILED.
  - difficulty/tier.
  - encounter_ids 또는 encounter definition.
  - reward_table_id.
  - completion_count 또는 1회성 여부 hook.
  - threat_reward/hook.
  - metadata.
- 요구사항:
  - Runtime combat Actor reference 저장 금지.
  - 첫 vertical slice Dungeon 1종만으로 충분.
  - 확정되지 않은 procedural dungeon generator 금지.
  - reward table은 data-driven 최소 구조.
- 완료조건:
  - Dungeon 1종 data-driven 생성/조회/state 전환 PASS.

### TASK-027-2 Dungeon Preparation / Validation

- 상태: QUEUED
- 설명: Dungeon 출발 전에 Party와 준비 자원을 검증하는 UI/서비스를 구현한다.
- 표시/입력:
  - Party member.
  - Food/Supply.
  - Potion slots.
  - Equipment summary.
  - Dungeon 위험도.
  - 예상 reward 정보 중 현재 공개 가능한 값.
- validation:
  - dead/unavailable/expedition 중 member 거부.
  - 동일 member 중복 거부.
  - 필수 Food 정책이 기존 설계에 있다면 적용.
  - Potion 미장착은 허용 여부를 기존 설계에 따름.
  - Equipment 미장착은 기존 설계에 따름.
- 금지:
  - 신규 Food/Potion/Equipment 규칙 발명.
  - Player 직접 dungeon entry.
- HUMAN_CHECK:
  - 출발 전에 무엇을 준비해야 하는지 읽히는지.
- 완료조건:
  - valid party 출발 가능.
  - invalid party 이유가 명확히 표시.

### TASK-027-3 Dungeon Runtime Scene / Actor Lifecycle

- 상태: QUEUED
- 설명: Dungeon Encounter용 최소 Runtime 공간과 Party/Enemy spawn-cleanup lifecycle을 만든다.
- 요구사항:
  - 기존 3D Combat Actor/Navigation3D를 최대한 재사용.
  - Overworld Actor와 Dungeon Actor를 중복 생성하지 않는다.
  - Party는 persistent Mercenary identity로 spawn.
  - encounter 종료 시 살아 있는 Actor를 roster data로 복귀하고 Runtime Actor 정리.
  - scene unload/cleanup은 Death Ledger death로 기록하지 않는다.
  - Dungeon scene/arena는 첫 vertical slice 1종이면 충분.
- 금지:
  - procedural room generator.
  - Player Avatar.
  - 신규 Combat Framework.
- 자동검증:
  - spawn 1회.
  - cleanup 1회.
  - duplicate actor 없음.
  - roster identity 유지.
- 완료조건:
  - Dungeon runtime enter/exit lifecycle 안정.

### TASK-027-4 Dungeon Auto Combat / Tactical Command

- 상태: QUEUED
- 설명: Dungeon Encounter에서 기존 Mercenary Auto Combat과 가능한 Tactical Command를 재사용한다.
- 요구사항:
  - target acquisition/attack/death는 기존 Combat AI 재사용.
  - Dungeon 방어 zone이 의미 없으면 Defense Zone을 억지로 적용하지 않는다.
  - Focus Target / Regroup / Retreat 등 Dungeon에서 의미 있는 명령만 명시적으로 활성화.
  - 명령 우선순위가 Overworld와 충돌하지 않음.
  - Player direct attack/skill cast 없음.
- Edge Case:
  - unreachable enemy permanent chase 금지.
  - actor death/freed 후 stale target 금지.
- 완료조건:
  - 최소 Encounter에서 auto combat + tactical decision PASS.

### TASK-027-5 Potion Auto-consume / Food Preparation Hook

- 상태: QUEUED
- 설명: 기존 Food/Potion 기반을 Dungeon 전투에 연결한다.
- 요구사항:
  - Food는 출발 전/장기 preparation 효과만.
  - Potion은 별도 slot에서 기존 조건에 따라 자동 consume.
  - Potion multi-consume/동일 frame 중복 소비 금지.
  - Dungeon 때문에 신규 Potion effect를 발명하지 않는다.
  - temporary buff를 DeathRecord identity snapshot에 섞지 않는다.
- 자동검증:
  - condition false → 미소비.
  - condition true → 정확히 1회.
  - slot empty 안전.
- 완료조건:
  - 기존 Food/Potion 역할 분리 유지.

### TASK-027-6 Dungeon Death / Retreat / Party Wipe

- 상태: QUEUED
- 설명: Dungeon 전투 종료 조건을 명확히 처리한다.
- lethal death:
  - Mercenary lethal death → 기존 Death Ledger 기록.
  - cleanup/despawn → 기록 금지.
  - dead Mercenary roster alive 상태 기존 규칙 유지.
- Retreat:
  - Player가 Tactical Retreat를 선택하면 현재 살아 있는 Party가 탈출/종료 state로 전환.
  - Retreat가 즉시 무적 teleport가 되지 않도록 기존 Retreat 의미를 가능한 범위 재사용.
  - 구체적인 escape duration이 미정이면 configurable `DESIGN_TUNING`.
- Party Wipe:
  - 모든 Party member lethal death → FAILED.
  - reward clear 지급 금지.
- 완료조건:
  - clear/retreat/wipe가 서로 중복 종료되지 않음.
  - Death Ledger 정확.

### TASK-027-7 Reward / Return

- 상태: QUEUED
- 요구사항:
  - CLEAR/RETREAT/FAIL 결과를 분리.
  - clear reward는 dungeon run당 정확히 1회.
  - retreat/fail reward 정책은 기존 설계가 없으면 0 또는 data hook만 두고 `DESIGN_TUNING`.
  - negative resource/duplicate reward 금지.
  - 살아 있는 member roster 복귀.
  - dead member 자동 부활 금지.
- 완료조건:
  - reward 1회.
  - roster return 안정.

### TASK-027-8 Dungeon 통합 검증

- 상태: QUEUED
- 시나리오:
  1. Region DISCOVERED.
  2. Dungeon DISCOVERED.
  3. Preparation UI.
  4. valid Party/Food/Potion 구성.
  5. Dungeon enter.
  6. Party/Enemy spawn.
  7. auto combat.
  8. Tactical Focus/Regroup 중 적용 가능한 명령.
  9. Potion conditional consume.
  10. Enemy death.
  11. Mercenary lethal death 별도 검증.
  12. clear.
  13. reward 1회.
  14. return.
  15. retreat 별도 시나리오.
  16. party wipe 별도 시나리오.
  17. repeated entry에서 duplicate actor/reward 없음.
- 회귀:
  - Overworld NIGHT combat.
  - Tactical Command.
  - Death Ledger/Ghost candidate.
  - Food/Potion.
  - Roster.
  - DAY/NIGHT.
- HUMAN_CHECK:
  - 직접 싸우지 않아도 준비/명령/퇴각 판단이 충분한지.
- 완료조건:
  - Dungeon vertical slice PASS.

---

## TASK-028 Dungeon ↔ Threat Integration

- 상태: QUEUED
- 핵심: Dungeon clear가 다음 Wave 압박을 감소 또는 지연하여 "위험을 감수하고 던전을 공략할 전략적 이유"를 만든다.

### TASK-028-1 Threat API Audit / Contract

- 상태: QUEUED
- 확인:
  - 현재 Threat owner.
  - increase/reduce/delay API.
  - Wave schedule 연결.
  - HUD signal.
  - duplicate application guard.
- 요구사항:
  - 새로운 ThreatManager를 만들기 전 기존 owner를 우선 재사용.
  - 감소량/지연량만 미정이면 config + `DESIGN_TUNING`.
- 완료조건:
  - Dungeon clear hook을 연결할 authoritative API 확정.

### TASK-028-2 Dungeon Clear Threat Reduction

- 상태: QUEUED
- 요구사항:
  - `CLEARED` 확정 시 run당 정확히 1회 적용.
  - RETREAT/FAILED에는 clear reduction 적용 금지.
  - 동일 Dungeon clear event 재수신으로 duplicate 감소 금지.
  - Threat HUD 즉시 갱신.
  - 다음 Wave schedule이 실제로 변경되어야 함.
- 완료조건:
  - clear 1회 → Threat reduce/delay 1회.
  - duplicate 없음.

### TASK-028-3 Strategic Loop Regression

- 상태: QUEUED
- 시나리오:
  1. Threat 상승.
  2. 다음 Wave 예정 상태 기록.
  3. Dungeon clear.
  4. Threat 감소/지연.
  5. HUD 갱신.
  6. 다음 NIGHT/Wave schedule 변화 확인.
  7. retreat/fail은 감소 없음 확인.
  8. repeated clear callback duplicate 없음.
- HUMAN_CHECK:
  - Dungeon 공략이 Wave 대비와 연결된다는 의미가 UI에서 읽히는지.
- 완료조건:
  - Dungeon↔Threat 전략 루프 PASS.

---

## PHASE-STOP-1 Expedition / Dungeon 종료 경계

- 상태: QUEUED
- 확인:
  - TASK-026~028 완료.
  - Player 직접 탐사/전투 미구현.
  - Scout/Expedition persistent identity 정상.
  - Dungeon death/cleanup 분리.
  - reward duplicate 없음.
  - Threat duplicate reduction 없음.
  - 임시 파일 없음.
- 종료 회귀:
  - Scout/Expedition 통합.
  - Dungeon 통합.
  - Dungeon↔Threat 통합.
  - 기존 Overworld DAY/NIGHT.
  - Death Ledger.
- 완료조건:
  - 회귀 PASS.
  - 다음 파일 기능 자동 시작 금지.
