# TASK-3D-VIS-001-1 Asset Acquire / License / Import 결과 리포트

> 실행일: 2026-08-25. 엔진: Godot 4.7.1 stable (headless import).
> 반입/검증 자동화: `tools/download_quaternius_packs.ps1` (단일 스크립트로
> 다운로드 → 추출 → curated 복사 → 의존성 검증까지 재현 가능).
> 회귀 테스트: `tests/task3dvis0011_test.gd` (137 assertions PASS).

---

## 1. 핵심 7개 팩 사용 가능 여부

전부 Quaternius 공식 배포처(itch.io 공식 페이지)에서 확보했고, 전부
**CC0 1.0**(영리 사용/재배포 허용, 귀속 불요)으로 확인됐다.

| # | 팩 | 공식 배포처 | 제공 형식 | 반입 형식 | 상태 |
|---|----|------------|-----------|-----------|------|
| 1 | Medieval Village MegaKit | quaternius.itch.io/medieval-village-megakit | FBX/OBJ/glTF | glTF | OK |
| 2 | Stylized Nature MegaKit | quaternius.itch.io/stylized-nature-megakit | FBX/OBJ/glTF | glTF | OK |
| 3 | Fantasy Props MegaKit | quaternius.itch.io/fantasy-props-megakit | FBX/OBJ/glTF | glTF | OK |
| 4 | Universal Base Characters | quaternius.itch.io/universal-base-characters | FBX/glTF | glTF(Godot - UE 폴더) | OK |
| 5 | Modular Character Outfits - Fantasy | quaternius.itch.io/modular-character-outfits-fantasy | FBX/glTF | glTF("glTF (Godot-Unreal)" 폴더) | OK |
| 6 | Universal Animation Library 1 | quaternius.itch.io/universal-animation-library | FBX/GLB | GLB(Unreal-Godot 폴더) | OK |
| 7 | Universal Animation Library 2 | quaternius.itch.io/universal-animation-library-2 | FBX/GLB | GLB(Unreal-Godot 폴더) | OK |

- 라이선스 원문 사본: 각 zip 동봉 License txt를
  `assets/third_party/quaternius/license/<slug>_License*.txt`로 보존.
  출처/구조/규칙 총괄 문서: `assets/third_party/quaternius/README.md`.
- MegaKit류 무료 Standard판은 유료 Source판(엔지니어링 프로젝트 포함, .blend,
  커스텀 셰이더)과 달리 모델의 60~70%만 담고 있다. 현재 범위에서는 충분하며
  부족분은 큐에 기록 후 필요 시 구매 판단 대상이다.
- 4/5번 팩은 Name-your-own-price라 itch.io purchase CSRF 흐름이 필요했다.
  스크립트가 이 경로를 자동 처리한다(재다운로드 가능).

## 2. Import 실행 기록

- 명령: `Godot_v4.7.1-stable_win64.exe --headless --path <project> --import`
- 로그: `test_results/task3dvis0011_import_run.txt`
- 결과: **import ERROR/WARNING 0건**. `.gltf/.glb/.png` 149개 전부
  `.import` 생성 완료(누락 0건을 테스트가 재확인).
- 계측 로그: `test_results/task3dvis0011_probe.txt` (catalog 83종 전량의
  mesh/surface/재질/AABB/애니메이션 수치).
- 렌더 증거: `test_results/quaternius_import_preview.png`(전경) /
  `quaternius_import_preview_zoom.png`(근접). catalog 키로 배치한 대표
  모델(tree/pine/rock/bush/flower/wall+window+door+chimney/barrel/crate/
  anvil/human base/ranger outfit)이 텍스처·재질과 함께 정상 렌더된다.
  캡처 도구: `tools/capture_quaternius_preview.gd`(임시 라이트/환경 자체
  구성, world scene 무수정).
- 회귀: `tests/task3dvis0011_test.gd` → `TASK3DVIS0011_RESULT=PASS`
  (137 PASS). 기존 smoke/task3d0012/task3dres0013 재실행 PASS 확인.

## 3. 원본 팩 결함 발견 기록 (수정 없이 기록 + 반입 단계 치환)

큐 운영 규칙 27(import 오류 은폐 금지)에 따라 아래 결함을 숨기지 않고
기록한다. 어떤 `.gltf` 원문도 수정하지 않았다.

| 결함 | 내용 | 조치 |
|------|------|------|
| UBC 헤어스타일 "Origin at 0" GLTF 버퍼 불일치 | `Hair_SimpleParted.gltf`가 buffer byteLength=32032를 선언하지만 실제 .bin은 51332바이트 → Godot importer가 ERR_PARSE_ERROR로 거절(로그: `byteLength < buffer_data.size()`) | 같은 모델의 byteLength가 정확한 **"Rigged to Head Bone/glTF (Godot -Unreal)" 변형**으로 교체 반입. head bone 리깅이라 attach 용도로도 더 적합 |
| UBC BaseCharacter 텍스처 참조 오탈자 | `Superhero_*_FullBody.gltf`가 존재하지 않는 `T_Eye_Normal_png.png`, `T_Hair_*_Normal_png.png`를 참조(실제 파일은 `_png` 접미사 없음) | 반입 스크립트 alias 치환: 참조된 이름 그대로 파일을 복사해 glTF URI가 유효해지게 함(원문 무수정). 테스트가 전 모델 재질 해석을 재검증 |
| Unreal 전용 노멀맵 변형 | Fantasy Props/Outfits/Medieval Village의 `Normals-UnrealEngine/` 노멀맵은 Y 방향이 Godot(glTF) 규약과 반대 | 해당 변형은 인덱스에서 제외하고 glTF 표준/Godot 지정 변형 우선 사용 |

