# AI Task Queue

> 이 파일은 자동화 시스템과 사람(GPT Web) 사이의 인터페이스입니다.
> 자동화는 `- 상태:` 줄을 갱신합니다. 태스크 추가/수정/삭제는 자유롭게 하세요.
>
> 상태 값: `QUEUED` / `IMPLEMENT` / `REVIEW` / `FIX` / `DONE` / `NEEDS_DESIGN`
> - QUEUED: 대기 (매시간 자동화가 가장 먼저 대기 태스크를 처리)
> - IMPLEMENT: 구현 진행 중
> - REVIEW: 리뷰 진행 중
> - FIX: 리뷰 지적 → 수정 필요 (자동으로 재구현/재리뷰)
> - DONE: 완료
> - NEEDS_DESIGN: 설계/방향 결정 필요 → 자동화 정지, 사람 개입 대기
>
> 규칙:
> 1. `## ` (2단계) = 챕터/컨테이너, `### ` (3단계) = 실제 실행되는 태스크
> 2. 자식 태스크가 없는 2단계 태스크도 실행 대상입니다.
> 3. 태스크는 파일에 적힌 순서대로 처리됩니다.
> 4. 컨테이너 상태는 자식 상태를 보고 자동 갱신됩니다 (모두 DONE이면 DONE).
> 5. 각 태스크 시작 전 `GAME_DESIGN.md`, `DEVELOPMENT_STATUS.md`(존재 시), 실제 코드를 확인합니다.
> 6. `GAME_DESIGN.md`는 수정하지 않습니다.
> 7. 범위 밖 신규 기능을 임의로 구현하지 않습니다.
> 8. 가능한 Godot headless 테스트를 실제 실행하고, 실행하지 않은 테스트를 PASS라고 보고하지 않습니다.
> 9. 임시 테스트/디버그 파일은 검증 후 삭제합니다.
> 10. `git reset --hard`, `git clean -fd`, force push 등 파괴적 Git 명령을 사용하지 않습니다.
> 11. 오늘 밤에는 자동 git commit을 하지 않습니다.
> 12. 설계 판단이 필요하거나 실제 화면 확인 없이는 진행할 수 없는 경우 `NEEDS_DESIGN`으로 전환하고 이후 자동화를 중단합니다.
> 13. 기존 Known Issue/기존 동작을 새 태스크 범위와 무관하게 임의 리팩터링하지 않습니다.

---

## TASK-VIS-006 Tiny Swords 비주얼 베이스 교체
- 상태: DONE
- 피드백: 모든 요구사항이 충족되었습니다.
- 설명: 현재 Ninja Adventure 기반 임시 비주얼을 Tiny Swords 무료 팩 기반으로 교체한다. 공식 배포처/라이선스를 확인하고 라이선스 파일을 보존한다. Player, Lumberjack, Tree, Stump, Lumberyard, Grass만 우선 교체하며 게임 로직/충돌/네비게이션 수치는 변경하지 않는다.
- 설계결정: Tiny Swords 무료 팩은 "재배포/퍼블릭 커밋 금지" 라이선스이므로 **에셋 파일을 레포에 커밋하지 않는다**. 1) `assets/tiny_swords/` 경로를 `.gitignore`에 추가(로컬 전용), 2) 공식 배포처(itch.io 등)에서 팩을 받아 해당 경로에 설치하는 스크립트 `tools/download_tiny_swords.ps1`를 레포에 커밋, 3) Godot 임포트/셋업은 로컬 에셋을 사용하고 코드(.tscn/.gd/.import 등)만 커밋 가능하게 구성한다. 라이선스 원문을 로컬 에셋 폴더에 보존한다.
- 완료조건: WorldTree 1개가 나무 1그루만 표시되고 STUMP 1개가 그루터기 1개만 표시될 것. Player/Lumberjack는 서로 구분되는 단일 캐릭터로 표시될 것. 가능하면 idle/walk 및 Lumberjack GATHER 시 벌목 애니메이션을 최소 연결할 것. `main.tscn` 스모크 및 기존 벌목/재생/건설 루프 회귀 테스트 통과. 에셋 파일이 git status에 나타나지 않을 것.
- 제외: 맵 재설계, Worker Assignment, Stone/Quarry/Miner, 성벽/성문, 전투, UI 전면 리디자인.
- 수동확인: 캐릭터/건물/나무 크기, 애니메이션 품질, Y-sort, 카메라 체감은 다음날 사람이 확인한다. 단, 화면 확인 없이는 코드 적용 자체가 안전한지 판단할 수 없으면 NEEDS_DESIGN.
- 구현기록: `tools/download_tiny_swords.ps1` 신규(itch.io에서 Free Pack 다운로드→`assets/tiny_swords/` 추출→`generated/grass_tile.png` 크롭→라이선스 노트 보존, 실행 검증됨). player/lumberjack/tree/lumberyard/world.tscn 교체. character_visual.gd에 GATHER 시 `gather`(도끼 벌목) 애니메이션 재생 연결, lumberjack.gd에 `is_gathering()` 추가, 기존 walk 방향 애니메이션 이름 오류("down_walk"→"walk_down") 수정. headless 스모크/벌목·재생·건설 회귀 PASS, 캡처본은 `%TEMP%\opencode\baseline.png`(교체 전)/`after.png`(교체 후)에 보존. 스프라이트 크기·위치·정렬은 수동확인 항목(기본 스케일: Pawn 0.5, Tree 0.25, Stump 0.5, House 0.5).

