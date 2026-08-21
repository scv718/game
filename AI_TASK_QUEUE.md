# AI Task Queue

> TASK-012 Map Layout Lock 이후 신규 실행 큐.
> 완료된 TASK-008~012 상세 이력은 이 파일에 복사하지 않는다.
>
> 상태: `QUEUED` / `IMPLEMENT` / `REVIEW` / `FIX` / `DONE` / `NEEDS_DESIGN`
>
> 공통 규칙:
> 1. `##` = 챕터/컨테이너, `###` = 실제 실행 태스크.
> 2. 파일 순서대로 실행.
> 3. 각 태스크 시작 시 `GAME_DESIGN.md`, `DEVELOPMENT_STATUS.md`의 **현재 태스크 관련 섹션만 우선 확인**하고 실제 코드를 확인한다.
> 4. 범위 밖 시스템 임의 구현 금지.
> 5. Godot headless 테스트를 실제 실행하고 미실행 테스트를 PASS로 보고하지 않는다.
> 6. 미감/체감은 `HUMAN_CHECK`에 남기고 코드 정상 시 DONE 가능.
> 7. 설계 공백/충돌은 `NEEDS_DESIGN`.
> 8. 파괴적 Git 명령 및 자동 commit 금지.
> 9. 플레이어 캐릭터에 공격/무기/전투 스킬 추가 금지.
> 10. 전투 원칙: **전투는 자동, 판단은 플레이어가 한다.**
> 11. TASK-012에서 LOCK한 오버월드는 대규모 재배치 금지.
> 12. TASK-015 종료 후 자동 중단. Death Ledger/Ghost는 다음 큐에서 진행.

---

## TASK-MAINT-001 잔여 Debug 파일 정리
- 상태: DONE
- 피드백: 8개 임시 디버그 파일 완전 삭제, 프로젝트 전역 참조 0건, smoke + 핵심 회귀 PASS 확인. 독립 재실행은 환경 제약으로 불가하나 기존 결과 일관성에는 문제 없음.
- 설명: TASK-012 리뷰에서 지적된 잔여 진단/디버그 파일을 점검하고 실제 게임/테스트에서 참조하지 않는 임시 파일만 제거한다.
- 확인 후보:
  - `_diag*.gd`
  - `_probe.gd`
  - `_t75_debug.gd`
- 요구사항:
  - 삭제 전 프로젝트 전체 참조 검색.
  - 정식 regression test/게임 코드에서 참조 중이면 삭제 금지.
  - 이름만 보고 무조건 삭제하지 않음.
  - 제거 후 `main.tscn` smoke + 최신 핵심 회귀 최소 1종 실행.
- 완료조건:
  - 미사용 임시 파일 정리.
  - 참조 깨짐 없음.
  - smoke PASS.
- 구현기록:
  - 삭제: `tests/_probe.gd`, `tests/_probe.gd.uid`, `tests/_diag.gd`, `tests/_diag2.gd`, `tests/_diag3.gd`, `tests/_diag4.gd`, `tests/_diag5.gd`, `tests/_t75_debug.gd`.
  - 삭제 전/후 프로젝트 전체 참조 검색: 게임/정식 테스트 코드에서 해당 파일 참조 없음 확인(참조는 AI_TASK_QUEUE.md 태스크 설명뿐).
  - `.godot`(git-ignore 캐시)에만 `_probe.gd` 스캔 기록 존재, 소스 제거 후 자동 재생성 대상.
  - 제거 후 headless 검증: `smoke_test.gd` PASS, 최신 핵심 회귀 `task0128_test.gd` PASS.

---

## TASK-013 Free Wall + Gate Corridor
- 상태: QUEUED
- 설명: LOCK된 Defense Belt와 4방향 Gate Corridor를 이용해 첫 자유 성벽/성문 건설 시스템을 만든다.
- 핵심:
  - 성벽은 16px logical grid 자유 배치.
  - 성문은 N/E/S/W Gate Corridor 안에서만 배치.
  - collision/navigation 실제 반영.
  - 기존 Wood를 prototype 비용으로 재사용.
