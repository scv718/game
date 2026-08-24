### TASK-3D-RES-001-1 ResourceNode3D Base / Selection

- 상태: REVIEW
- 피드백: [대기] 프로바이더 장애(exit=1 지속, 06:43~07:38) - 복구 후 재실행. 구현물/테스트 3종은 기존 커밋 존재

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

