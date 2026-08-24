### TASK-3D-001-5 Navigation3D Convention / Foundation Lock

- 상태: REVIEW
- 피드백: reviewer 지적 4건 전부 수정 + 재검증 완료. (1) is_target_reachable이 부분 경로를 reachable로 오판하던 것을 종점 일치 판정으로 수정, (2) 부분 경로 종점 접촉면 진동이 stuck guard를 무한 리셋하는 문제를 NavigationPolicy3D.judge_path_status(MOVING/ARRIVED/BLOCKED) 단일 종료 규약으로 policy 수준 해결, (3) gate 양끝을 경계 벽까지 잇는 회랑 벽 추가로 CLOSED 차단 assertion 성립 + Actor Origin LOCK(지면 접지 origin)·nav raster 해상도(1px cell) 확정, (4) scenes/_nav_test*.uid 3건 제거. task3d0015 신규 테스트 44 assertions PASS, 회귀 0012(47)·0013(42)·0014(45)·smoke(15) 전부 PASS.
- 피드백: 이전 시도 시간 초과: 실행 시간 초과 (7200초)

- 설명: Worker/Combat/Building 병렬 태스크가 서로 다른 Navigation 방식을 만들지 않도록 최소 Navigation3D 규칙을 확정한다.

- 요구사항:

  - NavigationRegion3D / NavigationMesh 기본 구조.
  - 지면 XZ 이동 기준.
  - Static Building/Wall obstacle 반영 정책.
  - Runtime Building placement 이후 nav update 정책 방향 확정.
  - Gate OPEN/CLOSED/BREACHED를 이후 3D nav에서 표현할 수 있는 구조.
  - Worker/Enemy/Mercenary가 공통 Navigation 정책을 사용할 수 있음.
  - Actor radius/height 기본 convention 기록.
  - unreachable target 처리 시 기존 영구 stall 방지 원칙 유지.

- 중요:

  - Worker/Combat 실제 전체 이식은 하지 않는다.
  - 복잡한 동적 NavMesh 최적화 시스템을 선행 구현하지 않는다.
  - 현재 Godot 버전에서 안정적인 최소 구조 우선.

- 완료조건:

  - Test Agent가 3D ground path 이동 가능.
  - Test obstacle 우회 가능.
  - nav convention이 병렬 태스크에서 재사용 가능.
  - Foundation 문서/코드 기준점 확정.

---

