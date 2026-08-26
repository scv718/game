# TASK-3D-VIS-001 INTEGRATION NOTE (Asset / Environment / Visual)

> 후속 태스크(INT-001, VIS-002)가 VIS 도메인 산출물을 소비할 때
> 필요한 계약 요약. 현재까지 TASK-3D-VIS-001-1(Asset Import), -001-2(Visual
> Catalog), -001-3(Environment / Lighting Prototype), -001-4(Character /
> Outfit / Animation Prototype), -001-5(Visual Village Composition
> Prototype)의 산출물을 다룬다.
>
> 자세한 배경: `auto_dev/VIS_ASSET_IMPORT_REPORT.md`(-001-1),
> `auto_dev/VIS_VISUAL_CATALOG_REPORT.md`(-001-2),
> `auto_dev/VIS_CHARACTER_ANIM_REPORT.md`(-001-4),
> `auto_dev/VIS_VILLAGE_COMPOSITION_REPORT.md`(-001-5, visual blockers 포함).

## 신규 파일 (TASK-3D-VIS-001-3 Environment / Lighting Prototype)

| 파일 | 역할 |
|------|------|
| `scripts/environment_lighting_3d.gd` | EnvironmentLighting3D. WorldEnvironment + DirectionalLight3D 레이어. DAY/NIGHT 프리셋 단일 소스 |
| `scenes/environment_3d.tscn` | 환경 레이어 scene. Main 3D World에 add_child로 얹는다 |
| `tools/capture_environment_3d.gd` | DAY/NIGHT 라이팅 스크린샷 캡처 도구 |
| `tests/task3dvis0013_test.gd` | 환경/라이팅 회귀 테스트(55 assertions) |

## 신규 파일 (TASK-3D-VIS-001-4 Character / Outfit / Animation Prototype)

| 파일 | 역할 |
|------|------|
| `scripts/character_rig_3d.gd` | CharacterRig3D. humanoid visual + 공용 애니메이션 + tool attach 공용 리그 |
| `scenes/character_prototype_3d.tscn` | 4 리그 라인업 프로토타입 scene(base/worker×2/mercenary) |
| `tools/capture_character_prototype_3d.gd` | 캐릭터 라인업 DAY/NIGHT 캡처 도구 |
| `tests/task3dvis0014_test.gd` | 캐릭터/애니메이션 회귀 테스트(130 assertions) |

## 신규 파일 (TASK-3D-VIS-001-5 Visual Village Composition Prototype)

| 파일 | 역할 |
|------|------|
| `scripts/village_composition_3d.gd` | VillageComposition3D. 4 zone + main path + 가옥/props/캐릭터 결정적 조립 |
| `scenes/village_composition_3d.tscn` | 마을 구성 프로토타입 scene |
| `tools/capture_village_composition_3d.gd` | overview / zoom-in / NIGHT 3컷 캡처 도구 |
| `tests/task3dvis0015_test.gd` | 구성/밀도/variation/path 가독성/camera/DAY-NIGHT 회귀 테스트(51 assertions) |

## 캐릭터 리그 소비 계약 (WRK-001 / CMB-001 / VIS-002 소비 지점)

1. **Wiring**
   - Actor3D(Worker/Mercenary/Enemy 도메인 소유)가 `CharacterRig3D`를 자식으로
     둔다. 이동/facing/state machine은 Actor 소유, 이 리그는 visual/animation만
     담당한다. rig root yaw 회전이 곧 방향 전환이다(sprite 개념 없음).
   - variant는 `body_key` catalog 키 교체만으로 만든다. base/outfit 전원이
     동일 65본 리그(실측, VIS_CHARACTER_ANIM_REPORT.md §2)라 어떤 조합이든
     공용 애니메이션이 그대로 재생된다. retarget/BoneMap 불필요.
   - tool은 `tool_key` export 또는 `attach_tool(catalog_key)`로 hand_r에 붙는다.
     grip 미세 조정은 `set_tool_grip_transform()`(bone space)을 사용한다.

2. **Animation 재생 계약**
   - 단일 소스는 `VisualAssetCatalog3D.ANIMATION_SETS`(action → 후보,
     first = primary)다. 도메인 코드에 애니메이션 이름을 하드코딩하지 않고
     `play_action("idle"/"walk"/"work"/"combat"/"hit"/"death")`만 호출한다.
   - `play_action()`은 미설치 action에 false를 반환한다. **재생 실패로 상태
     머신을 멈추지 않는다**(VIS-002-2 요구의 사전 준수).
   - loop 정책: idle/walk/work loop, combat/hit/death 1회성. UAL GLB 원본
     Animation은 변형하지 않고 duplicate 사본(static 캐시 1벌)만 사용한다.
   - AnimationTree는 도입하지 않는다. state graph가 필요해지면 그때 별도
     태스크로 협의한다.