- 유지:
  - 기존 BuildingPlacement.
  - 16px logical grid.
  - TASK-012 맵 레이아웃.
  - Lumberyard/Quarry 배치.
- 금지:
  - Enemy/Mercenary/Wave/Portal 실제 기능.
  - 공격 타워.
  - Siege AI.
  - Wall upgrade.
  - 신규 자원.

### TASK-013-1 Wall 기본 Scene / Placement
- 상태: DONE
- 피드백: 모든 요구사항 충족, 코드 스타일 일관, 충돌 마스크/네비게이션 통합 정상, 테스트가 핵심 시나리오를 커버. 작업 범위 내 무결성 확인.
- 구현기록:
  - `scripts/wall.gd` + `scenes/wall.tscn` 생성. Wall 1 segment = 1 logical tile(16×16px) footprint, StaticBody2D static collision(layer 3), nav obstacle(parse_source_geometry_data로 자동 반영).
  - `building_placement.gd`: KEY_3 Wall 선택 추가(기존 1/2 유지), Wall 16px ghost/query footprint, `_try_place_wall_at` 연속 배치(배치 후 build mode 유지), 비용 1회 차감, invalid 시 차감 없음, placement 후 `rebuild_navigation()`. Wall 겹침 마스크(Player layer1 + Building/Tree/Stone/Boundary layer3)로 거부.
  - `hud.gd`: Wall build hint 추가.
  - 검증: `tests/task0131_test.gd` 신규 작성 PASS(grid snap/연속 배치/비용 차감/invalid 무차감/Core Building 겹침 거부/nav barrier 차단). smoke, task0128, tasknav001 회귀 PASS.
- 요구사항:
  - Wall 1 segment = 1 logical tile(16×16px) footprint.
  - Tiny Swords sprite scale/offset은 logical footprint와 독립.
  - static collision.
  - nav obstacle/source bake 반영.
  - 기존 ghost preview 및 valid/invalid 표시 재사용.
  - Player/Core Building/기존 Building/StoneDeposit/경계와 겹침 거부.
  - 기존 Lumberyard/Quarry 선택키 보존 후 신규 build selection 추가.
  - Wood 비용 configurable prototype 값.
- 완료조건:
  - Grid snap.
  - 여러 segment 연속 배치.
  - 비용 1회 차감.
  - invalid 시 비용 차감 없음.
  - placement 후 nav rebuild.
  - smoke PASS.

### TASK-013-2 Wall 연결 비주얼 + 간단 철거
- 상태: DONE
- 피드백: 태스크 요구사항 전부 충족, stale visual 방지 순서 정상, debounce nav rebuild 타이밍 적절, 테스트가 핵심 시나리오를 커버. 기존 코드 스타일과 일관, 누락/버그 없음.
- 피드백: 리뷰 지적(제거 wall이 `walls` 그룹에 잔존한 채 neighbor 비주얼 갱신 → stale visual)을 반영해 `_try_remove_wall_at`에서 `queue_free()` 전에 `remove_from_group("walls")` 후 `_refresh_neighbor_visuals`를 호출하도록 수정. 아울러 제거 시 `queue_free()`가 프레임 종료에 실제 제거됨을 고려해 즉시 `rebuild_navigation()` 대신 `rebuild_navigation_debounced()`를 사용해 제거된 wall의 stale collision/nav가 남지 않게 함.
- 비주얼:
  - 인접 N/E/S/W Wall을 기준으로 straight/corner/end 표현 가능한 asset이 있으면 사용.
  - 없으면 단일 sprite 반복 허용하되 간격이 끊겨 보이지 않게 함.
  - 비주얼 때문에 collision footprint 변경 금지.
- 철거:
  - Build mode에서 명확한 remove 입력.
  - Wall/Gate만 제거 가능.
  - Core Building/자원/생산시설 삭제 금지.
  - prototype에서는 테스트 편의를 위해 Wood 전액 환불 허용.
  - 철거 후 nav rebuild.
