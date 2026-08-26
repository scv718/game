# TASK-3D-VIS-001-4 Character / Outfit / Animation Prototype 결과 리포트

> 실행일: 2026-08-26. 엔진: Godot 4.7.1 stable.
> 회귀 테스트: `tests/task3dvis0014_test.gd` (130 assertions PASS).
> 스크린샷: `test_results/character_prototype_{day,night}.png`.

---

## 1. 산출물 요약

| 파일 | 변경 | 내용 |
|------|------|------|
| `scripts/character_rig_3d.gd` | 신규 | CharacterRig3D. body/outfit 인스턴스화 + 공용 UAL 애니메이션 장착 + hand_r tool attach. `play_action()` 단일 진입점, AnimationTree 없음 |
| `scenes/character_prototype_3d.tscn` | 신규 | 요구 조합 4 리그 라인업(base male idle / worker peasant male+axe work / worker peasant female walk / mercenary ranger+sword combat) |
| `scripts/visual_asset_catalog_3d.gd` | 확장 | `attachment_scale_hint_for_key()` 역방향 조회 API 1개 추가(ENTRIES/SELECTIONS 데이터 무수정, 키 수 불변) |
| `tools/capture_character_prototype_3d.gd` | 신규 | 라인업 DAY/NIGHT 스크린샷 캡처 도구 |
| `tests/task3dvis0014_test.gd` | 신규 | 구조/tool/catalog 계약/공용 리그 호환/재생/재사용/방향전환/cleanup 회귀 |
| `test_results/task3dvis0014_test_run.txt` 외 rerun 4종 | 신규 | 본 태스크 + 회귀 실행 로그 |
| 본 문서, `auto_dev/INTEGRATION_NOTE_VIS.md` | 신규/확장 | 실측 기록 + 후속 태스크(WRK/CMB/VIS-002) 소비 계약 |

## 2. 공용 skeleton/animation 호환 실측 (완료조건의 데이터 근거)

probe(`_probe_char_anim`, 종료 후 제거)로 7개 skeleton의 본 이름 집합을 대조했다:

| skeleton | 본 수 | 기준(male_base 65본) 대조 |
|----------|-------|---------------------------|
| Superhero_Male_FullBody (human/male_base) | 65 | 기준 |
| Superhero_Female_FullBody (human/female_base) | 65 | missing 0 / extra 0 |
| Male_Peasant (outfit/male_peasant_full) | 65 | missing 0 / extra 0 |
| Female_Peasant (outfit/female_peasant_full) | 65 | missing 0 / extra 0 |
| Male_Ranger (outfit/male_ranger_full) | 65 | missing 0 / extra 0 |
| UAL1_Standard.glb | 65 | missing 0 / extra 0 |
| UAL2_Standard.glb | 65 | missing 0 / extra 0 |

- 전원이 동일한 65본 리그 + 동일한 `Armature/Skeleton3D` 노드 계층이라, UAL GLB의
  animation track(`Armature/Skeleton3D:pelvis` 형식)이 **경로 재매핑/retarget
  설정 없이** 캐릭터 skeleton에 그대로 해석된다.
- 재생 검증: base male에 UAL1 Walk를 얹었을 때 upperarm_r 골격 각도가 실제로
  변한다(정지 포즈 대비 rad 단위 변화). task3dvis0014_test PLAYBACK phase가
  6 action 전부에 대해 같은 방식(포즈 지문 변화)으로 재확인한다.
- 결론: Worker/Mercenary variant는 **body_key 교체만으로** 공용 애니메이션을
  재사용한다. 본 단위 retarget/BoneMap 리소스는 불필요하다(과도한 선행 구현 금지).

## 3. Animation 설치 방식

- 단일 소스: `VisualAssetCatalog3D.ANIMATION_SETS`(action → {library, name} 후보,
  first = primary). 리그는 후보를 전부 로컬 AnimationLibrary에 설치하고 첫 성공
  후보를 primary로 기록한다. 현재 16클립(idle 2/walk 3/work 4/combat 3/hit 3/
  death 1)이 전부 실제 GLB에 존재함을 테스트가 고정한다.
- UAL GLB 원본 Animation resource는 변형하지 않는다. loop 정책(idle/walk/work =
  LOOP_LINEAR, combat/hit/death = 1회성)은 duplicate한 사본에만 적용하고, 사본은
  static 캐시로 리그 인스턴스 수와 무관하게 1벌만 유지된다.
