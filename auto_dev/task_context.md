### TASK-3D-001-1 Current 2D Runtime Audit / Migration Map

- 상태: REVIEW
- 피드백: 산출물 자체는 요구사항을 충족하나, 감사 문서의 수치 근거에 오류 2건 — (1) building_placement.gd get_global_mouse_position 호출 수 "10곳"→실제 9곳(section 0 #4 및 산출물 1 해당 행 수정, #15(b) 라인 목록과 일치시킬 것), (2) world.tscn MapLayout Marker2D "27개"→실제 35개(section 0 #1, 산출물 1-B, 산출물 3 Map/Layout 행 3곳 수정). 두 수치만 교정 후 재검토 없이 완료 처리 가능.
- 피드백: 태스크의 필수 산출물(Migration Map 문서 5개 항목)이 하나도 작성되지 않았음. 제출된 "요약"은 작업 시작 의사 선언일 뿐 구현 결과가 아니며, 완료조건 3항 모두 미충족. 실제 코드 reference 검색을 수행하고 파일 수준 Migration Map 문서를 산출한 후 재검토 요청할 것.

- 설명: 실제 현재 코드에서 2D Runtime 의존성을 추적하고 도메인별 Migration Map을 만든다.

- 확인 대상:

  - Main World Scene.
  - Camera2D / camera controller.
  - Mouse selection / interaction.
  - BuildingPlacement.
  - Resource Node.
  - Worker / Lumberjack / Miner.
  - NavigationRegion2D / NavigationAgent2D / nav rebuild.
  - Wall / Gate collision/navigation.
  - Mercenary / Enemy.
  - Tactical command world reference.
  - World bounds.
  - Spawn / Region / landmark coordinate.
  - Day/Night visual hooks.
  - Death Ledger의 Actor reference 경계.
  - UI가 world position을 사용하는 모든 지점.

- 산출물:

  - 2D 전용 의존 목록.
  - 그대로 유지 가능한 순수 game/data logic 목록.
  - 3D 변환이 필요한 Scene/Script 목록.
  - 공유 파일 목록.
  - 병렬 태스크별 파일 ownership 초안.

- 중요:

  - Audit 단계에서 대량 수정 금지.
  - 문서만 보고 판단하지 말고 실제 reference 검색.
  - 이미 3D 또는 dimension-neutral 구조가 있으면 재작성하지 않는다.

- 완료조건:

  - 2D → 3D Migration 경계가 파일 수준으로 기록됨.
  - 병렬 작업 충돌 위험 파일이 식별됨.
  - 구현 전 reference 누락 없음.

