# AI Task Queue

> TASK-016 Death Ledger 완료 이후 신규 실행 큐.
>
> 완료된 TASK-013~016 상세 이력은 이전 큐에 보존하며 이 파일에 복사하지 않는다.
>
> 현재 목표:
> Player 직접 조작 제거 → Mouse/Camera 기반 관리형 조작 전환 → World Scale Expansion → World Map View → Exploration Foundation 순서로 기반을 재구성한다.
>
> 상태: `QUEUED` / `IMPLEMENT` / `REVIEW` / `FIX` / `DONE` / `NEEDS_DESIGN`

---

# 공통 실행 규칙

> 1. `##` = 챕터/컨테이너, `###` = 실제 실행 태스크.
>
> 2. 실제 구현은 `### TASK-*` 단위로 파일 순서대로 실행한다.
>
> 3. 각 태스크 시작 시 `GAME_DESIGN.md`, `DEVELOPMENT_STATUS.md`의 **현재 태스크 관련 섹션만 우선 확인**하고 실제 코드를 확인한다.
>
> 4. 문서보다 현재 코드가 더 최신일 수 있으므로 구현 전 실제 Scene/Script/API 구조를 반드시 확인한다.
>
> 5. 범위 밖 시스템 임의 구현 금지.
>
> 6. 현재 태스크 완료에 필요한 최소 변경만 허용한다.
>
> 7. 기존 정상 동작 시스템의 대규모 리팩터링 금지.
>
> 8. Godot headless 테스트를 실제 실행하고 미실행 테스트를 PASS로 보고하지 않는다.
>
> 9. 테스트 PASS만으로 미감/체감이 검증되었다고 판단하지 않는다.
>
> 10. 미감/체감/조작감은 `HUMAN_CHECK`에 남기고 코드/자동검증이 정상이라면 DONE 가능하다.
>
> 11. 설계 공백 또는 기존 설계와 직접 충돌이 있으면 임의 결정하지 말고 `NEEDS_DESIGN`으로 중단한다.
>
> 12. 파괴적 Git 명령 금지.
>
> 13. 자동 commit / push 금지.
>
> 14. 기존 사용자 변경사항을 임의 revert하지 않는다.
>
> 15. 임시 진단 파일은 태스크 종료 전 반드시 제거한다.
>
> 16. `_diag*`, `_probe*`, `_debug*`, `_temp*` 등 임시 파일이 남지 않았는지 종료 시 확인한다.
>
> 17. 기존 테스트를 단순히 PASS시키기 위해 assertion 의미를 약화시키지 않는다.
>
> 18. 요구사항 변경으로 기존 테스트를 수정해야 할 경우 변경 이유를 구현기록에 남긴다.
>
> 19. freed instance reference / duplicate actor / stale navigation 상태가 남지 않아야 한다.
>
> 20. TASK 완료 후 다음 `###` 태스크로만 진행하며 `## OVERNIGHT-STOP-*` 도달 시 신규 시스템을 자동 시작하지 않는다.

---

# 리뷰 규칙

> 1. 리뷰어 내부 판정과 Queue의 `상태:` 값은 별개다.
>
> 2. 리뷰어 판정은 `LGTM` / `FIX` / `HUMAN_CHECK` 등을 사용할 수 있다.
>
> 3. `상태: REVIEW`는 리뷰 진행 중 정상 상태이며 REVIEW라는 이유 자체를 FIX 사유로 판단하지 않는다.
>
> 4. 리뷰어는 구현/요구사항/테스트의 실제 문제만 FIX 사유로 제시한다.
>
> 5. 상태 전환은 자동화 Supervisor의 책임이며 리뷰어가 상태값 자체를 요구사항으로 평가하지 않는다.
>
> 6. 코드와 자동검증이 정상이고 남은 항목이 미감/플레이 감각뿐이면 `HUMAN_CHECK`를 남기고 LGTM 가능하다.
>
> 7. 동일한 잘못된 리뷰 사유를 반복해 무한 FIX loop를 만들지 않는다.
>
> 8. 리뷰 판정 문자열은 일반 텍스트/Markdown bold 여부와 무관하게 동일한 판정으로 취급한다.

---

# 게임 핵심 규칙

> 1. 플레이어 캐릭터는 어떤 상황에서도 직접 전투하지 않는다.
>
> 2. Player에 공격, 무기, 공격 스킬, Damage Dealer 역할을 추가하지 않는다.
>
> 3. 핵심 전투 원칙:
>
> **전투는 자동, 판단은 플레이어가 한다.**
>
> 4. Worker가 반복 노동을 수행한다.
>
> 5. Mercenary가 전투를 수행한다.
>
> 6. 향후 Scout / Expedition이 외부 탐사를 수행한다.
>
> 7. 플레이어는 상위 관리 주체이며 직접 필드를 걸어 다니는 Avatar가 아니다.
>
> 8. 기본 조작은 Camera + Mouse 기반 관리 조작으로 통일한다.
>
> 9. DAY는 경제/건설/고용/생산/탐사 준비 중심.
>
> 10. NIGHT는 자동전투 관찰 + 전술 명령 중심.
>
> 11. 조작 방식은 DAY/NIGHT 모두 Camera + Mouse 기반이지만 가능한 행동과 UI 목적은 명확히 구분한다.
>
> 12. 새로운 영역과 기회는 플레이어의 탐사와 판단으로 발견하며 반복되는 일은 주민과 시설이 대신한다.

