# TASK-3D-CMB-001-1 INTEGRATION NOTE (Mercenary / Enemy Actor3D)

> 후속 태스크(CMB-001-2 Tactical Wiring / CMB-001-3 Regression, BLD Gate3D,
> WRK/VIS 병렬 레인)가 3D Combat Actor Runtime을 소비할 때 필요한 계약 요약.
> 기존 2D 파일(mercenary_actor.gd / enemy_actor.gd / mercenary.tscn / enemy.tscn /
> first_encounter_spawner.gd의 spawn부 / mercenary_roster.gd의 spawn부)은
> LOCK 12에 따라 전부 무수정으로 유지되었다. 3D Runtime은 아래 신규 파일로 병행 운영된다.

## 신규 파일

| 파일 | 역할 |
|------|------|
| `scripts/mercenary_actor_3d.gd` | MercenaryActor3D. 2D 자동전투 FSM 전체(ACQUIRE/MOVE/ATTACK/RETURN/REGROUP/RETREAT/DEAD + focus target)의 3D판 |
| `scripts/enemy_actor_3d.gd` | EnemyActor3D. route 접근/교전/GATE_ATTACK FSM의 3D판 |
| `scenes/mercenary_3d.tscn` | Mercenary 3D scene(placeholder capsule visual, blue) |
| `scenes/enemy_3d.tscn` | Enemy 3D scene(placeholder capsule visual, red) |
| `tests/task3dcmb0011_test.gd` | 서브태스크 회귀 테스트(73 assertions headless PASS) |

## 도메인 간 계약 (후속 태스크 소비 지점)

1. **Tactical Wiring(CMB-001-2) - spawn/despawn**
   - Mercenary scene: `res://scenes/mercenary_3d.tscn`, root class `MercenaryActor3D`.
     spawn부는 2D mercenary_roster.gd `_spawn_actor`와 동일 순서로
     `merc_data`/`position`/`defense_point`(Vector3) 지정 → add_child →
     `died` signal connect. `retreat(safe_point: Vector3)` /
     `set_defense_zone(zone, new_rally: Vector3)` 좌표는 world XZ 단위다.
   - Enemy scene: `res://scenes/enemy_3d.tscn`, root class `EnemyActor3D`.
     spawner는 2D first_encounter_spawner.gd와 동일 계약이되 waypoint/final은
     Vector3(world XZ). `setup(id, name, direction)` 시그니처 불변.
     logical waypoint는 `WorldCoords3D.polyline_to_world()` / `to_world_xz()`로 변환.
   - focus target pick(2D `_enemy_at` 반경 조회의 3D판)은 그룹 `"enemies_3d"` +
     `WorldCoords3D.distance_xz`로 유지하는 것을 권장한다. actor body는
     ENEMY/MERCENARY layer(MASK_ACTORS)라 Foundation 선택 광선과 무간섭.

2. **Building(BLD) - Gate3D 계약**
   - 3D Enemy의 성문 공격 대상 탐색은 그룹 **`"gates_3d"`** +
     duck-typing `is_closed() -> bool` / `take_damage(amount)`다(2D gate.gd와
     동일 계약, 거리 감지 = `GATE_ATTACK_RANGE` 5 unit = 2D 40px 환산).
   - BLD가 Gate3D를 만들 때 이 그룹 + 메서드만 만족하면 Enemy측 수정 없이 연결된다.
     현재 Gate3D 부재 상태에서도 `_find_closed_gate()`는 안전하게 null을 반환한다.

3. **Death Ledger(CMB-001-3)**
   - record 생성은 die() 내부 단일 경로(2D TASK-016-3 계약 불변).
     DAY cleanup/despawn(queue_free 직접 호출)은 record를 만들지 않는다.
   - `death_position` 스키마(Vector2)를 유지하기 위해 world XZ를
     `WorldCoords3D.to_logical()`로 역변환해 저장한다. 즉 ledger 좌표 공간은
     2D record와 동일한 logical px 좌표다(dimension 간 ledger 혼용 안전).