- AnimationPlayer는 body 인스턴스 직속(`SharedAnimPlayer`)이며 root_node 기본값
  (`..`)으로 track 경로가 해석된다. AnimationTree는 도입하지 않았다(요구사항).
- 재생 API: `play_action(action) -> bool`. 미설치 action은 false — 호출부 상태
  머신은 재생 실패로 멈추지 않는다(VIS-002-2 계약과 동일 방어).

## 4. Tool attach 방식

- `Skeleton3D` 직속 `BoneAttachment3D`(bone = `hand_r`) 1개가 attach point다.
  도구 모델(axe/pickaxe/sword)은 catalog 키로 인스턴스화되며 배율은 catalog의
  hand attach scale_hint(0.85)를 `attachment_scale_hint_for_key()`로 역조회해
  적용한다.
- grip 미세 조정은 `set_tool_grip_transform()`(bone space)으로 wiring 태스크에
  위임한다. 기본값은 "손 위에 세워 든" 자세로, 스크린샷상 axe/sword 모두
  파지가 자연스럽게 읽힌다.
- tool prop은 의도적으로 unskinned rigid mesh다(스킨 대상 아님). 테스트의
  broken rig/skin 검사는 body mesh만 대상으로 한다.

## 5. 검증 결과

- `tests/task3dvis0014_test.gd`: **PASS**(130 assertions, FAIL/ERROR/WARNING
  0건). 로그: `test_results/task3dvis0014_test_run.txt`.
  - STRUCTURE: 4 리그 × (65본 / skinned mesh / 16클립 / humanoid 신장 밴드
    [1.50, 2.10] — 실측 1.82/2.02/1.53/1.87).
  - TOOL_ATTACH: hand_r 유효 본, catalog hint 배율, detach/re-attach 계약.
  - CONTRACT: ANIMATION_SETS 후보 16개 전부 실제 GLB 내 존재.
  - SHARED_COMPAT: 4 리그 본 집합 + action 매핑 완전 일치.
  - PLAYBACK: idle/walk/work/combat/hit/death 전부 골격 실제 가동.
  - REUSE: 4 리그 동시 walk, 독립 가동.
  - FACING: yaw 90° 회전 시 body/mesh 인스턴스 동일, 재시작 없음, CanvasItem 0개.
  - CLEANUP: 재생 중 free 안전.
- 회귀 재실행 PASS: smoke, task3dvis0011(import), task3dvis0012(catalog),
  task3dvis0013(environment). 로그: `test_results/*_rerun_vis0014.txt`.
- 스크린샷(완료조건 화면 증거): `test_results/character_prototype_day.png`,
  `character_prototype_night.png`. DAY에서 idle/작업(도끼)/walk/공격(검)이
  각각 다른 포즈로 동시 재생 중이며, NIGHT에도 실루엣이 읽힌다. 캡처 로그
  ERROR/WARNING 0건(`test_results/character_prototype_capture_run.txt`).
- 방향 전환: 3D mesh + yaw 회전이라 sprite 재생성 개념이 존재하지 않는다.
  테스트가 인스턴스 동일성과 재생 연속으로 고정.

## 6. 요구사항 대응표

| 요구사항 | 결과 |
|----------|------|
| Universal Base Character 1종 이상 | human/male_base(BaseMale 리그) |
| Worker visual variant 2종 이상 | outfit/male_peasant_full + outfit/female_peasant_full |
| Mercenary visual 1종 이상 | outfit/male_ranger_full |
| 공용 skeleton/animation 호환 확인 | 65본 집합 일치 실측 + 4 리그 동시 재생(§2, SHARED_COMPAT) |
| Idle / Walk | UAL1 Idle / Walk 재생 확인 |
| Work 계열 최소 1 | UAL2 TreeChopping(농경/채굴 대용 — catalog 비고 유지) |
| Attack | UAL1 Sword_Attack |
| Hit/Death 중 최소 1 | 둘 다 설치·재생 확인(Hit_Chest, Death01) |
| tool attachment point | hand_r BoneAttachment3D + catalog scale hint |
| AnimationTree 과도한 state graph 금지 | AnimationTree 미도입, play_action 단일 진입점 |

## 7. 남은 HUMAN_CHECK

- tool grip 미세 자세(도끼/검의 손안 각도)는 wiring(VIS-002) 단계
  `set_tool_grip_transform()` 최종 조정 대상이다. 현재 기본값도 스크린샷상
  자연스럽게 읽힌다.
- work action이 TreeChopping 대용이라는 catalog 비고(채굴 전용 모션 부재)는
  유지된다. 판단 자료: 위 스크린샷 2장.
