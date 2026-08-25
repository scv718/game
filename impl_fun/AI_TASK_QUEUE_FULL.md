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

## CHECKPOINT-1 Expedition / Dungeon 종료 경계

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

## CHECKPOINT-2 Equipment / Mercenary 종료 경계

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
  - checkpoint 회귀 PASS 후 다음 TASK를 계속 실행 가능.


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

## CHECKPOINT-3 Enemy / Village Progression 종료 경계

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
  - checkpoint 회귀 PASS 후 다음 TASK를 계속 실행 가능.


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

## CHECKPOINT-4 Boss / Portal 종료 경계

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
  - checkpoint 회귀 PASS 후 다음 TASK를 계속 실행 가능.


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

## CHECKPOINT-5 Persistence / Product 종료 경계

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
  - checkpoint 회귀 PASS 후 다음 TASK를 계속 실행 가능.


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