---

# Player Avatar 제거 LOCK

> 1. 기존 Player CharacterBody2D의 직접 WASD 이동 구조는 최종 게임에서 제거한다.
>
> 2. Player Avatar를 단순 장식 NPC로 유지하지 않는다.
>
> 3. 기존 Player InteractArea를 전역 마우스 클릭 상호작용 구조로 대체한다.
>
> 4. 건물 사용을 위해 Player가 물리적으로 접근할 필요가 없다.
>
> 5. 자원 채집을 Player가 직접 수행하는 구조는 제거한다.
>
> 6. Player 직접 탐험은 제거하고 향후 Scout / Expedition으로 대체한다.
>
> 7. 기존 Player 이동/상호작용 코드는 새 구조가 안정화된 뒤 안전하게 제거한다.
>
> 8. 테스트를 통과시키기 위해 화면 밖에 Player Actor를 숨겨 유지하는 방식은 금지한다.
>
> 9. 기존 코드가 Player node 존재를 전제로 하는 부분은 실제 필요성을 검토해 의존성을 제거하거나 더 적절한 소유자로 이전한다.
>
> 10. Player combat은 기존에도 없으며 앞으로도 추가하지 않는다.

---

# Mouse / Camera 조작 LOCK

> DAY 기본 입력:
>
> - WASD / 방향 입력 = Camera Pan.
> - Mouse Wheel = Camera Zoom.
> - Left Click = 건물/시설/유닛/월드 오브젝트 선택 또는 UI 열기.
> - Right Click / ESC = 선택 해제 또는 현재 contextual mode 취소.
> - Build 입력 = 기존 BuildingPlacement 진입.
>
> NIGHT 기본 입력:
>
> - WASD / 방향 입력 = Tactical Camera Pan.
> - Mouse Wheel = Tactical Zoom.
> - Left Click = Mercenary / Enemy / Gate / Tactical target 선택.
> - 기존 Defense Zone / Regroup / Retreat / Focus Target / Gate / Pause / 1x / 2x 유지.
>
> 공통:
>
> - Camera는 World boundary 밖으로 이동하지 않는다.
> - 클릭 가능한 오브젝트와 단순 decoration을 명확히 구분한다.
> - click interaction을 위해 대형 범용 ECS/Selection Framework를 선행 구현하지 않는다.
> - 이번 큐에서는 box selection, drag selection, RTS formation control을 구현하지 않는다.

---

# World 방향 LOCK

> 1. WEST = Main Threat / Main Portal / Main Battlefield.
>
> 2. 기본 Enemy 진입축 = WEST → EAST.
>
> 3. NORTH = Secondary Threat / Rift.
>
> 4. EAST = Royal Road / 외부 문명 방향이며 기본 Enemy Spawn이 아니다.
>
> 5. SOUTH = Production / Agriculture 방향이며 기본 Enemy Spawn이 아니다.
>
> 6. 현재 중앙 Core Village의 역할과 방향별 visual identity는 유지한다.
>
> 7. World 확대 시 중앙 마을 자체를 동일 비율로 확대하지 않는다.
>
> 8. 확대의 핵심은 Outer Wild / 접근로 / 탐사 공간 / 생산 외곽 공간을 늘리는 것이다.
>
> 9. 기존 Wall / Gate / Navigation / Tactical Combat 구조를 유지한다.
>
> 10. Gate 상태 `CLOSED / OPEN / BREACHED` 유지.
>
> 11. 현재 Tiny Swords는 임시 에셋으로 유지하며 이번 큐에서 전체 Asset Migration을 수행하지 않는다.

---

# Death Ledger LOCK

> 1. TASK-016 Death Ledger 구현을 유지한다.
>
> 2. Mercenary / Enemy 실제 lethal death 기록은 계속 동작해야 한다.
>
> 3. cleanup/despawn은 DeathRecord를 만들지 않는다.
>
> 4. Player Avatar 제거 과정에서 Death Ledger 구조를 변경하거나 제거하지 않는다.
>
> 5. Ghost 실제 기능은 이번 큐에서 구현하지 않는다.
>
> 6. TASK-017 First Ghost Return 번호/범위는 후속 큐로 보존한다.

---

# 이번 큐 금지 시스템

> 다음 기능은 명시적으로 금지:
>
> - GhostActor.
> - GhostFactory.
> - GhostReturnSpawner.
> - Ghost Shader / Ghost Combat.
> - 정식 WaveManager.
> - Wave progression.
> - Boss.
> - Siege Enemy.
> - 신규 Enemy archetype.
> - 신규 Mercenary class.
> - Food.
> - Cooking.
> - Potion.
> - Morale.
> - Equipment progression.
> - Farm 실제 생산 기능.
> - Dungeon 실제 기능.
> - 전체 Save/Load 시스템.
> - 전체 Asset Migration.
> - 대규모 UI polish.
> - Player combat.
> - Box Selection.
> - RTS formation editor.

---

## TASK-CTRL-001 Player Direct Control → Mouse/Camera Management

