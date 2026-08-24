# AI Task Queue

> 기존 2D Top-down 프로젝트를 **Stylized Top-down 3D**로 전환하는 실행 큐.
>
> 핵심 목표:
> 현재 게임의 기능/게임 규칙을 보존한 상태에서 2D 표현 계층을 실제 3D 월드로 교체하고,
> 고정 사선 Top-down Camera + Pan + Zoom 기반의 관리/전술 화면으로 완성한다.
>
> 이번 전환의 최우선 성공 기준은 **기능 추가량이 아니라, 기존 기능이 3D에서 정상 동작하면서 화면 품질이 명확히 개선되는 것**이다.
>
> 상태: `QUEUED` / `IMPLEMENT` / `REVIEW` / `FIX` / `DONE` / `NEEDS_DESIGN`

---

# 공통 실행 규칙

> 1. `##` = 챕터/컨테이너, `###` = 실제 실행 태스크.
>
> 2. 기본 자동화는 파일 순서대로 처리한다.
>
> 3. 단, 이 큐에서 `PARALLEL-WAVE-*`로 명시된 태스크는 **TASK-3D-001 Foundation 완료 후 서로 다른 AI 세션에서 병렬 수행 가능**하다.
>
> 4. 각 태스크 시작 시 `GAME_DESIGN.md`, `DEVELOPMENT_STATUS.md`의 현재 태스크 관련 섹션과 실제 Scene/Script/API 구조를 확인한다.
>
> 5. 문서보다 현재 코드가 더 최신일 수 있으므로 구현 전 실제 코드를 우선 확인한다.
>
> 6. 기존 게임 규칙/데이터 모델/상태 머신을 3D라는 이유만으로 임의 재설계하지 않는다.
>
> 7. 2D → 3D 전환에 필요한 최소 변경만 수행하며 범위 밖 신규 기능을 임의 구현하지 않는다.
>
> 8. 신규 기능 병렬 개발은 `TASK-3D-001` 완료 이후 **3D Foundation을 기준으로만** 허용한다. 신규 2D 기능 구현은 금지한다.
>
> 9. 병렬 세션은 자신에게 배정된 도메인 파일만 수정하고, 다른 병렬 세션의 소유 파일을 임의 수정하지 않는다.
>
> 10. `project.godot`, 최종 Main World Scene, 공통 Autoload 등록, 공통 InputMap, 전역 Collision/Layer 정의 등 공유 진입점은 Foundation 또는 Integration 태스크만 수정한다.
>
> 11. 병렬 태스크에서 공유 파일 변경이 불가피하면 직접 수정하지 말고 `INTEGRATION_NOTE`에 필요한 변경을 기록한다.
>
> 12. 기존 2D 구현은 3D 대체 기능이 검증되기 전까지 reference 용도로 유지한다. 기능별 3D 전환 완료 전 대량 삭제 금지.
>
> 13. 기존 정상 동작 시스템을 단순히 코드가 오래됐다는 이유로 대규모 리팩터링하지 않는다.
>
> 14. Godot headless 테스트를 실제 실행하고, 실행하지 않은 테스트를 PASS라고 보고하지 않는다.
>
> 15. 3D 렌더링/카메라/미감은 headless 테스트만으로 검증했다고 판단하지 않는다.
>
> 16. 미감/체감/가독성은 `HUMAN_CHECK`에 남기며 코드/자동검증이 정상이라면 DONE 가능하다.
>
> 17. 실제 화면 검증이 필요한 태스크는 최소 1개 이상의 실행 스크린샷 또는 캡처 경로를 결과에 남긴다.
>
> 18. 설계 LOCK과 직접 충돌하거나 기존 기능의 의미를 바꿔야 하는 경우 추측하지 말고 `NEEDS_DESIGN`으로 중단한다.
>
> 19. `git reset --hard`, `git clean -fd`, force push 등 파괴적 Git 명령 금지.
>
> 20. 자동 commit / push 금지.
>
> 21. 기존 사용자 변경사항을 임의 revert하지 않는다.
>
> 22. 임시 진단 파일은 태스크 종료 전 제거한다.
>
> 23. `_diag*`, `_probe*`, `_debug*`, `_temp*` 등 임시 파일이 남지 않았는지 종료 시 확인한다.
>
> 24. 기존 테스트를 PASS시키기 위해 assertion 의미를 약화시키지 않는다.
>
> 25. 요구사항 변경으로 기존 2D 전용 테스트를 수정/대체해야 할 경우 이유를 구현 기록에 남긴다.
>
> 26. freed instance reference / duplicate actor / stale navigation / orphan scene reference가 남지 않아야 한다.
>
> 27. 에셋 import 오류를 숨기지 않는다. missing dependency / broken material / animation mismatch는 실제 실패로 기록한다.
>
> 28. 병렬 세션 완료 시 `변경 파일`, `테스트 결과`, `INTEGRATION_NOTE`, `남은 HUMAN_CHECK`를 반드시 기록한다.
>
> 29. 최종 통합 전 각 병렬 태스크는 독립 Scene 또는 테스트 Scene에서 가능한 범위까지 검증 가능해야 한다.
>
> 30. `CHECKPOINT-3D-MIGRATION`은 3D 전환 검증 지점이며 전체 자동화 종료 지점이 아니다.
>
> 31. `CHECKPOINT-3D-MIGRATION`이 DONE이고 남은 문제가 `HUMAN_CHECK`뿐이면 POST-3D 기능 큐를 계속 진행한다.
>
> 32. 최종 자동화 종료 지점은 파일 마지막의 `OVERNIGHT-STOP-FEATURES`다.

---

# 리뷰 규칙

> 1. 리뷰어 내부 판정과 Queue의 `상태:` 값은 별개다.
>
> 2. 리뷰어 판정은 `LGTM` / `FIX` / `HUMAN_CHECK` 등을 사용할 수 있다.
>
> 3. `상태: REVIEW`는 리뷰 진행 중 정상 상태이며 REVIEW 자체를 FIX 사유로 판단하지 않는다.
>
> 4. 리뷰어는 구현/요구사항/테스트의 실제 문제만 FIX 사유로 제시한다.
>
> 5. 상태 전환은 Supervisor/자동화의 책임이며 리뷰어가 Queue 상태값 자체를 요구사항으로 평가하지 않는다.
>
> 6. 코드와 자동검증이 정상이고 남은 항목이 미감/플레이 감각뿐이면 `HUMAN_CHECK`를 남기고 LGTM 가능하다.
>
> 7. 동일한 잘못된 리뷰 사유를 반복해 무한 FIX loop를 만들지 않는다.
>
> 8. 3D 전환에서 단순히 "2D 노드가 남아 있다"는 사실만으로 FIX하지 않는다. 실제 Runtime 3D 경로에서 사용되는지 확인한다.
>
> 9. 반대로 Runtime 핵심 경로가 2D Actor/Navigation/Collision에 의존하면 전환 미완료로 판단한다.
>
> 10. 시각적 품질은 단순 에셋 존재 여부가 아니라 실제 Camera View에서의 가독성/통일성/HUMAN_CHECK 기준으로 판단한다.

---

# 게임 핵심 규칙 LOCK

> 1. 플레이어 캐릭터는 어떤 상황에서도 직접 전투하지 않는다.
>
> 2. Player에 공격, 무기, 공격 스킬, Damage Dealer 역할을 추가하지 않는다.
>
> 3. 핵심 전투 원칙:
>
> **전투는 자동, 판단은 플레이어가 한다.**
>
> 4. Worker가 반복 노동을 수행한다.
>
> 5. Mercenary가 전투를 수행한다.
>
> 6. Scout / Expedition 계열 외부 탐사는 기존 설계 범위를 유지한다.
>
> 7. 플레이어는 상위 관리 주체이며 직접 필드를 걸어 다니는 Avatar가 아니다.
>
> 8. 기본 조작은 Camera + Mouse 기반 관리 조작이다.
>
> 9. DAY는 경제/건설/고용/생산/탐사 준비 중심.
>
> 10. NIGHT는 자동전투 관찰 + 전술 명령 중심.
>
> 11. DAY/NIGHT 모두 Camera + Mouse 기반이며 가능한 행동과 UI 목적은 구분한다.
>
> 12. 3D 전환은 게임 기획 변경이 아니라 **표현/공간/입력 좌표계의 Migration**이다.

---

# Top-down 3D Direction LOCK

> 1. Runtime World는 실제 3D Node 기반으로 전환한다.
>
> 2. 지면 기준 좌표계:
>
> - `X / Z` = 지면 이동 평면.
> - `Y` = 높이.
>
> 3. Camera는 **사선 Top-down 고정 각도**를 사용한다.
>
> 4. 기본 투영은 `Orthographic Camera3D`.
>
> 5. 플레이 중 자유 Camera Rotation은 구현하지 않는다.
>
> 6. Camera 핵심 조작:
>
> - WASD / 기존 방향 입력 = Camera Pan.
> - Mouse Wheel = Zoom In / Out.
> - Left Click = 3D World Selection / Interaction.
> - Right Click / ESC = 현재 선택 또는 contextual mode 취소.
>
> 7. Camera Pitch/Yaw는 게임 화면 가독성을 위해 고정한다.
>
> 8. 3인칭 Follow Camera / First Person / Free Orbit Camera를 구현하지 않는다.
>
> 9. 건설은 3D 지면(XZ) 위 기존 logical grid 정책을 유지한다.
>
> 10. 2D `Vector2` 월드좌표를 의미 없이 1:1 숫자로 `Vector3`에 복사하지 않는다. 기존 logical grid/world 의미를 보존하는 명확한 변환 규칙을 Foundation에서 확정한다.
>
> 11. `CharacterBody2D`, `Area2D`, `CollisionShape2D`, `NavigationAgent2D` 등 기존 2D Runtime 의존은 각 도메인 전환 태스크에서 3D 대응 구조로 제거한다.
>
> 12. UI `Control` 계층은 2D UI가 정상이며 3D로 바꾸지 않는다.
>
> 13. DAY/NIGHT, HUD, Tactical UI, Roster, Recruitment 등 화면 UI 기능은 기존 동작을 유지한다.
>
> 14. 3D 전환을 이유로 월드 규모/경제 밸런스/전투 밸런스를 임의 변경하지 않는다.
>
> 15. 월드의 WEST/NORTH/EAST/SOUTH 역할과 현재 핵심 지역 의미를 유지한다.

---

# 3D Asset Stack LOCK

> 메인 아트 생태계는 **Quaternius**로 통일한다.
>
> 사용 우선순위:
>
> 1. `Medieval Village MegaKit`
>    - 건물 / 벽 / 지붕 / 문 / 마을 구조.
>
> 2. `Stylized Nature MegaKit`
>    - 나무 / 바위 / 풀 / 꽃 / 덤불 / 자연물.
>
> 3. `Fantasy Props MegaKit`
>    - 상자 / 통 / 도구 / 작업물 / 시장 / 장식 Props.
>
> 4. `Universal Base Characters`
>    - 주민/Worker/Mercenary 공용 Humanoid Base.
>
> 5. `Modular Character Outfits - Fantasy`
>    - 직업/용병 외형 변형.
>
> 6. `Universal Animation Library 1 / 2`
>    - Idle / Walk / Work / Farming / Combat / Hit / Death 등 공용 애니메이션.
>
> 에셋 규칙:
>
> - Quaternius의 실제 배포처와 해당 팩의 라이선스를 다운로드 시 다시 확인한다.
> - 라이선스/출처 정보를 프로젝트 내 문서로 보존한다.
> - Godot import는 `glTF / GLB`를 우선한다.
> - FBX는 GLTF/GLB 사용이 불가능하거나 애니메이션 호환상 명확한 이유가 있을 때만 사용한다.
> - Source가 불분명한 임의 인터넷 모델을 섞지 않는다.
> - 다른 제작자 에셋을 임의 혼합하지 않는다.
> - 기능 Scene은 특정 모델 파일 경로에 과도하게 결합하지 않고 Visual child/resource 계층으로 분리한다.
> - 반복 배치 모델은 rotation / scale / material variation을 제한적으로 사용해 반복감을 줄인다.
> - 모델 자체를 AI가 무리하게 새로 조형하는 것보다 기존 Pack 조립/배치/Material/Lighting을 우선한다.
> - 에셋이 없다는 이유로 게임 규칙을 변경하지 않는다.

---

# 병렬 실행 / 파일 Ownership LOCK

