# TASK-3D-INT-002-3 INTEGRATION NOTE (Visual Acceptance)

> 3D 전환 최종 시각 수용 자료. 필수 screenshot 7컷, 기능 regression 결과,
> visual blocker 점검, HUMAN_CHECK 기록을 한 곳에 모은다.
>
> 판정 규칙(태스크 요구): **HUMAN_CHECK의 미감 판단을 AI가 임의로 PASS 처리하지
> 않는다.** 아래 모든 HUMAN_CHECK 항목은 사용자 최종 판단 대기 상태로 남는다.
> 자동검증과 기능 회귀는 전부 실제 실행으로 PASS 확인되었으므로, 본 태스크는
> "HUMAN_CHECK만 남은 상태"로 사용자 판단에 회부된다.

## 1. 변경 파일

| 파일 | 변경 | 내용 |
|------|------|------|
| `tools/capture_visual_acceptance_3d.gd` | 신규 | 실제 main_3d 런타임을 부팅해 필수 7컷을 캡처하는 SceneTree 도구. SHOTS 계약(7키)을 상수로 노출해 테스트가 감사한다 |
| `tests/task3dint0023_test.gd` | 신규 | Acceptance 회귀: artifact audit(7 PNG/캡처 로그/report/regression 로그) + live functional slice(부팅~배치~생산~NIGHT~DAY cleanup) |
| `auto_dev/INTEGRATION_NOTE_INT_VISUAL_ACCEPTANCE.md` | 신규 | 본 문서. HUMAN_CHECK 사용자 판단 대기 기록의 단일 소스 |
| `test_results/visual_acceptance_*.png` (7건) | 신규 | 필수 스크린샷 산출물 |
| `test_results/visual_acceptance_capture_run.txt` | 신규 | 캡처 실행 로그(ERROR/WARNING 0건) |
| `test_results/task3dint0023_regression_int0021_run.txt` | 신규 | 컨테이너 자동검증(task3dint0021) 재실행 로그 |
| `test_results/task3dint0023_regression_smoke_run.txt` | 신규 | main scene smoke 재실행 로그 |
| `test_results/task3dint0023_run.txt` | 신규 | 본 태스크 테스트 실행 로그 |

프로덕션 scene/script는 한 줄도 수정하지 않았다(LOCK 12 / 소유권 규칙 준수).

## 2. 필수 Screenshot 인덱스 (완료조건 1)

캡처 조건: 프로젝트 main scene(`scenes/main_3d.tscn`)을 실제 런타임으로 부팅,
창 모드 1152x648, 실제 입력 경로(build mode 클릭 / 주점·여관 UI 버튼 /
GameTime phase 경계 advance / 집중 공격 명령)로만 게임을 진행하고 촬영했다.

| 필수 항목 | 파일 |
|-----------|------|
| DAY full village overview | `test_results/visual_acceptance_day_overview.png` |
| DAY zoom-in Worker scene | `test_results/visual_acceptance_day_worker_zoom.png` |
| Forest/resource area | `test_results/visual_acceptance_forest_resource.png` |
| Lumberyard/Quarry | `test_results/visual_acceptance_lumberyard_quarry.png` |
| Building placement | `test_results/visual_acceptance_building_placement.png` |
| NIGHT tactical overview | `test_results/visual_acceptance_night_tactical.png` |
| NIGHT combat | `test_results/visual_acceptance_night_combat.png` |

스테이징 투명성(과장 없는 판단 자료 제공 목적):

- 지면 톤만 VIS-001-5 소유 공개 API `VillageComposition3D.apply_ground_tone`을
  캡처 경로에 적용했다(INTEGRATION_NOTE_VIS §4가 허용한 캡처 도구 용법).
  village_composition 장식물은 조립하지 않았다. 실제 terrain 교체는 VIS-002
  소유로 아직 open이며, 이로 인한 "placeholder 지면" 상태는 아래 blocker 점검에
  기록되어 있다.
- 액터(Worker/Mercenary/Enemy placeholder capsule), 건물(placeholder box +
  NameLabel), 나무/돌, 조명, HUD, tactical UI는 전부 프로덕션 그대로다.
- NIGHT combat 컷은 실제 tactical 명령(집중 공격 focus target)으로 용병이
  raider에게 접근해 교전 거리(ATTACK_RANGE 인접)에 진입한 순간 촬영했다.

## 3. 기능 Regression (완료조건 2)

| 회귀 | 결과 | 근거 로그 |
|------|------|----------|
| TASK-3D-INT-002-1 Automated Regression(컨테이너 21항목 전체) | **PASS** | `test_results/task3dint0023_regression_int0021_run.txt` (`TASK3DINT0021_RESULT=PASS`) |
| main scene smoke | **PASS** | `test_results/task3dint0023_regression_smoke_run.txt` (`SMOKE_RESULT=PASS`) |
| 본 태스크 테스트(artifact audit + live slice) | **PASS** | `test_results/task3dint0023_run.txt` (`TASK3DINT0023_RESULT=PASS`) |

live slice는 스크린샷이 대표하는 런타임이 실제로 동작함을 headless로 재확인한다:
부팅 wiring → build mode 입력 경로 배치(비용 1회 차감) → 주점 고용/여관 배치 →
Worker Actor spawn → 자동 생산 입금 → NIGHT encounter + tactical UI → DAY
cleanup → duplicate/orphan/freed 없음.