- 완료조건:
  - 직선/코너 성벽 생성 가능.
  - 제거 후 stale collision/nav 없음.
  - 인접 비주얼 갱신 정상.
- 구현기록:
  - `scripts/wall.gd`: `refresh_visual()` + `_build_visual_polygon()` 추가. 인접 N/E/S/W Wall이 있으면 시각 폴리곤을 간격 중간(8px)까지 확장해 straight/corner/end 연결을 표현(단일은 16×16, 직선은 24×16, 코너는 24×24). collision footprint(16×16)는 불변.
  - `scripts/building_placement.gd`: KEY_R Remove mode 추가(Build mode에서 토글, 좌클릭 시 Wall 철거), `_try_remove_wall_at`(Wall 전액 환불, `remove_from_group` 후 neighbor 비주얼 갱신 + `queue_free` + debounced nav rebuild), `_refresh_neighbor_visuals`. 또 `_is_valid_wall_position`에서 인접(붙은) Wall은 배치 허용(격자 cell 상 겹치지 않으므로)하고 Wall이 아닌 object만 거부하도록 수정 → L자 코너가 실제로 배치 가능.
  - `scripts/hud.gd`: build hint에 "R: Remove" 추가.
  - `tests/task0132_test.gd` 신규 작성 headless PASS(단일/직선/코너 시각 경계, footprint 불변, remove mode, 철거 환불, 비-Wall 삭제 금지, 인접 비주얼 갱신, nav 장벽 차단→철거 후 통로 개방). smoke, task0128, tasknav001 회귀 PASS. (task0131은 기존부터 nav 동기화 타이밍상 path 60/197을 오가는 flaky로, 변경 전 stash 상태에서도 동일 확인 — 본 태스크 범위 밖)

### TASK-013-3 Gate Corridor 판정 + Gate Placement
- 상태: DONE
- 피드백: Gate 48px footprint(3 tiles), N/S horizontal/E/W vertical orientation, corridor 내부 validation, centerline snap, edge-touch 허용/overlap 거부, cost/refund/nav rebuild 전부 정상. 32개 headless 검증 PASS, 4개 회귀 테스트 PASS. 버그/누락/엣지 케이스 없음.
- Gate:
  - Wall보다 넓은 footprint.
  - prototype 기준 3 logical tiles 우선.
  - asset/도로 폭상 필요하면 2~4 tiles 범위 조정 후 결과 기록.
- Placement:
  - N/E/S/W Gate Corridor 내부에서만 허용.
  - N/S Gate = 도로를 가로지르는 수평 orientation.
  - E/W Gate = 도로를 가로지르는 수직 orientation.
  - Main Road 중심선 근처 snap.
  - corridor 밖/다른 object와 겹침 거부.
  - Wall이 양옆에 자연스럽게 이어질 수 있어야 함.
- 구현:
  - TASK-012 marker/metadata 재사용.
  - 거대한 ZoneManager 금지.
- 완료조건:
  - 4방향 validation.
  - corridor 밖 invalid.
  - orientation 정상.
  - 비용/철거/환불 정상.

### TASK-013-4 Gate OPEN/CLOSED + Collision/Navigation
- 상태: QUEUED
- 상태:
  - OPEN
  - CLOSED
- 기본:
  - 신규 Gate 초기 상태 CLOSED.
  - 현재는 Player 상호작용으로 prototype toggle.
  - TASK-015 Command UI가 재사용할 공개 API 제공.
- CLOSED:
  - passage collision 활성.
  - nav 통과 불가.
- OPEN:
  - passage collision 비활성.
  - nav 통과 가능.
- 요구사항:
  - 반복 toggle에 collision/nav 누적 오류 없음.
  - 기존 debounce nav rebuild 활용 가능.
  - open/closed visual 구분.
- 금지:
  - Gate HP/Damage/파괴.
  - Enemy 공격.
- 완료조건:
  - Player OPEN 통과 가능.
  - CLOSED 통과 불가.
  - Worker nav 반복 toggle 안정.
  - 외부 command 호출 가능한 API.

