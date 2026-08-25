# TASK-3D-VIS-001-5 Visual Village Composition Prototype 결과 리포트

> 실행일: 2026-08-26. 엔진: Godot 4.7.1 stable.
> 회귀 테스트: `tests/task3dvis0015_test.gd` (51 assertions, 전부 PASS).
> 스크린샷: `test_results/village_composition_{overview,worker_zoom,night}.png`.

---

## 1. 산출물 요약

| 파일 | 변경 | 내용 |
|------|------|------|
| `scripts/village_composition_3d.gd` | 신규 | VillageComposition3D. 4 zone + main path + 가옥/props/캐릭터 결정적 조립 스크립트 |
| `scenes/village_composition_3d.tscn` | 신규 | 마을 구성 프로토타입 scene(root + script) |
| `tests/task3dvis0015_test.gd` | 신규 | 구조/밀도/variation/path 가독성/캐릭터/camera pan-zoom/DAY-NIGHT 회귀(51 assertions) |
| `tools/capture_village_composition_3d.gd` | 신규 | overview / zoom-in / NIGHT 3컷 캡처 도구 |
| `test_results/village_composition_overview.png` | 신규 | 완료조건 1: DAY 전체 overview |
| `test_results/village_composition_worker_zoom.png` | 신규 | 완료조건 2: 벌목꾼 작업 zoom-in |
| `test_results/village_composition_night.png` | 신규 | 완료조건 3: NIGHT overview(주간과 동일 구도) |
| `test_results/task3dvis0015_test_run.txt`, `village_composition_capture_run.txt` | 신규 | 테스트/캡처 로그(캡처 ERROR/WARNING 0건) |
| 본 문서 | 신규 | 구성 기록 + visual blockers |

기존 파일 수정 없음(world3d.tscn / world_root_3d.gd / camera / BLD·RES·WRK 도메인 무수정).

## 2. 구성(태스크 요구 → 구현 대응)

| 요구 | 구현 |
|------|------|
| House 여러 채 | 5채(4x4 4채 + 6x6 1채). plaster/brick 2 palette, 문 방향 yaw 4방향, roundtiles 지붕 + 굴뚝/횃불 |
| Lumberyard 느낌 공간 | 서측(x[-30,-19], z[3,14]): stump 작업대+도끼, 원목 더미 4개, 마차, 크레이트/통, 횃불 |
| Quarry 느낌 공간 | 남동(x[16,30], z[10,22]): 암반 아웃크롭 6 + 석재 더미 3(scale 0.55 밴드), 곡괭이+크레이트 작업대 |
| Tree cluster | 북서 숲 24그루(variant 4종, scale 0.5/0.55) + 하층 식생 12 + 마을 포인트 수목 2그루 |
| Rock cluster | quarry 암반/잔반 6 + 석재 더미 3 + 숲 가장자리 1 |
| Main path | spine/east/west/forest_road/yard_road/quarry_road/plaza 7 corridor, 지면 strip(y=0.05, shadow off, 충돌 없음) |
| props | 시장 행(stall/stall_cart/농산 크레이트/coin/bag/통), 화단, 울타리, 작업 정체성 props |
| 주민/Worker/Mercenary | CharacterRig3D 6기: 주민 2(idle), 운반 walk 1, 벌목꾼(도끼·work), 광부(곡괭이·work), 용병(검·idle) |
| Camera Pan/Zoom 테스트 | task3dvis0015 CAMERA_PAN/ZOOM phase(경계 clamp + ortho size 수렴) |
| DAY/NIGHT lighting | environment_3d 레이어 + NIGHT/DAY 전환 smoke(테스트) + NIGHT 스크린샷 |

공간 밀도 원칙: zone RECT가 코드의 단일 소스이고 테스트가 겹침 없음과
`forest 수목 24 >= 마을 수목 2 x 3` 비율을 고정한다. 화면을 랜덤 에셋으로
채우지 않는다 — 배치 전원이 결정적 좌표 테이블이다(RNG 없음).

지면 톤: `apply_ground_tone()`이 world3d placeholder GroundVisual에 런타임
material_override(albedo 0.42/0.62/0.35, task3dvis0013 가독성 밴드와 동일 톤)를
입힌다. 기존 캡처 도구의 임시 관례를 VIS 소유 API로 정식화한 것이며 scene 파일은
무수정이다.

## 3. Visual Blockers (완료조건 4)

1. **stump 스테이션이 모루로 읽힘**: `tool/chopping_log`(Anvil_Log)가 로그 받침
   위 anvil 형태라 근접 시 벌목 대신 대장간으로 읽힌다. 팩 내 대체 후보가
   없는 catalog 기록 예외(log_pile)라 유지했으며, VIS-002-1 기능 Lumberyard
   wiring 시 후보를 재검토해야 한다.
2. **원목 더미 반복감**: 같은 모델 4개를 yaw/scale jitter로 쌓았지만 zoom-in에서
   "박힌 도끼" 실루엣 반복이 보인다. variation 상한 준수를 위한 의도적 절충.
3. **광부 work 모션이 벌목 동작**: 채굴 전용 animation이 UAL에 없음
   (VIS_VISUAL_CATALOG_REPORT §3 비고 유지). TreeChopping이 대용 재생된다.
4. **지면이 단색 톤**: 실제 terrain 텍스처/타일 변화가 없다. INT-001의
   GroundVisual 교체 전까지 apply_ground_tone 단색이 최선이다.
5. **가옥 footprint 정사각 한정**: roundtiles 지붕 균일 scale 조립식 특성상
   4x4/6x6만 지원한다(비정사각 가옥은 조립식 확장 필요).
6. **성문 미표현**: 마을 남쪽 출입구는 울타리 2쌍 암시 수준이며 실제 Gate는
   BLD-001-3(기능 도메인) 소유다.
7. **캐릭터 facing 근사값**: 리그 yaw가 수동 지정이라 일부 시선이 어긋난다.
   이동/facing은 WRK/CMB Actor 소유이며 기능 연결 시 대체된다.

## 4. 검증 결과

- `tests/task3dvis0015_test.gd`: **PASS**(51 assertions — 구조/zone 밀도/
  variation/path clearance/캐릭터 action·tool/camera pan-clamp·zoom 수렴/
  NIGHT-DAY 전환/free 안전). 로그: `test_results/task3dvis0015_test_run.txt`.
- 회귀 재실행 PASS: smoke, task3d0012(foundation), task3d0013(camera),
  task3dres0013(resource), task3dvis0011(import), task3dvis0012(catalog),
  task3dvis0013(environment), task3dvis0014(character).
- 스크린샷 3컷 캡처 로그 ERROR/WARNING 0건
  (`test_results/village_composition_capture_run.txt`).
- 캡처 실행 조건: `--headless`는 dummy rasterizer라 불가 — window 띄워 실행
  (기존 캡처 도구와 동일).

## 5. 남은 HUMAN_CHECK

- 첫 화면에서 "2D 때보다 확실히 낫다"는 인상이 있는지.
- 마을이 살아 있는 공간처럼 보이는지.
- Zoom-out에서 전체 구성이 읽히는지.
- Zoom-in에서 Worker 관찰 가치가 있는지.
- Quaternius 에셋끼리 한 세계처럼 보이는지.
- Top-down 3D 전환 방향을 계속 가져갈 시각적 가치가 충분한지.

판단 자료: `test_results/village_composition_overview.png`(전체 구성),
`village_composition_worker_zoom.png`(벌목꾼 작업),
`village_composition_night.png`(야간 동일 구도).
