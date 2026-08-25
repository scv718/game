## TASK-3D-CMB-001-1 TASK-3D-CMB-001-1 Mercenary / Enemy Actor3D

- 판정: LGTM
- 사유: 7개 요구사항·4개 완료조건을 실제 코드에서 전부 확인했고, 신규 테스트 73 assertions와 Foundation 회귀(task3d0015)를 reviewer가 직접 headless 재실행하여 PASS 재현함. git diff 범위가 보고와 정확히 일치하며 2D 파일 무수정 LOCK 준수. 지적 2건(.uid 커밋 포함, 테스트의 private 접근)은 모두 비차단 수준.
- 브랜치/워크트리: D:\game-wt\combat
- 완료 시각: 2026-08-25T10:40:53.518043

## TASK-3D-CMB-001-2 TASK-3D-CMB-001-2 Tactical Command World3D Wiring

- 판정: LGTM
- 사유: 지적된 `_nav_dest` ZERO 센티널 버그를 mercenary/enemy 양쪽에서 플래그 방식으로 올바르게 교체했고(원점 waypoint 무단 pop 방어까지 보강), 중복 _enter 제거와 assertion 수 77 문서 정렬을 확인했으며, 리뷰어 직접 재실행으로 0012 연속 3회(77/77)+0011(73/73) PASS를 재현함.
- 브랜치/워크트리: D:\game-wt\combat
- 완료 시각: 2026-08-25T14:03:01.777633