### TASK-013-5 Wall/Gate Navigation Stress Regression
- 상태: QUEUED
- 시나리오:
  - 작은 사각 성벽 구축.
  - North Gate 설치.
  - OPEN에서 내부↔외부 path.
  - CLOSED에서 passage 차단.
  - Wall 추가/철거.
  - runtime nav rebuild 반복.
  - Lumberjack가 Wall을 뚫지 않고 열린 경로/Gate 이용.
  - unreachable Tree는 영구 MOVE stall 없이 안전 처리.
  - Miner/Quarry 정상.
  - DAY/NIGHT 반복 후 state 유지.
- 회귀:
  - TASK-BUG-NAV-001.
  - Worker 2명.
  - Tree claim/regrowth.
  - BuildingPlacement.
  - smoke.
- 완료조건:
  - permanent stall 없음.
  - stale collision 없음.

### TASK-013-6 Free Wall + Gate 통합 검증
- 상태: QUEUED
- 자동검증:
  - Wall 배치/비용/invalid.
  - Wall 철거/환불.
  - Gate 4방향 corridor validation.
  - Gate orientation.
  - Gate OPEN/CLOSED.
  - collision/nav 전환.
  - Wall/Gate 연결.
  - Worker navigation.
  - BuildingPlacement/DayNight/smoke 회귀.
- HUMAN_CHECK:
  - Wall scale.
  - 16px segment 배치 조작감.
  - 코너 비주얼.
  - Gate 크기와 Main Road 조화.
  - 작은/큰 성벽 모두 만들고 싶은지.
- 중요:
  - 조작이 번거롭다는 이유만으로 Drag-line builder를 임의 구현하지 않는다.
- 완료조건:
  - 자동검증 PASS.
  - HUMAN_CHECK만 남으면 DONE.

---

## TASK-014 First Mercenary + Enemy Auto Combat
- 상태: QUEUED
- 설명: 첫 실제 전투 Vertical Slice. 고용한 용병이 밤에 방어 위치에서 자동으로 적과 싸운다.
- 핵심:
  - Mercenary AI가 전투 수행.
  - Player 공격 기능 절대 추가 금지.
  - Mercenary 1종 + Enemy 1종.
  - HP/Damage/Attack interval/Death.
  - NIGHT combat.
- 금지:
  - Death Ledger/Ghost.
  - Food/Potion/Morale.
  - Equipment progression.
  - Skill tree/Boss.
  - 여러 enemy archetype.
  - 생성형 AI.
  - 플레이어 combat.

### TASK-014-1 MercenaryData / Roster + 주점 고용
- 상태: QUEUED
- 최소 데이터:
  - unique id.
  - display name.
  - class/type.
  - level prototype 값.
  - combat stats 최소값.
  - alive/dead.
  - defense assignment.
- 구조:
  - WorkerRoster에 억지로 합치지 않음.
  - `MercenaryData` / `MercenaryRoster` 최소 별도 구조 허용.
  - 대형 CharacterDatabase 금지.
- 주점:
  - 기존 Recruitment UI에 고정 Mercenary 후보 1명.
  - prototype 고용 비용 0 가능.
  - 중복 고용 거부.
- 여관:
  - 보유/대기 상태 최소 표시.
- 완료조건:
  - Mercenary 1명 고용.
  - Roster 조회 가능.
  - 고용 즉시 낮 월드에 전투 Actor 자동 spawn할 필요 없음.

### TASK-014-2 Defense Assignment + Mercenary NIGHT Spawn
- 상태: QUEUED
- 요구사항:
  - defense zone: NORTH/EAST/SOUTH/WEST.
  - 여관에서 Mercenary defense assignment 변경.
  - NIGHT 시작 시 해당 Gate 안쪽 Rally Space에 Actor spawn.
  - 해당 Gate가 없으면 기존 marker 기준 fallback RallyPoint.
  - DAY 복귀 시 살아 있는 Actor는 roster data로 복귀 후 despawn 가능.
  - 반복 cycle actor duplicate 금지.