- 상태: QUEUED

- 설명: 기존 Player Avatar 직접 조작 구조를 제거하고 DAY/NIGHT 모두 Camera + Mouse 기반 관리 조작으로 전환한다. 이 작업은 프로토타입이 아니라 확정 조작 구조 변경이다.

- 핵심:

  - Player 직접 이동 제거.
  - Player 물리 접근 기반 interaction 제거.
  - DAY Camera 자유 이동.
  - Mouse click 기반 시설 interaction.
  - NIGHT Tactical Camera와 입력 정책 통합.
  - 기존 건설/고용/Worker/Combat/Tactical 기능 유지.

- 금지:

  - Player를 화면 밖에 숨겨 유지하는 임시 구조.
  - Player 대체 전투 유닛.
  - 범용 RTS Selection Framework.
  - Box Selection.
  - Scout / Expedition 실제 기능.
  - World Map View.
  - World Scale Expansion.

### TASK-CTRL-001-1 Camera Controller Ownership 분리

- 상태: DONE
- 피드백: 카메라 소유권 분리, Player 의존 제거, DAY/NIGHT pan/zoom, phase 전환 연속성, capture 도구 복구, 테스트 갱신 모두 요구사항 충족. 임시 파일 0건. 독립 하드코딩은 MAP 확장 태스크에서 해결 가능.
- 구현 노트 (TASK-CTRL-001-1):
  - 신규 `scripts/camera_controller.gd` + `scenes/camera_controller.tscn` (Camera2D 소유).
  - `main.tscn`에 CameraController 인스턴스 추가, Player에서 Camera2D 제거.
  - `player.gd`에서 Camera/Zoom/WASD 이동 제거 (Player는 정지, interact 로직만 유지).
  - DAY WASD = camera pan, NIGHT WASD = tactical camera pan 유지.
  - Mouse wheel zoom (zoom target 증감, min/max clamp) 지원.
  - World boundary clamp 유지 (WORLD_BOUNDS ±1024).
  - DAY↔NIGHT 전환 시 camera position 연속성 유지 (jump 최소화).
  - `tools/capture_world.gd:36` stale `Main/Player/Camera2D` reference를 `camera_controller` 그룹 기반으로 갱신 (screenshot 캡처 복구).
  - 영향받은 테스트 20개 갱신 (task0081/0082/0085/0103/0104/0105/0117/0127/0128/0134/0147/0151/0153~0158).
  - 회귀: 전체 테스트 스위트 실행. 단, `task0082`/`task0122`는 HEAD 시점부터 존재하던 World Visual Composition 이후 지도 변경 사항과
    불일치하는 pre-existing 실패(settlement center grass / secondary path 시작점)로 이번 태스크와 무관함. 그 외 전부 PASS.

- 설명: 기존 Player node가 소유하던 Camera2D 이동/Zoom 책임을 Player와 분리된 World Camera Controller로 이전한다.

- 요구사항:

  - DAY/NIGHT 모두 동일 Camera2D 또는 명확한 단일 Camera Controller가 관리.
  - DAY WASD = camera pan.
  - NIGHT WASD = 기존 Tactical camera pan 유지.
  - DAY/NIGHT zoom target 정책 유지.
  - Mouse wheel zoom 지원.
  - World boundary clamp 유지.
  - DAY↔NIGHT 전환 시 camera offset/position jump 최소화.
  - Player global_position에 camera가 종속되지 않음.

- 기존 유지:

  - TASK-010 Day/Night.
  - TASK-015 Night Tactical Camera.
  - Tactical Command UI.
  - World Visual Composition.

- 완료조건:

  - Player node 이동 없이 DAY camera pan 가능.
  - NIGHT tactical pan 정상.
  - zoom 정상.
  - world boundary clamp 정상.
  - DAY/NIGHT 반복 transition 안정.
  - camera가 Player node에 의존하지 않음.

### TASK-CTRL-001-2 Mouse World Selection / Interaction

- 상태: DONE
- 피드백: 56개 assertion 전부 PASS. 구현이 요구사항을 충족하며, 기존 interact() API를 정확히 재사용하고, decoration/ground/자원노드 클릭 안전, build mode/modal UI/NIGHT 가드 정상, Player 의존 없음. 코드 스타일과 설계 일관성 양호. 임시 파일 없음.
- 피드백: [재검토] 리뷰어 판정 미출력으로 파싱 실패 - 구현은 완료(taskctrl0012_test.gd 존재), 리뷰 재실행
- 구현 노트 (TASK-CTRL-001-2):
  - 신규 `scripts/world_selection.gd` + `scenes/main.tscn`에 `WorldSelection` 노드 추가.
  - Left Click = 클릭 지점 최상위 유효 관리 대상(건물/시설/성문) 1개 선택 + 기존 `interact()` API 재사용(Tavern→Recruitment, Inn→Roster).
  - decoration/ground/나무(자원 노드) click은 interaction 없음. 나무는 Worker 전용으로 제외해 마우스 직접 채집 차단.
  - Right Click / ESC = 선택 해제(ESC는 모달 UI 닫기와 공유, handled로 삼키지 않음).
  - Build mode 활성 / 모달 UI 열림 / NIGHT에서는 월드 click 차단(UI click-through 방지).
  - Player 근접/물리 접근 전제 제거(Player가 멀리 있어도 클릭 interaction 동작).
  - `building_placement.gd`에 `is_active()` 공개 접근자 추가(build mode 충돌 방지용).
  - 신규 `tests/taskctrl0012_test.gd` 50개 assertion headless PASS.

