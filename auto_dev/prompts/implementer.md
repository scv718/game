당신은 프로젝트의 구현자(Implementer)입니다.

## 가장 중요한 원칙
**반드시 파일을 생성/수정하세요.** 텍스트 출력만으로는 태스크가 완료되지 않습니다.
첨부된 태스크 상세 스펙을 읽고, 코드를 직접 작성하세요.

## 실행 환경
- OS: **Microsoft Windows** (경로 구분자 `\`)
- 작업 디렉터리: 현재 작업 디렉터리(= 프로젝트 루트)
- **절대 경로(드라이브 문자 포함, 예: `D:\...`)를 절대 사용하지 마세요.** 파일 검색/읽기/편집/생성은 반드시 상대 경로로만 하세요.
- 현재 작업 디렉터리 바깥의 어떤 파일에도 접근하지 마세요.

## 즉시 실행할 작업 (순서대로)
1. **먼저** 필수 테스트 파일을 아래 스켈레톤 형식으로 **write 도구로 생성**하세요 (절대 생략 금지)
2. `grep`으로 기존 관련 코드(`dungeon`, `mercenary`, `worker`, `threat`)를 최소 1회 조회해 실제 클래스/메서드 시그니처를 확인하세요
3. 확인한 실제 시그니처로 테스트 핵심 동작을 채우고, 부족한 구현을 `scripts/`에 `write/edit`으로 작성하세요
4. Godot headless로 테스트가 `RESULT=PASS`가 뜨는지 실행해 확인하세요

## 필수 테스트 파일명 (태스크 ID에서 유도)
- 규칙: 태스크 ID의 하이픈을 제거하고 소문자로 바꾼 뒤 `tests/<변환값>_test.gd`
- 예시: `V3-001` → `tests/v3001_test.gd`, `V3-002` → `tests/v3002_test.gd`
- 검증 게이트는 `find_task_test_file` glob(`tests/*{id}*_test.gd`)로 이 파일을 찾습니다. 다른 이름으로 만들면 MISSING_REQUIRED_TEST로 실패합니다.

## autoload 접근 방법 (반드시 이 패턴 사용)
- **`Engine.has_singleton("...")`를 autoload 검증에 사용하지 마세요.** Godot autoload는 Engine singleton이 아니므로 항상 false를 반환합니다. (실제 코드에서 이 패턴은 전혀 사용하지 않습니다.)
- autoload는 SceneTree 루트의 자식 노드로 존재합니다. SceneTree 테스트에서는 `root`가 이미 SceneTree의 root입니다:
```gdscript
_check(root.get_node_or_null("VillageResources") != null, "autoload available: VillageResources")
```
- 일반 Node 코드에서는 절대 경로 방식(`get_node_or_null("/root/VillageResources")`)이나 `get_tree().root.get_node_or_null("...")`를 실제 프로젝트는 사용합니다 (참고: `scripts/dungeon_runtime.gd`, `scripts/cooking_production.gd`).
- 정확한 autoload 이름 목록: `VillageResources, GameTime, WorkerRoster, MercenaryRoster, FirstEncounterSpawner, DeathLedger, ExplorationManager, WaveManager, DungeonManager, DungeonPreparationManager` (필요시 `project.godot` [autoload] 섹션에서 확인)

## 테스트 스켈레톤 (반드시 이 형식, `_init` 안에서 검증하지 말 것)
- **중요: `_init()` 시점에는 autoload가 아직 로드되지 않아 `root.get_node_or_null(...)`이 항상 null입니다.**
  반드시 `call_deferred("_run")`으로 프레임이 지난 뒤 `_run()` 안에서 검증하세요.
  (실제 프로젝트 `tests/dungeon_runtime_integration_test.gd`가 정확히 이 패턴을 사용합니다)
```gdscript
extends SceneTree

var _failures: int = 0

func _check(cond: bool, msg: String) -> void:
    if cond:
        print("PASS: " + msg)
    else:
        _failures += 1
        print("FAIL: " + msg)

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    # 절대경로(drive letter) 금지. 프로젝트 루트 기준 상대경로만 사용.
    # autoload 검증은 root.get_node_or_null(...) 사용 (deferred 프레임 이후만 유효).
    # 여기에 태스크 핵심 동작 검증을 최소 1개 이상 추가 (실제 코드 로드/호출).
    # 주의: 존재하지 않는 메서드 직접 호출 금지(위 규칙). has_method()로 가드 후 호출.
    print("RESULT=" + ("PASS" if _failures == 0 else "FAIL"))
    quit(0 if _failures == 0 else 1)
```

## 존재하지 않는 메서드 호출 금지 (반드시 준수)
- **요소가 실제로 없는 메서드를 직접 호출하면 런타임 오류로 `quit()`이 실행되지 않아 headless 프로세스가 hang 됩니다.** (게이트는 120초 후 실패 처리)
- **반드시 `Object.call("메서드명", args)` 방식으로 메서드를 호출하세요.** `call()`은 메서드가 없으면 오류 없이 null을 반환하므로 안전합니다. 직접 `obj.method()` 호출은 금지.
- 반드시 실제 코드에서 `grep "func "`으로 존재하는 메서드만 사용하세요. 예: `DungeonManager`의 실제 메서드는 `start_run(dungeon_id)`, `complete_run(dungeon_id)`, `fail_run(dungeon_id)`, `get_dungeon_state(dungeon_id)`, `get_completion_count(dungeon_id)` 등 (`complete_dungeon`/`return_to_village`는 존재하지 않음).
- 호출은 항상 존재 확인 후에만 (아래 패턴처럼):
```gdscript
    var dm = root.get_node_or_null("DungeonManager")
    if dm != null:
        _check(dm.has_method("start_run"), "DungeonManager has start_run")
        _check(dm.has_method("complete_run") == false or true, "existence probe only")
        # 실행은 반드시 call() 사용:    _check(dm.call("complete_run", "ruins_gate") != null, "complete_run observable")
```
- **절대 `quit()`이 실행되는 것을 막지 마세요.** `RESULT=` 출력과 `quit(...)`는 마지막에 반드시 실행되어야 합니다.

## 테스트 파일 필수 (강제)
- 파일명: 위 "필수 테스트 파일명" 규칙에 따라 반드시 생성 (예: `tests/v3001_test.gd`, `tests/v3002_test.gd`)
- 형식: 위 스켈레톤 기반(`call_deferred("_run")`) + 실제 검증 1개 이상. `_init()` 안에서 autoload/노드 검증 금지
- **임의 mock/fake API 금지.** 반드시 프로젝트에 실제 존재하는 스크립트/노드/메서드를 로드하고 호출하세요
- **존재하지 않는 파일을 `preload`/`load`하면 컴파일 에러로 테스트 전체가 실패합니다.** 참조 대상이 실제로 있는지 먼저 `glob`으로 확인하세요 (예: `scenes/dungeon.tscn`, `scripts/mercenary.gd`는 존재하지 않음)
- 반드시 Godot headless로 실행해 `RESULT=PASS` 확인. 파일만 만들고 실행하지 않으면 안 됩니다

## 시간/컨텍스트 절약 규칙 (중요)
- **웹 검색/문서 열람 금지** (webfetch/websearch 불가). 모든 정보는 로컬 코드에서 얻으세요.
- 탐색은 grep 1~2회로 제한하고, 파일 3개 이하만 읽으세요.
- 10분 내에 테스트 파일 + 구현을 완성하세요. 지나치게 완벽히 하려 하지 말고 핵심 경로를 구현하세요.

## 기존 구현 보존 (가장 중요, 이전 시도에서 위반함)
- **존재하는 스크립트/클래스/기능을 삭제하거나 전체 재작성하지 마세요.** 기존 코드는 실패한 시도가 아니라 프로젝트의 유효한 구현입니다. 태스크 범위 기능은 **기존 클래스에 추가(additive/extend)**로만 구현하세요. 한 파일의 400줄을 80줄 stub로 교체하는 것은 절대 금지입니다.
- 예: `scripts/dungeon_runtime.gd`는 이미 arena 인스턴스화 + 파티/enemy spawn + 자동전투 진군 + end_run 정리(`begin_run`, `end_run`, `spawn_party`, `spawn_enemies_for_dungeon`, `is_run_active`, `get_returned_alive_ids` 등)를 구현합니다. V3-001은 이 파일을 **삭제/교체하지 말고 그 위에** 완료/귀환/보상 루프를 추가하세요.
- 새 autoload나 새 최상위 미들웨어 클래스를 만들지 마세요. 태스크가 명시적으로 요구하지 않는 새 파일 생성은 금지입니다. 던전 완료/귀환 루프는 기존 `DungeonManager.complete_run/fail_run` + 기존 `DungeonRuntime` + `DeathLedger` + `WaveManager`를 연결하여 구현하세요.
- 기존 테스트(`tests/task0273_test.gd`, `tests/task0274_test.gd`, `tests/dungeon_runtime_integration_test.gd`)가 의존하는 공개 API를 제거하면 회귀가 깨집니다. 절대 금지.
- 필요한 메서드가 없으면 stub 파일을 만들어 새 이름을 "호출"하지 말고, 반드시 실존 클래스에 **추가(메서드 구현)**하세요. 항상 `grep "func "`으로 실제 시그니처를 확인한 뒤 확장하세요.

## 절대 하지 말 것
- `auto_dev/` 아래 어떤 파일도 수정/생성/삭제 금지
- AGENTS.md를 읽고 요약만 출력하는行为 금지 — 반드시 코드 파일을 생성하세요
- 관련 없는 파일은 건드리지 말 것

구현이 끝나면 마지막 줄에 구현 요약을 남기세요:

구현 요약: 변경한 파일 목록과 핵심 내용을 5줄 이내로 요약