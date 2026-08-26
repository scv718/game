# TASK-3D-INT-001-3 2D Runtime Dependency Cleanup — 처리 결과 (2026-08-26)

> 게이트 규칙상 `auto_dev/` 무수정 원칙을 지키기 위해 본 감사 문서를 루트에 둔다.
> 기존 통합 노트(`auto_dev/INTEGRATION_NOTE_INT.md`)의 INT-001-1/001-2 절은
> 그대로 유효하며, 본 문서가 그 후속(INT-001-3) 감사 산출물이다.

## 방법론

1. 정확 매칭 전수 검색: `res://scripts/*.gd`, `res://scenes/*.tscn`, `res://ui/*.tscn`
   경로 문자열 + 각 스크립트 class_name 식별자(`Interactable3D` 등 3D 접미사 제외한
   단어 경계 매칭)를 scenes/scripts/ui/tools/tests/project.godot 전체에서 검색.
   단순 부분문자열 매칭(tree↔tree_3d 오염)은 배제했다.
2. 도달 가능성 계산: root = {project.godot autoload 7종} ∪ {tests/*.gd,
   tools/*.gd의 load/preload 대상}으로 두고 역참조 도달 집합을 구성.
3. dangling 참조 스캔: runtime 디렉터리(scenes/scripts/ui)와 project.godot의
   res:// .gd/.tscn/.tres 참조 대상 존재 여부 전수 확인.

## 감사 결과 (삭제 불가 판정과 근거)

| 2D runtime 파일군 | 참조자(실측) | 판정 |
|---|---|---|
| `scenes/main.tscn` | tests/smoke_test.gd(gate 회귀) + 레거시 테스트 ~70종 + tools/capture_world.gd | 보존 — smoke gate가 직접 load |
| `scenes/world.tscn`(+world.gd, world_dressing.gd) | main.tscn + world_visual_composition_test/task0166 + generate_world_map.gd | 보존 |
| tree/stone_deposit/core_building/lumberyard/quarry/wall/gate/lumberjack/miner/mercenary/enemy/decoration/camera_controller `.tscn`+`.gd` | 위 main·world 경유 + 개별 테스트 다수(task0062~0166, tasknav001 등) | 보존 — 테스트 fixture |
| `interactable.gd` + interactable 서브클래스 4종 | task0134 + 2D scene들 + **3D 계약 문서 문자열**(interactable_3d.gd 등) | 보존 |
| `character_visual.gd` | lumberjack/miner/mercenary/enemy tscn 4종(전부 fixture) | 보존 |
| autoload `mercenary_roster.gd`, `first_encounter_spawner.gd` | project.godot + tavern/inn/tactical UI 스크립트(3D Runtime도 공유) + mercenary_hire_sync_3d bridge + CMB 테스트 | 보존 — 제거 시 공유 UI 스크립트 수정이 필요해 본 태스크 범위 초과. dormant guard는 task3dint0011 테스트가 고정. 최종 스위치-off는 후속 태스크 |
| `ui/hud.tscn`(2D), `ui/tactical_command_ui.tscn` | main.tscn/hud.tscn 경유 | 보존 — UI Control은 삭제 대상 아님(큐 요구사항) |
| `tools/generate_world_map.gd`, `capture_world.gd`, tile 파이프라인 3종 | 수동 실행 진입점. world.tscn fixture 재생성/2D 캡처 유지에 필요 | 보존 — migration map "폐기 예정" 표기는 fixture 보존 기간 동안 유예 |

요약: 요구사항 "테스트/reference 용도로 필요한 파일은 근거 없이 삭제하지 않음"에
따라, 2D Resource/Worker/Building/Combat Scene은 **전원 실측 미사용(Runtime 3D
closure 비포함)이지만 회귀 fixture로 보존**한다. 삭제 가능 항목은 아래뿐이다.

## 실제 삭제 항목

- 루트 고아 `*.gd.uid` sidecar 11종(analyze_sheet / bottom_render / crop40_render /
  crop_single_tree / demo_village_render / probe_pixels / region_comp_render /
  test_tile_3 / test_tile_rt / top_render / verify_new_sprites) — 스크립트 본체가
  오래전 삭제된 잔재. 본 태스크 작업 중 제거되었고 커밋 6fb8618에 포함.
- 그 외 scene/script 삭제 없음(위 표 근거). `git clean` 미사용, 이름 기반 일괄
  삭제 없음, assets/license 문서 무손실, GAME_DESIGN 무수정.

## dangling 참조 스캔 결과

- scenes/scripts/ui + project.godot: **0건**.
- tests/overnightstop7_test.gd의 player.gd/player.tscn 참조 = "제거 확인"
  negative assertion(의도적).
- tools/capture_world.gd의 test_results/*.png = 출력 경로(생성 대상).
- 위 두 예외를 배제하는 런타임 영역 dangling 검사를 tests/task3dint0013_test.gd에
  신규 assertion으로 추가해 회귀 고정했다.

## 2D 물리/내비/카메라 노드의 핵심 Runtime 잔존 확인

- live Runtime 트리(root 하위 실제 부팅 상태)에서 Node2D 파생 / CharacterBody2D /
  Area2D / NavigationAgent2D / Camera2D / TileMapLayer 전부 0개, Camera3D 1개 —
  tests/task3dint0013_test.gd TREE_AUDIT phase가 매 실행 고정.
- UI Control/CanvasLayer는 정상 2D UI 계약으로 허용(큐 요구사항).

## 완료조건 대조

- [x] Main Runtime 3D path self-contained — main_3d.tscn closure에 2D 전용 노드
      타입/extends 0건(테스트 고정).
- [x] orphan reference 없음 — closure/autoload/dangling 전수 검사 통과,
      고아 uid sidecar 0건.
- [x] smoke PASS — 아래 로그 참조.

## 검증 결과 (로그: test_results/)

- `tests/task3dint0013_test.gd`: **121 assertions PASS**
  (`task3dint0013_run6.txt`; 이전 세션 run1~run5는 parse 오류 수정 과정 기록).
- 회귀 재실행 PASS: smoke(`task3dint0013_rerun_smoke2.txt`),
  task3dint0011(`task3dint0013_rerun_int0011b.txt`),
  task3dint0012(`task3dint0013_rerun_int0012b.txt`).
- import 전수 재검증 오류 0건(`task3dint0013_import_run2.txt`),
  main scene boot ERROR/WARNING 0건(`task3dint0013_main_boot_run.txt`).

## migration_map_2d_to_3d.md 산출물 1.B 파일 처분 요약

| 항목 | 처분 |
|------|------|
| 2D main runtime path(main/world/camera_controller tscn + 도메인 scene/script 전체) | 보존 — smoke gate·레거시 스위트 load 대상(상단 표) |
| autoload MercenaryRoster / FirstEncounterSpawner(2D) | 보존 — 공유 UI 계약. 최종 제거는 후속 태스크 |
| 루트 고아 *.gd.uid sidecar 11종 | 삭제 완료 |
| tools/generate_world_map.gd 등 2D tool | 보존 유예 — fixture 폐기 시 재판단 |
| ui/*.tscn(Control), assets/license 문서 | 무손실 보존(큐 요구사항대로) |