- 설명: 기존 Player InteractArea/E 접근 방식 대신 마우스 클릭으로 건물/시설/주요 상호작용 오브젝트를 선택하고 기존 UI를 열 수 있게 한다.

- 최소 대상:

  - Tavern.
  - Inn.
  - Keep.
  - Grocery.
  - Equipment Shop.
  - Lumberyard.
  - Quarry.
  - Gate.

- 요구사항:

  - Left Click으로 world object 선택.
  - 오브젝트가 기존 interact() API를 보유하면 가능한 범위에서 재사용.
  - 클릭 지점의 최상위 유효 interaction 대상 1개만 선택.
  - decoration / ground click은 interaction을 실행하지 않음.
  - ESC 또는 Right Click으로 selection/context 해제.
  - UI가 열린 상태에서 월드 클릭이 UI를 관통하지 않게 처리.
  - Player가 근처에 없어도 interaction 가능.
  - 기존 Tavern Recruitment / Inn Roster UI 재사용.

- 금지:

  - 새로운 대형 InteractionManager.
  - 전체 UI 재디자인.
  - 클릭할 때 Player Actor를 순간이동시키는 방식.

- 완료조건:

  - Tavern click → 기존 Recruitment UI open.
  - Inn click → 기존 Roster UI open.
  - Gate click → 상태 확인/기존 interaction 정책과 충돌 없음.
  - Lumberyard/Quarry click 가능.
  - 빈 땅/장식 클릭 안전.
  - UI click-through 없음.

### TASK-CTRL-001-3 Building Placement Mouse Workflow 정리

- 상태: DONE
- 피드백: `building_placement.gd:88-89`에 Right Click cancel이 이미 구현되어 있고, `taskctrl0013_test.gd:286-296`에서 4개 assertion으로 검증하고 있다. 피드백에서 "처리 누락"이라고 기술한 부분은 실제 코드와 불일치하며 stale feedback으로 판단된다. 전체 10개 검증 항목이 충족되었고, 기존 설계/스타일과 일관성 유지, 임시 파일 없음.**
- 피드백: -87 |
| ESC = cancel | ✅ | `ui_cancel` → `_set_active(false)` (lines 69-71) |
| Right Click = cancel | ✅ | `MOUSE_BUTTON_RIGHT` → `_set_active(false)` (lines 88-89) |
| Wall continuous placement | ✅ | `_try_place_wall_at()` does NOT call `_set_active(false)` |
| Remove mode | ✅ | KEY_R toggle (line 63), refund (line 487) |
| Gate Corridor validation | ✅ | `_is_valid_gate_position()` (line 264) |
|
- 피드백: Task 요구사항 "ESC / Right Click = build mode cancel" 미충족. `building_placement.gd`의 `_unhandled_input`에 `MOUSE_BUTTON_RIGHT` → `_set_active(false)` 처리 누락. ESC만으로는 build mode cancel 경로가 불완전함.

- 설명: Player 직접 이동 제거 후에도 기존 BuildingPlacement가 Camera + Mouse 기반으로 자연스럽게 동작하도록 입력 ownership을 정리한다.

- 요구사항:

  - 기존 16px logical grid 유지.
  - 기존 Lumberyard / Quarry / Wall / Gate placement 유지.
  - 기존 valid/invalid ghost 유지.
  - Camera pan/zoom 중 world mouse position 계산 정상.
  - Build mode와 normal selection mode 충돌 금지.
  - Build mode에서 Left Click = place.
  - ESC / Right Click = build mode cancel.
  - Wall continuous placement 유지.
  - Remove mode 유지.
  - Gate Corridor validation 유지.
  - placement 후 nav rebuild 정책 유지.

- 완료조건:

  - zoom/pan 상태에서도 정확한 grid cell에 배치.
  - normal object selection과 build click이 동시에 실행되지 않음.
  - 비용/환불 정상.
  - Wall/Gate nav 정상.

### TASK-CTRL-001-4 Player Avatar Dependency 제거

- 상태: DONE
- 피드백: 모든 요구사항 충족. Player 노드/파일 완전 제거, HUD 전환 정상, 31개 테스트 no-player 검증 패턴 일관, 런타임 dangling reference 0건, 기존 시스템 영향 없음. headless smoke PASS 확인. PLAYER_AVATAR 제거 Lock 10개 항목 전부 충족.
- 구현 노트 (TASK-CTRL-001-4):
  - `scenes/main.tscn`에서 Player 인스턴스/player.tscn ext_resource 제거 (runtime Player Actor 없음).
  - `scripts/hud.gd` Player proximity prompt 제거 → WorldSelection.selection_changed 기반 마우스 컨텍스트 prompt 전환("E - " → "Click - "). `ui/hud.tscn` InteractLabel 기본 텍스트 갱신.
  - 미사용 `scenes/player.tscn` / `scripts/player.gd` / `scripts/player.gd.uid` 안전 제거 (참조 0건 확인).
  - GameTime/NIGHT Player movement disable 의존 없음 확인 (기존에 Player를 참조하지 않음).
  - 테스트 41개 갱신: `_player` var/할당 제거, `player exists` assertion → `get_nodes_in_group("player").size() == 0` (Player 비전투 핵심 규칙 의도 유지), Player Start 좌표 assertion → Settlement Start (0,+60) clearing/axis 검증, task0134는 테스트 전용 CharacterBody2D physics probe fixture로 대체, task0144 enemy-probe는 정착지 중심 고정 좌표로 대체.
  - 회귀: 전체 테스트 스위트 headless 실행. task0082/task0122는 HEAD 시점부터 존재하던 pre-existing 실패(settlement center grass / secondary path 시작점), taskctrl0013은 headless mouse-position 문제로 pre-existing 실패(HEAD 원복 후에도 동일). 그 외 전부 PASS.