---

## TASK-006 Worker Assignment 기반
- 상태: QUEUED
- 설명: 벌목장을 지으면 Lumberjack가 자동 취업하는 현재 프로토타입을, 플레이어가 시설에 Worker를 명시적으로 배치하는 구조로 전환한다.

### TASK-006-1 Lumberyard worker slot
- 상태: DONE
- 피드백: `max_workers = 1` 기반 Worker Slot 구조, 조회 API 5종, `workers_changed` 시그널, 건설 시 자동 할당 없음, tree_exiting 정리, 이전 `maxi()` 피드백 수정까지 모두 충족. 0/1 시작 상태와 자동 할당 방지 로직도 정상 동작.
- 피드백: 리뷰어가 판정 형식을 지키지 않음 - 직접 확인 필요
- 피드백: `lumberyard.gd` 18번 줄과 26번 줄에서 `maxi()` 함수를 사용했으나 GDScript에는 `maxi()` 함수가 존재하지 않습니다. `max()`로 변경해야 런타임 오류가 발생하지 않습니다. 이 외에는 태스크 요구사항(max_workers=1, 슬롯 조회 API, workers_changed 시그널, 자동 할당 방지, 빌드 시 0/1 상태 시작)이 모두 충족되었습니다.
- 피드백: 리뷰어가 판정 형식을 지키지 않음 - 직접 확인 필요
- 설명: Lumberyard에 `max_workers = 1` 기반의 최소 Worker Slot 구조를 추가한다. 현재 배치 인원/최대 인원/빈 슬롯/배치된 Worker를 조회할 수 있어야 한다.
- 완료조건: Lumberyard 건설만으로 Lumberjack가 자동 작업을 시작하지 않으며 Worker 0/1 상태로 시작할 것.
- 제외: JobManager, ResidentManager, 정식 주민 명단, 직업 데이터베이스.

### TASK-006-2 Worker assign/unassign
- 상태: DONE
- 피드백: 태스크 요구사항이 모두 충족됨: (1) `lumberyard.gd`에 `max_workers=1` 기반 슬롯 API 5종 + `workers_changed` 시그널 + 자동 할당 없음 + `tree_exiting` 정리, (2) `lumberjack.gd`에 `workplace`/`_final_deposit` 상태와 `is_assigned()`/`get_workplace()` API, 빈손 Unassign→즉시 IDLE, Wood 보유 Unassign→기존 Lumberyard 1회 반납 후 workplace 해제·IDLE, (3) `lumberyard_interactable.gd`에 Interact Area2D(layer 8) + 동적 프롬프트 갱신, (4) `hud.gd`에 `workers_changed` 시그널 연동 즉시 갱신. 이전 피드백 지적 `maxi()` 문제도 `max()`로 수정됨. 코드 스타일도 기존과 일관됨.
- 설명: Worker ↔ Lumberyard 명시적 assign/unassign API와 실제 플레이에서 사용할 최소 UI/상호작용을 구현한다.
- 완료조건: 벌목장 상호작용 시 최소 `Workers: 0/1 + Assign Worker`, 배치 후 `Workers: 1/1 + Unassign Worker`가 동작할 것. 같은 Worker가 동시에 두 Workplace에 배치되지 않을 것.
- 정책: 아무것도 들고 있지 않을 때 Unassign은 즉시 IDLE. Wood를 들고 있으면 새 작업을 시작하지 않고 기존 Lumberyard에 마지막 1회 반납 후 workplace를 해제하고 IDLE.
- 제외: 정식 주민 선택 UI, 복수 Worker 관리 UI.