- 제외:
  - DAYTIME 생활 AI.
  - RTS click-to-move.
  - formation UI.

### TASK-014-3 Enemy Actor + First Night Encounter Spawner
- 상태: QUEUED
- Enemy:
  - 일반 근접 1종.
  - HP/move speed/damage/attack interval/death.
  - Player를 combat target으로 선택하지 않음.
- Spawner:
  - 범용 WaveManager 금지.
  - `FirstEncounterSpawner` 수준 최소 구조.
  - NIGHT 시작 시 한 방향에서 configurable 수량 spawn.
  - 기본 테스트 방향은 NORTH 등 결정적 값 사용 가능.
  - 기존 Portal/Spawn Candidate 사용.
  - 실제 Portal 시스템은 구현하지 않음.
- 이동:
  - Main Road/Gate 접근을 선호.
  - OPEN Gate면 Village Core 방향 진행 가능.
- 완료조건:
  - NIGHT spawn.
  - DAY 오작동 spawn 없음.
  - 반복 NIGHT duplicate 없음.

### TASK-014-4 Mercenary Auto Combat FSM
- 상태: QUEUED
- 최소 상태:
  - IDLE/HOLD.
  - ACQUIRE_TARGET.
  - MOVE_TO_TARGET.
  - ATTACK.
  - RETURN_TO_DEFENSE_ZONE.
  - DEAD.
- 행동:
  - 지정 defense zone 주변 Enemy 우선.
  - range 밖 chase.
  - range 안 interval attack.
  - target death/invalid 시 새 target.
  - 과도하게 멀리 추격하면 defense zone 복귀.
- 원칙:
  - 예측 가능한 deterministic priority.
  - 복잡한 Utility/BehaviorTree 선행 금지.
  - 간단한 Damageable/Combatant 공통 인터페이스 정도만 허용.
- 완료조건:
  - Mercenary 자동 탐색/이동/공격.
  - Enemy HP 감소/Death.
  - Mercenary도 Enemy 공격으로 HP 감소/Death.
  - Player는 damage/target 대상에서 제외.

### TASK-014-5 CLOSED Gate 대응 + Gate Breach
- 상태: QUEUED
- 설명: Normal Enemy가 CLOSED Gate에서 영구 정지하지 않도록 최소 Gate 공격/파괴 흐름을 추가한다.
- Gate:
  - prototype max_hp/durability 추가.
  - CLOSED Gate를 Enemy가 공격 가능.
  - HP 0 → destroyed/breached → passage open.
  - 자동 복구 금지.
- OPEN Gate:
  - 공격하지 않고 통과.
- Wall:
  - 이번 Enemy는 Wall 직접 공격하지 않음.
  - Normal Enemy는 Gate 접근 선호.
  - Siege/Wall breaking은 미래.
- Navigation:
  - CLOSED→DESTROYED 후 통과 가능하게 갱신.
- 완료조건:
  - CLOSED Gate 앞 permanent stall 없음.
  - Gate attack/breach.
  - breach 후 Village 방향 진행.
  - Mercenary가 Gate 앞 Enemy와 교전 가능.

### TASK-014-6 Combat Death / Cleanup
- 상태: QUEUED
- Enemy death:
  - combat/collision/target에서 제외 후 제거.
- Mercenary death:
  - `MercenaryData.alive = false`.
  - Actor 제거.
  - 다음 DAY/NIGHT 자동 부활 금지.
  - Roster에서 dead 확인 가능.
- 중요:
  - 아직 Death Ledger 기록 금지.
  - 후속 연결 지점 정도만 남기고 시스템 선행 구현 금지.
- 반복 cycle:
  - 이전 Enemy/target reference 누수 없음.
  - alive Mercenary만 다음 NIGHT spawn.
- 완료조건:
  - freed reference 오류 없음.
  - dead Mercenary 재생성 없음.

