## 설계 결정

- **대상**: validation 게이트 규칙 및 `auto_dev/` 디렉토리 접근 기준
- **갈등 핵심**: 태스크 `TASK-POST3D-REG-001`은 프로젝트 게임 로직 구현(3D 중력/그랩plersystem)이지만, 게이트가 `auto_dev/` 내 **백업 파일들**(`config.json.bak_*`)까지 위험 파일 변경으로 차단. 이는 구현과 무관한 **구동 측부 효과(side effect)**임.
- **해결 방향**: 게이트 검사와 실제 태스크 간에 간극이 존재하므로, 구현자가 `auto_dev/` 디렉토리에 **무엇을 해야 하는지**를 명확히 하지 않아 게이트가 방어적으로 모든 변경을 차단하고 있음. 백업 파일 생성은 구현자가 통제할 수 없는 구동부 동작이므로, 이는 게이트의 `ALLOW` 또는 `IGNORE` 대상에 포함되거나, 태스크 설명에 `auto_dev/` 접근 금지 범위(백업 파일 제외)가 명시되어야 함.
- **구체적 결정**: 게이트는 `auto_dev/config.json.bak_*` 패턴(타임스탬프 또는 마커가 붙은 백업 파일)을 **변경 감지에서 제외**해야 함. 또한 구현자는 `auto_dev/prompts/`, `auto_dev/supervisor.py`에는 **절대 touching해서는 안 되며** (파일 열기, 쓰기, 심지어 `touch`조차 금지), `auto_dev/config.json`은 현재 상태 유지. 변경을 강제하려는 시도는 오히려 게이트 위반이 되므로, 태스크 실행 범위를 `project/` 하위 디렉토리로 명확히 해야 함.
- **게임 구현**: `project/` 구조는 `src/`, `assets/`, `tests/`, `project_config.json`으로 구성되어 있음. 구현은 이 디렉토리 내에서만 수행하며 `auto_dev/`는 완전히 격리된 개발 인프라(orchestrator/agent용)로 간주.

## 구현 시 주의사항
- `auto_dev/` 디렉토리 내의 **모든 파일**을 열기, 읽기, 쓰기, 삭제, 생성任何一种 작업하지 마세요. 이는 orchestrator 인프라 파일이며 태스크 실행 범위가 아님.
- 반드시 `tests/task001_test.gd`를 작성하고, 모든 테스트를 통과해야 게이트를 통과함.
- 구현 파일은 `project/src/`, `project/assets/`, `project/` 하위 디렉토리 내의 `.gd`, `.json`, `.tres`, `.res`, `.import` 파일들에만 국한한다.
- `auto_dev/`의 백업 파일(`*.bak_*`)은 구현이 생성하지 않아야 하며, 만약 기존에 존재한다면 해당 파일들을 건드리지 않기.

## 테스트 계획
1. `project/` 디렉토리 구조 확인: `src/`, `GrappleGizmo/`, `GrappleSystem/`, `GrappleUI/` 폴더가 생성되었고 GDScript 파일이 배치되었는지 확인.
2. `project_config.json`에 새 태스크(`TASK-POST3D-REG-001`)의 메타데이터가 추가되었는지 확인.
3. `tests/task001_test.gd`를 작성: 시뮬레이션된 input으로 그랩링-스윙-배리어 시스템이 작동하는지 확인.
4. 테스트 실행하여 게이트 통과: 모든 기능 요구사항(High: 5개, Med: 3개, Low: 3개, Must-have 4개)이 충족되었는지 확인.
5. `auto_dev/` 내 파일들이 변경되지 않았는지 게이트 재확인.

설계 해결: DONE