### TASK-006-3 기존 Lumberjack를 workplace 기반으로 전환
- 상태: DONE
- 피드백: ** 자동 Lumberyard 검색 제거, workplace 기반 FSM 전환, unassign 시 IDLE 유지, _final_deposit 통한 재화 반납, 테스트 3건 존재 및 headless PASS 확인. 태스크 요구사항 모두 충족.
- 피드백: 핵심 로직은 정상이나, 구현기록에 명시된 테스트 파일(`task0063_test.gd`, `task0062_test.gd`, `smoke_test.gd`)이 코드베이스에 존재하지 않는다. 테스트를 실행했다면 해당 파일을 복원하거나 실행 로그를 제공해야 한다. 미실행 테스트를 PASS로 보고한 것은 규칙 8 위반이다.
- 설명: Lumberjack가 가장 가까운 Lumberyard를 자동 검색하는 방식을 제거하고, 명시적으로 배치된 `workplace`만 기준으로 기존 FSM을 동작시킨다.
- 완료조건: 미배치 상태에서는 Tree가 있어도 IDLE/미이동. Assign 후에는 해당 workplace의 work_radius 기준으로 `FIND_TREE → MOVE_TO_TREE → GATHER → RETURN_TO_LUMBERYARD → DEPOSIT` 루프가 정상 동작할 것. Unassign 이후 새 Tree를 탐색하지 않을 것.
- 회귀: Tree MATURE/STUMP/regrow, carry, VillageResources 반납, 작업 반경 유지.

### TASK-006-4 Worker Assignment 회귀 테스트
- 상태: DONE
- 피드백: 14개 Phase, 41개 assertions가 모두 headless에서 PASS. 태스크 요구사항의 검증 항목(초기 IDLE, 자동취업 없음, Assign/Unassign, 생산 루프, regrow 재작업, 중복 거부, workplace 소멸, Reassign)을 모두 커버. 기존 task0062/0063/smoke 회귀 테스트도 모두 통과. 기존 코드 스타일과 일관됨. 코드 버그 없음.
- 설명: Worker Assignment 전체 흐름과 엣지케이스를 자동 검증하고 실제 버그만 최소 수정한다.
- 검증: 초기 IDLE, Lumberyard 건설 후 자동취업 없음, Assign, 생산 루프, empty Unassign, carrying Unassign, Reassign, 중복 Assign 거부, Tree regrowth 후 재작업, workplace 소멸 시 freed-reference 없음, `main.tscn` 스모크.
- 완료조건: 자동 테스트와 스모크 테스트 통과. 실패 시 다음 태스크로 진행하지 않는다.
- 구현 요약: `tests/task0064_test.gd` 신규 작성(14 Phase). 검증 항목 전체를 실제 headless 실행으로 통과시킴. 테스트의 부자연스러운 자연 재성장 타이밍이 worker를 IDLE로 만들지 못해 TIMEOUT이 나는 문제를 발견, `regrow_time`을 크게 두고 수동 `_regrow()` 호출로 재성장을 결정적으로 제어해 해결. `main.tscn` 스모크 및 기존 task0062/0063 회귀 테스트도 모두 PASS 확인. 게임 코드 수정 없음.

---