4. **Visual(VIS) 인계**
   - visual slot은 `Visual`(Node3D) 하위 `BodyVisual`(MeshInstance3D)이다.
     mesh/material 교체만으로 Quaternius 유닛 투입이 가능하며 game logic 무수정.
   - facing/rotation 계약: 이동 중 velocity 방향, 공격 중 target 방향으로
     `Visual.rotation.y`가 -Z forward 관례 yaw로 보간된다(root는 회전하지 않음).
     모델 교체 시 forward 축이 다르면 Visual 하위에 보정 노드를 두는 방식 권장.
   - attack/hit/death hook: signal `attack_performed(target)` /
     `hit_taken(amount)` / `death_started(actor)`(merc/enemy 공통).
     hit placeholder = emission flash(0.15s), death placeholder = Visual hidden.
     material은 `_ready`에서 instance별 duplicate하므로 flash가 개체 단위로 동작한다.

## Movement / Balance 규약 (Foundation 001-5 소비)

- NavigationAgent3D는 `NavigationPolicy3D.configure_agent()` 단일 적용.
  개별 agent 튜닝 없음. 이동 종료는 `judge_path_status`(MOVING/ARRIVED/BLOCKED)
  단일 규약 + stuck guard(`NavigationPolicy3D.STUCK_MOVE_EPSILON_UNITS`,
  timeout은 2D parity 2.0s).
- 모든 gameplay 거리/사거리는 `WorldCoords3D.distance_xz`. 상수는 2D px *
  `PX_TO_UNIT` 환산 그대로(ATTACK_RANGE 26px→3.25u, CHASE_RETURN 180px→22.5u,
  REACH 12px→1.5u, GATE 감지 40px→5u, enemy speed 90px/s→11.25u/s,
  merc speed는 MercenaryData.move_speed(px/s)를 런타임에 PX_TO_UNIT 환산).
  전투 밸런스 비율 불변.
- **unreachable chase lock 방지**: 추격 중 BLOCKED(부분 경로 소진) 또는 stuck이면
  해당 target을 `CHASE_RETRY_COOLDOWN`(2.5s) 동안 재탐색에서 제외하고 bounded 포기.
  focus target이 unreachable이면 focus까지 해제(2D stuck 규약의 3D 완성판).
  cooldown 만료 후에는 1회 재시험(gate 개방 등 가용성 변화 수용).
- Enemy MOVE의 BLOCKED/stuck: 남은 waypoint는 다음 목표로 bounded skip,
  최종 목표 차단이면 HOLD 종료(영구 MOVE stall 금지 원칙 준수).

## Collision / Group

- Mercenary body = MERCENARY layer(64), Enemy body = ENEMY layer(128),
  공통 mask = MASK_ACTOR_SOLID(GROUND|BUILDING|WALL|GATE|RESOURCE).
  actor끼리 물리 충돌 없음(2D 관례 불변). motion_mode FLOATING, Y 고정.
- body volume = SphereShape r=1.0 @ y=1.0(Actor Origin LOCK: origin 지면 접지).
  2D circle r=8px 환산 불변. 이 shape가 collision 겸 향후 select query volume이다
  (2D와 동일하게 selection은 physics volume이 아니라 그룹 거리 조회 기준).
- groups: `mercenaries_3d` / `enemies_3d` / `gates_3d`(BLD용). 2D group("mercenaries",
  "enemies", "gates")과 구조적으로 분리되어 2D/3D Runtime 혼재 오염이 없다.

## 검증 결과

- `tests/task3dcmb0011_test.gd` — 73 assertions 전부 PASS(headless).
  커버: scene 구조/collision 정책/상수 스케일, 자동전투 수렴(상호 데미지·XZ 사거리·
  Y 고정·facing), player 무피격 경로 없음, lethal death cleanup(그룹 제외·freed·
  ledger 1회·despawn 무기록), sealed-pen chase lock 방지(BLOCKED→bounded 포기→IDLE,
  pen 미침입), gates_3d 계약(CLOSED 공격→OPEN 통과 재개), orphan/stale 잔여 없음.
- 실행 로그: `test_results/task3dcmb0011_test_run.txt`.
- Foundation 회귀 재확인: `tests/task3d0015_test.gd` PASS(공유 Navigation policy 위
  신규 actor 추가가 기존 convention을 깨지 않음).
