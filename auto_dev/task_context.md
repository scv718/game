### TASK-EXP-001-2 Minimal Exploration Action

- 상태: REVIEW
- 피드백: 구현·테스트·회귀 모두 통과했으나, full-screen Backdrop(mouse_filter=STOP)이 클릭을 소비해 실제 마우스 입력으로 region 선택이 동작하지 않음을 프로브로 실증함. mouse_filter=IGNORE 변경 + 실제 입력 경로(push_input) 테스트 추가 후 재검토 필요.
- 구현 노트 (FIX 라운드):
  - `ui/world_map_overlay.tscn` Backdrop mouse_filter STOP(0) → IGNORE(2). 루트 Control(STOP + `_gui_input`)이 클릭을 받아 region hit-test로 연결. 월드 click-through 차단은 여전히 world_selection의 `world_map_overlay` 모달 그룹 가드와 루트 Control STOP이 담당(이중 안전).
  - `tests/taskexp0012_test.gd`에 실제 입력 경로 검증 추가: headless 기본 window가 64x64라 overlay 레이아웃이 붕괴되어 RegionPanel이 화면 대부분을 덮는 문제를 프로브로 확인 → 테스트에서 `root.size = 1152x648` 강제 후 `root.push_input(InputEventMouseButton)`으로 마커 클릭이 `Control._gui_input`까지 도달해 region을 선택하는지 실제 GUI 라우팅으로 PASS 확인.
  - 회귀 재실행: taskexp0011 / taskmap0021 / taskmap0023 / taskctrl0012 / smoke 전부 PASS(taskctrl0012의 floor assertion은 HEAD부터 존재한 pre-existing 128↔192 불일치).
  - `tests/taskmap0022_test.gd`: Node에 없는 `has()` 호출로 매 프레임 SCRIPT ERROR 루프가 나며 완주하지 못하던 pre-existing 버그(실행 기록 파일 자체가 없었음)를 taskmap0023과 동일한 `get(...) != null` 접근성 패턴으로 교정 후 최초 완주 45 PASS. assertion 의도(상수 존재) 유지, 규칙 17/18 준수.

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

