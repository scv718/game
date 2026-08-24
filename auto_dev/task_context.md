### TASK-3D-RES-001-1 ResourceNode3D Base / Selection

- 상태: QUEUED

- 요구사항:

  - Foundation Interaction3D 계약 사용.
  - Area3D/CollisionShape3D 등 적절한 3D hit volume.
  - visual child와 game logic 분리.
  - Resource depletion/regrowth 시 visual/collision state 일관.
  - instance freed 후 claim/reference 정리.

- 완료조건:

  - Tree/Stone 3D 선택 가능.
  - decoration과 구분됨.
  - depletion/regrowth 상태 정상.
  - stale reference 없음.

### TASK-3D-RES-001-2 Tree / Stone Quaternius Visual

- 상태: QUEUED

- 요구사항:

  - `Stylized Nature MegaKit` 기반 Tree/Rock 우선.
  - 동일 resource type에 제한적인 visual variation.
  - collision은 mesh polygon을 그대로 쓰지 말고 gameplay에 적합한 단순 shape 우선.
  - top-down camera에서 resource 종류 식별 가능.
  - Tree stump/regrowth visual이 기존 기능과 연결됨.
  - gameplay footprint를 visual scale 변경과 분리.

- HUMAN_CHECK:

  - 숲이 복사/붙여넣기처럼 보이지 않는지.
  - Tree/Stone이 건물/Worker 대비 너무 크거나 작지 않은지.
  - Zoom-out에서도 자원 지역이 읽히는지.

- 완료조건:

  - 기능 검증 PASS.
  - visual screenshot 생성.
  - HUMAN_CHECK만 남으면 DONE.

### TASK-3D-RES-001-3 Resource Regression

- 상태: QUEUED

- 자동검증:

  - Tree claim.
  - Tree depletion.
  - Tree regrowth.
  - Stone source state.
  - VillageResources Wood/Stone 반영.
  - duplicate claim 없음.
  - freed resource reference 없음.
  - Foundation selection/raycast 회귀.

- 완료조건:

  - 기존 Resource 핵심 동작 PASS.
  - 3D Runtime에서 2D Resource Actor 의존 없음.
  - `INTEGRATION_NOTE` 작성.

---