## 4. Runtime Catalog (필요한 asset만 노출)

- 단일 소스: `scripts/visual_asset_catalog_3d.gd`(VisualAssetCatalog3D,
  autoload 아님 - Foundation/Integrations 전용 영역 불침벌).
- 9개 카테고리, **83개 키**만 노출: trees(9)/rocks(3)/vegetation(8)/
  building(20)/props(14)/tools(6)/human(3)/outfit(17)/animation(3).
- 기능 Scene은 파일 경로를 직접 참조하지 않고 catalog 키만 조회한다.
  미등록 키는 빈 경로/null 반환 + push_error 기록(오류 은폐 금지 준수).
- 원본 팩 전체(`_source/`)는 `.gdignore` + gitignore로 이중 격리되어
  runtime에 노출되지 않는다(테스트 ISOLATION phase가 ResourceLoader
  관점에서 검증).
- VIS-001-2 catalog 확장 시: 스크립트의 curated 목록에 경로를 추가하고
  반입 스크립트를 재실행하면 된다. 의존성 누락은 스크립트 검증 단계에서
  실패한다.

## 5. Scale / Orientation 기준 (측정 근거)

전체 수치는 `test_results/task3dvis0011_probe.txt` 참조. 요지:

- **Y-up, origin=지면 접지점**: wall/floor/chimney/barrel/anvil/tree/rock 등
  지면 오브젝트 AABB min.y ≈ 0(-0.34 이내, 나무 뿌리 flare 포함). 예외는
  처마 장식용 `bld/vine_1`(origin 위 매달림, 설계 의도대로 문서화).
- **Modular grid**: Medieval Village 벽/바닥은 정확히 2.0m 모듈
  (wall 2.0×3.12×0.41, floor 2×2 XZ 평면). WorldCoords3D.GRID_CELL_UNITS
  = 2.0 unit와 정수 호환 → 건물 배치 grid snap과 충돌 없음.
- **Humanoid 실물 스케일**: male/female base 신장 1.82/1.78, mannequin 1.81.
  outfit 파츠는 캐릭터 origin 기준으로 이미 착용 위치에 배치된 좌표
  (예: arms y≈1.37, hood y≈1.53) → base 캐릭터에 그대로 parent 하면 됨.
- **Tree 스케일 주의**: Nature MegaKit 나무는 원판 기준 7.0~11.5 unit로
  humanoid 대비 크다. RES-001-2가 남긴 Visual slot 계약(visual scale variation
  과 gameplay footprint 분리, TrunkCollision r=0.75 불변) 안에서
  VIS-002-1 wiring 시 slot 쪽 uniform scale로 최종 조정할 것.
- glTF(Y-up 오른손) → Godot 추가 회전 보정 불요. forward 축 별도 지정 없음.

## 6. 애니메이션 / 리그 호환성

- `anim/ual1_standard`: 43 anims(Idle, Death01, Hit_Chest, Fixing_Kneeling 등
  로코모션+전투+작업), Skeleton 보유.
- `anim/ual2_standard`: 43 anims(Farm_Harvest, Farm_PlantSeed, Chest_Open,
  Hit_Knockback 등 농사/상호작용 특화), Skeleton 보유.
- `anim/mannequin_female`: 리깅된 여성 마네킹(애니메이션 없음, retarget
  프리뷰용).
- Universal Base Characters / Outfits 파츠 전원 Skeleton3D 보유 →
  VIS-001-4에서 공용 skeleton 재사용 가능. chest_wood(열림 anim 4개),
  female_peasant_body(anim 1개)처럼 소품에 애니메이션이 묻어 있는 것도 확인.

## 7. 저장소 반입 범위

| 위치 | 커밋 | 내용 |
|------|------|------|
| `assets/third_party/quaternius/models/` (229MB) | O | curated GLTF/GLB + 필수 bin/texture. CC0라 재배포 가능 |
| `assets/third_party/quaternius/license/` | O | 팩 동봉 라이선스 원문 7종 |
| `assets/third_party/quaternius/README.md` | O | 출처/라이선스/반입 구조 문서 |
| `assets/third_party/quaternius/_source/` | X | 원본 zip+추출본(.gdignore+gitignore). 스크립트로 재구축 |
| `tools/download_quaternius_packs.ps1` | O | 재현 스크립트 |
| `tools/capture_quaternius_preview.gd` | O | 반입 에셋 렌더 프리뷰 캡처 |
| `scripts/visual_asset_catalog_3d.gd` | O | runtime catalog |
| `tests/task3dvis0011_test.gd` | O | 회귀 테스트 |
| `test_results/task3dvis0011_*.{txt,png}` | O | import 로그/계측/프리뷰 |

## 8. 남은 HUMAN_CHECK

- 없음(본 태스크는 acquire/import 검증 단계). 미감 판단은 VIS-001-3/-5의
  screenshot HUMAN_CHECK로 이관된다.