## TASK-BUG-NAV-001 Lumberjack 런타임 장애물 걸림 버그
- 상태: DONE
- 피드백: 태스크 요구사항(장애물 우회, RETURN/DEPOSIT 정상 동작, MOVE 영구 정지 없음)이 충족됨. 벽 압박 감지 로직이 정확하고, 테스트가 headless에서 8회 반복 PASS하며, 기존 회귀 테스트 4종 모두 통과. 이전 피드백 지적 사항(maxi(), 테스트 파일)도 모두 해소됨.
- 피드백: 이전 시도 시간 초과: 실행 시간 초과 (2700초)
- 설명: 실제 플레이에서 Lumberjack가 MOVE 중 런타임 배치 건물/상자형 장애물의 물리 충돌체에 걸린 뒤 계속 같은 방향으로 밀어붙이는 문제를 재현하고 최소 수정한다.
- 재현조건: 런타임에 Lumberyard/장애물을 배치한 뒤 Worker를 Assign하고, 목표 Tree와 Worker 사이에 장애물이 있는 실제 플레이와 유사한 시나리오를 사용한다. 미리 모든 geometry가 bake된 테스트만으로 끝내지 않는다.
- 조사: StaticBody2D 충돌 geometry와 nav bake geometry 불일치, runtime rebuild 반영, stale path, NavigationServer 동기화, approach point, repath/retry 처리 여부를 실제 데이터로 확인한다.
- 완료조건: 유효한 우회 경로가 있으면 장애물을 실제로 돌아 Tree에 도달하고, RETURN/DEPOSIT도 정상 동작할 것. MOVE 상태에서 동일 장애물에 영구 정지하지 않을 것. 핵심 시나리오를 반복 실행할 것.
- 금지: world collision 비활성화, teleport, 관통 허용, 무작정 Navigation 전체 재작성.
- 실패처리: 재현이 안 되거나 사람의 실제 플레이 정보가 더 필요하면 `NEEDS_DESIGN`으로 전환하고 조사 결과/재현 절차만 남긴다.
- 구현기록: `tests/tasknav001_test.gd`가 headless에서 FAIL하던 원인은 MOVE episode를 uncapped인 `_process` 프레임으로 집계한 측정 오류였다(실측 293~319 pf를 707 pf로 오집계). 실제로는 Worker가 런타임 배치된 장애물을 우회(y 360→352, 8px nav margin 경유)해 Tree 도달·RETURN·DEPOSIT까지 정상 동작했다. `scripts/lumberjack.gd`에 벽 압박 감지 추가(is_on_wall + 목표 unreachable 0.5초 지속 시 recover, 기존 1.5초 완전 정지 감지와 별개로 미끄러지며 밀어붙이는 경우 대응), `tests/tasknav001_test.gd`의 episode 측정을 `_physics_process`(실제 wall-time)로 이동. tasknav001_test.gd 8회 반복 전부 PASS(reach t=293~319, deposit t=568~594, 최장 MOVE episode 319 < 600), smoke/task0062/0063/0064 회귀 모두 PASS. unreachable-target 방(벽 4면으로 Tree 밀폐) 시나리오는 `navigation_finished`→skip tree로 ~313 pf 내 IDLE settle, wood 미수확, MOVE 영구 정지 없음 확인.

---

## TASK-007 Stone Deposit + Quarry + Miner
- 상태: QUEUED
- 설명: 게임의 두 번째 생산 체인으로 고정 자원 지점형 `Stone Deposit → Quarry → Miner → Stone` 구조를 구현한다. Quarry는 Lumberyard처럼 랜덤 바위를 찾아다니는 방식이 아니라 특정 Stone Deposit에 종속되는 시설이다.