- 남은 것: CMB-001-2(roster/spawner 3D wiring, tactical camera/명령 wiring),
  CMB-001-3(전체 시나리오 regression + 최종 INTEGRATION_NOTE 갱신).

---

# TASK-3D-CMB-001-2 INTEGRATION NOTE (Tactical Command World3D Wiring)

> 후속 태스크(CMB-001-3 Regression, INT Main World 통합)가 Tactical 3D wiring을
> 소비할 때 필요한 계약 요약. 기존 2D 파일(mercenary_roster.gd /
> first_encounter_spawner.gd / tactical_command_ui.gd / tactical_command_ui.tscn)은
> LOCK 12에 따라 전부 무수정으로 유지되었다. 3D wiring은 아래 신규 파일로 병행 운영된다.

## 신규 파일

| 파일 | 역할 |
|------|------|
| `scripts/mercenary_roster_3d.gd` | MercenaryRoster3D. 2D mercenary_roster.gd의 NIGHT spawn/DAY despawn + 전술 명령 처리 + focus target 관리의 3D판 |
| `scripts/first_encounter_spawner_3d.gd` | FirstEncounterSpawner3D. 2D first_encounter_spawner.gd spawn/despawn 계약의 3D판 |
| `scripts/tactical_command_ui_3d.gd` | TacticalCommandUI3D. Control 계층 유지, gates_3d 조회만 차별화 |
| `ui/tactical_command_ui_3d.tscn` | 2D tactical_command_ui.tscn과 동일 레이아웃의 3D wiring용 scene |
| `tests/task3dcmb0012_test.gd` | 서브태스크 회귀 테스트(77 assertions headless PASS) |

## 도메인 간 계약 (후속 태스크 소비 지점)

1. **INT(통합) - wiring 방법**
   - world3d에 `MercenaryRoster3D` / `FirstEncounterSpawner3D`(Node)를 add_child하고,
     HUD 계열 CanvasLayer에 `ui/tactical_command_ui_3d.tscn`을 인스턴스하면 그룹 조회
     ("mercenary_roster_3d" / "tactical_command_ui_3d")로 명령 경로가 양방향 guarded
     connect 된다(추가/역숛 추가 어느 순서든 중복 연결 없음). autoload 등록 불요.
   - Camera는 Foundation `camera_controller_3d.tscn`을 그대로 소비한다(수정 없음).
     DAY/NIGHT zoom policy와 고정 사선 basis는 001-3 소유대로 동작한다.
   - 3D 월드에 MapLayout/Keep 노드를 나중에 붙여도 roster/spawner가 우선 조회한다.
     없으면 WorldMap logical 상수를 WorldCoords3D XZ 해석해 사용(현재 기본 경로).

2. **BLD - Gate3D 명령 계약**
   - UI 성문 목록/명령은 그룹 **"gates_3d"** + duck-typing
     `get_direction()` / `is_open()` / `is_breached()` / `set_open(open)` /
     signal `gate_state_changed(gate, open)`를 사용한다(2D gate.gd 공개 API와 동일).
   - BREACHED 판정은 gate 측 set_open no-op 책임이다(2D 계약 동일). Gate3D 부재 시
     UI는 "설치된 성문 없음" 문구만 표시하고 명령은 안전하게 무시된다.

3. **UI / 입력**
   - 명령 코드는 기존 `TacticalCommandUI.Command` enum을 차원 중립적으로 재사용한다.
     새 enum을 만들지 않으므로 코드 값 drift가 없다.
   - focus ray pick은 camera_controller_3d 그룹의 `ground_point_from_screen()` +
     "enemies_3d" 그룹 + `WorldCoords3D.distance_xz` 최근접 반경 조회다
     (반경 = 32px * PX_TO_UNIT, 2D FOCUS_PICK_RADIUS 비율 보존).

4. **DAY/NIGHT transient 규약**
   - DAY 복귀 시 roster가 actor despawn(queue_free, 무기록)과 함께 focus mode/target을
     명시적으로 해제한다. GameTime time scale 복원/카메라 policy 복귀는 각자 소유
     (GameTime/CameraController3D)이며 wiring은 개입하지 않는다.

## -s 테스트 컴파일 주의 (회귀 재발 방지)

