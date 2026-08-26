# TASK-3D-VIS-001-2 Visual Catalog / Scale Convention 결과 리포트

> 실행일: 2026-08-25. 엔진: Godot 4.7.1 stable (headless).
> 반입 확장: `tools/download_quaternius_packs.ps1`(기존 스크립트 재사용).
> 회귀 테스트: `tests/task3dvis0012_test.gd` (전부 PASS).

---

## 1. 산출물 요약

| 파일 | 변경 | 내용 |
|------|------|------|
| `scripts/visual_asset_catalog_3d.gd` | 확장 | `SELECTIONS`(role → variation 선택 카탈로그), `ANIMATION_SETS`(action → 애니메이션 후보), `SCALE_CONVENTION`(월드 스케일 규약), 조회 API 추가. ENTRIES에 `tool/chopping_log` 1키 추가(84키) |
| `tools/download_quaternius_packs.ps1` | 확장 | fantasy-props curated 목록에 `Anvil_Log.gltf` 추가(zip 존재 시 다운로드/추출 생략 확인) |
| `assets/third_party/quaternius/models/fantasy-props-megakit/Anvil_Log.{gltf,bin}` | 신규 | Log/Wood pile 카테고리 유일 후보(반입 절차로 추가, CC0) |
| `tests/task3dvis0012_test.gd` | 신규 | role 커버리지/키 무결성/API 안전 실패/scale 정합성/animation 실재성 회귀 |
| `tests/task3dvis0011_test.gd` | 상수 1개 갱신 | `EXPECTED_KEY_COUNT` 83→84. catalog 확장 절차(VIS-001-1 리포트 §4가 정의)에 따른 의도적 증가 반영이며, 기타 assertion은 무수정 |
| `test_results/task3dvis0012_{probe,test_run}.txt` | 신규 | UAL 애니메이션 이름 계측 + 회귀 실행 로그 |
| 본 문서 | 신규 | 선택 카탈로그 + scale convention 기록 |

---

## 2. Visual Catalog (role → variation)

Visual Agent는 파일 검색 없이 아래 role 조회만으로 모델을 고른다.
조회 API: `has_role / roles / role_label / variation_ids_for_role /
candidate_parts(role, id) / candidate_keys_for_role(role) / candidate_scale_hint(role, id)`.

| role | 태스크 최소 카테고리 | variation (후보 수) |
|------|----------------------|---------------------|
| `house_building` | House / Village Building | plaster_gable, brick_gable (조립 팔레트) |
| `wall_segment` | Wall / Gate | wall_plaster_straight, wall_brick_straight, fence_interior |
| `gate` | Wall / Gate | plaster, brick (door-wall + door 조합) |
| `workplace_lumberyard` | Lumberyard visual candidates | stump_station, storage_corner, cart_loading |
| `workplace_quarry` | Quarry visual candidates | deposit_outcrop, miner_station |
| `tavern_inn_keep` | Tavern / Inn / Keep | tavern, inn, keep (CoreBuilding core_type 매핑) |
| `tree` | Tree variants | common_a, common_b, pine_a, pine_b, dead (5) |
| `rock` | Rock variants | medium_a/b/c (3) |
| `vegetation` | Grass / Bush / Flower | grass_short/tall, bush_plain/flowers, flower_group (5) |
| `container_cart` | Crate / Barrel / Cart | barrel, crate, cart(wagon) |
| `log_pile` | Log / Wood pile | chopping_log (팩에 변형 부재 — 기록된 예외) |
| `stone_pile` | Stone pile | pile_single(scaled), pile_cluster(3-rock cluster) |
| `tool_gather` | Axe / Pickaxe | axe, pickaxe (hand attach hint 0.85) |
| `market_props` | Market / Work props | stall, stall_cart, crate_apple, crate_carrot, coin_pile (5) |
| `human_base` | Base Human | male, female (native scale LOCK) |
| `outfit_worker` | Worker outfit | peasant_male, peasant_female, peasant_male_modular |
| `outfit_mercenary` | Mercenary outfit | ranger_male, ranger_male_modular |
| `weapon` | Weapons | sword_bronze (bronze tier 통일 — 기록된 예외) |