- 설명: Camera/Interaction/BuildingPlacement 전환 후 Player Actor와 Player-specific runtime 의존성을 제거한다.

- 요구사항:

  - main/world scene에서 Player Avatar 제거.
  - CharacterBody2D Player spawn 제거.
  - Player collision 제거.
  - Player InteractArea 제거.
  - Player 직접 resource gathering 경로 제거.
  - HUD에서 Player proximity 기반 prompt 제거 또는 mouse-context 기반으로 전환.
  - GameTime/NIGHT 로직의 Player movement disable 의존 제거.
  - 테스트에서 Player node 존재를 성공 조건으로 보던 assertion 갱신.
  - Player combat 없음이라는 핵심 규칙은 Player node 삭제 이후에도 문서/테스트 의도로 유지.

- 중요:

  - Player script를 즉시 삭제하기 전에 프로젝트 전체 reference 검색.
  - 더 이상 참조되지 않는 Player scene/script만 안전하게 제거.
  - 테스트용 fixture가 실제 Player runtime을 억지로 필요로 하면 fixture도 새 구조에 맞게 수정.
  - unrelated system까지 리팩터링하지 않음.

- 완료조건:

  - 정상 게임 실행에 Player Actor가 필요하지 않음.
  - Player scene/script 미사용이면 안전 제거.
  - dangling reference 없음.
  - smoke PASS.

### TASK-CTRL-001-5 Mouse/Camera Management 통합 검증

- 상태: QUEUED

- 설명: Player 없이 DAY 관리 → NIGHT 전술 → DAY 복귀의 전체 조작 흐름을 하나의 headless/입력 시뮬레이션 시나리오로 검증한다.

- 시나리오:

  1. 게임 시작.
  2. Player Actor가 runtime world에 존재하지 않음 확인.
  3. DAY camera pan.
  4. mouse wheel zoom.
  5. Tavern click → Recruitment UI.
  6. Mercenary 고용.
  7. Inn click → Roster UI.
  8. defense assignment.
  9. Lumberyard/Quarry interaction.
  10. BuildingPlacement 진입.
  11. pan/zoom 상태에서 building placement.
  12. Wall/Gate placement.
  13. NIGHT 전환.
  14. Tactical Camera pan.
  15. Tactical Command UI 사용.
  16. Enemy/Mercenary auto combat.
  17. Death Ledger lethal death 기록 유지.
  18. DAY 복귀.
  19. Camera/selection/build state 정상 reset.
  20. 다음 NIGHT 반복 시 duplicate/stale reference 없음.

- 회귀:

  - smoke.
  - Worker/Navigation.
  - TASK-013 Wall/Gate.
  - TASK-014 Combat.
  - TASK-015 Tactical Combat.
  - TASK-016 Death Ledger.
  - World Visual Composition.

- HUMAN_CHECK:

  - DAY에 Player가 없어도 게임을 조작하는 느낌이 충분한지.
  - camera pan 속도.
  - mouse zoom 범위/속도.
  - 건물 클릭 hit area.
  - 건설과 일반 선택 mode 구분이 직관적인지.
  - DAY/NIGHT 조작감 차이가 목적에 맞게 느껴지는지.

- 완료조건:

  - Player 없는 full cycle 자동검증 PASS.
  - 기존 핵심 시스템 회귀 PASS.
  - HUMAN_CHECK만 남으면 DONE.

---

## TASK-MAP-001 World Scale Expansion 128 → 192

- 상태: QUEUED

- 설명: Player 직접 이동 제거 이후 오버월드의 선형 크기를 128×128 logical tiles에서 192×192 logical tiles로 확장해 탐사/물류/방어/외곽 공간을 확보한다.

- 목표 크기:

  - logical grid: 16px 유지.
  - 기존: 128×128 = 2048×2048px.
  - 신규: 192×192 = 3072×3072px.

- 핵심:

  - Core Village 규모는 대폭 확대하지 않음.
  - Outer Wild / 접근로 / 생산 외곽 / 탐사 공간을 확대.
  - WEST Main Threat / NORTH Secondary / EAST Royal Road / SOUTH Production 방향 유지.
  - 기존 시스템 좌표 하드코딩 점검.
  - Navigation / Camera bounds / SpawnCandidate / Gate / World tests 갱신.