> `TASK-3D-001` 완료 전에는 병렬 3D Migration을 시작하지 않는다.
>
> Foundation 완료 후 다음 컨테이너는 병렬 실행 가능:
>
> - `TASK-3D-RES-001` Resource.
> - `TASK-3D-BLD-001` Building.
> - `TASK-3D-WRK-001` Worker / Navigation.
> - `TASK-3D-CMB-001` Combat / Tactical World.
> - `TASK-3D-VIS-001` Asset / Environment / Visual.
>
> 공통 공유 파일 수정 권한:
>
> - Foundation 단계: `TASK-3D-001`만 허용.
> - Integration 단계: `TASK-3D-INT-001`만 허용.
> - 병렬 태스크는 공유 진입점 수정 대신 `INTEGRATION_NOTE` 기록.
>
> 병렬 작업 디렉터리 예시:
>
> - `world3d/`
> - `systems/resources3d/`
> - `systems/buildings3d/`
> - `systems/workers3d/`
> - `systems/combat3d/`
> - `visual3d/`
>
> 실제 기존 프로젝트 구조가 다르면 억지로 위 경로를 만들지 말고, **현재 코드 구조를 확인한 뒤 충돌이 최소인 대응 경로**를 사용한다.

---

# 신규 기능 병렬 개발 규칙

> `TASK-3D-001` 완료 이후 별도 AI 세션에서 신규 기능 개발을 병렬 진행하는 것은 허용한다.
>
> 단:
>
> 1. 신규 기능은 반드시 3D Foundation의 좌표/Interaction/Navigation/Building/Actor 정책을 따른다.
> 2. 신규 기능을 2D Node 기반으로 먼저 만든 뒤 나중에 재전환하는 방식은 금지한다.
> 3. 3D Migration 병렬 태스크가 소유한 공통 파일을 직접 수정하지 않는다.
> 4. 기존 게임 설계에 없는 신규 기능을 임의로 발명하지 않는다.
> 5. 기능 태스크는 이 Migration Queue와 별도 TASK 범위를 가져야 한다.
> 6. 최종 Integration 시 Migration 회귀를 깨면 기능 쪽이 새 3D 기준에 맞춰 수정한다.

---

## TASK-3D-001 Top-down 3D Foundation

- 상태: QUEUED

- 설명: 모든 병렬 3D Migration이 공통으로 사용할 최소 3D 기반을 먼저 확정한다. 이 태스크 완료 전 Resource/Building/Worker/Combat의 본격 병렬 전환을 시작하지 않는다.

- 핵심:

  - 3D World Root.
  - XZ ground / Y height 좌표 정책.
  - Orthographic Camera3D.
  - Camera Pan / Zoom.
  - Mouse → 3D World Ray.
  - 3D Selection / Interaction 최소 계약.
  - Collision Layer / Mask 공통 정책.
  - Navigation3D 공통 방향.
  - 기존 UI와 3D World 입력 ownership 분리.
  - 기존 logical grid → 3D world 단위 변환 규칙.
  - 병렬 도메인이 사용할 최소 공통 API/Convention.

- 금지:

  - Resource 전체 변환.
  - Building 전체 변환.
  - Worker 전체 변환.
  - Combat 전체 변환.
  - 전체 Asset Dressing.
  - 신규 게임 기능.
  - 기존 게임 시스템 대규모 리팩터링.

### TASK-3D-001-1 Current 2D Runtime Audit / Migration Map