- `-s script` 기동 초기에는 autoload가 미등록인 컴파일 단계가 존재한다. 이 단계에서
  bare autoload 참조(GameTime 등)를 포함한 스크립트(본 태스크의 roster/spawner/UI3D 및
  2D tactical_command_ui.gd)를 **테스트가 정적으로 참조하면** 그 스크립트의 컴파일 자체가
  파괴되어 `.new()`가 bare base 인스턴스가 된다(리뷰 프로브로 원인 확정됨).
- 회피 규약: 테스트에서 해당 스크립트/상수/enum은 런타임 `load()` + duck-typing으로만
  접근한다(`tests/task3dcmb0012_test.gd` 헤더 주석 참고). autoload 미참조 유틸
  (WorldCoords3D/MercenaryData/MercenaryActor3D/EnemyActor3D/WorldMap 상수)은 정적
  참조 가능(001-1 선행 사례와 동일).

## 검증 결과

- `tests/task3dcmb0012_test.gd` — 77 assertions 전부 PASS(headless).
  커버: wiring 구조(UI=Control 계층, 명령 코드 계약, guarded connect), 카메라
  DAY/NIGHT policy 전환 + basis 불변(rotation 없음), defense zone rally/safe/spawn/
  route의 XZ 단일 해석(Y=GROUND_Y), NIGHT spawn 배치, focus ray pick(빈 ground 안전),
  FOCUS > zone auto-combat 우선순위, REGROUP/RETREAT 실측 이동(teleport 없음),
  RETREAT 중 focus 지정 즉시 전환 금지, DEFENSE_ZONE 실시간 전환, gates_3d
  OPEN/CLOSE/BREACHED 명령, TIME pause/2x/1x, DAY transient 정리(despawn 무기록,
  focus 해제, 1x 복원), 반복 NIGHT duplicate 없음, orphan 잔여 없음.
- 실행 로그: `test_results/task3dcmb0012_test_run.txt`.
- 선행 서브태스크 회귀 재확인: `tests/task3dcmb0011_test.gd` PASS.
- 남은 것: CMB-001-3(전체 시나리오 regression + 최종 INTEGRATION_NOTE 갱신),
  INT(Main Scene에 3D tactical runtime wiring).

---

# TASK-3D-CMB-001-3 INTEGRATION NOTE (Combat / Death Ledger Regression)

> CMB-001 레인의 최종 회귀 서브태스크. 이 서브태스크 자체가 새로 추가/수정한
> production 코드는 없고, 큐 시나리오 14단계(용병 배치 → NIGHT → 조우 → 자동전투 →
> Focus → Regroup → Retreat → Gate Open/Close → Pause → 2x → lethal death →
> Death Ledger 확인 → DAY → 다음 NIGHT 반복)를 3D Runtime Actor 위에서 전부 재생하는
> 회귀 테스트만 추가했다.
>
> production 변경 귀속 명시: 작업 트리에는 001-2 FIX 사이클에서 만든 미커밋 production
> 변경이 있다(`scripts/mercenary_actor_3d.gd` / `scripts/enemy_actor_3d.gd`의
> `_nav_dest := Vector3.ZERO` 미설정 센티널을 `_has_nav_dest` 플래그로 교체).
> 본 001-3 회귀의 RETREAT 관찰 / re-defense 복귀 / lethal 배치 타이밍은 이 수정에
> 의존하므로, "기존 파일 무수정"은 이 서브태스크 기준일 뿐이며 현재 작업 트리는
> 001-2 FIX 변경을 포함한다(소급 문서화는 AI_TASK_QUEUE.md TASK-3D-CMB-001-2 참고).

## 신규 파일

| 파일 | 역할 |
|------|------|
| `tests/task3dcmb0013_test.gd` | 전체 시나리오 회귀 테스트(85 assertions headless PASS) |

## 검증 매핑 (큐 "검증" 항목 → 테스트 근거)

1. **Player combat 없음**: 자동전투/focus/regroup/lethal 관찰 루프 전체에서 모든 살아
   있는 enemy의 `_target`이 mercenaries_3d 소속(null 또는 gate 제외)임을 순회 단정하고,
   player 모형 노드가 전투 그룹에 끼지 않고 이동/해방되지 않음을 확인.