- 금지:

  - 256×256 이상 확장.
  - procedural generation.
  - World Map View.
  - Scout / Expedition 실제 기능.
  - Ghost.
  - 전체 Asset Migration.

### TASK-MAP-001-1 World Bounds / Ground / Navigation Expansion

- 상태: QUEUED

- 설명: World의 물리적 크기와 Navigation 영역을 192×192 logical map에 맞게 확장한다.

- 요구사항:

  - World bounds = 3072×3072px 기준.
  - center 기준 사용 시 약 -1536 ~ +1536 범위로 일관화.
  - Floor / grass / base terrain 확대.
  - navigation source/bake 영역 확대.
  - boundary collision 확대.
  - Camera Controller clamp 확대.
  - BuildingPlacement world bounds 확대.
  - fallback bounds 하드코딩 검색/갱신.
  - 기존 16px logical grid 유지.

- 완료조건:

  - 전체 192×192 world valid.
  - camera가 신규 boundary까지 이동.
  - placement 신규 영역에서 정상.
  - nav 신규 영역에서 path 생성.
  - 기존 중심 지역 nav 회귀 없음.

### TASK-MAP-001-2 Region Layout Expansion

- 상태: QUEUED

- 설명: 기존 방향별 역할을 유지하면서 확장된 외곽 공간에 주요 Region/Approach를 재배치한다.

- Core Village:

  - 현재 중앙 마을 composition을 최대한 유지.
  - Keep / Tavern / Inn / Grocery / Equipment Shop 역할 유지.
  - 중앙 광장/소로 구조 유지.

- WEST:

  - Main Portal을 기존보다 외곽으로 이동.
  - Portal → Corrupted Wild → Ruined Approach → West Battlefield → West Gate 단계가 읽히게 공간 확보.
  - 기본 Enemy route = WEST → EAST 유지.

- NORTH:

  - Secondary Rift를 외곽으로 이동.
  - mountain/rough approach 공간 확대.
  - North Battlefield / Gate 유지.
  - NE Dungeon Candidate를 더 먼 탐사 대상 위치로 이동.

- EAST:

  - Royal Road를 신규 world edge까지 연장.
  - Enemy Spawn으로 사용하지 않음.
  - world 밖 문명으로 이어지는 출구 인상 유지.

- SOUTH:

  - Production / Agriculture 공간 확대.
  - Future Event Threat marker는 비기능 상태 유지.

- Resource Regions:

  - NW Starter Forest는 Core Village와 너무 멀어지지 않음.
  - SW Large Forest는 외곽 위험 생산지 역할 강화.
  - SE Stone Region은 기존보다 충분한 공간 확보.
  - NE Sparse Forest / Dungeon approach 확장.

- 완료조건:

  - 4방향 역할이 기존보다 명확.
  - Core Village 과도한 확대 없음.
  - 외곽 공간 증가가 실제 screenshot에서 확인 가능.
  - 기존 Region이 단순히 동일 비율로 scale-up된 형태가 아님.

### TASK-MAP-001-3 Spawn / Combat / Travel Distance Rebalance

- 상태: QUEUED

- 설명: 확장된 월드에서 Enemy 접근, Mercenary 방어, Worker 물류가 의미 있는 거리감을 갖도록 주요 좌표와 이동 시간을 재조정한다.

- 검증 대상:

  - West Portal → West Gate.
  - North Rift → North Gate.
  - Core Village → resource regions.
  - Core Village → Dungeon Candidate.
  - Worker workplace → resource target.
  - Enemy route waypoint.
  - Mercenary rally / defense zone.
  - Gate interaction/command.
  - FirstEncounterSpawner.

- 원칙:

  - Player 직접 이동 시간은 더 이상 밸런스 기준이 아니다.
  - Worker/Enemy/Mercenary/향후 Expedition의 실제 world distance는 중요하다.
  - Enemy가 너무 오래 걸어오기만 하는 시간 낭비가 되지 않게 한다.
  - West Battlefield에 실제 전투가 모이도록 접근 route 조정.
  - Worker가 지나치게 긴 거리 때문에 생산이 사실상 멈추지 않게 한다.

- 완료조건:

  - WEST encounter 정상.
  - North secondary route 정상.
  - Worker production 정상.
  - Gate breach/combat 정상.
  - permanent nav stall 없음.

### TASK-MAP-001-4 Expanded World Visual Dressing

- 상태: QUEUED

- 설명: 192×192 확장으로 생긴 공간이 거대한 빈 grass field처럼 보이지 않도록 기존 World Visual Composition 규칙을 확장한다.

- 요구사항:

  - 현재 Tiny Swords 임시 에셋 유지.
  - 기존 world_dressing 구조 재사용.
  - 외곽을 랜덤 props로 꽉 채우지 않는다.
  - authored region density 유지.
  - Village / Defense / Forest / Production / Wild density 구분.
  - WEST는 위험/오염 분위기.
  - NORTH는 거친/산악 분위기.
  - EAST는 정돈된 Royal Road.
  - SOUTH는 생활/생산 공간.

- 중요:

  - 최종 Asset Migration 아님.
  - 새 코드 드로잉 소품을 과도하게 추가하지 않는다.
  - 기능보다 screenshot composition 보완 수준.