3. **catalog 변경 시**
   - `attachment_scale_hint_for_key()`는 SELECTIONS의 scale_hint 역방향 조회다.
     새 tool/weapon 키에 hint를 주려면 SELECTIONS variation에 scale_hint를
     기록한다(코드 하드코딩 금지).
   - ANIMATION_SETS에 후보를 추가하면 리그가 자동 설치한다. 단, 존재하지 않는
     이름은 push_warning + 실패 확정 캐시되므로 task3dvis0014 CONTRACT 항목을
     함께 갱신할 것.

## 통합 계약 (INT-001 소비 지점)

1. **Wiring**
   - `scenes/environment_3d.tscn`을 Main 3D World Root(`world3d.tscn` 인스턴스)
     위에 add_child로 연결한다(camera_controller_3d와 동일 방식). world3d.tscn /
     world_root_3d.gd는 Foundation 소유라 무수정이며, 환경은 자식 node로 추가만 한다.
   - viewport당 WorldEnvironment는 **1개만** 허용된다. 이중 주입 시 마지막 진입
     환경이 이기므로, 임시 라이트를 스스로 만들던 기존 캡처 도구들
     (capture_resources_3d / capture_quaternius_preview)과 함께 쓰지 않는다.
   - 스크립트가 스스로 `GameTime.phase_changed`를 구독하고 _ready에서 현재 phase를
     적용하므로 별도 초기화 호출이 필요 없다. free 시 구독도 자동 해제된다
     (task3dvis0013_test가 회귀 고정).