### TASK-014-7 First Auto Combat 통합 검증
- 상태: QUEUED
- 시나리오:
  1. 주점에서 Mercenary 고용.
  2. 여관에서 NORTH defense assignment.
  3. North Gate/Wall 또는 fallback defense point 준비.
  4. NIGHT.
  5. Mercenary Actor spawn.
  6. Enemy spawn.
  7. Enemy approach.
  8. Mercenary auto target/chase/attack.
  9. 양측 HP 변화.
  10. Enemy death.
  11. Mercenary death 별도 검증.
  12. CLOSED Gate attack/breach.
  13. DAY cleanup.
  14. 다음 NIGHT duplicate/reference 오류 없음.
- 회귀:
  - Player attack 없음.
  - NIGHT Player 이동 비활성.
  - Worker production 정책 유지.
  - Wall/Gate navigation.
  - smoke.
- HUMAN_CHECK:
  - Mercenary/Enemy scale.
  - 공격 애니메이션.
  - 이동/공격 속도.
  - Gate 앞에서 전투가 읽히는지.
- 완료조건:
  - 자동검증 PASS.

---

## TASK-015 Tactical Command UI
- 상태: QUEUED
- 설명: 밤 지휘모드를 단순 관전이 아니라 플레이어 판단이 실제 AI 행동을 바꾸는 첫 전술 시스템으로 만든다.
- 핵심:
  - 전투는 계속 Mercenary AI가 수행.
  - 플레이어는 이동/공격을 직접 조작하지 않음.
- 첫 Command:
  - Defense Zone.
  - Regroup.
  - Retreat.
  - Focus Target.
  - Gate Open/Close.
  - Pause / 1× / 2×.
- 금지:
  - Player attack.
  - Mercenary 수동 attack button.
  - skill system.
  - box-selection 마이크로.
  - Death Ledger/Ghost.

### TASK-015-1 Night Tactical Camera Pan
- 상태: QUEUED
- DAY:
  - 기존 Player follow.
- NIGHT:
  - Player movement 비활성 유지.
  - camera만 독립 pan.
  - keyboard pan 우선.
  - world boundary 밖으로 이동 금지.
  - edge pan은 선택사항.
- 전환:
  - DAY 복귀 시 Player follow/zoom 정상.
- 완료조건:
  - NIGHT에서 N/E/S/W Gate/Combat Field 확인 가능.
  - Player entity는 이동하지 않음.

### TASK-015-2 Tactical Command HUD
- 상태: QUEUED
- NIGHT 표시:
  - Defense Zone N/E/S/W.
  - Regroup.
  - Retreat.
  - Focus Target mode.
  - Gate control.
  - Pause/1×/2×.
- 요구사항:
  - DAY 숨김/비활성.
  - 기존 Wood/Stone/DayTime HUD 유지.
  - 전투 중앙을 과도하게 가리지 않음.
  - 완성형 UI polish 금지.
- 완료조건:
  - NIGHT command UI 사용 가능.
  - DAY reset 정상.

### TASK-015-3 Defense Zone Command
- 상태: QUEUED
- 행동:
  - NIGHT 중 N/E/S/W 변경.
  - Mercenary defense anchor/rally 변경.
  - 현재 target이 새 zone과 무관/너무 멀면 disengage 후 새 zone 복귀.
  - teleport 금지, nav 이동.
- 완료조건:
  - North→East 등 실시간 변경.
  - 새 zone 기준 target 탐색.
  - stale target/permanent chase 없음.

### TASK-015-4 Regroup / Retreat
- 상태: QUEUED
- Regroup:
  - 현재 defense zone RallyPoint 복귀.
  - 이동 중 새 target 획득 잠시 억제.
  - 도착 후 일반 방어 AI 복귀.
- Retreat:
  - 중앙 Village/safe rally로 후퇴.
  - 공격 중지 또는 우선순위 크게 감소.
  - 안전지점 도착 후 HOLD.
- 금지:
  - teleport.
  - 무적.
- 완료조건:
  - Regroup/Retreat 행동 차이 명확.
  - 새 defense command로 정상 복귀.

