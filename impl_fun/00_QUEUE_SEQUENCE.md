# Ox Alpha Autonomous Queue Sequence

이 디렉터리는 기존 `TASK-026~052` 장기 로드맵을 **Ox Alpha/OpenCode 장시간 무인 실행용**으로 세분화한 버전이다.

## 권장 실행 순서

1. `01_TASK_026_028_EXPEDITION_DUNGEON.md`
2. `02_TASK_029_032_EQUIPMENT_MERCENARY.md`
3. `03_TASK_033_040_ENEMY_VILLAGE_PROGRESSION.md`
4. `04_TASK_041_045_BOSS_WORLD_PORTAL.md`
5. `05_TASK_046_049_PERSISTENCE_PRODUCT.md`
6. `06_TASK_050_052_BALANCE_STRESS_DEMO.md`

각 파일은 기존 파서 규칙을 유지한다.

- `##` = 챕터/컨테이너
- `### TASK-*` = 실제 실행 태스크
- `- 상태:` = `QUEUED / IMPLEMENT / REVIEW / FIX / DONE / NEEDS_DESIGN`

## 왜 여러 파일로 분리했는가

- 한 모델 컨텍스트에 026~052 전체 세부 명세를 동시에 넣지 않기 위해.
- Ox Alpha가 현재 기능군과 무관한 후반 기능을 선행 구현하는 것을 막기 위해.
- 긴 태스크가 실패/타임아웃 났을 때 재시도 범위를 줄이기 위해.
- Review/FIX loop가 현재 phase 안에서 닫히게 하기 위해.
- 각 밤에 하나의 의미 있는 Vertical Slice 묶음을 맡기기 위해.

## 기본 운용

한 밤에 **한 phase 파일**을 Queue로 지정하는 방식을 권장한다.

각 phase 파일 끝의 `PHASE-STOP-*`는 다음 대형 기능군을 자동 시작하지 않는 안전 경계다.
예상보다 빨리 끝나더라도 STOP에서 멈추고 결과/회귀/HUMAN_CHECK를 확인한다.

## 완전 무인 연속 실행

`AI_TASK_QUEUE_FULL.md`는 026~052를 하나로 합친 버전이다.
중간 phase stop은 checkpoint 취급하고 연속 실행 가능하도록 작성되어 있다.

단, FULL은 매우 긴 Queue이므로 다음 상황에서는 split 파일이 더 안전하다.

- 신규 시스템의 핵심 설계 공백이 아직 있을 때.
- 모델 provider rate limit이 자주 발생할 때.
- 한 태스크가 장시간 실행되는 환경.
- 사람 플레이테스트가 필요한 구간을 phase별로 끊고 싶을 때.

## autonomous 실행에서 중요한 판정

- 정확한 수치만 미정 → `DESIGN_TUNING`으로 기록하고 계속 구현.
- 미감/체감만 미확인 → `HUMAN_CHECK`, 코드 정상 시 DONE 가능.
- 플레이 경험 자체가 달라지는 핵심 규칙 충돌 → `NEEDS_DESIGN`, 추측 구현 금지.
- 테스트 미실행 → PASS 보고 금지.
- 기존 기능이 이미 존재 → 재작성보다 재사용.
