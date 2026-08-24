### TASK-EXP-001-3 Exploration Foundation 통합 검증

- 상태: REVIEW
- 피드백: (1) 테스트 스크립트가 `GameTime.set_time_scale()` 직접 호출(237/246/254/264행)로 인해 컴파일 실패 — 실행 자체가 불가. (2) 컴파일을 우회해도 `Phase.COMPLETE_WAIT`의 `_sub` 가드 누락으로 DISCOVERED 이후 무한 루프에 빠져 PASS 도달 불가(실측 확인). (3) 테스트 결과 파일 부재로 완료조건(Exploration loop PASS + 핵심 회귀 PASS)이 실증되지 않음. 프로덕션 코드(exploration_manager/exploration_region/world_map_overlay)는 프로브 실행에서 정상 동작을 확인했으므로, 위 2건의 테스트 하네스 수정 + 재실행 검증만으로 완료 가능.
- 구현 노트 (FIX 라운드):
  - (1) 컴파일 실패 원인 = autoload 식별자 직접 메서드 호출(`GameTime.set_time_scale()`). 이 프로젝트 테스트 컨벤션(노드 변수 경유, task0152/task0156 패턴)대로 `_game_time.set_time_scale(GameTime.TIME_SCALE_*)`로 교정. 상수 접근(`GameTime.TIME_SCALE_*`)은 별도 프로브로 정상 컴파일 확인.
  - (2) COMPLETE_WAIT 무한 루프 = `_sub` 가드 없는 phase 본문에서 매 프레임 `_wait_frames(4)` 재호출로 `_wait`가 리셋되던 구조 문제 → sub 가드 구조로 재작성. 동일 결함 잠재 지점이던 COMBAT_LEDGER_REGRESSION sub2→3 전이도 함께 수정.
  - 추가 하네스 버그 1건 수정: WORKER_REGRESSION에서 `_budget`을 stone 기준값과 프레임 카운터로 이중 사용하여 생산 판정이 매 프레임 인상되던 문제(`_work_base` 분리). 게임 코드 문제 아님(state=2 MINE, stone 증가 실측).
  - 실행 증적: `tests/taskexp0013_test.gd` headless 78 assertion 전부 PASS → `test_results/taskexp0013_test_run.txt`. 탐사 loop은 직접 advance() 호출 없이 실제 런타임 프레임 진행으로 완료까지 검증(progress 단조 증가/전술 Pause 동결/2x 배율/DAY↔NIGHT 정책 일관/완료 시 열린 Map 패널 실시간 갱신/repeated 차단).
  - 회귀 재실행 전부 PASS: smoke / taskexp0011 / taskexp0012 / taskmap0023. Worker(quarry/miner 생산)·Combat(용병 자동전투 사살)·Death Ledger(ENEMY record PENDING, cleanup 무기록, stale reference 0) 회귀는 통합 테스트 내 시나리오 12번으로 직접 검증. 임시 파일 0건.

- 시나리오:

  1. Player Actor 없음.
  2. World Map open.
  3. UNKNOWN region 확인.
  4. Explore 시작.
  5. GameTime 진행.
  6. progress 확인.
  7. 완료.
  8. DISCOVERED 확인.
  9. Map marker 갱신.
  10. repeated Explore 차단.
  11. DAY/NIGHT 반복.
  12. Worker/Combat/Death Ledger 회귀.

- HUMAN_CHECK:

  - 직접 이동 없이도 “새로운 지역을 발견했다”는 느낌이 있는지.
  - Map View와 Exploration UI가 과도하게 메뉴 게임처럼 느껴지지 않는지.
  - 이후 Scout/Expedition 확장 방향이 자연스러운지.

- 완료조건:

  - 최소 Exploration loop PASS.
  - 기존 핵심 시스템 회귀 PASS.
  - HUMAN_CHECK만 남으면 DONE.

---

