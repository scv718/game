# TASK-049-1 Asset / License Audit + Audio Bus

> 상태: IMPLEMENT 완료 (TASK-049 Audio/VFX의 기반 태스크)
> 엔진: Godot 4.7.1 stable. 실행: `Godot_v4.7.1-stable_win64_console.exe --headless`
> 회귀: `tests/task0491_test.gd` (`TASK0491_RESULT=PASS`)

---

## 1. 기존 audio/vfx asset 확인 (Audit)

프로젝트 저장소(`git ls-files`) 기준 오디오/사운드 파일(`.wav/.ogg/.mp3/.flac`)
은 **0건**이다. 기존 BGM/SFX/Ambient 에셋은 없으며, `scripts/` 전역에서
`AudioStreamPlayer`/`AudioServer` 사용도 **0건**으로 확인됐다.

VFX(시각 효과) 관련 기존 에셋은 별도 오디오 파일이 아니라 Quaternius 3D 모델/
재질이며, 반입·라이선스 기록은 이미 `auto_dev/VIS_ASSET_IMPORT_REPORT.md`에
있고(전부 CC0 1.0), 정리된 런타임 카탈로그는 `scripts/visual_asset_catalog_3d.gd`
다. 이 태스크는 그 기록을 다시 쓰지 않고 승계한다.

결론: **오디오는 신규 도메인**이다. 기존 에셋을 재사용하거나 위반할 대상이 없어
이번 태스크는 코드 기반(Bus + playback foundation)만 추가한다.

## 2. 신규 asset / 리소스 출처·라이선스 기록

이 태스크에서 추가하는 것은 **에셋 파일이 아닌 프로젝트 리소스/코드**다.

| 항목 | 종류 | 출처 | 라이선스/근거 |
|------|------|------|---------------|
| `audio/default_bus_layout.tres` | Godot AudioBusLayout(코드 리소스) | 자체 작성 | GPL 게임 원본 규칙 없음 — Godot 엔진 프로젝트 설정 리소스. 외부 컨텐츠 미포함 |
| `scripts/audio_manager.gd` | Godot autoload(코드) | 자체 작성 | 자체 작성 |
| `user://audio_settings.cfg` | 런타임 볼륨 설정 저장 | 자체 생성(런타임) | 사용자 기기 로컬 파일 |

정책: 이후 TASK-049-2/3에서 실제 사운드/VFX 에셋을 들여올 때는 아래 규칙을
따른다(POST-3D 공통 규칙 18과 동일 방향).

1. 출처 불명/라이선스 미확인 음원·모델·텍스처를 임의 추가하지 않는다.
2. 신규 에셋을 반입할 때 이 문서의 표에 출처(배포 URL), 라이선스, 반입 형식,
   정제 날짜를 추가한다.
3. CC0(Quaternius 계열) 또는 동등 허용 라이선스 우선. 귀속 요구 라이선스는
   `assets/third_party/` 동봉 라이선스 원문 사본을 함께 보존한다.
4. AI가 사운드를 "생성"해 에셋으로 첨부하는 것은 출처를 명시할 수 없으므로
   기본적으로 금지하고, 반드시 필요한 경우 이 문서에 생성 도구/파라미터/재현
   방법을 기록한다.

## 3. Audio Bus: Master / Music / SFX / Ambient / UI

- 버스 레이아웃 매니페스트: `audio/default_bus_layout.tres`
  (`Master`(기본) / `Music` / `SFX` / `Ambient` / `UI` 순서).
- project 설정 `audio/default_bus_layout`에 등록 → 엔진 startup 시 자동 적용.
- `scripts/audio_manager.gd` (autoload `AudioManager`)가 startup 시
  idempotent하게 버스 존재를 보장(`_ensure_buses()`). 누락 버스만 복구한다.

### 버스 배정(후속 태스크 사용 계약)

| 버스 | 용도 |
|------|------|
| Music | BGM(DAY/NIGHT 테마) |
| SFX | 이펙트(전투/Worker/Gate/Potion/배치 등) |
| Ambient | 주변음(바람/불/물 등) |
| UI | UI 클릭/경고음 |

## 4. Volume setting hook

`AudioManager`가 제공하는 최소 설정 API(설정 화면이 호출할 진입점).

- `set_volume_db(bus_name, db)` / `get_volume_db(bus_name)` — -80..0 db, clamp.
- `set_volume_linear(bus_name, 0..1)` / `get_volume_linear(bus_name)` — UI slider용.
- `set_volumes(dict)` / `get_volumes()` — 일괄 설정/조회.
- `reset_volumes()` — 기본값(0 db) 복원.
- `save_volumes()` / `load_volumes()` — `user://audio_settings.cfg`(ConfigFile)
  최소 persist/restore. `_ready()`에서 자동 restore.
- `signal volume_changed(bus_name, volume_db)` — 설정 반영 통지.

TASK-046 Save/Load가 확정되면 이 ConfigFile을 게임 Save에 흡수하는 것은 허용된
후속 작업이다. `DESIGN_TUNING`: 기본 볼륨/민감도 수치는 확정 밸런스가 아니므로
`DEFAULT_VOLUME_DB` 상수로 조정 가능하다.

## 5. Playback foundation

- `play_on_bus(bus_name, stream, volume_db, pitch_scale, one_shot)` — 단일 진입점.
- `play_sfx()`, `play_ui()` — one-shot(완료 시 자동 해제) 재생.
- `play_music()`, `play_ambient()` — 유지형 재생(`stop_loops()`/`stop_all()`로 해제).
- `stop_all()` / `stop_one_shots()` — 이벤트 정리.
- 미지 버스/`null` 스트림은 Master 폴백 + `push_error`로 오류를 숨기지 않는다.
- **per-frame playback 금지**: 이 계층은 폴링 없이 이벤트(호출)로만 재생한다.
  반복 이벤트의 throttling은 TASK-049-2의 호출 정책에서 다룬다.

## 6. 회귀 결과

- `tests/task0491_test.gd` headless 실행 `TASK0491_RESULT=PASS`.
  버스 존재·순서, layout 적용, volume hook(db/linear/일괄/clamp/reset/persist),
  one-shot 자동 해제, 유지형 해제, 문서 존재를 검증한다.
- 기존 회귀(smoke) 재실행 PASS.

## 7. 남은 HUMAN_CHECK

- 실제 청취(볼륨 균형/버스 분리감)는 오디오 에셋이 들어온 TASK-049-2 이후
  사람 청취로 확인한다.