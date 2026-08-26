# TASK-3D-WRK-001 INTEGRATION NOTE (Worker / Navigation 3D Migration)

> 후속 도메인(BLD/CMB/INT/VIS)이 3D Worker Runtime과 연계될 때 필요한 계약 요약.
> 기존 2D Worker 파일(lumberjack.gd / miner.gd / lumberyard.gd / quarry.gd /
> workplace.gd 및 관련 tscn)은 LOCK 12에 따라 reference로 무수정 유지되며,
> 3D Runtime은 아래 신규 파일로 병행 운영된다.

## 신규 파일

| 파일 | 역할 |
|------|------|
| `scripts/worker_actor_3d.gd` | WorkerActor3D base(CharacterBody3D + NavigationAgent3D). XZ ground 이동, yaw-only facing, 단일 종료 이동 규약 |
| `scripts/lumberjack_3d.gd` | Lumberjack FSM(IDLE/FIND/MOVE/GATHER/RETURN/DEPOSIT). claim/carry/final-deposit/despawn 규약 |
| `scripts/miner_3d.gd` | Miner FSM(IDLE/MOVE_TO_WORK/MINE/RETURN_TO_FACILITY). 직접 반납(carry 없음) |
| `tests/task3dwrk0011_test.gd` | WorkerActor3D 이동 골격 회귀 |
| `tests/task3dwrk0012_test.gd` | Lumberjack/Miner FSM wiring 회귀 |
| `tests/task3dwrk0013_test.gd` | Worker navigation stress regression(본 태스크) |

## 도메인 간 계약 (후속 태스크 지원)

1. **WRK - Foundation Navigation**
   - agent 생성 후 `NavigationPolicy3D.configure_agent()`만 호출한다. 도메인별
     agent 튜닝 금지(Foundation 001-5 LOCK).
   - 모든 이동은 `begin_move_to(pos)` / `begin_move_to_node(node)` 1건 시작 +
     `move_finished` 신호 정확히 1회 종료다. ARRIVED/BLOCKED/STALLED/TARGET_LOST/
     CANCELED 5값 외 종료 없고, 이동 중 재명령은 이전 시도를 무신호 대체한다.
   - unreachable target은 BLOCKED(부분 경로 소진) 또는 STALLED(stuck guard)로
     bounded 종료가 보장된다. 영구 MOVE stall 없음(stress test가 4초 window로
     상시 감시).
   - tracked node가 freed되면 다음 physics frame에 TARGET_LOST로 정리되며,
     freed 참조의 재수용은 `begin_move_to_node`가 false로 거부한다.

2. **WRK - RES (Resource)**
   - 자원 조회는 그룹 `"resource_nodes_3d"` + `resource_id == "wood"` +
     `can_interact()` + `is_claimed_by_other()` 필터(lumberjack `_find_nearest_tree`).
   - claim/release 규약 불변. stress test가 "claimer는 항상 live이며 그 worker의
     target_tree여야 함"을 매 frame 검증하고, full release 시점마다 잔여 claim 0을
     확인한다(claim leak 없음).

3. **WRK - BLD (BLD 3D 전환 전 duck-typed 계약)**
   - workplace는 Node면 충분하며 다음을 지원해야 한다:
     `work_radius`(px, float/int 프로퍼티), 자식 마커 `DepositPoint`/`SpawnPoint`/
     `WorkPoint`/`WorkPoint2`(Node3D), miner 분배가 필요하면
     `get_work_point_for(worker)` 메서드.
   - 배치/해제는 `worker._on_assigned(building)` / `worker._on_unassigned()`
     직접 호출 계약이다. BLD가 3D Workplace로 전환되어도 이 두 메서드 의미와
     "unassign 시 LJ는 마지막 1회 deposit 후 해제, miner는 즉시 IDLE" 규약을
     유지해야 한다.
   - duplicate actor 방지의 최종 담당은 BLD 측 `spawn_worker_actor`/
     `despawn_worker_actor` + WorkerRoster 오케스트레이션이다(3D 전환 대상).
     본 stress test는 group/subtree census 4/2/2 상시 일치로 회귀 감시망을 제공한다.

4. **Gate OPEN/CLOSED 표현 (BLD 3D gate 전환 시 동일 유지)**
   - passage CollisionShape3D 노드의 존재 여부가 곧 nav 장애물이다
     (OPEN = shape 제거, CLOSED = shape 생성). collision_layer 토글이나
     `disabled` 플래그로 표현하지 않는다(bake가 무시한다).
   - 상태 전환 후 `NavigationPolicy3D.request_rebuild_debounced()` 1회 호출.
     stress test가 반복 toggle + rebake 카운터 증가 + 폐쇄 중 침입 0을 검증했다.

5. **GameTime (DAY/NIGHT)**
   - Worker 생산/이동은 phase와 무관하게 지속된다(night 생산 stall 없음).
     stress run 전체를 DAY/NIGHT 수백 회 전환 속에서 진행해 확인했다.
   - 테스트에서 시간 진행은 `set_auto_advance(false)` + `advance()` 직접 호출
     규약(game_time.gd 주석)을 따른다.

## Stress Regression (TASK-3D-WRK-001-3) 검증 매핑

- 시나리오: LJ 2명(Lumberyard) + MN 2명(Quarry), Tree 6그루 + WorkPoint 2개 +
  StoneDeposit anchor, Static Building obstacle, 남북 완전 분리 wall row,
  toggle gate(유일 통로), 봉쇄 pen 안 unreachable Tree, assign/unassign 3라운드,
  DAY/NIGHT 반복 전환.
- obstacle 통과 금지: wall/building/gate(CLOSED)/trunk/deposit XZ 볼륨 center
  침입을 매 frame 검사 - 위반 0.
- permanent MOVE stall 없음: 연속 이동 240 physics tick(4s) displacement
  0.5unit 미만 감시 - 위반 0.
- duplicate actor 없음: 그룹/월드 census 전 구간 4/2/2 + 이름 unique.
- freed reference 없음: 운행 중 대상 tree 강제 free -> TARGET_LOST bounded 전이,
  freed 참조 보유 위반 0.
- 생산 중복 없음: wood 항등식 `deposited + carried == consumed(freed 포함)`을
  전 checkpoint에서 정확 일치, stone은 MINE tick 누적 대비 상한 이내.
- claim leak 없음: mid-run claim 정합성 + full release 시 잔여 claim 0.

## 테스트 작성 시 주의(후속 테스트 공통)

- `-s` 스탠드얼론 실행에서는 autoload 전역 식별자를 코드 참조로 쓰지 않고
  `root.get_node("VillageResources")` + `load()` 지연 로드를 사용한다.
- headless에서 idle(_process) frame rate와 physics tick rate가 1:1이 아니다.
  시간 의미 판정(예산/stall window/생산량 bound)은 반드시 `physics_frame` 신호
  기준으로 잰다. idle frame 기준으로 재하면 생산 과다 오탐이 발생한다.

## 검증 결과

- `tests/task3dwrk0013_test.gd`: 81 assertions 전부 PASS.
- 실행 로그: `test_results/task3dwrk0013_test_run.txt`.
- 실행 명령:
  `Godot_v4.7.1-stable_win64_console.exe --headless --path <project> -s res://tests/task3dwrk0013_test.gd`

## Visual 슬롯

- carry prop(`CarryProp`)과 work anim hook(`work_anim_started/stopped`)은
  WRK-001-2에서 확정한 VIS 교체 슬롯이다. 본 태스크에서 변경 없음.
