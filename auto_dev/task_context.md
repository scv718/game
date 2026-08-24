### TASK-3D-001-3 Camera3D Pan / Zoom / Screen-to-World

- 상태: REVIEW

- 설명: 기존 Camera + Mouse 관리 조작을 Orthographic Camera3D로 이전한다.

- 요구사항:

  - 고정 Top-down 사선 Pitch/Yaw.
  - WASD = XZ Camera Pan.
  - Mouse Wheel = orthographic size 기반 Zoom.
  - 최소/최대 Zoom clamp.
  - World boundary clamp.
  - Camera rotation 입력 없음.
  - Screen mouse position → 3D ground/world raycast 가능.
  - UI 위 Mouse 입력이 world click으로 누수되지 않음.
  - DAY/NIGHT Camera policy를 이후 Tactical Migration에서 재사용 가능.

- HUMAN_CHECK:

  - 프로젝트 좀보이드처럼 월드를 내려다보는 느낌이 자연스러운지.
  - 최대 Zoom-out에서 마을 운영 상황이 읽히는지.
  - Zoom-in에서 Worker 작업을 관찰할 수 있는지.
  - 카메라 각도가 건물/캐릭터를 지나치게 가리지 않는지.
  - Pan/Zoom 속도가 관리 게임에 적절한지.

- 완료조건:

  - Pan 정상.
  - Zoom 정상.
  - boundary clamp 정상.
  - mouse → world 좌표 정상.
  - UI click-through 없음.
  - HUMAN_CHECK만 남으면 DONE.

