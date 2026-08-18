# AI Task Queue

> 이 파일은 자동화 시스템과 사람(GPT Web) 사이의 인터페이스입니다.
> 자동화는 `- 상태:` 줄을 갱신합니다. 태스크 추가/수정/삭제는 자유롭게 하세요.
>
> 상태 값: `QUEUED` / `IMPLEMENT` / `REVIEW` / `FIX` / `DONE` / `NEEDS_DESIGN`
> - QUEUED: 대기 (매시간 자동화가 가장 먼저 대기 태스크를 처리)
> - IMPLEMENT: 구현 진행 중
> - REVIEW: 리뷰 진행 중
> - FIX: 리뷰 지적 → 수정 필요 (자동으로 재구현/재리뷰)
> - DONE: 완료
> - NEEDS_DESIGN: 설계/방향 결정 필요 → 자동화 정지, 사람 개입 대기
>
> 규칙:
> 1. `## ` (2단계) = 챕터/컨테이너, `### ` (3단계) = 실제 실행되는 태스크
> 2. 자식 태스크가 없는 2단계 태스크도 실행 대상입니다.
> 3. 태스크는 파일에 적힌 순서대로 처리됩니다.
> 4. 컨테이너 상태는 자식 상태를 보고 자동 갱신됩니다 (모두 DONE이면 DONE).

---

## TASK-006 Worker Assignment 기반
- 상태: QUEUED
- 설명: Worker Assignment 기반

### TASK-006-1 Lumberyard worker slot
- 상태: QUEUED
- 설명: Lumberyard worker slot

### TASK-006-2 Worker assign/unassign
- 상태: QUEUED
- 설명: Worker assign/unassign

### TASK-006-3 기존 Lumberjack를 workplace 기반으로 전환
- 상태: QUEUED
- 설명: 기존 Lumberjack를 workplace 기반으로 전환

### TASK-006-4 회귀 테스트
- 상태: QUEUED
- 설명: 회귀 테스트