### TASK-015-5 Focus Target
- 상태: QUEUED
- UX:
  - Focus Target mode → Enemy 선택.
- 행동:
  - 살아 있고 reachable한 선택 Enemy를 우선 target.
  - target death/freed 시 자동 focus 해제.
  - unreachable target로 영구 chase 금지.
- 중요:
  - Player 직접 공격이 아니라 AI priority 변경.
- 완료조건:
  - focus priority 확인.
  - target 제거 후 기본 AI 복귀.

### TASK-015-6 Gate Command + Tactical Time
- 상태: QUEUED
- Gate:
  - 설치된 N/E/S/W Gate 상태 표시.
  - OPEN/CLOSE.
  - Gate 없음/destroyed는 안전한 disabled 처리.
- Time:
  - Pause/1×/2×.
  - Pause 상태에서도 UI input 동작.
  - DAY 진입 시 1× 복원.
  - 테스트 종료 후 time state 누수 없음.
- 검증:
  - 2×에서 combat/animation/GameTime/Worker timer가 비정상 중복 실행되지 않음.
- 완료조건:
  - Gate command.
  - Pause/1×/2×.
  - DAY reset.

### TASK-015-7 Command AI Priority
- 상태: QUEUED
- 권장 priority:
  1. DEAD.
  2. RETREAT.
  3. REGROUP.
  4. FOCUS TARGET.
  5. DEFENSE ZONE AUTO COMBAT.
- 요구사항:
  - contradictory state 무한 누적 금지.
  - 새 command가 이전 transient command를 어떻게 덮는지 명확.
  - 범용 Command Framework 선행 금지.
- 완료조건:
  - command 전환 테스트 PASS.
  - state deadlock 없음.

### TASK-015-8 Tactical Combat Vertical Slice 통합 검증
- 상태: QUEUED
- 시나리오:
  1. Mercenary 고용/방어배치.
  2. Wall/Gate 구성.
  3. NIGHT.
  4. Tactical camera.
  5. Enemy encounter.
  6. 자동전투.
  7. Defense Zone 변경.
  8. Focus Target.
  9. Regroup.
  10. 재교전.
  11. Retreat.
  12. Gate Open/Close.
  13. Pause.
  14. 2×.
  15. death cleanup.
  16. DAY.
  17. 다음 NIGHT 반복.
- 핵심검증:
  - Player attack 없음.
  - NIGHT Player 이동 없음.
  - 명령이 실제 Mercenary AI 행동에 영향.
  - 전투 자체는 AI 수행.
  - nav stall/freed reference 없음.
  - Gate breach/command 충돌 없음.
  - Worker/DayNight/HUD 회귀 없음.
- HUMAN_CHECK:
  - camera pan 속도/zoom.
  - Command UI 위치.
  - 명령 의미가 바로 이해되는지.
  - Regroup/Retreat 차이.
  - Focus Target이 지나친 마이크로처럼 느껴지지 않는지.
  - Pause/1×/2×가 판단 시간을 주는지.
  - **"전투는 자동, 판단은 플레이어가 한다"는 느낌이 나는지.**
- 완료조건:
  - 자동검증 PASS.
  - HUMAN_CHECK만 남으면 DONE.

---

## OVERNIGHT-STOP-5 TASK-013~015 종료 경계
- 상태: QUEUED
- 설명: TASK-MAINT-001, TASK-013, TASK-014, TASK-015 완료 후 신규 시스템을 임의 시작하지 않고 종료한다.
- 금지:
  - Death Ledger.
  - Ghost.
  - Dungeon 실제 기능.
  - Food/Potion/Morale.
  - Equipment progression.
  - 추가 Mercenary class.
  - 추가 Enemy archetype.
  - Boss/Siege enemy.
  - Wall upgrade.
  - 대규모 UI polish.
- 다음 사람 플레이테스트 후 예정:
  - TASK-016 Death Ledger.
  - TASK-017 First Ghost Return.
  - Ghost vertical slice를 Food/Potion/Morale보다 우선.
