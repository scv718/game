### TASK-3D-001-2 World3D / Coordinate / Collision Foundation

- 상태: REVIEW
- 피드백: `tests/task3d0012_test.gd`의 한글 주석이 바이트 단위 mojibake로 손상됨(저장소 UTF-8 관례와 불일치, 내용 복구 불가). 주석을 유효 UTF-8 한국어로 재작성 후 재검토 필요. 그 외 요구사항·완료조건·회귀는 실제 headless 실행으로 전부 충족 확인(47/47 PASS, smoke PASS, LOCK 12 준수).
- 피드백: [재시도] exit=1 무응답도 백오프 재시도 대상에 포함 후 재실행

- 설명: 기존 게임 규칙을 담을 3D World Root와 공통 좌표/충돌 정책을 만든다.

- 요구사항:

  - `Node3D` 기반 World Root.
  - XZ ground plane.
  - Y = height.
  - 기존 logical grid의 의미를 보존하는 world unit 변환 상수/유틸리티.
  - 기존 Region/World bounds를 3D XZ로 표현 가능.
  - 공통 collision layer/mask 정책 문서화.
  - Interactable / Building / Resource / Worker / Mercenary / Enemy / Wall / Gate 구분 가능.
  - UI는 별도 CanvasLayer/Control 구조 유지.
  - 2D Main World를 즉시 삭제하지 않음.

- 금지:

  - 3D라는 이유로 world size 확대/축소.
  - 기존 gameplay distance 임의 재밸런스.
  - physics-heavy terrain.
  - 자유 높이 이동/점프.

- 완료조건:

  - 빈 3D World 정상 실행.
  - World bounds/ground coordinate 확인.
  - 공통 layer/mask 충돌 테스트 PASS.
  - 기존 UI overlay를 3D World 위에 표시 가능.