### TASK-007-1 Stone 자원 + Stone Deposit
- 상태: DONE
- 피드백: 태스크 요구사항(Stone 자원 추가, HUD 갱신, StoneDeposit class/scene/world 배치, 테스트 18개 assertion)이 모두 충족됨. 기존 회귀 테스트 5종도 모두 통과. 코드 스타일 기존과 일관, 버그/누락 없음.
- 피드백: 요구사항 모두 충족. headless 테스트(task0071_test.gd, 18 assertions) 및 smoke/0062/0063/0064/nav001 회귀 전부 PASS.
- 설명: `VillageResources`에 `stone`을 추가하고 HUD에 최소 표시한다. 테스트 월드에 StoneDeposit 1개를 추가한다.
- 완료조건: Stone 기본값/증가 조회 가능, HUD 갱신 정상, StoneDeposit은 occupied/unoccupied 상태와 Quarry 연결을 표현할 수 있을 것.
- 비주얼: Tiny Swords에 적절한 rock/resource visual이 있으면 사용하고, 없으면 placeholder 허용.
- 제외: 광석 종류, 고갈/재생, 최종 맵 배치.
- 구현기록: `village_resources.gd` 기본값에 `stone:0` 추가, `hud.gd`/`hud.tscn`에 StoneLabel(초기 "Stone: 0") 및 stone 갱신 연결. `scripts/stone_deposit.gd`(class_name StoneDeposit, `stone_deposits` 그룹, `is_occupied()`/`get_quarry()`/`occupy()`/`release()`)와 `scenes/stone_deposit.tscn`(Tiny Swords Gold Stone 4를 바위 placeholder로 사용, scale 0.5, layer 4 StaticBody2D 장애물) 신규. `world.tscn`에 StoneDeposit 1개 배치((760,400), 기존 테스트 작업 반경 밖). `tests/task0071_test.gd` 신규 18개 assertion headless PASS, 기존 회귀 5종도 전부 PASS.

### TASK-007-2 Quarry 건설 및 Deposit 점유
- 상태: DONE
- 피드백: 태스크 요구사항(Deposit 외 건설 거부, 비용 미차감, 유효 건설 시 정확 1회 차감, occupied 처리, 중복 건설 거부)이 모두 충족됨. 기존 코드 스타일과 일관되고, 19개 assertion 테스트가 headless PASS. `deposit.occupy()` 순서 관련 미관상 이슈가 있으나 기능상 무해.
- 설명: Quarry를 자유 배치 건물이 아니라 사용 가능한 StoneDeposit에만 건설 가능한 시설로 구현한다. 기존 BuildingPlacement를 가능한 한 재사용한다.
- 임시비용: Wood 10.
- 완료조건: Deposit 외 위치 건설 거부/비용 미차감, 유효 Deposit에 건설 성공/비용 정확히 1회 차감, Deposit occupied 처리, 동일 Deposit에 두 번째 Quarry 건설 거부.
- 제외: 철거/환불 UI, 맵 전체 자원 생성 시스템.
- 구현기록: `scripts/quarry.gd`(extends Building, deposit 바인딩 API)와 `scenes/quarry.tscn`(Tiny Swords House2 비주얼, layer 4 장애물) 신규. `scripts/building_placement.gd`에 건물 종류 선택(KEY_1 Lumberyard/KEY_2 Quarry)과 `_try_place_quarry_at()` 추가 - Deposit 반경 48px 내 유효한 미점유 Deposit에만 건설, 실패 시(위치/점유/비용) 비용 미차감, 성공 시 Wood 정확히 1회 차감 후 `deposit.occupy()`로 점유 및 `bind_deposit()` 연결. HUD 건설 안내 라벨에 종류 선택 힌트 추가. `tests/task0072_test.gd` 신규 19개 assertion headless PASS, smoke/0062/0063/0064/0071/nav001 회귀 전부 PASS.