- 상태: DONE
- 피드백: 지적된 2건의 수치 오류가 모두 실측 기반으로 정확히 교정됨 — get_global_mouse_position 9곳(라인 목록까지 #15(b)와 일치), MapLayout Marker2D 35개(관련 4개 행 전부 반영). 코드 무수정 제약도 git diff로 확인.
- 피드백: 산출물 자체는 요구사항을 충족하나, 감사 문서의 수치 근거에 오류 2건 — (1) building_placement.gd get_global_mouse_position 호출 수 "10곳"→실제 9곳(section 0 #4 및 산출물 1 해당 행 수정, #15(b) 라인 목록과 일치시킬 것), (2) world.tscn MapLayout Marker2D "27개"→실제 35개(section 0 #1, 산출물 1-B, 산출물 3 Map/Layout 행 3곳 수정). 두 수치만 교정 후 재검토 없이 완료 처리 가능.
- 피드백: 태스크의 필수 산출물(Migration Map 문서 5개 항목)이 하나도 작성되지 않았음. 제출된 "요약"은 작업 시작 의사 선언일 뿐 구현 결과가 아니며, 완료조건 3항 모두 미충족. 실제 코드 reference 검색을 수행하고 파일 수준 Migration Map 문서를 산출한 후 재검토 요청할 것.

- 설명: 실제 현재 코드에서 2D Runtime 의존성을 추적하고 도메인별 Migration Map을 만든다.

- 확인 대상:

  - Main World Scene.
  - Camera2D / camera controller.
  - Mouse selection / interaction.
  - BuildingPlacement.
  - Resource Node.
  - Worker / Lumberjack / Miner.
  - NavigationRegion2D / NavigationAgent2D / nav rebuild.
  - Wall / Gate collision/navigation.
  - Mercenary / Enemy.
  - Tactical command world reference.
  - World bounds.
  - Spawn / Region / landmark coordinate.
  - Day/Night visual hooks.
  - Death Ledger의 Actor reference 경계.
  - UI가 world position을 사용하는 모든 지점.

- 산출물:

  - 2D 전용 의존 목록.
  - 그대로 유지 가능한 순수 game/data logic 목록.
  - 3D 변환이 필요한 Scene/Script 목록.
  - 공유 파일 목록.
  - 병렬 태스크별 파일 ownership 초안.

- 중요:

  - Audit 단계에서 대량 수정 금지.
  - 문서만 보고 판단하지 말고 실제 reference 검색.
  - 이미 3D 또는 dimension-neutral 구조가 있으면 재작성하지 않는다.

- 완료조건:

  - 2D → 3D Migration 경계가 파일 수준으로 기록됨.
  - 병렬 작업 충돌 위험 파일이 식별됨.
  - 구현 전 reference 누락 없음.

### TASK-3D-001-2 World3D / Coordinate / Collision Foundation

- 상태: DONE
- 피드백: 이전 피드백 2건(mojibake 재작성, exit=1 무응답 백오프 재시도 편입) 모두 해소를 코드·바이트 단위로 확인했고, 47/47 PASS 및 smoke PASS를 리뷰어가 직접 재실행으로 재현함. 요구사항·완료조건·금지 항목 전부 충족, 기존 스타일/운영 규칙(migration map 5, LOCK 12) 준수.
- 피드백: `tests/task3d0012_test.gd`의 한글 주석이 바이트 단위 mojibake로 손상됨(저장소 UTF-8 관례와 불일치, 내용 복구 불가). 주석을 유효 UTF-8 한국어로 재작성 후 재검토 필요. 그 외 요구사항·완료조건·회귀는 실제 headless 실행으로 전부 충족 확인(47/47 PASS, smoke PASS, LOCK 12 준수).
- 피드백: [재시도] exit=1 무응답도 백오프 재시도 대상에 포함 후 재실행

- 설명: 기존 게임 규칙을 담을 3D World Root와 공통 좌표/충돌 정책을 만든다.

- 요구사항:

  - `Node3D` 기반 World Root.
  - XZ ground plane.
  - Y = height.
  - 기존 logical grid의 의미를 보존하는 world unit 변환 상수/유틸리티.
  - 기존 Region/World bounds를 3D XZ로 표현 가능.
  - 공통 collision layer/mask 정책 문서화.
  - Interactable / Building / Resource / Worker / Mercenary / Enemy / Wall / Gate 구분 가능.
  - UI는 별도 CanvasLayer/Control 구조 유지.
  - 2D Main World를 즉시 삭제하지 않음.

- 금지:

  - 3D라는 이유로 world size 확대/축소.
  - 기존 gameplay distance 임의 재밸런스.
  - physics-heavy terrain.
  - 자유 높이 이동/점프.

- 완료조건:

  - 빈 3D World 정상 실행.
  - World bounds/ground coordinate 확인.
  - 공통 layer/mask 충돌 테스트 PASS.
  - 기존 UI overlay를 3D World 위에 표시 가능.

### TASK-3D-001-3 Camera3D Pan / Zoom / Screen-to-World

- 상태: DONE
- 피드백: 9개 요구사항 전부 구현 확인, 42 assertions를 reviewer가 직접 headless 재실행하여 PASS 재현, 0012 회귀·smoke도 통과, Foundation/2D 무수정 LOCK 준수 및 UTF-8 인코딩 관례 준수 확인. 지적된 2건은 비차단 개선 여지이며 후속 태스크(001-4) 범위.

- 설명: 기존 Camera + Mouse 관리 조작을 Orthographic Camera3D로 이전한다.

- 요구사항:

  - 고정 Top-down 사선 Pitch/Yaw.
  - WASD = XZ Camera Pan.
  - Mouse Wheel = orthographic size 기반 Zoom.
  - 최소/최대 Zoom clamp.
  - World boundary clamp.
  - Camera rotation 입력 없음.
  - Screen mouse position → 3D ground/world raycast 가능.
  - UI 위 Mouse 입력이 world click으로 누수되지 않음.
  - DAY/NIGHT Camera policy를 이후 Tactical Migration에서 재사용 가능.

- HUMAN_CHECK:

  - 프로젝트 좀보이드처럼 월드를 내려다보는 느낌이 자연스러운지.
  - 최대 Zoom-out에서 마을 운영 상황이 읽히는지.
  - Zoom-in에서 Worker 작업을 관찰할 수 있는지.
  - 카메라 각도가 건물/캐릭터를 지나치게 가리지 않는지.
  - Pan/Zoom 속도가 관리 게임에 적절한지.

- 완료조건:

  - Pan 정상.
  - Zoom 정상.
  - boundary clamp 정상.
  - mouse → world 좌표 정상.
  - UI click-through 없음.
  - HUMAN_CHECK만 남으면 DONE.

### TASK-3D-001-4 Interaction3D / Selection Contract

- 상태: DONE
- 피드백: 요구사항 7건·완료조건 4건 전부 실제 코드에서 확인되었고, 45 assertions 포함 전 회귀(47/42/15)를 reviewer가 직접 headless 재실행하여 PASS 재현. 금지 항목 부재, LOCK/운영 규칙·기존 2D 정책과의 일관성 확인. 지적 사항은 전부 비차단 서술 수준.
- 피드백: 요구사항 7건 전부 구현 확인, 신규 task3d0014 테스트 45 assertions headless 실행 PASS, 0012(47)·0013(42)·smoke(15) 회귀 통과. Foundation 신규 파일만 추가하고 2D interactable/world_selection 및 기존 도메인 파일 무수정(LOCK 12/운영 규칙 4 준수). re-base는 각 도메인(RES/BLD) 전환 태스크가 자기 파일만 수행.

- 설명: 기존 2D mouse selection/interaction 의미를 3D Raycast 기반으로 연결할 최소 공통 계약을 만든다.

- 요구사항:

  - Left Click → 유효한 3D selectable/interactable 1개 선택.
  - 빈 ground / decoration click 안전.
  - Right Click / ESC selection 해제.
  - UI open 상태 world interaction 누수 없음.
  - 기존 interact/select API가 dimension-neutral하면 최대한 재사용.
  - 3D node 자체를 순수 game data owner로 강제하지 않음.
  - 기능 도메인이 별도 거대 Selection Framework를 만들 필요 없는 최소 API 제공.

- 금지:

  - Box Selection.
  - Drag Selection.
  - RTS formation framework.
  - 새로운 범용 ECS.

- 완료조건:

  - Test interactable 3D object 선택/해제 PASS.
  - decoration/ground 안전.
  - UI 차단 PASS.
  - 병렬 Building/Resource/Combat 태스크가 공통 계약 사용 가능.

### TASK-3D-001-5 Navigation3D Convention / Foundation Lock

- 상태: DONE
- 피드백: reviewer 지적 4건이 모두 코드로 실제 반영되었음을 직접 확인했고, 신규 44 assertions 및 회귀 4종을 직접 실행해 전부 PASS를 재현함. 요구사항 8건과 완료조건 4건이 문서/코드/테스트로 충족되어 Foundation 기준점으로 확정 가능.
- 피드백: reviewer 지적 4건 전부 수정 + 재검증 완료. (1) is_target_reachable이 부분 경로를 reachable로 오판하던 것을 종점 일치 판정으로 수정, (2) 부분 경로 종점 접촉면 진동이 stuck guard를 무한 리셋하는 문제를 NavigationPolicy3D.judge_path_status(MOVING/ARRIVED/BLOCKED) 단일 종료 규약으로 policy 수준 해결, (3) gate 양끝을 경계 벽까지 잇는 회랑 벽 추가로 CLOSED 차단 assertion 성립 + Actor Origin LOCK(지면 접지 origin)·nav raster 해상도(1px cell) 확정, (4) scenes/_nav_test*.uid 3건 제거. task3d0015 신규 테스트 44 assertions PASS, 회귀 0012(47)·0013(42)·0014(45)·smoke(15) 전부 PASS.
- 피드백: 이전 시도 시간 초과: 실행 시간 초과 (7200초)

- 설명: Worker/Combat/Building 병렬 태스크가 서로 다른 Navigation 방식을 만들지 않도록 최소 Navigation3D 규칙을 확정한다.

- 요구사항:

  - NavigationRegion3D / NavigationMesh 기본 구조.
  - 지면 XZ 이동 기준.
  - Static Building/Wall obstacle 반영 정책.
  - Runtime Building placement 이후 nav update 정책 방향 확정.
  - Gate OPEN/CLOSED/BREACHED를 이후 3D nav에서 표현할 수 있는 구조.
  - Worker/Enemy/Mercenary가 공통 Navigation 정책을 사용할 수 있음.
  - Actor radius/height 기본 convention 기록.
  - unreachable target 처리 시 기존 영구 stall 방지 원칙 유지.

- 중요:

  - Worker/Combat 실제 전체 이식은 하지 않는다.
  - 복잡한 동적 NavMesh 최적화 시스템을 선행 구현하지 않는다.
  - 현재 Godot 버전에서 안정적인 최소 구조 우선.

- 완료조건:

  - Test Agent가 3D ground path 이동 가능.
  - Test obstacle 우회 가능.
  - nav convention이 병렬 태스크에서 재사용 가능.
  - Foundation 문서/코드 기준점 확정.

---

## PARALLEL-WAVE-3D-A Existing Systems Migration

> 선행조건: `TASK-3D-001` 전체 DONE.
>
> 아래 `TASK-3D-RES-001`, `TASK-3D-BLD-001`, `TASK-3D-WRK-001`, `TASK-3D-CMB-001`, `TASK-3D-VIS-001`은 서로 다른 AI 세션에서 병렬 실행 가능하다.
>
> 병렬 태스크끼리 상대 도메인 파일을 임의 수정하지 않는다.

---

## TASK-3D-RES-001 Resource / Gathering 3D Migration

- 상태: NEEDS_DESIGN
- 피드백: 구현 실행 오류: 알 수 없는 오류
- 피드백: [재구성 반영] 리프 실행 당시 구현물+테스트 3종 이미 존재(커밋됨). 하위 태스크에서 검증/보완 진행

- 설명: 기존 Resource 시스템의 게임 규칙을 유지하면서 Tree / Stone 등 Runtime 표현과 상호작용을 3D로 이전한다.

- 소유 범위:

  - Resource Node 3D 표현.
  - Tree.
  - Stone / StoneDeposit 계열.
  - Resource collision/select shape.
  - Resource visual state.
  - Resource claim/regrowth 관련 3D 연결.

- 유지:

  - VillageResources 데이터/신호.
  - resource amount 의미.
  - Tree claim 정책.
  - regrowth 정책.
  - Stone 생산 의미.
  - Worker가 자원을 획득/반납하는 기존 game rule.

- 금지:

  - Worker Navigation 직접 재구현.
  - BuildingPlacement 수정.
  - 신규 자원 추가.
  - 경제 밸런스 변경.
  - Main World Scene 수정.

### TASK-3D-RES-001-1 ResourceNode3D Base / Selection

- 상태: DONE
- 피드백: 5개 요구사항·4개 완료조건을 실제 코드에서 전부 확인했고, 테스트 3종(51/15/23 assertions)을 reviewer가 직접 headless 재실행하여 전부 PASS 재현. 기존 2D claim/gather/deplete/nav 규약과의 일관성, LOCK 준수, 엣지 케이스(freed timer, 공유 shape 리소스, stale claim) 모두 안전. 지적 2건은 비차단 보고 수치·문서 해석 수준.
- 피드백: [대기] 프로바이더 장애(exit=1 지속, 06:43~07:38) - 복구 후 재실행. 구현물/테스트 3종은 기존 커밋 존재

- 요구사항:

  - Foundation Interaction3D 계약 사용.
  - Area3D/CollisionShape3D 등 적절한 3D hit volume.
  - visual child와 game logic 분리.
  - Resource depletion/regrowth 시 visual/collision state 일관.
  - instance freed 후 claim/reference 정리.

- 완료조건:

  - Tree/Stone 3D 선택 가능.
  - decoration과 구분됨.
  - depletion/regrowth 상태 정상.
  - stale reference 없음.

### TASK-3D-RES-001-2 Tree / Stone Quaternius Visual

- 상태: DONE
- 피드백: 6개 요구사항 중 검증 가능한 전 항목을 실제 코드와 독립 headless 재실행(3종 전부 PASS)으로 확인했고, 스크린샷 2장이 실제 렌더임을 확인함. MegaKit 실물 mesh는 큐 설계상 VIS-001-1/VIS-002-1 소유로 문서화되어 있어 본 태스크 범위 내 결함 없음. 남은 HUMAN_CHECK 3항목만 사람 확인 대상.

- 요구사항:

  - `Stylized Nature MegaKit` 기반 Tree/Rock 우선.
  - 동일 resource type에 제한적인 visual variation.
  - collision은 mesh polygon을 그대로 쓰지 말고 gameplay에 적합한 단순 shape 우선.
  - top-down camera에서 resource 종류 식별 가능.
  - Tree stump/regrowth visual이 기존 기능과 연결됨.
  - gameplay footprint를 visual scale 변경과 분리.

- HUMAN_CHECK:

  - 숲이 복사/붙여넣기처럼 보이지 않는지.
  - Tree/Stone이 건물/Worker 대비 너무 크거나 작지 않은지.
  - Zoom-out에서도 자원 지역이 읽히는지.

- 완료조건:

  - 기능 검증 PASS.
  - visual screenshot 생성.
  - HUMAN_CHECK만 남으면 DONE.

### TASK-3D-RES-001-3 Resource Regression

- 상태: QUEUED

- 자동검증:

  - Tree claim.
  - Tree depletion.
  - Tree regrowth.
  - Stone source state.
  - VillageResources Wood/Stone 반영.
  - duplicate claim 없음.
  - freed resource reference 없음.
  - Foundation selection/raycast 회귀.

- 완료조건:

  - 기존 Resource 핵심 동작 PASS.
  - 3D Runtime에서 2D Resource Actor 의존 없음.
  - `INTEGRATION_NOTE` 작성.

---

## TASK-3D-BLD-001 Building / Placement 3D Migration

- 상태: QUEUED

- 설명: 기존 건물, 건설 Grid, Wall/Gate를 XZ 3D 월드로 이전한다.

- 소유 범위:

  - Building3D scene/base.
  - Building visual root.
  - Building collision/select volume.
  - BuildingPlacement 3D 계산.
  - placement preview.
  - Wall/Gate 3D representation.
  - 건물 도메인 내부 nav obstacle metadata.

- 유지:

  - 기존 logical grid 의미.
  - 비용/환불.
  - valid/invalid placement.
  - Wall 연속 배치 정책.
  - Gate Corridor 정책.
  - Gate `CLOSED / OPEN / BREACHED`.
  - Tavern/Inn/Keep/Grocery/Equipment Shop/Lumberyard/Quarry 등 현재 존재하는 건물의 역할.
  - 기존 UI open semantics.

- 금지:

  - 새로운 건물.
  - 건물 업그레이드.
  - Building 경제 재설계.
  - Worker AI 수정.
  - Main World Scene 직접 수정.

### TASK-3D-BLD-001-1 Building3D Base / Existing Building Scenes

- 상태: QUEUED

- 요구사항:

  - 3D Mesh/visual과 game logic 분리.
  - selectable collision.
  - static world collision.
  - Foundation Interaction3D 사용.
  - 기존 building identity/data 유지.
  - 각 기존 핵심 건물은 최소 placeholder 3D representation으로 기능 연결 가능.
  - Quaternius building visual은 VIS 태스크와 충돌하지 않도록 visual slot/resource 구조 사용.

- 완료조건:

  - 기존 핵심 건물 3D scene/runtime 경로 존재.
  - click → 기존 UI/interaction 연결 가능.
  - 2D Sprite/Collision에 Runtime 의존하지 않음.

### TASK-3D-BLD-001-2 BuildingPlacement XZ Grid

- 상태: QUEUED

- 요구사항:

  - mouse ray → ground XZ.
  - XZ logical grid snap.
  - pan/zoom 상태 정확한 target cell.
  - valid/invalid ghost는 3D transparent/material 표시.
  - ground/building/resource/wall/gate overlap validation.
  - 비용 1회 차감.
  - invalid placement 비용 차감 없음.
  - remove/refund 기존 정책 유지.
  - gameplay footprint와 visual mesh 크기 분리.

- 완료조건:

  - pan/zoom 상태 grid placement 정상.
  - invalid validation 정상.
  - 비용/환불 회귀 PASS.

### TASK-3D-BLD-001-3 Wall / Gate 3D

- 상태: QUEUED

- 요구사항:

  - Wall segment 3D.
  - Gate 3D.
  - 기존 4방향/Corridor 의미 유지.
  - Gate orientation이 3D world 방향과 일치.
  - OPEN/CLOSED/BREACHED visual state 연결 가능.
  - collision state 전환.
  - nav update는 Foundation convention을 따르고 최종 wiring 필요 시 `INTEGRATION_NOTE`.

- 완료조건:

  - Wall 배치/철거.
  - Gate validation.
  - Gate state.
  - collision 정상.
  - orientation 정상.

### TASK-3D-BLD-001-4 Building Regression

- 상태: QUEUED

- 자동검증:

  - Building selection.
  - placement.
  - invalid.
  - remove/refund.
  - Wall.
  - Gate.
  - UI interaction.
  - pan/zoom coordinates.
  - 3D collision.
  - Resource overlap validation.

- HUMAN_CHECK:

  - Top-down에서 건물 형태가 즉시 읽히는지.
  - 지붕 때문에 클릭/유닛 가독성이 지나치게 나빠지지 않는지.
  - 건물 footprint와 실제 model scale이 자연스러운지.

- 완료조건:

  - 자동검증 PASS.
  - HUMAN_CHECK만 남으면 DONE.
  - `INTEGRATION_NOTE` 작성.

---

## TASK-3D-WRK-001 Worker / Navigation 3D Migration

- 상태: QUEUED

- 설명: 기존 Worker Assignment / Lumberjack / Miner의 상태 머신과 생산 규칙을 유지하면서 Actor와 이동을 Navigation3D로 이전한다.

- 소유 범위:

  - Worker Actor3D.
  - Worker movement.
  - NavigationAgent3D.
  - Lumberjack Actor3D.
  - Miner Actor3D.
  - Carry/Work visual attachment hooks.
  - Worker navigation regression.

- 유지:

  - Worker Assignment.
  - workplace slot.
  - assign/unassign.
  - IDLE/FIND/MOVE/GATHER/RETURN/DEPOSIT 계열 기존 상태 의미.
  - 생산량/쿨다운/운반량.
  - resource claim.
  - workplace return/despawn 정책.
  - duplicate actor 방지.
  - unreachable target 영구 stall 방지.

- 금지:

  - 경제 수치 변경.
  - 신규 Worker 직업.
  - BuildingPlacement 수정.
  - Resource 로직 재설계.
  - Main World Scene 직접 수정.

### TASK-3D-WRK-001-1 WorkerActor3D / Movement

- 상태: QUEUED

- 요구사항:

  - 3D Actor root.
  - NavigationAgent3D.
  - XZ ground movement.
  - 이동 방향으로 visual facing/rotation.
  - Y height drift/tilt 없음.
  - Foundation Navigation convention 사용.
  - workplace/resource target position을 3D 좌표로 해석.
  - agent freed/unassigned cleanup 안정.

- 완료조건:

  - Test Worker 3D path 이동.
  - obstacle 회피.
  - unreachable target 안전 처리.
  - stale target/reference 없음.

### TASK-3D-WRK-001-2 Lumberjack / Miner State Machine Wiring

- 상태: QUEUED

- 요구사항:

  - 기존 state transition 의미 유지.
  - Tree/Stone 3D target과 연결.
  - workplace 3D deposit 위치와 연결.
  - carry 상태 시 prop attach hook 제공.
  - work/chop/mine animation hook 제공.
  - 실제 animation asset이 아직 없으면 기능 상태와 visual hook을 분리.
  - Animation 누락을 이유로 기능 state를 지연시키지 않음.

- 완료조건:

  - Lumberjack full loop.
  - Miner full loop.
  - assign/unassign.
  - 2명 동시 작업.
  - claim 충돌 없음.

### TASK-3D-WRK-001-3 Worker Navigation Stress Regression

- 상태: QUEUED

- 시나리오:

  - Worker 2명 Lumberyard.
  - Worker 2명 Quarry.
  - 여러 Tree/Stone target.
  - Static Building obstacle.
  - Wall obstacle.
  - Gate OPEN/CLOSED 전환 가능한 테스트 환경.
  - unreachable Resource.
  - assign/unassign 반복.
  - DAY/NIGHT 반복.

- 검증:

  - obstacle 통과 금지.
  - permanent MOVE stall 없음.
  - duplicate actor 없음.
  - freed reference 없음.
  - 생산 중복 없음.
  - claim leak 없음.

- 완료조건:

  - stress regression PASS.
  - `INTEGRATION_NOTE` 작성.

---

## TASK-3D-CMB-001 Combat / Tactical World 3D Migration

- 상태: QUEUED

- 설명: 기존 Mercenary / Enemy / Wall-Gate 전투 / Tactical command / Death Ledger의 World Actor 의존을 3D로 이전한다.

- 소유 범위:

  - Mercenary Actor3D.
  - Enemy Actor3D.
  - combat movement/range world coordinate.
  - Tactical world target selection.
  - Defense Zone 3D world representation.
  - Focus Target 3D reference.
  - Retreat/Regroup 3D position.
  - lethal death actor cleanup wiring.

- 유지:

  - 자동전투.
  - Player 직접 전투 없음.
  - HP/Damage/Attack interval 기존 의미.
  - Defense Zone.
  - Focus Target.
  - Regroup.
  - Retreat.
  - Gate command.
  - Pause/1x/2x.
  - Death Ledger lethal death 기록.
  - cleanup/despawn은 DeathRecord를 만들지 않음.

- 금지:

  - 신규 Mercenary class.
  - 신규 Enemy archetype.
  - 신규 Wave progression.
  - Boss.
  - Ghost 기능 확장.
  - 전투 밸런스 임의 변경.
  - Main World Scene 직접 수정.

### TASK-3D-CMB-001-1 Mercenary / Enemy Actor3D

- 상태: QUEUED

- 요구사항:

  - Navigation3D 이동.
  - XZ range/distance 계산.
  - facing/rotation.
  - attack/hit/death visual hook.
  - collision/select volume.
  - 3D world에서 target acquire 정상.
  - unreachable target chase lock 방지.

- 완료조건:

  - Mercenary vs Enemy 자동전투 PASS.
  - death cleanup 정상.
  - stale target 없음.
  - Player attack 경로 없음.

### TASK-3D-CMB-001-2 Tactical Command World3D Wiring

- 상태: QUEUED

- 요구사항:

  - Tactical Camera는 Foundation Camera3D를 기반으로 DAY/NIGHT policy 확장.
  - Defense Zone 위치/범위를 XZ world 기준으로 처리.
  - Focus Target ray selection.
  - Regroup target.
  - Retreat target.
  - Gate world command.
  - command priority 기존 규칙 유지.
  - UI 자체는 Control 계층 유지.

- 완료조건:

  - NIGHT tactical selection 정상.
  - command가 실제 3D Actor AI 행동에 영향.
  - DAY 복귀 시 tactical transient state 정리.
  - Camera rotation 없음.

### TASK-3D-CMB-001-3 Combat / Death Ledger Regression

- 상태: QUEUED

- 시나리오:

  1. Mercenary 배치.
  2. NIGHT.
  3. Enemy encounter.
  4. 자동전투.
  5. Focus Target.
  6. Regroup.
  7. Retreat.
  8. Gate Open/Close.
  9. Pause.
  10. 2x.
  11. lethal death.
  12. Death Ledger 확인.
  13. DAY.
  14. 다음 NIGHT 반복.

- 검증:

  - Player combat 없음.
  - duplicate death record 없음.
  - cleanup record 없음.
  - freed reference 없음.
  - Gate/nav stale state 없음.
  - command deadlock 없음.

- 완료조건:

  - 기존 Tactical Combat 의미 유지.
  - 3D Runtime Actor 기반 PASS.
  - `INTEGRATION_NOTE` 작성.

---

## TASK-3D-VIS-001 Quaternius Asset / Visual Foundation

- 상태: QUEUED

- 설명: 기능 로직과 분리된 Visual 전담 태스크. Quaternius 에셋을 기준으로 Top-down Stylized 3D의 실제 화면 스타일을 확립한다.

- 소유 범위:

  - asset download/import.
  - asset catalog.
  - visual scenes/resources.
  - materials.
  - environment.
  - lighting.
  - terrain/ground visual.
  - props.
  - vegetation visual.
  - character visual/animation setup.
  - screenshot composition test scene.

- 금지:

  - 게임 기능 로직 변경.
  - Worker 상태 머신 수정.
  - BuildingPlacement 수정.
  - Combat AI 수정.
  - 경제/밸런스 변경.
  - Main World Scene 직접 수정.
  - 외부 스타일 에셋 임의 혼합.

### TASK-3D-VIS-001-1 Asset Acquire / License / Import

- 상태: QUEUED

- 대상:

  - Medieval Village MegaKit.
  - Stylized Nature MegaKit.
  - Fantasy Props MegaKit.
  - Universal Base Characters.
  - Modular Character Outfits - Fantasy.
  - Universal Animation Library 1.
  - Universal Animation Library 2.

- 요구사항:

  - 공식 배포처 우선.
  - 각 팩의 실제 라이선스 확인.
  - 출처/라이선스 문서 보존.
  - GLTF/GLB 우선 import.
  - import warning/error 기록.
  - 필요한 asset만 runtime catalog에 노출.
  - 원본 전체를 무분별하게 Scene에 직접 참조하지 않음.
  - 모델 scale/orientation 기준 통일.
  - broken material/texture 없음.

- 완료조건:

  - 핵심 7개 팩의 사용 가능 여부 정리.
  - 필요한 모델 Godot import 성공.
  - license/source 기록 존재.
  - missing dependency 없음.

### TASK-3D-VIS-001-2 Visual Catalog / Scale Convention

- 상태: QUEUED

- 설명: AI가 이후 일관된 모델을 고를 수 있도록 실제 사용 후보를 카탈로그화한다.

- 최소 카테고리:

  - House / Village Building.
  - Wall / Gate.
  - Lumberyard visual candidates.
  - Quarry visual candidates.
  - Tavern / Inn / Keep visual candidates.
  - Tree variants.
  - Rock variants.
  - Grass / Bush / Flower.
  - Crate / Barrel / Cart.
  - Log / Wood pile.
  - Stone pile.
  - Axe / Pickaxe.
  - Market / Work props.
  - Base Human.
  - Worker outfit.
  - Mercenary outfit.
  - Weapons.
  - Idle / Walk / Work / Combat / Hit / Death animation.

- 요구사항:

  - top-down에서 실루엣이 읽히는 모델 우선.
  - 과도한 high-detail asset 제외.
  - world scale convention 기록.
  - 동일 카테고리 variation 2~5개 선별.
  - 모든 asset을 쓰려고 하지 않는다.

- 완료조건:

  - Visual Agent가 랜덤 검색 없이 catalog에서 선택 가능.
  - 주요 gameplay object에 최소 1개 이상의 후보 존재.

### TASK-3D-VIS-001-3 Environment / Lighting Prototype

- 상태: QUEUED

- 요구사항:

  - WorldEnvironment.
  - DirectionalLight3D.
  - Shadow.
  - Ambient lighting.
  - top-down 가독성 우선.
  - DAY 기본 look.
  - NIGHT 기본 look.
  - 과도한 bloom/fog/post-processing 금지.
  - terrain/ground가 캐릭터와 건물을 묻히게 하지 않음.
  - stylized low-poly 색감 유지.

- HUMAN_CHECK:

  - DAY에 밝고 생활감 있는 마을 느낌.
  - NIGHT에 위험 분위기가 생기지만 유닛/길이 읽히는지.
  - 그림자가 지형/건물 가독성을 개선하는지.
  - 너무 모바일 게임처럼 가볍거나 반대로 반실사처럼 보이지 않는지.

- 완료조건:

  - DAY screenshot.
  - NIGHT screenshot.
  - 렌더 오류 없음.
  - HUMAN_CHECK만 남으면 DONE.

### TASK-3D-VIS-001-4 Character / Outfit / Animation Prototype

- 상태: QUEUED

- 요구사항:

  - Universal Base Character 1종 이상.
  - Worker visual variant 2종 이상.
  - Mercenary visual 1종 이상.
  - 공용 skeleton/animation 호환 확인.
  - Idle.
  - Walk.
  - Work 계열 최소 1.
  - Attack.
  - Hit/Death 중 최소 1.
  - tool attachment point 또는 명확한 prop attach 방식.
  - AnimationTree는 현재 필요 이상의 복잡한 state graph를 선행하지 않음.

- 완료조건:

  - Test character가 3D scene에서 애니메이션 재생.
  - 방향 전환 시 sprite 재생성 필요 없음.
  - Worker/Mercenary에서 공용 animation 재사용 가능.
  - broken rig/skin 없음.

### TASK-3D-VIS-001-5 Visual Village Composition Prototype

- 상태: QUEUED

- 설명: 실제 기능 연결 전 동일 에셋 스택만으로 "게임처럼 보이는" 작은 마을 화면을 만든다.

- 구성:

  - House 여러 채.
  - Lumberyard 느낌 공간.
  - Quarry 느낌 공간.
  - Tree cluster.
  - Rock cluster.
  - Main path.
  - props.
  - 주민/Worker/Mercenary visual.
  - Camera Pan/Zoom 테스트.
  - DAY/NIGHT lighting.

- 원칙:

  - 랜덤 에셋으로 화면을 꽉 채우지 않는다.
  - Village / Work / Forest / Quarry 공간 밀도를 구분한다.
  - 반복 모델은 제한적 variation.
  - 건물 주위 props로 기능 정체성을 강화한다.
  - gameplay path/selection 가독성을 장식이 방해하지 않는다.

- HUMAN_CHECK:

  - 첫 화면에서 "2D 때보다 확실히 낫다"는 인상이 있는지.
  - 마을이 살아 있는 공간처럼 보이는지.
  - Zoom-out에서 전체 구성 읽힘.
  - Zoom-in에서 Worker 관찰 가치가 있음.
  - Quaternius 에셋끼리 한 세계처럼 보이는지.
  - Top-down 3D 전환 방향을 계속 가져갈 시각적 가치가 충분한지.

- 완료조건:

  - overview screenshot.
  - zoom-in screenshot.
  - NIGHT screenshot.
  - visual blockers 기록.
  - HUMAN_CHECK만 남으면 DONE.
  - `INTEGRATION_NOTE` 작성.

---

## PARALLEL-WAVE-3D-B Visual / Domain Wiring

> 선행조건:
>
> - `TASK-3D-RES-001` DONE.
> - `TASK-3D-BLD-001` DONE.
> - `TASK-3D-WRK-001` DONE.
> - `TASK-3D-CMB-001` DONE.
> - `TASK-3D-VIS-001` DONE.
>
> 이 Wave에서는 병렬 결과를 실제 Main 3D World에 연결하기 위한 준비를 수행한다.
> 공유 진입점 직접 병합은 `TASK-3D-INT-001`에서만 한다.

---

## TASK-3D-VIS-002 Gameplay Visual Wiring / Polish

- 상태: QUEUED

- 설명: 기능 도메인의 3D Scene에 Quaternius visual/animation을 연결하고 실제 gameplay 화면의 일관성을 맞춘다.

### TASK-3D-VIS-002-1 Resource / Building Visual Wiring

- 상태: QUEUED

- 요구사항:

  - Tree/Stone catalog 연결.
  - Lumberyard/Quarry visual 연결.
  - 기존 건물 visual 연결.
  - Wall/Gate visual 연결.
  - gameplay footprint/collision은 visual mesh와 독립 유지.
  - 모델 교체가 game logic를 깨지 않음.

- 완료조건:

  - 기능 scene에 최종 후보 visual 연결.
  - collision/selection 회귀 없음.

### TASK-3D-VIS-002-2 Worker / Combat Animation Wiring

- 상태: QUEUED

- 요구사항:

  - Idle/Walk.
  - Lumberjack work.
  - Miner work.
  - carry/tool prop.
  - Mercenary attack.
  - Enemy/mercenary hit/death 가능한 범위.
  - 상태 머신이 Animation 재생 실패 때문에 멈추지 않음.
  - 방향별 sprite 개별 제작 없음.

- 완료조건:

  - Worker full loop에 visual animation 연결.
  - Combat loop에 최소 attack/death 표현 연결.
  - animation error 없음.

### TASK-3D-VIS-002-3 Roof / Occlusion / Selection Readability

- 상태: QUEUED

- 설명: 고정 사선 Top-down 3D에서 건물/지붕이 유닛과 선택 대상을 과도하게 가리는 문제를 최소 정책으로 처리한다.

- 허용 방식:

  - 필요 시 roof visual child fade/hide.
  - selected object highlight.
  - camera-facing occlusion 최소 처리.
  - 단순 shader/material alpha.

- 금지:

  - 거대한 범용 occlusion framework.
  - 자유 camera rotation으로 문제 회피.
  - 모든 벽을 상시 투명화.

- HUMAN_CHECK:

  - 건물 뒤 Worker가 지속적으로 안 보이는 문제가 없는지.
  - 클릭 대상이 명확한지.
  - 투명화가 시각적으로 거슬리지 않는지.

- 완료조건:

  - 핵심 건물 주변 가독성 확보.
  - selection 정상.
  - HUMAN_CHECK만 남으면 DONE.

---

## TASK-3D-INT-001 3D Main World Integration

- 상태: QUEUED

- 설명: 병렬 태스크 결과를 하나의 실제 Runtime Main 3D World에 통합한다. 공유 진입점 수정은 이 태스크에서 수행한다.

- 선행조건:

  - `TASK-3D-001` DONE.
  - `TASK-3D-RES-001` DONE.
  - `TASK-3D-BLD-001` DONE.
  - `TASK-3D-WRK-001` DONE.
  - `TASK-3D-CMB-001` DONE.
  - `TASK-3D-VIS-001` DONE.
  - `TASK-3D-VIS-002` DONE.

- 통합 대상:

  - Main World root → 3D.
  - Camera3D.
  - Ground/World bounds.
  - 3D Resources.
  - 3D Buildings.
  - BuildingPlacement3D.
  - Worker3D.
  - Navigation3D.
  - Mercenary/Enemy3D.
  - Wall/Gate3D.
  - Tactical command 3D world target.
  - 3D visual/environment.
  - 기존 Control UI.
  - Day/Night.
  - Death Ledger.
  - 기존 data/autoload/game logic.

- 요구사항:

  - 각 병렬 태스크의 `INTEGRATION_NOTE` 확인.
  - 동일 기능 중복 구현 제거.
  - 병렬 세션이 임시로 만든 공통 API가 충돌하면 Foundation 계약을 우선.
  - UI Control layer는 유지.
  - Runtime 핵심 경로에 불필요한 2D Actor/Navigation 의존 제거.
  - 기존 2D Scene은 최종 회귀 완료 전 즉시 전량 삭제하지 않음.
  - Main Scene에서 3D Runtime이 기본 실행 경로가 됨.

### TASK-3D-INT-001-1 Main Scene Wiring / Shared Config

- 상태: QUEUED

- 요구사항:

  - project main scene 3D path 연결.
  - 필요한 Autoload/InputMap/shared layer 갱신.
  - duplicate input owner 제거.
  - duplicate Camera 제거.
  - duplicate NavigationRegion 제거.
  - missing resource/path 없음.

- 완료조건:

  - Main 실행 성공.
  - parser/import error 없음.
  - duplicate singleton/camera/input 없음.

### TASK-3D-INT-001-2 Existing Gameplay Vertical Slice 3D

- 상태: QUEUED

- 시나리오:

  1. 게임 시작.
  2. 3D Main World 확인.
  3. DAY Camera pan.
  4. Zoom in/out.
  5. 건물 click.
  6. Tavern/Inn 등 기존 UI.
  7. Lumberyard/Quarry interaction.
  8. Worker assign.
  9. Lumberjack 생산.
  10. Miner 생산.
  11. BuildingPlacement.
  12. Wall/Gate.
  13. Resource depletion/regrowth.
  14. NIGHT.
  15. Tactical camera.
  16. Mercenary/Enemy auto combat.
  17. Tactical command.
  18. Gate command.
  19. lethal death.
  20. Death Ledger.
  21. DAY 복귀.
  22. 다음 cycle 반복.

- 핵심검증:

  - Player Avatar runtime 없음.
  - Player combat 없음.
  - Camera rotation 없음.
  - 3D Resource/Building/Worker/Combat Actor 사용.
  - 기존 핵심 game rule 유지.
  - duplicate actor 없음.
  - stale nav 없음.
  - freed reference 없음.
  - UI click-through 없음.

- 완료조건:

  - 전체 vertical slice PASS.
  - 기존 핵심 기능의 의미적 회귀 없음.

### TASK-3D-INT-001-3 2D Runtime Dependency Cleanup

- 상태: QUEUED

- 설명: 3D Main World가 정상 동작한 뒤 Runtime에서 더 이상 사용하지 않는 2D 전용 경로를 안전하게 정리한다.

- 요구사항:

  - 프로젝트 전체 reference 검색.
  - 2D Resource/Worker/Building/Combat Scene이 실제 Runtime에서 미사용인지 확인.
  - 테스트/reference 용도로 필요한 파일은 근거 없이 삭제하지 않음.
  - 사용하지 않는 2D main runtime path 제거.
  - CharacterBody2D / NavigationAgent2D / Area2D 등이 핵심 Runtime에 남은 경우 용도 확인.
  - UI Control/CanvasItem은 정상 2D UI이므로 삭제 대상 아님.
  - asset/license 문서는 보존.

- 금지:

  - `git clean`.
  - 이름에 `2d`가 있다는 이유만으로 일괄 삭제.
  - unrelated legacy cleanup.
  - GAME_DESIGN 대규모 재작성.

- 완료조건:

  - Main Runtime 3D path self-contained.
  - orphan reference 없음.
  - smoke PASS.

---

## TASK-3D-INT-002 3D Regression / Performance / Visual Acceptance

- 상태: QUEUED

- 설명: 3D 전환 전체를 자동검증 + 실제 화면 + 기본 성능 관점에서 최종 확인한다.

### TASK-3D-INT-002-1 Automated Regression

- 상태: QUEUED

- 검증:

  - main scene smoke.
  - Camera pan/zoom.
  - mouse ray/selection.
  - Building interaction.
  - BuildingPlacement.
  - Wall/Gate.
  - Tree claim/regrowth.
  - Wood/Stone production.
  - Worker 2명 이상.
  - Miner 2명 이상.
  - Navigation obstacle.
  - unreachable target.
  - DAY/NIGHT.
  - Tactical combat.
  - Tactical commands.
  - Gate command.
  - Death Ledger.
  - repeated cycle.
  - no duplicate actor.
  - no freed reference.
  - no stale navigation.

- 완료조건:

  - 실행 가능한 자동검증 전부 PASS.
  - 미실행 테스트를 PASS로 기록하지 않음.

### TASK-3D-INT-002-2 Basic Performance / Stress

- 상태: QUEUED

- 설명: 3D 전환으로 기본 프로토타입이 명백하게 사용 불가능한 수준으로 느려지지 않는지 확인한다.

- 검증:

  - 현재 실제 Worker/Building/Resource 규모.
  - Tree/Rock/Prop 다수 배치.
  - Camera full overview.
  - Zoom in/out 반복.
  - Worker navigation.
  - NIGHT combat.
  - DAY/NIGHT 반복.
  - excessive material/mesh duplication 여부.
  - 명백한 per-frame allocation/scene spawn loop 여부.

- 원칙:

  - 아직 대규모 최적화 시스템은 만들지 않는다.
  - 실제 병목이 확인된 부분만 최소 개선.
  - 단순 추측으로 MultiMesh/ECS/LOD framework를 선행하지 않는다.

- 완료조건:

  - 현재 vertical slice 정상 플레이 가능한 성능.
  - 명백한 runaway allocation/process 없음.
  - 확인된 병목은 기록.

### TASK-3D-INT-002-3 Visual Acceptance

- 상태: QUEUED

- 필수 Screenshot:

  - DAY full village overview.
  - DAY zoom-in Worker scene.
  - Forest/resource area.
  - Lumberyard/Quarry.
  - Building placement.
  - NIGHT tactical overview.
  - NIGHT combat.

- HUMAN_CHECK:

  - **2D 버전보다 비주얼이 확실히 마음에 드는가.**
  - 첫 화면이 임시 개발용 프로토타입이 아니라 실제 게임 방향처럼 보이는가.
  - 줌 아웃 시 마을/자원/방어 공간이 읽히는가.
  - 줌 인 시 Worker 행동을 보는 재미가 있는가.
  - 캐릭터/건물/자연물이 하나의 아트 스타일로 보이는가.
  - 카메라 각도/줌 범위가 프로젝트 좀보이드 계열의 탑다운 시야감과 목적에 맞는가.
  - 낮/밤 분위기 차이가 의미 있는가.
  - 장식이 gameplay selection/navigation 가독성을 방해하지 않는가.
  - 3D 전환 이후 계속 기능 개발할 동기가 생길 정도의 화면이 나오는가.

- 중요:

  - HUMAN_CHECK의 미감 판단을 AI가 임의로 PASS 처리하지 않는다.
  - 자동검증과 기능 회귀가 정상이라면 HUMAN_CHECK만 남은 상태는 DONE 가능하며, 사용자 최종 판단용 screenshot을 남긴다.

- 완료조건:

  - 필수 screenshot 존재.
  - 기능 regression PASS.
  - 치명적 visual blocker 없음.
  - HUMAN_CHECK 항목 명확히 기록.

---

---

## CHECKPOINT-3D-MIGRATION Top-down 3D Migration 검증 지점

- 상태: QUEUED

- 설명: Top-down 3D Migration 전체가 완료되었는지 확인하는 **중간 체크포인트**다. 이 지점은 전체 Queue 종료가 아니다.

- 확인:

  - TASK-3D-001 DONE.
  - TASK-3D-RES-001 DONE.
  - TASK-3D-BLD-001 DONE.
  - TASK-3D-WRK-001 DONE.
  - TASK-3D-CMB-001 DONE.
  - TASK-3D-VIS-001 DONE.
  - TASK-3D-VIS-002 DONE.
  - TASK-3D-INT-001 DONE.
  - TASK-3D-INT-002 DONE.
  - Main Runtime = 3D.
  - Top-down Orthographic Camera.
  - Pan/Zoom 정상.
  - Camera rotation 없음.
  - 기존 핵심 Worker/Building/Resource/Combat/Tactical/Death Ledger 기능 정상.
  - Quaternius 기반 시각 스타일 적용.
  - 필수 screenshot 존재.
  - 임시 파일 없음.

- 중요:

  - 기능/자동검증 문제가 남아 있으면 다음 Feature Wave로 넘어가지 않는다.
  - 미감/체감에 대한 `HUMAN_CHECK`만 남아 있다면 코드상 DONE 처리 후 다음 Feature Wave로 진행할 수 있다.
  - 사용자 확인이 없다는 이유만으로 밤샘 자동화를 중단하지 않는다.
  - 3D Migration 결과를 되돌리는 신규 2D gameplay 구현은 이후 전 구간에서 금지한다.

- 체크포인트 회귀:

  - smoke.
  - Camera/Mouse.
  - Resources.
  - Buildings/Placement.
  - Worker/Navigation.
  - Wall/Gate.
  - Tactical Combat.
  - Death Ledger.
  - DAY/NIGHT.
  - visual screenshot set.

- 완료조건:

  - 3D Migration 전체 기능 회귀 PASS.
  - Runtime 3D default path.
  - 치명적 import/render/runtime error 없음.
  - HUMAN_CHECK 이외 blocker 없음.
  - 다음 `POST-3D FEATURE QUEUE` 실행 가능.

---

# POST-3D FEATURE QUEUE 공통 규칙

> 이 구간은 기존 로드맵의 다음 기능을 **3D Runtime 기준으로 계속 개발**한다.
>
> 실행 우선순위:
>
> **First Ghost Return → Food → Farming → Cooking → Herb/Potion → Inn Capacity → Morale → Threat/Wave → Portal/Ghost Expansion**
>
> 1. 이 구간의 모든 World Actor / Building / Resource / Interaction은 3D Foundation을 사용한다.
>
> 2. 신규 기능을 2D Node 기반으로 먼저 만든 뒤 나중에 재전환하는 방식은 금지한다.
>
> 3. 정확한 밸런스 수치만 미정인 경우 `NEEDS_DESIGN`으로 멈추지 않는다.
>
>    - exported/config/data-driven parameter로 둔다.
>    - 최소 테스트 기본값을 사용한다.
>    - 결과에 `DESIGN_TUNING`으로 표시한다.
>
> 4. 반대로 게임 규칙 자체가 불명확해 서로 다른 플레이 경험이 되는 선택이 필요하면 `NEEDS_DESIGN`으로 중단한다.
>
> 5. 한 기능을 위해 범용 프레임워크를 과설계하지 않는다.
>
> 6. 각 기능은 최소 vertical slice → regression → visual wiring 순서로 완성한다.
>
> 7. 새 UI는 기존 Control/CanvasLayer 체계를 사용한다.
>
> 8. 새 Worker/Actor는 기존 Navigation3D / selection / actor lifecycle / cleanup 규칙을 사용한다.
>
> 9. 새 Building은 기존 BuildingPlacement3D / footprint / collision / nav update 규칙을 사용한다.
>
> 10. 새 Resource는 기존 ResourceNode3D / claim / depletion/regrowth 규칙을 재사용한다.
>
> 11. 새 전투 소비품/상태는 기존 Tactical Combat와 충돌하지 않아야 한다.
>
> 12. 플레이어 캐릭터 직접 전투 금지 규칙은 계속 유지한다.
>
> 13. 플레이어 Avatar 직접 필드 노동을 부활시키지 않는다. 관리/지휘 Camera + Mouse 방향을 유지한다.
>
> 14. 새 기능으로 인해 기존 DAY/NIGHT 전체 루프가 깨지면 해당 Feature를 DONE 처리하지 않는다.
>
> 15. 각 Feature 완료 후 smoke + 해당 기능 regression + 기존 핵심 회귀 subset을 실행한다.
>
> 16. HUMAN_CHECK만 남은 경우 자동화는 다음 Feature로 계속 진행할 수 있다.
>
> 17. 기능별 시각 요소는 기존 Quaternius 스타일과 충돌하지 않도록 우선 기존 Asset Stack에서 조립한다.
>
> 18. 인터넷의 출처 불명 3D 모델/텍스처/음원을 임의로 추가하지 않는다.
>
> 19. 새 기능이 기존 `GAME_DESIGN.md`에 이미 명시되어 있다면 그 문서를 우선한다.
>
> 20. 독립적인 후속 Feature 하나가 `NEEDS_DESIGN`이라도 이후 Feature가 해당 구현에 의존하지 않고 안전하게 개발 가능하면 다음 Feature로 진행한다.
>
> 21. `NEEDS_DESIGN`을 우회하기 위해 임의 게임 규칙을 발명하지 않는다.
>
> 22. 최종 자동화 종료는 `OVERNIGHT-STOP-FEATURES`에서만 수행한다.

---

## FEATURE-WAVE-017 First Ghost Return

> 기존 로드맵상 Death Ledger 다음 우선순위.
>
> Food / Potion / Morale보다 먼저 Ghost 핵심 경험을 검증한다.
>
> 목표:
>
> **실제 lethal death → Ghost 후보 기록 → 이후 NIGHT에서 1회 재등장 → 처치 후 재귀 등록 없이 종료**

---

## TASK-017 First Ghost Return

- 상태: QUEUED

- 핵심 규칙 LOCK:

  - 실제 lethal death만 Ghost 후보가 된다.
  - cleanup / despawn / scene unload는 Ghost 후보가 아니다.
  - 현재 Runtime에 실제 존재하는 eligible entity부터 적용한다.
  - Ghost는 원본 존재와 연결 가능한 identity snapshot을 가진다.
  - 한 death event당 Ghost return은 최대 1회다.
  - Ghost 자신이 다시 죽어도 동일 chain으로 무한 재등록되지 않는다.
  - Ghost return은 death 직후 즉시 부활이 아니라 **이후 NIGHT/Wave 쪽 재등장**이다.
  - Mercenary Ghost는 가능한 범위에서 원본 전투 특성/스킬 정보를 유지한다.
  - Ghost는 시각적으로 원본과 구분되어야 한다.
  - Ghost를 막는 별도 anti-ghost 시스템은 만들지 않는다.
  - Player 직접 전투 없음.

### TASK-017-1 Death Ledger → Ghost Return Candidate

- 상태: QUEUED

- 설명: 기존 Death Ledger를 깨지 않고 Ghost Return에 필요한 최소 1회성 후보 상태를 연결한다.

- 요구사항:

  - 기존 DeathRecord source-of-truth를 우선 검토.
  - duplicate death event가 duplicate ghost candidate를 만들지 않음.
  - cleanup/despawn 제외.
  - candidate는 원본 entity category / source death / combat identity를 추적 가능.
  - 이미 return 처리된 candidate는 다시 consume되지 않음.
  - save/load가 현재 존재한다면 기존 save 정책에 맞춤.
  - 새 거대 event sourcing 시스템 금지.

- 완료조건:

  - lethal death 1회 → candidate 1개.
  - duplicate death signal → candidate 1개 유지.
  - cleanup → candidate 0개.
  - already-consumed candidate 재사용 없음.

### TASK-017-2 Subsequent NIGHT Ghost Spawn

- 상태: QUEUED

- 설명: 소비 가능한 Ghost 후보가 이후 NIGHT spawn 경로를 통해 실제 3D Ghost Actor로 1회 등장한다.

- 요구사항:

  - 현재 Portal/Spawn marker가 있으면 재사용.
  - 없으면 기존 spawn convention 안에서 최소 marker 사용.
  - candidate consume과 spawn 성공 순서가 안전해야 함.
  - spawn 실패 시 candidate를 유실시키지 않음.
  - Ghost Actor는 기존 Enemy/Mercenary combat foundation을 최대한 재사용.
  - 원본 identity를 Ghost visual/label/debug에서 확인 가능.
  - 같은 candidate 2회 spawn 없음.

- 완료조건:

  - lethal death → 다음 유효 NIGHT → Ghost spawn.
  - Ghost 자동전투 참여.
  - duplicate spawn 없음.
  - failed spawn recovery 안전.

### TASK-017-3 Ghost Visual / Combat Identity

- 상태: QUEUED

- 요구사항:

  - Quaternius 원본 visual을 재사용하되 material/tint/emission/alpha 등 최소 처리로 Ghost 구분.
  - readability를 해치는 과도한 transparency 금지.
  - Mercenary Ghost는 원본 class/stat/skill data 중 현재 구현된 범위를 유지.
  - Enemy Ghost도 원본 archetype을 추적 가능.
  - Ghost death animation/cleanup 정상.
  - Ghost 사망이 다시 Ghost Return Candidate를 만들지 않음.

- HUMAN_CHECK:

  - 일반 Actor와 Ghost가 즉시 구분되는지.
  - NIGHT 전투에서 Ghost가 너무 투명해 가독성을 해치지 않는지.
  - "전에 죽었던 존재가 돌아왔다"는 identity가 느껴지는지.

- 완료조건:

  - Ghost visual screenshot.
  - combat regression PASS.
  - HUMAN_CHECK만 남으면 DONE.

### TASK-017-4 Ghost Vertical Slice Regression

- 상태: QUEUED

- 시나리오:

  1. Mercenary 또는 Enemy lethal death.
  2. Death Ledger 확인.
  3. DAY.
  4. 다음 NIGHT.
  5. Ghost spawn.
  6. Ghost combat.
  7. Ghost lethal death.
  8. 다음 DAY/NIGHT 반복.

- 검증:

  - 원 death record 1개.
  - ghost candidate 1개.
  - ghost spawn 1회.
  - ghost death 후 candidate 재귀 생성 없음.
  - freed reference 없음.
  - duplicate actor 없음.
  - Death Ledger 기존 기능 회귀 없음.
  - Player combat 없음.

- 완료조건:

  - First Ghost Return vertical slice PASS.

---

## FEATURE-WAVE-018 Food Economy Foundation

> 식량은 주민/Worker/Mercenary가 지속적으로 소비하는 필수 자원이다.
>
> raw ingredient는 바로 먹을 수 있지만 효율이 낮다.
>
> 첫 단계에서는 복잡한 영양/체중/개인 취향을 만들지 않는다.

---

## TASK-018 Food Resource / Consumption

- 상태: QUEUED

- 핵심 규칙 LOCK:

  - Food는 지속 소비되는 필수 자원.
  - 현재 존재하는 주민/Worker/Mercenary가 소비 대상.
  - raw ingredient는 가공 없이 먹을 수 있으나 효율이 낮다.
  - cooked food는 이후 Cooking Feature에서 더 높은 효율을 제공한다.
  - exact consumption rate는 data-driven `DESIGN_TUNING`.
  - 식량 부족 페널티가 문서에 명확하지 않으면 임의 starvation damage/death를 만들지 않는다.
  - 부족 상태/event/UI까지 구현하고 punitive rule은 확정 설계만 적용한다.

### TASK-018-1 Food Data / Village Resource Integration

- 상태: QUEUED

- 요구사항:

  - 기존 VillageResources 또는 실제 resource data 구조를 우선 재사용.
  - Food stock.
  - Raw edible ingredient category.
  - consumption efficiency metadata.
  - cooked meal category를 이후 확장 가능하게 최소 구조화.
  - string 분기 남발 금지.
  - save/load 정책이 있으면 포함.

- 완료조건:

  - Food add/remove/query.
  - raw edible conversion/query.
  - negative stock 없음.
  - resource UI event 연결 가능.

### TASK-018-2 Population Consumption Tick

- 상태: QUEUED

- 요구사항:

  - per-frame 감소 금지.
  - 기존 DAY/time tick과 결합.
  - active resident/worker/mercenary count를 중복 없이 집계.
  - Food 우선 소비.
  - Food 부족 시 raw edible fallback 가능.
  - raw ingredient는 낮은 efficiency 적용.
  - 부족량/부족 상태를 명시적으로 기록.
  - exact rate는 config/data로 분리.

- 완료조건:

  - 인구 0 → consumption 0.
  - 인구 N → deterministic consumption.
  - Food 충분 → raw ingredient 미사용.
  - Food 부족 → raw edible fallback.
  - 둘 다 부족 → shortage state.
  - stock 음수 없음.

### TASK-018-3 Food HUD / Shortage Feedback

- 상태: QUEUED

- 요구사항:

  - 현재 HUD에 Food 표시.
  - shortage는 명확한 경고.
  - raw ingredient가 비효율적으로 소비되는 상황을 확인 가능.
  - UI가 world input을 차단해야 하는 기존 규칙 유지.

- HUMAN_CHECK:

  - Food가 Wood/Stone과 구분되어 읽히는지.
  - 부족 경고가 과도하게 화면을 방해하지 않는지.

- 완료조건:

  - Food HUD 정상.
  - shortage feedback 정상.
  - HUMAN_CHECK만 남으면 DONE.

### TASK-018-4 Food Regression

- 상태: QUEUED

- 검증:

  - DAY 반복 consumption.
  - Worker/Mercenary population change.
  - raw fallback.
  - shortage.
  - save/load가 있다면 stock persistence.
  - DAY/NIGHT 회귀.
  - 기존 Wood/Stone 영향 없음.

- 완료조건:

  - Food economy foundation PASS.

---

## FEATURE-WAVE-019 Farming

> 목표:
>
> **Farm workplace → Farmer assignment → crop growth/harvest → raw edible ingredient → Food 시스템 연결**
>
> Seed inventory / season / fertilizer / irrigation은 이번 vertical slice 범위 밖이다.

---

## TASK-019 First Farm / Farmer / Crop

- 상태: QUEUED

### TASK-019-1 Farm Building / Plot 3D

- 상태: QUEUED

- 요구사항:

  - 기존 BuildingPlacement3D 사용.
  - Farm 또는 Farm Plot을 기존 설계 문서에서 우선 확인.
  - 정확한 건물 형태가 잠겨 있지 않으면 최소 Farm workplace 1종으로 제한.
  - XZ grid/footprint/collision/nav 정상.
  - Quaternius Village/Nature/Props 범위에서 visual 구성.
  - crop area가 top-down에서 읽힘.

- 금지:

  - 여러 농장 tier.
  - season.
  - irrigation.
  - fertilizer.
  - seed inventory.

- 완료조건:

  - build/remove/select.
  - nav update.
  - farm UI open.
  - visual screenshot.

### TASK-019-2 Farmer Worker Assignment

- 상태: QUEUED

- 요구사항:

  - 기존 Worker Assignment framework 사용.
  - Farmer는 새 별도 범용 AI framework를 만들지 않음.
  - workplace slot.
  - assign/unassign.
  - MOVE → WORK → HARVEST/DEPOSIT 계열을 기존 Worker convention에 맞춤.
  - Animation Library farming/work animation을 가능한 범위에서 사용.
  - tool/prop attach는 기존 visual hook 사용.

- 완료조건:

  - Farmer 1명.
  - Farmer 2명 동시 assignment 가능한 범위.
  - duplicate actor 없음.
  - unassign cleanup 정상.

### TASK-019-3 Crop Growth / Harvest

- 상태: QUEUED

- 요구사항:

  - crop definition data-driven.
  - 첫 vertical slice crop 1종.
  - growth time `DESIGN_TUNING`.
  - visual growth stage 최소 표현.
  - harvest → raw edible ingredient.
  - Food raw fallback에서 소비 가능.
  - crop node와 decorative vegetation 구분.
  - regrowth/replant 정책은 기존 설계를 확인.
  - 불명확하면 최소 반복 production cycle로 캡슐화하고 `DESIGN_TUNING` 표시.

- 완료조건:

  - growth.
  - harvest.
  - raw ingredient 증가.
  - Food fallback 연결.
  - freed crop reference 없음.

### TASK-019-4 Farm Vertical Slice Regression

- 상태: QUEUED

- 시나리오:

  1. Farm 건설.
  2. Farmer assign.
  3. Crop work.
  4. Growth.
  5. Harvest.
  6. Raw ingredient stock 증가.
  7. Food 부족.
  8. Raw ingredient 소비.
  9. DAY/NIGHT 반복.

- 완료조건:

  - farm → raw food → consumption loop PASS.
  - 기존 Lumberjack/Miner 회귀 없음.

---

## FEATURE-WAVE-020 Cooking / Meal

> 목표:
>
> **raw ingredient → cooked meal → raw 직접 섭취보다 높은 효율**
>
> 복잡한 레시피 수집/요리 미니게임/개인 취향은 범위 밖이다.

---

## TASK-020 Cooking / Meal Vertical Slice

- 상태: QUEUED

- 핵심 규칙 LOCK:

  - raw ingredient는 즉시 섭취 가능하지만 효율이 낮다.
  - cooking은 같은 원재료를 더 효율적인 Food/Meal로 전환한다.
  - 음식은 장기/사전 버프 계열이며 Potion과 역할이 다르다.
  - 음식 등급 확장이 가능해야 하지만 첫 slice에서 모든 등급 콘텐츠를 만들 필요는 없다.
  - exact recipe/efficiency/buff 값은 data-driven.

### TASK-020-1 Cooking Recipe / Meal Data

- 상태: QUEUED

- 요구사항:

  - recipe input.
  - recipe output.
  - food efficiency.
  - quality/tier field.
  - optional long-duration/pre-battle buff metadata 확장점.
  - 첫 slice recipe 1~2개.
  - 문자열 하드코딩 분기 최소화.

- 완료조건:

  - recipe validation.
  - insufficient ingredient rejection.
  - output deterministic.
  - raw보다 cooked efficiency 높음.

### TASK-020-2 Cooking Production Path

- 상태: QUEUED

- 요구사항:

  - `GAME_DESIGN.md`에 확정된 Cooking workplace/building이 있으면 그것을 사용.
  - 확정 building이 없다면 기존 building을 임의로 요리 시설로 변조하지 않는다.
  - 최소 production component/test path를 구현.
  - building identity 자체가 필요한데 설계가 없으면 이 subtask만 `NEEDS_DESIGN`.
  - worker production pattern 재사용 가능 여부 우선 검토.

- 완료조건:

  - raw ingredient 소비.
  - meal 생성.
  - duplicate production 없음.
  - negative ingredient 없음.

### TASK-020-3 Meal Consumption / Efficiency

- 상태: QUEUED

- 요구사항:

  - cooked meal의 소비 효율이 raw보다 높음.
  - exact consumption priority가 문서에 없으면 deterministic policy를 data로 둠.
  - raw fallback 유지.
  - Meal buff가 설계상 충분히 명확한 경우 최소 1개만 vertical slice.
  - buff가 불명확하면 효율 증가까지만 완료하고 임의 combat stat buff 생성 금지.

- 완료조건:

  - cooked meal consumption.
  - raw 대비 효율 차이.
  - shortage loop 정상.

### TASK-020-4 Cooking Regression

- 상태: QUEUED

- 검증:

  - crop/raw input.
  - recipe.
  - meal output.
  - consumption.
  - raw fallback.
  - Food HUD.
  - DAY/NIGHT.
  - Worker production 회귀.

- 완료조건:

  - Farm → Cook → Consume vertical slice PASS.

---

## FEATURE-WAVE-021 Herb / Potion

> Food와 Potion의 역할을 분리한다.
>
> Food:
>
> - 장기/사전 준비.
>
> Potion:
>
> - Mercenary 별도 슬롯.
> - 자동전투 중 조건부 소비.
> - 위기 대응.

---

## TASK-021 Herb / Potion Vertical Slice

- 상태: QUEUED

- 핵심 규칙 LOCK:

  - Potion은 Food와 별도.
  - Potion은 Mercenary 장착 슬롯을 사용.
  - 자동전투 중 조건부로 소비된다.
  - 플레이어가 실시간 직접 Potion 버튼을 난사하는 구조로 만들지 않는다.
  - 첫 slice는 Potion 1종.
  - exact trigger/amount는 data-driven.
  - 약초/버섯 자원은 현재 Camera+Mouse 관리 구조를 깨고 Player Avatar 직접 채집을 부활시키지 않는다.

### TASK-021-1 Wild Herb Resource3D

- 상태: QUEUED

- 요구사항:

  - 기존 ResourceNode3D 사용.
  - Herb visual은 Stylized Nature MegaKit 우선.
  - resource/depletion/regrowth convention 재사용.
  - 획득 경로는 현재 설계 문서 우선.
  - Worker 채집이 필요하면 기존 Worker pattern을 최소 확장.
  - Player Avatar 직접 수확 구현 금지.

- 완료조건:

  - Herb source 1종.
  - acquire stock.
  - depletion/regrowth.
  - visual/readability 정상.

### TASK-021-2 Potion Data / Craft

- 상태: QUEUED

- 요구사항:

  - Potion definition.
  - herb ingredient.
  - effect.
  - trigger condition.
  - stack/slot rule.
  - 첫 slice Potion 1종.
  - crafting workplace가 확정되어 있으면 사용.
  - 확정되어 있지 않으면 crafting data/service까지만 만들고 임의 건물 추가 금지.

- 완료조건:

  - ingredient validation.
  - potion create.
  - stock negative 없음.

### TASK-021-3 Mercenary Potion Slot / Auto Consume

- 상태: QUEUED

- 요구사항:

  - Mercenary 별도 Potion slot.
  - battle start 전에 장착.
  - combat condition 만족 시 자동 소비.
  - 동일 조건에서 multi-consume 방지.
  - pause/2x에서도 deterministic.
  - dead mercenary가 Potion consume하지 않음.
  - Potion effect가 Player combat 경로를 만들지 않음.

- 완료조건:

  - equip.
  - condition false → 미사용.
  - condition true → 1회 사용.
  - effect 적용.
  - stock 반영.

### TASK-021-4 Potion Combat Regression

- 상태: QUEUED

- 시나리오:

  - Mercenary Potion 장착.
  - NIGHT combat.
  - trigger 이전.
  - trigger 만족.
  - auto consume.
  - combat 지속.
  - death/retreat/regroup.
  - 다음 NIGHT.

- 완료조건:

  - auto potion vertical slice PASS.
  - Food와 역할/데이터 경로 분리.
  - Tactical command 회귀 없음.

---

## FEATURE-WAVE-022 Inn / Recruitment Capacity

> 기존 Tavern/Inn/Roster/Recruitment를 재사용한다.
>
> 새 고용 시스템을 다시 만들지 않는다.
>
> 목표:
>
> **Inn progression → Hire/Roster capacity 증가 → Inn 개수/용량 제한 정책 연결**

---

## TASK-022 Inn Upgrade / Hire Capacity

- 상태: QUEUED

### TASK-022-1 Existing Recruitment Audit

- 상태: QUEUED

- 확인:

  - hire candidate.
  - roster capacity.
  - active mercenary count.
  - Inn/Tavern building identity.
  - building count.
  - UI.
  - cost.
  - save/load.

- 완료조건:

  - 기존 시스템 재사용 경계 명확.
  - duplicate recruitment framework를 만들 필요 없음.

### TASK-022-2 Inn Level / Capacity Data

- 상태: QUEUED

- 요구사항:

  - Inn upgrade level.
  - hire/roster capacity contribution.
  - Inn count 제한과 연결 가능.
  - exact level cost/capacity는 `DESIGN_TUNING`.
  - upgrade data-driven.
  - max cap이 문서에 있으면 그대로 사용.

- 금지:

  - 무제한 Inn spam.
  - 새로운 rarity/gacha system.
  - 후보 생성 알고리즘 전면 재작성.

- 완료조건:

  - level 변화.
  - capacity 변화.
  - cap enforcement.

### TASK-022-3 Inn Upgrade UI / Visual

- 상태: QUEUED

- 요구사항:

  - 기존 building interaction UI 확장.
  - level/capacity 표시.
  - upgrade 비용.
  - invalid reason.
  - 3D building visual은 prop/visual variation 정도만 허용.

- HUMAN_CHECK:

  - 업그레이드 결과가 이해 가능한지.
  - capacity 변화가 Roster UI에서 명확한지.

- 완료조건:

  - UI flow 정상.
  - HUMAN_CHECK만 남으면 DONE.

### TASK-022-4 Recruitment Capacity Regression

- 상태: QUEUED

- 검증:

  - 초기 capacity.
  - hire.
  - cap 도달.
  - upgrade.
  - 추가 hire.
  - building count policy.
  - remove/refund가 있다면 capacity 감소 안전성.
  - active Mercenary reference 안전.

- 완료조건:

  - Inn → recruitment capacity loop PASS.

---

## FEATURE-WAVE-023 Morale

> 핵심 설계:
>
> 강한 동료가 살아 있는 것은 전역적인 사기 이점이 된다.
>
> 의도적 희생 전략 자체를 시스템적으로 금지하지 않는다.
>
> 첫 vertical slice는 사기 수치/보너스의 존재와 생존자 연계를 검증한다.

---

## TASK-023 Mercenary Morale Vertical Slice

- 상태: QUEUED

### TASK-023-1 Morale State / Contributor Model

- 상태: QUEUED

- 요구사항:

  - Mercenary roster/active roster에서 morale contributor 계산.
  - 강한 동료의 기준이 기존 design/data에 있으면 그대로 사용.
  - 기준 수치가 없으면 기존 level/tier 등 power metadata를 활용하는 data-driven weight.
  - exact formula는 `DESIGN_TUNING`.
  - Ghost는 원본 생존자로 계산하지 않음.
  - morale state는 duplicate actor가 아닌 roster identity 기준.

- 완료조건:

  - contributor 변화 → morale 재계산.
  - death → 적절한 변화.
  - duplicate count 없음.

### TASK-023-2 Global Morale Bonus Hook

- 상태: QUEUED

- 요구사항:

  - 전역 보너스는 기존 combat/economy stat pipeline이 있으면 그곳에 최소 연결.
  - exact stat 종류가 문서에 없으면 임의로 여러 스탯을 추가하지 않는다.
  - 최소 1개의 확정 bonus hook만 구현하거나 이 subtask를 `NEEDS_DESIGN`.
  - base stat 영구 변조 금지.
  - modifier add/remove 안전.

- 완료조건:

  - morale increase/decrease가 modifier에 반영.
  - actor spawn/despawn 반복 시 누적 중복 없음.

### TASK-023-3 Morale UI / Regression

- 상태: QUEUED

- 요구사항:

  - current morale.
  - major contributor 확인.
  - bonus 확인.
  - NIGHT lethal death 후 변화.
  - DAY 복귀 후 일관성.

- HUMAN_CHECK:

  - 강한 동료를 지키는 가치가 UI에서 느껴지는지.
  - 수치가 과도하게 복잡하지 않은지.

- 완료조건:

  - morale vertical slice PASS.
  - HUMAN_CHECK만 남으면 DONE.

---

## FEATURE-WAVE-024 Threat / Wave Progression

> 핵심 설계:
>
> Threat는 장기적인 Wave 압력을 표현한다.
>
> 향후 Dungeon clear는 Threat/Wave를 지연시키는 효과를 가질 수 있다.
>
> Dungeon 자체는 이 Wave에서 구현하지 않는다.
>
> 먼저 Threat와 Wave schedule 기반 및 외부 감소 API를 만든다.

---

## TASK-024 Threat Gauge / Wave Scheduling

- 상태: QUEUED

### TASK-024-1 Threat State

- 상태: QUEUED

- 요구사항:

  - Threat current/max 또는 threshold model.
  - DAY/time progression과 연결.
  - exact growth rate는 `DESIGN_TUNING`.
  - pause/time scale과 일관.
  - save/load가 있으면 persistence.
  - UI signal/event.

- 완료조건:

  - deterministic growth.
  - clamp.
  - repeated DAY/NIGHT 안정.

### TASK-024-2 Wave Trigger / Delay Contract

- 상태: QUEUED

- 요구사항:

  - 기존 NIGHT enemy spawn과 연결.
  - Threat가 Wave schedule에 영향을 주는 최소 규칙.
  - 동일 NIGHT duplicate wave trigger 없음.
  - `reduce/delay threat` 외부 API 제공.
  - 향후 Dungeon clear가 이 API를 호출할 수 있음.
  - Dungeon placeholder gameplay를 구현하지 않음.
  - wave scaling 수치가 문서에 없으면 새로운 대규모 scaling table 생성 금지.

- 완료조건:

  - Threat 증가.
  - threshold/schedule trigger.
  - delay/reduce 호출.
  - 다음 wave timing 변화.
  - duplicate trigger 없음.

### TASK-024-3 Threat HUD

- 상태: QUEUED

- 요구사항:

  - Threat gauge.
  - 다음 위험 증가 방향을 직관적으로 표시.
  - countdown이 실제 schedule과 불일치하지 않게 함.
  - DAY/NIGHT UI 전환에서 유지.

- HUMAN_CHECK:

  - 플레이어가 "언제 위험해지는지" 읽을 수 있는지.
  - 화면을 지나치게 차지하지 않는지.

- 완료조건:

  - gauge 정상.
  - schedule과 UI 일치.
  - HUMAN_CHECK만 남으면 DONE.

### TASK-024-4 Threat / Wave Regression

- 상태: QUEUED

- 검증:

  - DAY progression.
  - threat increase.
  - NIGHT.
  - wave trigger.
  - delay/reduce.
  - next wave.
  - pause/1x/2x.
  - save/load가 있다면 persistence.
  - Gate/Tactical/Ghost 회귀.

- 완료조건:

  - Threat → Wave pressure vertical slice PASS.

---

## FEATURE-WAVE-025 Portal / Ghost Expansion

> `TASK-017`의 First Ghost Return을 현재 실제 entity category에 적용 가능한 구조로 확장한다.
>
> 새로운 entity category를 이 기능 때문에 가짜로 만들지 않는다.

---

## TASK-025 Portal Memory / Ghost Expansion

- 상태: QUEUED

- 핵심 규칙 LOCK:

  - eligible lethal death는 Portal 기억 대상이 될 수 있다.
  - 몬스터/동물/적대 NPC/아군 주민 등 실제 구현된 category에 확장 가능해야 한다.
  - Ghost는 1회 재등장.
  - Ghost death가 재귀 Ghost를 만들지 않음.
  - Mercenary Ghost는 가능한 범위에서 기존 스킬/특성 유지.
  - 의도적 희생 전략을 시스템적으로 차단하는 별도 anti-ghost mechanic을 추가하지 않는다.

### TASK-025-1 Eligibility / Identity Generalization

- 상태: QUEUED

- 요구사항:

  - TASK-017의 특정 Actor 의존 제거.
  - entity category 기반 eligibility.
  - identity snapshot.
  - source/death context.
  - one-return invariant.
  - 아직 존재하지 않는 animal/NPC system을 억지로 생성하지 않음.

- 완료조건:

  - 현재 존재하는 eligible category 지원.
  - unsupported category 안전 skip.
  - duplicate record 없음.

### TASK-025-2 Ghost Spawn Mix Integration

- 상태: QUEUED

- 요구사항:

  - existing Wave/Threat spawn과 충돌 없이 Ghost return mix 가능.
  - Ghost가 일반 enemy spawn budget을 어떻게 점유하는지는 기존 설계 우선.
  - exact ratio가 없으면 hardcoded random system을 만들지 말고 configurable queue insertion 정책 사용.
  - same candidate once only.
  - spawn failure recovery.

- 완료조건:

  - regular + ghost mixed NIGHT.
  - duplicate 없음.
  - wave 완료 조건 deadlock 없음.

### TASK-025-3 Ghost Identity Feedback

- 상태: QUEUED

- 요구사항:

  - 최소한 이름/category/origin을 확인 가능.
  - 과도한 lore UI를 새로 만들지 않음.
  - 전투 중 원본 identity가 의미 있는 경우 표시.
  - Death Ledger와의 연결을 debug/inspection 가능.

- HUMAN_CHECK:

  - 이전에 죽었던 존재가 돌아왔다는 인지가 가능한지.
  - UI clutter가 심하지 않은지.

- 완료조건:

  - feedback 정상.
  - HUMAN_CHECK만 남으면 DONE.

### TASK-025-4 Portal / Ghost Regression

- 상태: QUEUED

- 검증:

  - 여러 eligible death.
  - duplicate lethal signal.
  - cleanup/despawn.
  - candidate queue.
  - mixed wave.
  - one-return.
  - ghost death.
  - repeated nights.
  - Threat/Wave.
  - Death Ledger.
  - Mercenary Potion.
  - Morale contributor.
  - freed reference.
  - duplicate actor.

- 완료조건:

  - Portal/Ghost 현재 범위 PASS.
  - 무한 Ghost recursion 없음.

---

## TASK-POST3D-INT-001 Economy / Combat Integrated Vertical Slice

- 상태: QUEUED

- 설명: POST-3D에서 추가된 기능들이 각각 동작하는 것만으로 끝내지 않고 하나의 DAY/NIGHT 운영 루프로 연결되는지 확인한다.

- 통합 시나리오:

  1. 3D World 시작.
  2. Food stock 확인.
  3. Farm 건설.
  4. Farmer assign.
  5. Crop 생산.
  6. Raw edible 확보.
  7. Cooking 경로가 활성화된 경우 Meal 생산.
  8. Food consumption.
  9. Herb 확보.
  10. Potion 제작 경로가 활성화된 경우 Potion 준비.
  11. Inn/Roster 확인.
  12. Mercenary Potion 장착.
  13. Morale 확인.
  14. Threat 증가.
  15. NIGHT.
  16. Wave.
  17. Mercenary auto combat.
  18. Potion conditional auto consume.
  19. lethal death.
  20. Death Ledger.
  21. Morale update.
  22. DAY.
  23. Food consumption/production 반복.
  24. 다음 NIGHT.
  25. Ghost Return.
  26. Ghost death.
  27. 다음 NIGHT에서 동일 Ghost 재등장하지 않음.

- 핵심검증:

  - Player Avatar 직접 노동/전투 없음.
  - Player combat 없음.
  - Camera + Mouse 유지.
  - Food/Potion 역할 분리.
  - Farm production 중복 없음.
  - Worker duplicate 없음.
  - Mercenary duplicate 없음.
  - Potion multi-consume 없음.
  - Death Ledger duplicate 없음.
  - Ghost recursion 없음.
  - Threat duplicate wave 없음.
  - freed reference 없음.
  - stale navigation 없음.
  - UI click-through 없음.

- 완료조건:

  - 가능한 모든 활성 Feature가 하나의 연속 vertical slice에서 PASS.
  - 설계 미확정 때문에 비활성화된 optional path는 실패로 위장하지 않고 명시.
  - 기존 3D Migration regression 유지.

---

## TASK-POST3D-VIS-001 Feature Visual Polish

- 상태: QUEUED

- 설명: 새 기능이 placeholder debug object로만 남지 않도록 Quaternius 기반 최소 시각 연결을 수행한다.

- 대상:

  - Ghost.
  - Farm.
  - Crop.
  - Food/Meal UI visual.
  - Herb.
  - Potion.
  - Inn upgrade state 가능한 범위.
  - Threat gauge.
  - Farm/food production props.

- 원칙:

  - 동일 Quaternius 스타일 유지.
  - 새 외부 art ecosystem 도입 금지.
  - 기능 Scene과 visual child 분리.
  - top-down zoom-out silhouette 우선.
  - debug primitive가 최종 runtime에 과도하게 남지 않도록 정리.

- 필수 Screenshot:

  - DAY farm/worker.
  - DAY village with Food/Threat HUD.
  - NIGHT combat with Potion.
  - Ghost encounter.
  - zoom-out overview.

- HUMAN_CHECK:

  - 3D 전환 직후 화면보다 새 기능이 추가됐는데도 시각적 통일감이 유지되는지.
  - Farm/Herb/Ghost가 서로 구분되는지.
  - UI가 점점 복잡해져도 핵심 정보가 읽히는지.

- 완료조건:

  - screenshot set 존재.
  - broken material/animation 없음.
  - HUMAN_CHECK만 남으면 DONE.

---

## TASK-POST3D-REG-001 Full Overnight Regression

- 상태: QUEUED

- 설명: 밤샘 큐에서 수행된 모든 변경을 마지막으로 회귀 검증한다.

- 자동검증:

  - Main 3D smoke.
  - Camera pan/zoom.
  - Selection.
  - Building.
  - BuildingPlacement.
  - Wall/Gate.
  - Resource.
  - Lumberjack.
  - Miner.
  - Navigation.
  - Mercenary.
  - Enemy.
  - Tactical command.
  - Death Ledger.
  - First/expanded Ghost.
  - Food.
  - Farming.
  - Cooking 활성 경로.
  - Herb/Potion 활성 경로.
  - Inn capacity.
  - Morale 활성 경로.
  - Threat/Wave.
  - repeated DAY/NIGHT.
  - no duplicate actor.
  - no freed reference.
  - no stale navigation.
  - no ghost recursion.
  - no negative resource.
  - no duplicate wave.
  - no potion multi-consume.

- 정적검증:

  - parser error 없음.
  - missing scene/resource 없음.
  - missing asset import 없음.
  - duplicate Autoload 없음.
  - Runtime 2D gameplay path 신규 추가 없음.
  - temporary diagnostic files 없음.
  - destructive Git operation 없음.

- 중요:

  - 미실행 테스트를 PASS라고 기록하지 않는다.
  - 특정 Feature가 `NEEDS_DESIGN`으로 중단되었다면 이후 Feature가 독립적으로 실행 가능한지 판단하고, 안전하면 계속 진행한다.
  - `NEEDS_DESIGN` 기능을 억지로 추측 구현해서 전체 회귀를 통과시키지 않는다.
  - HUMAN_CHECK는 blocker가 아니지만 결과 목록에 남긴다.

- 완료조건:

  - 실행 가능한 전체 regression PASS.
  - blocker/NEEDS_DESIGN/HUMAN_CHECK 목록 정리.
  - 임시 파일 없음.

---

# DEFERRED FEATURE LOCK

> 아래 기능은 현재 프로젝트에서 후속 범위로 알려져 있지만, 이 밤샘 Queue에서는 구현하지 않는다.
>
> 이유:
>
> 현재 확정 설계 없이 AI가 독자적으로 구현하면 게임 구조 자체를 잘못 고정할 위험이 크다.
>
> - Dungeon 실제 gameplay.
> - Scout / Expedition 전체 시스템.
> - Equipment progression 전체.
> - 추가 Mercenary class.
> - 추가 Enemy archetype.
> - Boss / Siege.
> - Wall upgrade.
>
> 규칙:
>
> 1. 위 기능을 기존 Feature를 구현하기 위한 임시 우회 기능으로 추가하지 않는다.
> 2. marker/interface 정도가 이미 존재하면 보존한다.
> 3. Threat의 `reduce/delay` API처럼 향후 연결점은 허용하되 실제 Dungeon을 자동 생성하지 않는다.
> 4. First Ghost Return/Portal 확장을 위해 존재하지 않는 Animal/NPC/Dungeon 시스템을 임의 생성하지 않는다.
> 5. 이 목록은 `OVERNIGHT-STOP-FEATURES` 이후 별도 설계/Queue에서 다룬다.

---

## OVERNIGHT-STOP-FEATURES Final 종료 경계

- 상태: QUEUED

- 설명: 3D Migration + 안전하게 확정 가능한 후속 Feature Queue를 모두 처리한 뒤 자동화를 종료한다.

- 필수 확인:

  - CHECKPOINT-3D-MIGRATION DONE.
  - TASK-017 First Ghost Return 처리.
  - TASK-018 Food 처리.
  - TASK-019 Farming 처리.
  - TASK-020 Cooking 처리 또는 명시적 `NEEDS_DESIGN`.
  - TASK-021 Herb/Potion 처리 또는 설계 미확정 subtask 명시.
  - TASK-022 Inn Capacity 처리.
  - TASK-023 Morale 처리 또는 확정 bonus hook 부재 명시.
  - TASK-024 Threat/Wave 처리.
  - TASK-025 Portal/Ghost Expansion 처리.
  - TASK-POST3D-INT-001 처리.
  - TASK-POST3D-VIS-001 처리.
  - TASK-POST3D-REG-001 처리.

- 최종 기능 회귀:

  - Main 3D Runtime.
  - Top-down Camera Pan/Zoom.
  - Resource.
  - Building/Placement.
  - Worker/Navigation.
  - Wall/Gate.
  - Mercenary/Enemy auto combat.
  - Tactical command.
  - Death Ledger.
  - Ghost one-return.
  - Food consumption.
  - Farm/Raw ingredient.
  - Cooking 활성 경로.
  - Potion 활성 경로.
  - Inn/Recruitment capacity.
  - Morale 활성 경로.
  - Threat/Wave.
  - DAY/NIGHT 반복.

- 최종 안전성:

  - Player direct combat 없음.
  - Player Avatar 직접 노동 부활 없음.
  - 자유 Camera rotation 없음.
  - duplicate actor 없음.
  - duplicate DeathRecord 없음.
  - duplicate Ghost 없음.
  - Ghost recursion 없음.
  - negative resource 없음.
  - duplicate wave 없음.
  - potion multi-consume 없음.
  - freed reference 없음.
  - stale navigation 없음.
  - orphan scene/resource 없음.
  - parser/import error 없음.

- 최종 Visual 확인 자료:

  - 3D DAY village overview.
  - Worker zoom-in.
  - Farm.
  - Food/Threat HUD.
  - NIGHT tactical.
  - Potion combat.
  - Ghost encounter.
  - 최종 zoom-out overview.

- 임시 파일:

  - `_diag*`.
  - `_probe*`.
  - `_debug*`.
  - `_temp*`.
  - 모두 제거.

- 결과 보고:

  - DONE 목록.
  - `NEEDS_DESIGN` 목록.
  - `DESIGN_TUNING` 목록.
  - `HUMAN_CHECK` 목록.
  - 실패/미실행 테스트 목록.
  - 남은 known blocker.
  - 변경 파일 summary.
  - 새 Asset/license summary.
  - 마지막 regression 결과.

- 종료조건:

  - 실행 가능한 Queue 전부 처리.
  - 최종 regression 수행.
  - 결과 보고 작성.
  - 임시 파일 제거.
  - `DEFERRED FEATURE LOCK` 기능 미시작 확인.
  - **이 태스크 이후 신규 기능 자동 시작 금지.**