2. **DAY/NIGHT look 단일 소스**
   - 프리셋은 `EnvironmentLighting3D.PRESETS`(DAY/NIGHT)다. 수치 변경은 이곳만
     수정한다. `apply_phase(phase)` public API로 수동 전환 가능하다(캡처/테스트 용).
   - post-processing 예산은 코드로 고정되어 있다: glow/fog/volumetric_fog/ssao/
     ssil/sdfgi/adjustment 상시 off + LINEAR tonemap("과도한 bloom/fog/
     post-processing 금지" 요구의 코드화). NIGHT 가독성을 올리려면 프리셋의
     ambient 수치만 조정하고 postfx 예산을 열지 않는다.
   - Shadow는 상시 on(SHADOW_ORTHOGONAL 단일 분할, max distance 220 unit =
     camera min_zoom 0.4 overview 커버). phase와 무관하다.

3. **가독성 수치 계약**
   - preset은 ground 반사휘도 밴드 검증을 통과하는 값으로 고정되어 있다
     (task3dvis0013_test READABILITY 항목): DAY ground 휘도 [0.45, 0.95],
     NIGHT [0.06, 0.30] + NIGHT/DAY 비율 0.5 미만 + NIGHT 중간톤 유닛 휘도 0.10 초과.
   - 프리셋 수치를 바꿀 때 이 밴드 테스트가 깨지면 top-down 가독성 요구
     ("terrain이 캐릭터/건물을 묻히지 않음") 위반이므로 수치를 되돌리거나
     밴드를 재협의한다.

4. **Ground / terrain 경계**
   - world3d.tscn의 placeholder `GroundVisual`(기본 흰 PlaneMesh)에 대한 임시
     톤 처리는 VIS-001-5가 `VillageComposition3D.apply_ground_tone(world_root)`
     로 소유 API화했다(albedo 0.42/0.62/0.35 = task3dvis0013 가독성 밴드 톤).
     scene 파일은 무수정이며, 런타임에서 마을 구성 scene이 자식으로 들어오면
     이 함수가 material_override를 입힌다. 기존 캡처 도구들의 `_dress_ground`
     임시 하드코딩은 본 API로 대체 가능하다.
   - 실제 terrain/ground visual 교체는 여전히 INT-001 소유다. 교체 시 이
     override를 제거해도 마을 구성은 깨지지 않는다(함수가 GroundVisual 부재 시
     false 반환, 마을 자체는 독립 동작).
   - Main path/plaza는 VillageComposition3D 소유의 지면 strip 장식이다
     (y=0.05, shadow off, collision/selection 노드 없음). gameplay nav/selection
     와 충돌하지 않으며, 기능 도메인 path 표현이 필요하면 BLD/WRK 도메인
     구현물로 대체한다.

## 검증 결과

- `tests/task3dvis0013_test.gd` — 구조/postfx 예산/DAY-NIGHT 전환·복원/가독성
  밴드/그림자 설정/통합 smoke/freed 구독 정리: **55 assertions PASS**.
- `tests/task3dvis0014_test.gd` — 리그 구조/tool attach/catalog 계약/공용 65본
  호환/6 action 재생/동시 재사용/방향 전환 무재생성/free 안전: **130
  assertions PASS**. 로그: `test_results/task3dvis0014_test_run.txt`.
- `tests/task3dvis0015_test.gd` — 구조/zone 밀도 분리/variation 상한/path
  clearance(solid 장식의 corridor 침범 금지)/캐릭터 action·tool attach/
  camera pan clamp·zoom 수렴/NIGHT-DAY 전환/free 안전: **51 assertions PASS**.
  로그: `test_results/task3dvis0015_test_run.txt`.
- 회귀 재실행 PASS: smoke, task3d0012(foundation), task3d0013(camera),
  task3dres0013(resource), task3dvis0011(import), task3dvis0012(catalog),
  task3dvis0013, task3dvis0014.
  로그: `test_results/*_rerun_vis0013.txt`, `test_results/*_rerun_vis0014.txt`,
  `test_results/smoke_test_rerun_vis0015.txt`.
- 스크린샷(완료조건 1·2): `test_results/environment_3d_day.png`,
  `test_results/environment_3d_night.png`. 캡처 로그에 ERROR/WARNING 0건
  (`test_results/environment_3d_capture_run.txt`, 완료조건 3).
  캐릭터 라인업: `test_results/character_prototype_day.png`,
  `character_prototype_night.png`
  (`test_results/character_prototype_capture_run.txt`, ERROR/WARNING 0건).
- 마을 구성(완료조건): `test_results/village_composition_overview.png`,
  `village_composition_worker_zoom.png`, `village_composition_night.png`
  (`test_results/village_composition_capture_run.txt`, ERROR/WARNING 0건).
- 캡처 실행 조건: `--headless`는 dummy rasterizer라 캡처가 불가능하므로
  window를 띄워 실행한다(기존 캡처 도구와 동일).

## 남은 HUMAN_CHECK (TASK-3D-VIS-001-3)

- DAY에 밝고 생활감 있는 마을 느낌인지.
- NIGHT에 위험 분위기가 생기면서도 유닛/길이 읽히는지.
- 그림자가 지형/건물 가독성을 개선하는지.
- 너무 모바일 게임처럼 가볍거나 반대로 반실사처럼 보이지 않는지.

판단 자료: 위 DAY/NIGHT 스크린샷 2장(동일 구도, zoom 2.0). 스크린샷 내 마을
구성물 배치는 라이팅 판독용 임시 구성이며 실제 마을 조립은 VIS-001-5 소유다.

## 남은 HUMAN_CHECK (TASK-3D-VIS-001-4)

- tool grip 미세 자세(도끼/검의 손안 각도) 최종 조정은 wiring(VIS-002)의
  `set_tool_grip_transform()` 몫이다. 기본값도 자연스럽게 읽힌다.
- work action이 TreeChopping 대용이라는 catalog 비고(채굴 전용 모션 부재) 유지.

판단 자료: `test_results/character_prototype_{day,night}.png`. 4 리그가
idle/work(도끼)/walk/combat(검)을 동시 재생한 장면이다.

## 남은 HUMAN_CHECK (TASK-3D-VIS-001-5)

- 첫 화면에서 "2D 때보다 확실히 낫다"는 인상이 있는지.
- 마을이 살아 있는 공간처럼 보이는지.
- Zoom-out에서 전체 구성 읽힘.
- Zoom-in에서 Worker 관찰 가치가 있음.
- Quaternius 에셋끼리 한 세계처럼 보이는지.
- Top-down 3D 전환 방향을 계속 가져갈 시각적 가치가 충분한지.

판단 자료: `test_results/village_composition_{overview,worker_zoom,night}.png`.
알려진 visual blocker 7건은 `auto_dev/VIS_VILLAGE_COMPOSITION_REPORT.md` §3에
기록되어 있으며, 전부 기능 wiring(VIS-002/BLD/WRK) 또는 INT-001 인계 항목이다.
