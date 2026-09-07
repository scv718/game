# AGENTS.md — 프로젝트 컨텍스트 (학습 기록)

## 프로젝트 개요

Godot 4.x + GDScript 기반 **2D 탑다운 마을 운영 / 자동화 / 웨이브 디펜스 게임**.
현재 실행 런타임은 **3D / 2.5D 마을 운영 프로토타입** (`main_3d.tscn`) 이다.

## 필수 결정 문서

- `GAME_DESIGN.md` — 게임 디자인 기준 (수정 금지). 핵심 원칙:
  1. 플레이어는 절대 직접 전투하지 않는다.
  2. 전투는 용병 AI/방어시설, 플레이어는 지휘.
  3. 밤은 마을 전체 지휘 모드 중심.
  4. 죽은 모든 존재는 반드시 한 번 망령으로 돌아온다 (Death Ledger).
  5. 반복 노동은 자동화로 위임.
  6. 주민은 주점에서 고용, 여관에서 관리/배치.
  7. 미배치 주민은 월드에 독립 NPC로 존재하지 않음.
  8. 배치된 주민만 시설에서 Worker Actor로 출현.
  9. 벌목장/채석장 등 주요 생산시설은 초기 Worker Slot 2.
  10. 거점/주점/여관/식료품점/장비점은 시작부터 존재하는 핵심 업그레이드 건물.
  11. 미래 시스템을 과도하게 선행 구현하지 않음.

- `CURRENT_IMPLEMENTATION_INVENTORY.md` — 현재 구현 현황 감사 보고서 (가장 신뢰할 수 있는 진실 기록).
- `AI_TASK_QUEUE.md` — V3 실행 큐 (인간↔자동화 인터페이스).

## 현재 런타임 구성

- 메인 씬: `res://scenes/main_3d.tscn` (project.godot:14)
- Godot 버전: 4.7.1 (Forward Plus)
- autoload 목록 (project.godot:22-38): InnCapacity, VillageResources, GameTime, WorkerRoster, MercenaryRoster, PopulationConsumption, FirstEncounterSpawner, DeathLedger, ExplorationManager, AudioManager, ThreatSystem, WaveManager, DungeonManager, DungeonPreparationManager, GameSettings

## 실행 배치 틀 (V3)

- Canonical baseline: `main` @ `63914f5642d40e73d6cfe3223fefe16d9f0ffa88`
- 큐: `AI_TASK_QUEUE.md` — 14개 V3 태스크 모두 QUEUED
- 상태: `auto_dev/state_v2.json` (V3-001~V3-014 전부 QUEUED), integration_baseline_commit `b25f943`
- 태스크 정의: `auto_dev/tasks/V3-*.md`
- 자동화 도구: `auto_dev/auto_lane.py`, `supervisor.py`, `night_exec.py`, `run_lane.ps1` 등 (config json 의존): key는 `openai`/`anthropic`/... 가 아니라 `openai` 스타일 접근 불가 — `config.json` 참조.
- 각 V3 태스크는 격리 worktree + `baseline_commit`/`source_commit`/`integrated_commit`/`integration_status`/`depends_on` 기록, `tests/baseline_3d_health_test.gd` 통과 필수.

## 코드베이스 핵심 위치

- 스크립트: `scripts/` (3D 기준: `*_3d.gd`)
- 씬: `scenes/` (`main_3d.tscn`, `world3d.tscn`, 등)
- UI: `ui/` (`hud_3d.tscn`, `hud.gd`, `tavern_recruitment_ui.gd`, `inn_roster_ui.gd`, `dungeon_preparation_ui.gd`, `tactical_command_ui_3d.tscn`)
- 테스트: `tests/` — **핵심 baseline**: `tests/baseline_3d_health_test.gd` (main scene, autoload, no-direct-player, 3D invariants)
- 자산: `assets/` (외부 팩은 `.gitignore`로 제외, `tools/download_*.ps1`로 부트스트랩 — Tiny Swords·Quaternius는 재배포/커밋 금지 라이선스라 로컬 전용)

## 주요 시스템 구현 상태 (요약)

- **구현됨**: 3D 진입/월드/카메라/선택/건물 배치, 자원 노드, Worker roster/FSM, 용병 roster/FSM, 자동 전투, 성벽/성문, 위협/웨이브, Ghost/Death Ledger, 던전 준비/조우 스켈레톤, 음식 소비, 포션 슬롯/자동사용, 사기, 탐험/맵 UI, 오디오 기반.
- **부분**: 던전 완료/보상/귀환 루프, 농장→음식 수직 슬라이스, 비주얼 자산 전달, 3D UI 완성도, 포탈 개념, 주민 인구 모델.
- **스텁**: 던전 보상 테이블, 장비 준비 요약, 포탈 마커.
- **없음(NOT_FOUND)**: 영구 세이브/로드, 장비 시스템, 스킬, 퀘스트, 진영, 상점/교역, 보스, 창고/물류, 치료/수리/훈련 건물.

## 테스트 주의사항

- `tests/smoke_test.gd`는 **LEGACY 2D** — `main.tscn` 기준이라 현재 3D 런타임 검증에 부적합. 하위 호환용.
- 신규 작업은 `main_3d.tscn` 3D 클로저를 대상으로 하고 2D 런타임 가정을 복원하지 않는다.
- headless 테스트는 실제 실행 결과만 PASS로 보고한다 (미실행 테스트 PASS 보고 금지).

## 개발 원칙 / 규칙

1. 현재 작업에 불필요한 미래 시스템을 선행 구현하지 않는다 (과도한 추상화/오버엔지니어링 금지).
2. `GAME_DESIGN.md` 절대 수정하지 않는다.
3. 범위 밖 신규 기능 임의 구현 금지.
4. `git reset --hard`, `git clean -fd`, force push 등 파괴적 Git 명령 금지.
5. 코드 스타일: 기존 파일 컨벤션 준수, 주석은 요청 시에만 작성.
6. 물류/자동화는 지나치게 복잡하게 만들지 않는다 (Factorio 수준 금지).
7. 기존 Known Issue/동작을 태스크 범위 밖에서 임의 리팩터링하지 않는다.

## 참고: 작업 가이드라인 (질문 시)

- 주민 시스템은 Roster 데이터 ↔ 월드 Actor 분리 유지, Worker Spawn/Despawn 생명주기 명확화.
- 외부 자산 클로저 문제(신규 체크아웃 시 에셋 부재)가 해결 전 까지는 외부 에셋 경로 의존 작업에 주의.