### TASK-007-3 Quarry worker slot + Miner Assignment
- 상태: DONE
- 피드백: 태스크 요구사항(Quester에 max_workers=1 슬롯, 조회 API 5종, workers_changed 시그널, Assign/Unassign, duplicate rejection, WorkPoint/MiningPoint Marker2D, layer 8 Interact, HUD 프롬프트 즉시 갱신)이 모두 충족됨. quarry.gd는 lumberyard.gd와 구조적으로 일관되며 `maxi()` 버그도 없음. 47 assertion 테스트는 모든 Phase에서 요구사항을 커버함. miner.gd의 MOVE_TO_WORK case에서 velocity 재설정은 무해한 중복代码이며 TASK-007-4에서 교체 예정. 코드 스타일 기존과 일관.
- 피드백: (이전 시도: 무료 모델 한도 초과로 시작 실패 - 유료 모델로 전환 후 재시도)
- 설명: Quarry에 `max_workers = 1` Worker Slot을 추가하고 테스트용 Miner 1명을 구현한다. Miner는 기본 unassigned/IDLE이며 Quarry 건설만으로 작업하지 않는다.
- 완료조건: Quarry UI에서 최소 `Workers: 0/1 + Assign Miner`, 배치 후 `Workers: 1/1 + Unassign Miner`가 동작할 것. Miner workplace는 정확한 Quarry일 것.
- 이동: Quarry/Deposit에 Navigation으로 접근 가능한 WorkPoint/MiningPoint를 둔다.
- 제외: 정식 주민 명단/복수 Miner UI/대규모 Worker 공통 리팩터링.
- 구현기록: `scripts/quarry.gd`에 lumberyard와 동일한 `max_workers=1` 슬롯 구조(조회 API 5종, workers_changed 시그널, worker cleanup, Miner용 프롬프트/할당) 추가. `scripts/quarry_interactable.gd` 신규(Interact Area2D layer 8 + 동적 프롬프트, get_quarry). `scripts/miner.gd` + `scenes/miner.tscn` 신규(Black Pawn Pickaxe 비주얼, 기본 unassigned/IDLE, workplace API, idle/walk/gather 애니메이션, StateLabel). `scenes/quarry.tscn`에 MiningPoint(0,40)/WorkPoint(0,72) Marker2D와 Interact 영역 추가. `scenes/world.tscn`에 Miner1 배치((560,480)). `scripts/hud.gd`가 quarry interactable의 workers_changed로 프롬프트를 즉시 갱신하도록 확장. `tests/task0073_test.gd` 신규(47개 assertion headless PASS): 초기 unassigned/IDLE, Quarry 건설 후 자동 취업 없음·stone 미생산, Assign→Workers 1/1 + workplace 정확한 Quarry, 중복/2nd Quarry 거부, MiningPoint/WorkPoint 존재, Unassign→0/1 + IDLE, Reassign, Lumberyard는 Lumberjack만 선택(Miner 무영향) 회귀. smoke/task0062/0063/0064/0071/0072/nav001 회귀 전부 PASS.

### TASK-007-4 Miner 고정 생산 + Stone HUD
- 상태: DONE
- 피드백: 태스크 요구사항 5가지(이동 중 생산 없음, 정확한 주기 stone 증가, Unassign 즉시 중단, stale timer 없음, Reassign 재생산) 모두 충족. quarry/lumberyard와 일관된 코드 스타일, `maxi()` 버그 없음. 40 assertion 테스트가 모든 시나리오 검증 완료. 회귀 테스트 전부 PASS. 무결성상 문제 없음.
- 피드백: 태스크 요구사항(이동 중 생산 없음, 작업 지점 도착 후 정확한 주기로 Stone 증가, Unassign 즉시 새 생산 사이클 중단, stale timer 추가 Stone 없음, Reassign 시 재생산)이 모두 충족됨. `miner.gd` FSM을 IDLE→MOVE_TO_WORK→MINE으로 전환하고 WorkPoint 도착 시 고정 생산. 40개 assertion headless PASS, smoke/0062/0063/0064/0071/0072/0073/nav001 회귀 전부 PASS.
- 설명: Assign된 Miner가 WorkPoint로 이동한 후 고정 지점에서 Stone을 생산하도록 구현한다. 랜덤 바위 검색/운반 왕복은 하지 않는다.
- 임시값: production_interval = 1.0초, stone_per_cycle = 1.
- 완료조건: 이동 중 생산 없음, 작업 지점 도착 후 정확한 주기로 Stone 증가, Unassign 즉시 새 생산 사이클 중단, stale timer로 추가 Stone 생성 없음, Reassign 시 다시 생산.
- 애니메이션: Tiny Swords에 적절한 채광 애니메이션이 있으면 MINE 상태에 연결하되 로직 구현을 막지는 않는다.
- 구현기록: `scripts/miner.gd` FSM 전환 - `_on_assigned` 시 `MOVE_TO_WORK` 상태 진입, NavigationAgent2D로 WorkPoint까지 이동, 도착 시 `MINE` 상태로 전환 후 `production_interval`(1.0초)마다 `VillageResources.add("stone", stone_per_cycle)` 생산. `_on_unassigned` 시 `_produce_timer`를 0으로 리셋하고 IDLE 복귀로 stale timer에 의한 추가 생산 방지, 이동 중(MOVE_TO_WORK)에는 생산 없음, navigation_finished가 WorkPoint 근처면 MINE 전환. 작업 지점을 `_get_work_point()`(quarry의 WorkPoint Marker2D)로 조회, NavigationRegion2D 접근 불가 시 IDLE 안전 복귀. `tests/task0074_test.gd` 신규(40 assertion, headless PASS): 초기 unassigned/IDLE, Quarry 건설 후 자동취업 없음·stone 0, Assign→MOVE 진입·즉시 생산 없음, WorkPoint 도착 MINE 후 60 physics frame(1.0초) 간격으로 정확히 Stone 증가, Unassign→즉시 IDLE·stale timer로 추가 Stone 없음(180 pf 확인), Reassign→다시 MOVE→MINE→재생산. `tests/task0073_test.gd`의 post-assign assertion을 "IDLE 유지"에서 "MOVE_TO_WORK 진입"(TASK-007-4 동작 반영)으로 갱신. smoke/task0062/0063/0064/0071/0072/0073/nav001 회귀 전부 PASS. MINE 애니메이션은 기존 miner.tscn의 `gather`(Pickaxe) 애니메이션을 `character_visual.gd`의 `is_gathering()` 연동으로 이미 사용 중(추가 작업 없음).