- 완료조건:

  - DAY overview screenshot에서 확장 영역이 의도적으로 구성되어 보임.
  - 신규 외곽이 단순 빈 공간으로 보이지 않음.
  - 전투 가독성을 decoration이 방해하지 않음.

### TASK-MAP-001-5 192×192 World 통합 검증

- 상태: QUEUED

- 설명: 확장 월드에서 Camera/Selection/Building/Worker/Combat/Death Ledger 전체 회귀를 검증한다.

- 자동검증:

  - 192×192 floor/bounds.
  - camera boundary.
  - mouse world selection.
  - pan/zoom world coordinate.
  - building placement 신규 외곽.
  - navigation 신규 외곽.
  - Worker production.
  - West Enemy encounter.
  - Wall/Gate.
  - Tactical Combat.
  - Death Ledger.
  - repeated DAY/NIGHT.

- Screenshot:

  - DAY Core Village.
  - DAY full overview.
  - WEST Battlefield.
  - EAST Royal Road.
  - NIGHT Tactical.

- HUMAN_CHECK:

  - 맵이 실제로 충분히 넓게 느껴지는지.
  - 반대로 불필요하게 비어 보이지 않는지.
  - camera로 이동할 때 너무 느리거나 빠르지 않은지.
  - WEST/NORTH/EAST/SOUTH의 방향성이 한눈에 읽히는지.
  - 확장 후 Tactical zoom이 유효한지.

- 완료조건:

  - 자동검증 PASS.
  - 기존 핵심 회귀 PASS.
  - screenshot 생성.
  - HUMAN_CHECK만 남으면 DONE.

---

## TASK-MAP-002 World Map View

- 상태: QUEUED

- 설명: 확대된 World의 전체 구조와 주요 Landmark를 확인할 수 있는 최소 World Map View를 구현한다. Tactical Command 화면과 분리된 정보 화면이다.

- 핵심:

  - 전체 world overview.
  - 주요 지역/landmark 표시.
  - Camera management 보조.
  - Map View에서 직접 combat/build/RTS command는 수행하지 않는다.

- 최소 표시:

  - Core Village.
  - Main Portal.
  - North Rift.
  - West/North Gate.
  - Forest Regions.
  - Stone Region.
  - Dungeon Candidate.
  - Royal Road.
  - Production Region.
  - 현재 Camera View 위치.

- 금지:

  - Fog of War.
  - Minimap 상시 HUD.
  - Fast Travel.
  - Map에서 직접 Building Placement.
  - Map에서 Mercenary 명령.
  - Expedition 실제 파견.

### TASK-MAP-002-1 World Map Overlay 기본 구조

- 상태: QUEUED

- 요구사항:

  - `M` 또는 명확한 입력으로 open/close.
  - full-screen 또는 large overlay.
  - Game world 좌표를 map-space로 안정적으로 변환.
  - 192×192 bounds 반영.
  - 기존 HUD/Tactical UI와 충돌하지 않음.
  - Map 열림 상태에서 의도치 않은 world click 차단.
  - close 후 기존 camera/input 정상 복귀.

- 완료조건:

  - Map open/close 정상.
  - world coordinate mapping 정상.
  - UI input leakage 없음.

### TASK-MAP-002-2 Landmark / Region 표시

- 상태: QUEUED

- 요구사항:

  - 데이터 기반 최소 marker 표시.
  - 실제 World marker/metadata 재사용 우선.
  - marker 위치 하드코딩 중복 최소화.
  - WEST/NORTH/EAST/SOUTH 역할이 Map에서도 구분되어 읽힘.
  - decorative minimap rendering framework 선행 금지.

- 완료조건:

  - 주요 landmark 누락 없음.
  - marker world position과 map position 일치.
  - world expansion 이후 하드코딩 좌표 불일치 없음.

### TASK-MAP-002-3 World Map 통합 검증

- 상태: QUEUED

- 시나리오:

  1. DAY.
  2. Map open.
  3. 주요 landmark 표시.
  4. current camera viewport 표시.
  5. Map close.
  6. camera pan/zoom 정상.
  7. NIGHT.
  8. Map open/close.
  9. Tactical Command state 보존.
  10. DAY 복귀.

- HUMAN_CHECK:

  - 전체 구조가 즉시 이해되는지.
  - marker가 너무 많지 않은지.
  - 지도 화면이 전술 명령 화면과 혼동되지 않는지.
  - 추후 Exploration UI를 얹을 여지가 충분한지.

- 완료조건:

  - 자동검증 PASS.
  - DAY/NIGHT input state 정상.
  - HUMAN_CHECK만 남으면 DONE.

---

## TASK-EXP-001 Exploration Foundation

- 상태: QUEUED

- 설명: Player 직접 탐험을 대체할 향후 Scout / Expedition 시스템의 최소 데이터/지역 탐사 기반만 준비한다. 실제 던전 플레이나 복잡한 원정 시스템은 구현하지 않는다.

- 핵심:

  - Player가 직접 걸어가지 않는다.
  - unexplored region을 선택한다.
  - Scout/Expedition이 시간과 위험을 소비해 조사한다.
  - 완료 시 Region이 discovered 상태로 전환된다.
  - 실제 전투/던전 내부는 후속 태스크.

