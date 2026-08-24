### TASK-3D-001-4 Interaction3D / Selection Contract

- 상태: REVIEW
- 피드백: 요구사항 7건 전부 구현 확인, 신규 task3d0014 테스트 45 assertions headless 실행 PASS, 0012(47)·0013(42)·smoke(15) 회귀 통과. Foundation 신규 파일만 추가하고 2D interactable/world_selection 및 기존 도메인 파일 무수정(LOCK 12/운영 규칙 4 준수). re-base는 각 도메인(RES/BLD) 전환 태스크가 자기 파일만 수행.

- 설명: 기존 2D mouse selection/interaction 의미를 3D Raycast 기반으로 연결할 최소 공통 계약을 만든다.

- 요구사항:

  - Left Click → 유효한 3D selectable/interactable 1개 선택.
  - 빈 ground / decoration click 안전.
  - Right Click / ESC selection 해제.
  - UI open 상태 world interaction 누수 없음.
  - 기존 interact/select API가 dimension-neutral하면 최대한 재사용.
  - 3D node 자체를 순수 game data owner로 강제하지 않음.
  - 기능 도메인이 별도 거대 Selection Framework를 만들 필요 없는 최소 API 제공.

- 금지:

  - Box Selection.
  - Drag Selection.
  - RTS formation framework.
  - 새로운 범용 ECS.

- 완료조건:

  - Test interactable 3D object 선택/해제 PASS.
  - decoration/ground 안전.
  - UI 차단 PASS.
  - 병렬 Building/Resource/Combat 태스크가 공통 계약 사용 가능.