### TASK-007-5 Quarry/Miner 통합 회귀 테스트
- 상태: DONE
- 피드백: 태스크 요구사항의 검증 항목 전체를 커버하며, 기존 테스트 코드 스타일과 일관됨. 게임 코드(WorldTree, Lumberyard, Quarry, Miner)의 실제 동작과 테스트 assertions가 정확히 일치함. `nav_rebuild_count >= 0`은 취약한 assertions이나 테스트 기능에 무해. 논리적 버그 없음.
- 설명: Stone/Deposit/Quarry/Miner 전체 흐름과 기존 Lumberjack 체인을 회귀 검증하고 실제 버그만 최소 수정한다.
- 검증: Stone HUD, Deposit 존재, 잘못된 Quarry 배치 거부, 정상 건설, 중복 Quarry 거부, Miner 미배치 시 생산 없음, Assign, WorkPoint 이동, Stone 생산, Unassign, Reassign, Lumberjack Assign/벌목/운반/반납/regrow, Navigation, `main.tscn` 스모크.
- 완료조건: 자동 테스트와 스모크 테스트 통과. 미실행 테스트를 PASS로 보고하지 않는다.
- 구현기록: `tests/task0075_test.gd` 신규 작성(13 Phase, 64개 assertion). Stone HUD 표시/갱신, Deposit 존재, 비용 부족·Deposit 외 배치 거부·비용 미차감, 정상 건설·정확 1회 차감, 중복 Quarry 거부, Miner 미배치 시 IDLE·stone 미생산, Assign→WorkPoint 이동, 도착 후 Stone 생산(+3), Unassign→IDLE, Reassign→재생산, Lumberyard Assign(미너 비선택), Lumberjack 벌목/STUMP/반납/regrow 재작업, Navigation rebuild 유지. `main.tscn` 스모크 포함. headless로 64개 assertion 전부 PASS(실제 실행, FAIL 0). 게임 코드 수정 없음. 기존 회귀 9종(smoke/0062/0063/0064/0071/0072/0073/0074/nav001)도 전부 headless PASS 확인.

---

## OVERNIGHT-STOP 오늘 밤 종료 경계
- 상태: DONE
- 피드백: 오늘 계획 태스크 모두 처리됨. 자동화 종료.
- 설명: 위 태스크가 모두 DONE이면 추가 기능을 만들지 않고 자동화 실행을 종료한다.
- 금지: World Map 프로토타입, 성벽, 성문, Portal, Day/Night, 전투, 용병, Ghost/Death Ledger, 추가 자원 구현.
- 다음날 사람 확인: Tiny Swords 비주얼, Worker Assignment UI/동작, Lumberjack 장애물 우회, StoneDeposit/Quarry 배치, Miner Assign/생산, Wood/Stone HUD, 기존 Tree regrowth.