- 금지:

  - Dungeon 실제 진입.
  - Expedition 전투.
  - 복잡한 supply system.
  - Food/Potion.
  - procedural events.
  - 대형 Quest system.
  - 새로운 World 생성.

### TASK-EXP-001-1 ExplorationRegion Data

- 상태: QUEUED

- 최소 데이터:

  - region_id.
  - display_name.
  - world_position / region bounds.
  - discovery_state.
  - exploration_duration.
  - base_risk.
  - discovered_features.
  - metadata.

- 상태 최소값:

  - UNKNOWN.
  - DISCOVERED.

- 선택적으로 최소 진행 상태가 필요하면:

  - EXPLORING.

- 요구사항:

  - world Actor reference 금지.
  - 향후 Save 가능 순수 데이터 구조.
  - 현재 NE Dungeon Candidate / resource region 같은 기존 marker를 연결할 수 있는 구조.
  - 범용 QuestDatabase 금지.

- 완료조건:

  - Region 생성/조회/상태 변경.
  - world marker와 연결 가능.
  - Actor 없이 데이터 유지.

### TASK-EXP-001-2 Minimal Exploration Action

- 상태: QUEUED

- 설명: World Map 또는 최소 Region UI에서 탐사 가능한 Region 하나를 선택해 일정 시간이 지난 뒤 discovered 처리하는 가장 작은 vertical slice를 만든다.

- Prototype 대상:

  - NE Dungeon Candidate 또는 별도 테스트 Region 1개.

- 요구사항:

  - Player Avatar 필요 없음.
  - Map/Region UI에서 Explore 시작.
  - GameTime 기준 exploration progress.
  - 완료 시 DISCOVERED.
  - 발견 결과는 고정 deterministic prototype.
  - Scout roster/mercenary escort/supply는 아직 구현하지 않음.
  - 실제 Dungeon 생성/진입 금지.

- 완료조건:

  - UNKNOWN → EXPLORING → DISCOVERED.
  - repeated start duplicate 없음.
  - DAY/NIGHT 전환에서도 progress 정책 일관.
  - 발견 후 Map View 갱신.

### TASK-EXP-001-3 Exploration Foundation 통합 검증

- 상태: QUEUED

- 시나리오:

  1. Player Actor 없음.
  2. World Map open.
  3. UNKNOWN region 확인.
  4. Explore 시작.
  5. GameTime 진행.
  6. progress 확인.
  7. 완료.
  8. DISCOVERED 확인.
  9. Map marker 갱신.
  10. repeated Explore 차단.
  11. DAY/NIGHT 반복.
  12. Worker/Combat/Death Ledger 회귀.

- HUMAN_CHECK:

  - 직접 이동 없이도 “새로운 지역을 발견했다”는 느낌이 있는지.
  - Map View와 Exploration UI가 과도하게 메뉴 게임처럼 느껴지지 않는지.
  - 이후 Scout/Expedition 확장 방향이 자연스러운지.

- 완료조건:

  - 최소 Exploration loop PASS.
  - 기존 핵심 시스템 회귀 PASS.
  - HUMAN_CHECK만 남으면 DONE.

---

## OVERNIGHT-STOP-7 Control / Map / Exploration Foundation 종료 경계

- 상태: QUEUED

- 설명: Player 조작 구조 전환, 192×192 World 확대, World Map View, Exploration Foundation 완료 후 Ghost/Wave 등 다음 핵심 시스템을 임의로 시작하지 않고 종료한다.

- 확인:

  - TASK-CTRL-001 완료.
  - TASK-MAP-001 완료.
  - TASK-MAP-002 완료.
  - TASK-EXP-001 완료.
  - runtime Player Actor 없음.
  - DAY/NIGHT Camera + Mouse 조작 정상.
  - 192×192 World 정상.
  - WEST/NORTH/EAST/SOUTH 역할 유지.
  - World Map View 정상.
  - 최소 Exploration state 정상.
  - TASK-016 Death Ledger 정상.

- 금지 시스템 미시작 확인:

  - GhostActor.
  - GhostFactory.
  - GhostReturnSpawner.
  - Ghost Shader.
  - Ghost Combat.
  - 정식 WaveManager.
  - Wave progression.
  - Boss.
  - 신규 Mercenary class.
  - 신규 Enemy archetype.
  - Food/Potion/Morale.
  - Dungeon 실제 기능.
  - Asset Migration.

- 임시 파일:

  - `_diag*`.
  - `_probe*`.
  - `_debug*`.
  - `_temp*`.
  - 종료 시 모두 제거 확인.

- 종료 회귀:

  - smoke.
  - Mouse/Camera Management 통합.
  - 192×192 World 통합.
  - World Map 통합.
  - Exploration Foundation 통합.
  - TASK-015 Tactical Combat.
  - TASK-016 Death Ledger.

- 다음 예정:

  - TASK-017 First Ghost Return.
  - 이후 실제 Wave System.
  - 최종 Asset Style Lock / Migration은 실제 Wave 전투 가독성을 확인한 뒤 별도 결정.

- 완료조건:

  - 이번 큐 전체 완료.
  - 금지 시스템 미시작.
  - 임시 파일 없음.
  - 종료 회귀 PASS.
  - 다음 TASK 자동 시작 금지.