- variation은 단일 모델(`key`) 또는 조립 팔레트(`parts`)다. parts의 실제 배치/
  조립은 wiring 태스크(TASK-3D-VIS-002-x) 소유이고 catalog는 palette만 확정한다.
- 일부러 ENTRIES 전체를 소비하지 않는다: 84키 중 58키만 선택 레이어가 참조하고
  26키는 예비분(테스트가 고정). mushroom, flower_group_3, dead_2 등은 미선택.
- top-down 실루엣 판단 기준: canopy/roof 같은 지면 투영 면적이 큰 모델 우선,
  high-detail 소품(책/식기류 등)은 애초에 반입하지 않았다.

## 3. Animation Map (ANIMATION_SETS)

UAL 라이브러리 GLB 내부의 실제 AnimationPlayer 이름을 계측
(`task3dvis0012_probe.txt`)해 gameplay action에 매핑했다. first = primary.

| action | 후보 (library/name) |
|--------|---------------------|
| idle | ual1 Idle · ual1 Idle_Torch |
| walk | ual1 Walk · ual2 Walk_Carry · ual1 Jog_Fwd |
| work | ual2 **TreeChopping** · ual2 Farm_Harvest · ual2 Farm_Watering · ual1 Fixing_Kneeling |
| combat | ual1 Sword_Attack · ual2 Melee_Hook · ual2 Sword_Regular_A |
| hit | ual1 Hit_Chest · ual1 Hit_Head · ual2 Hit_Knockback |
| death | ual1 Death01 |

비고: 채굴 전용 모션이 라이브러리에 없어 work는 TreeChopping이 괭이질 대용이다.
VIS-001-4에서 공용 skeleton retarget으로 재생한다.

## 4. World Scale Convention (SCALE_CONVENTION)

단일 소스는 catalog 스크립트 상수이며, 테스트가 WorldCoords3D 상수와 실측 AABB와
대조한다. 요지:

- 단위: 1 논리 px = 0.125 unit(`WorldCoords3D.PX_TO_UNIT`), grid 1칸 = 2.0 unit,
  ground Y = 0 고정. **uniform scale만 허용**(월드 비율 불변 LOCK).
- humanoid: native 실물 스케일(측정 1.78~1.82) — base/outfit 무보정 사용.
  outfit 파츠는 캐릭터 origin 기준 착용 좌표라 parent만 하면 된다.
- 건물: 벽 모듈 2.0×3.12×0.41 = grid 1칸 폭. floor 2×2. roof_wooden_2x1은
  모듈당 스트립, roof_roundtiles_6x6은 ~8×8 지붕(tavern/inn/keep급).
- tree: 원판 높이 7.0~11.5 unit은 벽(3.12)/집(~5.5) 대비 과대 → Visual slot에서
  uniform scale_hint 0.45~0.65 적용해 3.0~6.0 밴드로 맞춘다. gameplay
  footprint(TrunkCollision r=0.75 등)와 분리(RES-001-2 계약 유지).
- 지면 오브젝트 origin ≈ 0(나무 뿌리 flare -0.34까지 허용). 예외: bld/vine_1.
- organic prop(tree/rock/vegetation/pile)은 yaw 자유, 건물 모듈은 grid snap.
- tool/weapon hand attach 권장 배율 0.85(바닥 설치 시 native).

## 5. 검증 결과

- `tests/task3dvis0012_test.gd`: **PASS** (role 커버리지 17카테고리, 키 무결성,
  안전 실패, scale 실측 대조, animation 실재성, 예비분 유지).
  로그: `test_results/task3dvis0012_test_run.txt`.
- `tests/task3dvis0011_test.gd` 재실행: **PASS** (83→84 핀 갱신만 반영).
  로그: `test_results/task3dvis0011_rerun_vis0012.txt`.
- `tests/smoke_test.gd`: **PASS** (`test_results/smoke_test_rerun_vis0012.txt`).
- 신규 반입분 Anvil_Log import error/warning 0건, AABB
  0.93×1.07×0.82, origin 접지 확인(probe txt).

## 6. 남은 HUMAN_CHECK

- 없음(본 태스크는 데이터/문서 계약). 미감 판단은 VIS-001-3/-5 screenshot
  HUMAN_CHECK와 wiring(VIS-002)에서 scale_hint 최종 조정으로 이관된다.
