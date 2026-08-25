# Quaternius Asset Stack — Source / License Record (TASK-3D-VIS-001-1)

메인 아트 생태계는 Quaternius로 통일한다(3D Asset Stack LOCK).
이 문서는 핵심 7개 팩의 공식 배포처, 다운로드 일시, 라이선스, 그리고
프로젝트 내 반입 경로를 기록한다.

## 공통 라이선스

- 전부 **CC0 1.0 Universal (Public Domain Dedication)**
  https://creativecommons.org/publicdomain/zero/1.0/
- 개인 / 교육 / 상업 이용 전부 허용, 귀속 표기 불요.
- 각 팩 zip 안에 동봉된 원문 사본을 `license/` 폴더에 함께 보존한다.
- 출처: Quaternius 공식 사이트(https://quaternius.com) 및 공식 itch.io 페이지.
  본 프로젝트는 itch.io 공식 배포본(`https://quaternius.itch.io/<slug>`)을 사용했다.
- 재다운로드/재구축은 `tools/download_quaternius_packs.ps1` 하나로 수행된다.

## 팩별 사용 가능 여부 (2026-08-25 확인)

| # | 팩 | 공식 배포처 | 형식 | 라이선스 | 사용 가능 |
|---|----|------------|------|----------|-----------|
| 1 | Medieval Village MegaKit | https://quaternius.itch.io/medieval-village-megakit | FBX/OBJ/glTF | CC0 | YES (glTF) |
| 2 | Stylized Nature MegaKit | https://quaternius.itch.io/stylized-nature-megakit | FBX/OBJ/glTF | CC0 | YES (glTF) |
| 3 | Fantasy Props MegaKit | https://quaternius.itch.io/fantasy-props-megakit | FBX/OBJ/glTF | CC0 | YES (glTF) |
| 4 | Universal Base Characters | https://quaternius.itch.io/universal-base-characters | FBX/glTF | CC0 | YES (glTF, Godot - UE 폴더) |
| 5 | Modular Character Outfits - Fantasy | https://quaternius.itch.io/modular-character-outfits-fantasy | FBX/glTF | CC0 | YES (glTF, "glTF (Godot-Unreal)" 폴더) |
| 6 | Universal Animation Library | https://quaternius.itch.io/universal-animation-library | FBX/GLB | CC0 | YES (GLB, Unreal-Godot 폴더) |
| 7 | Universal Animation Library 2 | https://quaternius.itch.io/universal-animation-library-2 | FBX/GLB | CC0 | YES (GLB, Unreal-Godot 폴더) |

참고:
- 4번과 5번은 "Name your own price"(무료 진입 가능)라서 다운로드에
  itch.io purchase 경유 CSRF 흐름이 필요하다. 스크립트가 자동 처리한다.
- MegaKit류의 무료 Standard판은 유료 Source판 대비 모델의 일부(60~70%)만
  포함한다. 현재 프로토타입 범위에서는 Standard판으로 충분하다.

## 저장소 반입 구조

```
assets/third_party/quaternius/
├── README.md            <- 이 문서 (커밋)
├── license/             <- 팩 동봉 라이선스 원문 사본 (커밋)
├── models/              <- runtime catalog가 노출하는 curated GLTF/GLB (커밋)
│   ├── medieval-village-megakit/
│   ├── stylized-nature-megakit/
│   ├── fantasy-props-megakit/
│   ├── universal-base-characters/
│   ├── modular-character-outfits-fantasy/
│   ├── universal-animation-library/
│   └── universal-animation-library-2/
└── _source/             <- 원본 zip + 전체 추출본 (gitignore + .gdignore)
    ├── zips/*.zip
    └── extracted/<pack>/...
```

규칙:

- `models/`의 파일만 Godot import 대상이고, runtime catalog
  (`scripts/visual_asset_catalog_3d.gd`)는 여기 있는 에셋만 노출한다.
- 기능 Scene이 `_source/` 원본이나 `models/` 파일 경로를 직접 참조하지
  않는다. 반드시 catalog 키(path) 조회를 거친다.
- `models/`에 새 모델을 추가할 때는 curated 목록을 스크립트에 추가한 뒤
  재실행해서 의존성(.bin/texture) 누락이 없음을 스크립트 검증으로 확인한다.

## Import 시 발견된 원본 팩 결함 (수정하지 않고 기록만 함)

1. Universal Base Characters `Superhero_*_FullBody.gltf`가 존재하지 않는
   `T_Eye_Normal_png.png` / `T_Hair_*_Normal_png.png`를 참조한다.
   실제 파일명은 `T_Eye_Normal.png` / `T_Hair_1_Normal.png`다.
   -> 반입 스크립트가 참조된 이름 그대로 파일을 복사하는 alias 치환으로
   해결하며, `.gltf` 원문은 수정하지 않는다.
2. Fantasy Props / Modular Outfits의 `Normals-UnrealEngine/` 변형 노멀맵은
   Godot(glTF 규약)과 Y 방향이 달라 반입에서 제외하고, glTF 표준 변형을
   사용한다.