2. **duplicate death record 없음**: ledger 전체 source_uid 스캔으로 중복 0 + 개별
   kill(bait/m_south)별 record 수 == 1 + "관측된 died signal 총횟수 == ledger 증가량"
   대응으로 누락/과다 기록까지 동시 차단.
3. **cleanup record 없음**: DAY despawn, 수동 queue_free(fixture/probe), final free()
   정리 각 단계 직후 ledger 크기 불변을 4회 확인.
4. **freed reference 없음**: 사망 즉시 roster `_actors` erase(died bind), focus target
   자동 해제, DAY 후 actor/encounter reference freed, 반복 NIGHT fresh actor 보장.
5. **Gate/nav stale state 없음**: CLOSED 성문 교전(GATE_ATTACK + 실제 take_damage 누적)
   중 GATE_OPEN 명령 한 번으로 bounded 시간 내 상태 탈출 + 성문 선 통과(경로 재개).
   영구 gate lock 없음.
6. **command deadlock 없음**: Pause 중 FOCUS 토글 응답, TIME 배율 체인 적용, 반복
   NIGHT의 fresh actor에게 REGROUP 재응답. 모든 관찰 루프는 budget bounded.

## 회귀 테스트 결정성 규약 (후속 테스트 작성 시 재발 방지 지침)

- **encounter walker는 core HOLD로 kill이 안 될 수 있다**: 이동 encounter는 chase
  leash(CHASE_RETURN_DISTANCE) 밖 village core에 도달하면 HOLD로 종료한다(기존 설계
  동작). 확정 kill 검증은 rally 근처 고정 fixture로 하고, ledger 정합성은 died signal
  카운트 대응으로 닫는다. 참고: Enemy FSM에는 추격 로직이 없다(근접 시 정지 교전만).
- **전역 REGROUP/RETREAT 명령은 모든 생존 용병을 움직인다**: lethal 검증 대상 용병도
  RETREAT를 따라 safe rally로 이간진다. actor 공개 계약
  `set_defense_zone(zone, rally)`으로 해당 용병만 자기 진지에 복귀시킨 뒤 1:1 교전을
  성립시켰다(우회 없이 공개 API만 사용).
- **-s 기동 frame이 GameTime._elapsed를 오염한다**: autoload는 테스트가 auto_advance를
  끄기 전 frame부터 혼자 시간을 누적한다(실측 11 frame ≈ 0.18s). 따라서 elapsed 판정은
  절대값이 아니라 상대 증분(delta)으로 하고, `_initialize()`에서 guarded
  `set_auto_advance(false)`로 오염 원천을 조기 차단한다.
- **autoload 미등록 컴파일 단계 규약은 001-2와 동일**: roster/UI 계열 정적 참조 금지,
  런타임 load() + duck-typing만 사용(파일 헤더 주석 참고).
- **RETREAT/re-defense/lethal 시나리오는 001-2 FIX(`_has_nav_dest`)에 의존한다**:
  센티널 방식(`_nav_dest == Vector3.ZERO` 미설정 취급)으로 되돌리면 safe rally가
  세계 원점인 RETREAT 목적지 설정이 무시되어 본 회귀의 RETREAT 도착/lethal 배치
  타이밍이 FAIL로 바뀐다. 이 의존은 001-2 구현 기록에 소급 문서화되어 있다.

## 실행 결과

- `tests/task3dcmb0013_test.gd` — 85 assertions 전부 PASS(headless), 연속 재실행 PASS.
- 실행 로그: `test_results/task3dcmb0013_test_run.txt`, 재실행:
  `test_results/task3dcmb0013_fix_rerun1.txt`.
- 선행 서브태스크 회귀 재확인(각각 별도 로그로 분리):
  - `tests/task3dcmb0011_test.gd` PASS → `test_results/task3dcmb0013_prior_0011_rerun.txt`
  - `tests/task3dcmb0012_test.gd` PASS → `test_results/task3dcmb0013_prior_0012_rerun.txt`
- 남은 것: INT(Main Scene에 3D tactical runtime wiring). CMB-001 레인의 기능 범위는
  여기서 완결.