## 4. Visual Blocker 점검 (완료조건 3)

캡처 실행 로그(`visual_acceptance_capture_run.txt`)에서 ERROR/WARNING 0건.
렌더 자체의 치명적 결함(검은 화면, 누락 지면/액터, 깨진 material)은 없었다.

치명적이지는 않지만 사용자 판단에 영향을 주는 알려진 제한 사항:

1. **placeholder visual**: 건물/액터/나무는 primitive placeholder다. Quaternius
   visual wiring은 TASK-3D-VIS-002-1(IMPLEMENT)/-002-2 소유로 진행 중이며 본
   태스크 범위 밖이다. HUMAN_CHECK의 "아트 스타일" 판단은 이 상태 기준이다.
2. **지면 톤**: 캡처 경로에서만 API로 톤 적용(위 스테이징 투명성 참조). 실제
   terrain 교체는 VIS-002 인계 항목으로 open 되어 있다.
3. **NIGHT encounter 접근 정지 발견(기능 관찰, CMB 도메인 권장)**: 창 모드
   캡처 2회 모두 raiders가 spawn 직후 약 6 unit 이동 뒤 정지(HOLD)했다. 용병
   집중 공격(focus) 체이스와 교전/사망/Death Ledger는 정상 동작했고
   task3dcmb0012/0021 회귀도 전부 PASS이므로 기존 자동검증 범위에서는 감지되지
   않는다. 적 원거리 접근 루트(route init BLOCKED 시 waypoint 소진 → HOLD)의
   CMB 후속 확인을 권장한다. 본 태스크에서 production 수정은 하지 않았다.
4. **tactical UI 화면 점유**: NIGHT 지휘 패널이 화면 우측 약 26%를 상시 덮는다
   (기존 UI 계약 유지). 최대 zoom-out에서 마을 우측이 패널에 가려질 수 있다.

기타 발견(-s 계열 참고, 런타임 무영향): `scripts/lumberjack_3d.gd:241`이
autoload 전역 식별자 `VillageResources`를 직접 참조한다. 게임 부팅 런타임에는
영향 없으나, `-s` 스탠드얼론 컴파일 단계에서는 이 식별자가 resolve되지 않아
(INT-001-2/CMB-001-2가 문서화한 규약) Lumberjack3D를 이르게 참조하는 테스트/
도구가 컴파일 실패한다. 캡처 도구는 runtime load 규약으로 회피했다. 후속 -s
계열 작업 시 동일하게 회피할 것.

## 5. HUMAN_CHECK 기록 (완료조건 4) — 전부 사용자 판단 대기

> 아래 9항목 중 미감/체감 판정은 AI가 임의로 PASS 처리하지 않는다.
> 각 항목의 판정란은 전부 **사용자 판단 대기**이며, 판단 자료 스크린샷만 연결한다.

| # | HUMAN_CHECK 항목 | 판정 | 판단 자료 |
|---|------------------|------|-----------|
| 1 | **2D 버전보다 비주얼이 확실히 마음에 드는가.** | 사용자 판단 대기 | 전체 7컷 (2D 참고: 기존 `scenes/main.tscn`) |
| 2 | 첫 화면이 임시 개발용 프로토타입이 아니라 실제 게임 방향처럼 보이는가. | 사용자 판단 대기 | `visual_acceptance_day_overview.png` |
| 3 | 줌 아웃 시 마을/자원/방어 공간이 읽히는가. | 사용자 판단 대기 | `visual_acceptance_day_overview.png`, `visual_acceptance_forest_resource.png`, `visual_acceptance_night_tactical.png` |
| 4 | 줌 인 시 Worker 행동을 보는 재미가 있는가. | 사용자 판단 대기 | `visual_acceptance_day_worker_zoom.png`, `visual_acceptance_lumberyard_quarry.png` |
| 5 | 캐릭터/건물/자연물이 하나의 아트 스타일로 보이는가. | 사용자 판단 대기 | `visual_acceptance_day_overview.png`, `visual_acceptance_lumberyard_quarry.png` (현재 placeholder 상태 포함) |
| 6 | 카메라 각도/줌 범위가 프로젝트 좀보이드 계열의 탑다운 시야감과 목적에 맞는가. | 사용자 판단 대기 | `visual_acceptance_day_overview.png` vs `visual_acceptance_day_worker_zoom.png` (zoom 범위 양단) |
| 7 | 낮/밤 분위기 차이가 의미 있는가. | 사용자 판단 대기 | `visual_acceptance_day_overview.png` vs `visual_acceptance_night_tactical.png` |
| 8 | 장식이 gameplay selection/navigation 가독성을 방해하지 않는가. | 사용자 판단 대기 | `visual_acceptance_building_placement.png` (ghost/radius 가독), `visual_acceptance_lumberyard_quarry.png` (nav/작업 공간) |
| 9 | 3D 전환 이후 계속 기능 개발할 동기가 생길 정도의 화면이 나오는가. | 사용자 판단 대기 | 전체 7컷 |

사용자 판단 방법: 위 표의 스크린샷을 확인하고 각 항목에 만족/불만을 기록한다.
불만 판정이 나오면 해당 항목을 FIX 사유로 큐에 반영한다(예: 5번은 VIS-002
완료 후 재판단이 자연스럽다).
