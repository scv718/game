### TASK-3D-RES-001-1 ResourceNode3D Base / Selection

- 상태: IMPLEMENT
- 피드백: [재시도] 프로바이더 장애(exit=1)로 실패 - 구현물/테스트는 기존 커밋 존재, 검증 후 완료 처리 필요

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

