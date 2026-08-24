### TASK-EXP-001-1 ExplorationRegion Data

- 상태: REVIEW
- 피드백: 재시도 후에도 구현물이 전무함 — ExplorationRegion 클래스·enum·테스트 파일이 레포지토리 어디에도 없고(grep/Glob/git status로 확인), 테스트 실행 증적 없음. 계획 서술만으로는 리뷰 불가하며 실제 코드 작성 + 테스트 실행 증명이 선행되어야 함
- 피드백: 구현물이 전무함 — ExplorationRegion 데이터 클래스, 상태 enum, 테스트 모두 미생성. 코드 작성 + 테스트 실행 증명이 선행되어야 재리뷰 가능.
- 피드백: [재시도] 빈 응답 백오프 재시도(최대 4회) 적용 후 재실행. 요구사항: ExplorationRegion 데이터 클래스 + 상태 enum + 테스트 (리뷰어 피드백 참조)

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

