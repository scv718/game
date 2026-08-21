# AI Task Queue

> TASK-013~015 Tactical Combat Vertical Slice 완료 이후 신규 실행 큐.
>
> 완료된 TASK-013~015 상세 이력은 이전 큐에 보존하며 이 파일에 복사하지 않는다.
>
> 현재 목표:
> Death Ledger → First Ghost Return → 실제 Wave 시스템 순서로 핵심 게임 루프를 확장한다.
>
> 상태: `QUEUED` / `IMPLEMENT` / `REVIEW` / `FIX` / `DONE` / `NEEDS_DESIGN`

---

# 공통 실행 규칙

> 1. `##` = 챕터/컨테이너, `###` = 실제 실행 태스크.
>
> 2. 실제 구현은 `### TASK-*` 단위로 파일 순서대로 실행한다.
>
> 3. 각 태스크 시작 시 `GAME_DESIGN.md`, `DEVELOPMENT_STATUS.md`의 **현재 태스크 관련 섹션만 우선 확인**하고 이후 실제 코드를 확인한다.
>
> 4. 문서 내용보다 현재 코드가 더 최신일 수 있으므로 구현 전 실제 코드/API/Scene 구조를 반드시 확인한다.
>
> 5. 범위 밖 시스템을 편의상 임의 구현하지 않는다.
>
> 6. 현재 태스크 완료에 반드시 필요한 최소 변경만 허용한다.
>
> 7. 기존 정상 동작 시스템의 대규모 리팩터링 금지.
>
> 8. Godot headless 테스트를 실제 실행한다.
>
> 9. 실행하지 않은 테스트를 PASS로 보고하지 않는다.
>
> 10. 테스트 PASS만으로 미감/체감이 검증되었다고 판단하지 않는다.
>
> 11. 미감/체감/플레이 감각은 `HUMAN_CHECK`에 남기고 코드/자동검증이 정상이라면 DONE 가능하다.
>
> 12. 요구사항 사이에 설계 공백 또는 기존 설계와 직접적인 충돌이 있으면 임의 결정하지 말고 `NEEDS_DESIGN`으로 중단한다.
>
> 13. 파괴적 Git 명령 금지.
>
> 14. 자동 commit / push 금지.
>
> 15. 기존 사용자 변경사항을 임의 revert하지 않는다.
>
> 16. 임시 진단 파일을 만들 수는 있으나 태스크 종료 전 반드시 제거한다.
>
> 17. `_diag*`, `_probe*`, `_debug*` 등 임시 파일이 남아 있지 않은지 종료 시 확인한다.

---

# 게임 핵심 규칙

> 1. 플레이어 캐릭터는 어떤 상황에서도 직접 전투하지 않는다.
>
> 2. Player에 공격, 무기, 공격 스킬, Damage Dealer 역할을 추가하지 않는다.
>
> 3. 핵심 전투 원칙:
>
> **전투는 자동, 판단은 플레이어가 한다.**
>
> 4. Mercenary가 실제 전투를 수행한다.
>
> 5. Player는 배치, 방어구역, 집결, 후퇴, Focus Target, Gate, 시간 제어 등 전략 판단만 수행한다.
>
> 6. 새로운 일은 플레이어가 직접 발견하고 시작한다.
>
> 7. 반복되는 일은 주민과 시설이 대신한다.

---

# Death / Ghost 핵심 규칙

> 1. 실제 게임플레이에서 죽은 생명체는 Death Ledger에 기록된다.
>
> 2. 향후 기록 대상:
>
> - Mercenary.
> - Worker / Villager.
> - Enemy.
> - Monster.
> - Animal.
> - Hostile NPC.
> - Elite.
> - Boss.
>
> 3. 현재 TASK-016에서는 실제 구현되어 있는 `MERCENARY`, `ENEMY`만 연결한다.
>
> 4. 사망 기록은 Actor 자체가 아니라 사망 시점의 독립 snapshot이다.
>
> 5. Actor가 despawn/free되어도 DeathRecord는 유지되어야 한다.
>
> 6. 실제 lethal death만 기록한다.
>
> 7. DAY cleanup, scene unload, spawner reset, 일반 despawn은 죽음이 아니다.
>
> 8. 동일 실제 죽음은 정확히 한 번만 기록한다.
>
> 9. 이름이 같은 존재라도 서로 다른 개체라면 서로 다른 기록이다.
>
> 10. 죽은 존재는 이후 Ghost Return 대상이 된다.
>
> 11. Ghost Return을 방지하거나 DeathRecord를 삭제하는 시스템은 존재하지 않는다.
>
> 12. Ghost는 원래 존재의 정체성을 유지한다.
>
> 13. Ghost가 다시 죽으면 해당 기존 DeathRecord가 RESOLVED 된다.
>
> 14. Ghost의 죽음은 새로운 DeathRecord를 생성하지 않는다.
>
> 15. Ghost가 Ghost를 또 생성하는 재귀 구조는 절대 허용하지 않는다.
>
> 16. NIGHT Day N에서 사망한 존재는 같은 NIGHT에 즉시 Ghost로 등장하지 않는다.
>
> 17. 최소 `eligible_day = N + 1`.
>
> 18. 실제 Ghost Spawn/Visual/Combat은 TASK-017에서 구현한다.

---

# 현재 World / Combat Lock

> 1. 오버월드는 128×128 logical map 구조를 유지한다.
>
> 2. logical construction grid는 16px 유지.
>
> 3. 현재 World Visual Composition을 기준으로 한다.
>
> 4. 이번 큐에서 신규 Asset migration을 수행하지 않는다.
>
> 5. 현재 Tiny Swords 에셋은 임시 상태 그대로 유지한다.
>
> 6. WEST = Main Threat / Main Portal / Main Battlefield.
>
> 7. 기본 Enemy 진입축은 WEST → EAST.
>
> 8. NORTH = Secondary Threat / Rift.
>
> 9. EAST = Royal Road / 외부 문명 방향이며 기본 Enemy Spawn이 아니다.
>
> 10. SOUTH = Production / Agriculture 방향이며 기본 Enemy Spawn이 아니다.
>
> 11. 기존 Wall / Gate / Navigation 구조를 유지한다.
>
> 12. Gate 상태 `CLOSED / OPEN / BREACHED`를 유지한다.
>
> 13. NIGHT Tactical Command 구조를 유지한다.
>
> 14. TASK-012 이후 검증된 월드 전체 크기/경계를 임의 변경하지 않는다.
>
> 15. 이번 큐에서 대규모 World 재배치 및 추가 Visual Composition Pass를 수행하지 않는다.

---

# 구현 범위 제어

> 다음 기능은 TASK 명세에 명시되어 있지 않는 한 선행 구현 금지:
>
> - 정식 WaveManager.
> - Wave progression.
> - Boss.
> - Siege Enemy.
> - 신규 Enemy archetype.
> - 신규 Mercenary class.
> - Food.
> - Cooking.
> - Potion.
> - Morale.
> - Equipment progression.
> - Farm 실제 생산 기능.
> - Dungeon 실제 기능.
> - Player combat.
> - Save/Load 전체 시스템.
> - Asset migration.
> - 대규모 UI polish.
>
> "나중에 필요할 것 같아서"라는 이유로 framework를 선행 구현하지 않는다.

---

# 테스트 규칙

> 1. 각 태스크별 신규 headless test를 작성하거나 기존 적절한 테스트를 확장한다.
>
> 2. 신규 테스트는 해당 태스크 요구사항을 직접 검증해야 한다.
>
> 3. 기존 테스트를 단순히 PASS시키기 위해 assertion 의미를 약화시키지 않는다.
>
> 4. 요구사항 변경으로 기존 테스트 수정이 필요할 경우 이유를 구현기록에 남긴다.
>
> 5. flaky test가 발견되면 기존부터 존재하던 문제인지 현재 변경에 의해 발생한 문제인지 구분한다.
>
> 6. 테스트 우회용 production API 추가 금지.
>
> 7. 테스트 종료 후 Autoload / time scale / spawned actor / temporary state가 다음 테스트에 누수되지 않도록 한다.
>
> 8. freed instance reference 오류가 없어야 한다.
>
> 9. 반복 DAY/NIGHT cycle에서 duplicate actor/reference 누수가 없어야 한다.
>
> 10. 최신 통합 테스트와 smoke test를 회귀 검증에 포함한다.

---

# 리뷰 규칙

> 1. 구현자와 리뷰어의 역할을 구분한다.
>
> 2. 리뷰어 내부 판정은 `LGTM` / `FIX` / `HUMAN_CHECK` 등을 사용할 수 있다.
>
> 3. 리뷰어 판정 문자열과 Queue의 `상태:` 값은 서로 다른 개념이다.
>
> 4. `상태: REVIEW`는 리뷰 진행 중 정상 상태이며, REVIEW라는 이유 자체를 FIX 사유로 판단하지 않는다.
>
> 5. 리뷰어는 구현/요구사항/테스트의 실제 문제만 FIX 사유로 제시한다.
>
> 6. 상태 전환은 자동화 Supervisor의 책임이며 리뷰어가 상태값 자체를 요구사항으로 평가하지 않는다.
>
> 7. 코드와 테스트가 정상이고 남은 항목이 미감/플레이 감각뿐이면 `HUMAN_CHECK`를 남기고 LGTM 가능하다.
>
> 8. 동일한 잘못된 리뷰 사유를 반복해 무한 FIX loop를 만들지 않는다.

---

## TASK-016 Death Ledger

- 상태: QUEUED

- 설명: 실제 전투에서 사망한 Mercenary/Enemy의 정체성과 전투 정보를 Actor 생명주기와 분리된 Death Ledger에 기록한다. 이후 Ghost Return 시스템이 이 기록을 원본 데이터로 사용한다.

- 핵심:

  - 실제 lethal combat death만 기록.

  - Actor reference가 아닌 순수 snapshot 데이터 저장.

  - 동일 실제 죽음 중복 기록 금지.

  - NIGHT Day N 사망 → 최소 Day N+1부터 Ghost Return 대상.

  - Ghost 사망이 새로운 DeathRecord를 만들지 않도록 재귀 기록 방지 구조 준비.

- 유지:

  - 기존 MercenaryData / MercenaryRoster.

  - 기존 EnemyActor / FirstEncounterSpawner.

  - TASK-014 Combat death/cleanup 흐름.

  - TASK-015 Tactical Combat.

  - WEST → EAST Main Combat 방향.

  - 현재 World Visual Composition.

- 금지:

  - Ghost Actor 실제 구현.

  - Ghost Spawn.

  - Ghost Shader/Visual.

  - 정식 WaveManager.

  - Portal 시스템 확장.

  - Food/Potion/Morale.

  - Dungeon.

  - Save/Load 전체 시스템.

  - 신규 Mercenary/Enemy archetype.

  - Asset 교체.

### TASK-016-1 DeathRecord Data Model

- 상태: DONE
- 피드백: 17개 데이터 필드 정확 구현, Actor reference/Node reference 저장 없음, metadata mutable 참조 방지(복사), to_snapshot/from_snapshot round-trip 정상, set_status 유효값 검증, DeathPhase 자체 enum으로 GameTime 의존성 없음. 테스트 57건 PASS, 회귀 5개 테스트 PASS. 코드 스타일이 기존 MercenaryData/WorkerData와 일관. 임시 파일 없음.

- 설명: 사망한 존재의 정체성과 Ghost Return에 필요한 정보를 Actor와 독립된 snapshot으로 저장하는 DeathRecord 데이터 모델을 구현한다.

- 최소 데이터:

  - `record_id`.

  - `source_uid`.

  - `source_kind`: `MERCENARY` / `ENEMY`.

  - `display_name`.

  - `class_or_type`.

  - `level`.

  - `max_hp`.

  - `attack_damage`.

  - `attack_interval`.

  - `move_speed`.

  - `death_day`.

  - `death_phase`.

  - `death_position`.

  - `status`: `PENDING` / `ACTIVE` / `RESOLVED`.

  - `eligible_day`.

  - `resolved_day`.

  - `metadata`.

- 규칙:

  - Actor/Node reference 저장 금지.

  - NodePath/Callable/SceneTree reference 저장 금지.

  - 사망 시점 값을 copy/snapshot.

  - Actor가 free되어도 record 유지.

  - mutable object를 그대로 참조하지 않는다.

  - 향후 Worker/Animal/Boss 등을 추가할 수 있도록 source_kind 확장 가능 구조.

  - temporary combat state는 저장하지 않는다.

- 저장하지 않는 값:

  - current target.

  - FSM state.

  - temporary buff.

  - Food/Potion 효과.

  - Morale temporary modifier.

- 완료조건:

  - Actor 없이 DeathRecord 단독 생성/조회 가능.

  - serialize 가능한 순수 데이터 구조.

  - 원본 Actor 제거 후에도 모든 snapshot 값 유지.

### TASK-016-2 DeathLedger Autoload + Record State

- 상태: DONE
- 피드백: 10개 API, 3개 시그널, 상태 전환 정책(RESOLVED 보호, 멱등, 안전 no-op), 복사본 반환, eligible_day 자동 계산이 모두 요구사항대로 구현됨. 테스트 83건 PASS, 회귀 PASS. 임시 파일 없음.

- 설명: DeathRecord의 생성/조회/상태 변경을 담당하는 최소 DeathLedger 전역 서비스를 구현한다.

- 최소 API:

  - `record_death(snapshot)`.

  - `get_record(record_id)`.

  - `get_all_records()`.

  - `get_pending_records()`.

  - `get_active_records()`.

  - `get_resolved_records()`.

  - `mark_active(record_id)`.

  - `mark_pending(record_id)`.

  - `resolve(record_id, day)`.

  - `has_record_for_source(source_uid)`.

- Signals:

  - `record_added`.

  - `record_status_changed`.

  - `record_resolved`.

- 상태:

  - `PENDING` = Ghost Return 대기.

  - `ACTIVE` = 해당 record의 Ghost가 현재 월드에 존재.

  - `RESOLVED` = Ghost가 처치되어 영구 종료.

- Eligibility:

  - NIGHT Day N에서 사망하면 `eligible_day = N + 1`.

  - 같은 NIGHT 즉시 재등장 금지.

- 요구사항:

  - 상태 변경 API는 존재하지 않는 record에 대해 안전하게 처리.

  - RESOLVED record를 실수로 ACTIVE/PENDING으로 되돌리지 않도록 명확한 정책 적용.

  - query 결과를 외부에서 수정해 Ledger 내부 상태를 우회 변경하지 않도록 주의.

- 중요:

  - DeathLedger는 Ghost를 spawn하지 않는다.

  - DeathLedger는 Portal/Wave를 제어하지 않는다.

  - SaveGame 시스템 구현 금지.

- 완료조건:

  - record 생성/조회 정상.

  - PENDING→ACTIVE→PENDING 전환 가능.

  - PENDING/ACTIVE→RESOLVED 가능.

  - Day/Night 전환 후에도 Autoload 내부 record 유지.

### TASK-016-3 Mercenary / Enemy Combat Death Integration

- 상태: QUEUED

- 설명: TASK-014에서 구현된 실제 Mercenary/Enemy lethal death 흐름을 DeathLedger에 연결한다.

- Mercenary:

  - 실제 HP 0 이하 사망 시 record 생성.

  - MercenaryData의 정체성/전투 stat snapshot 사용.

  - 기존 `MercenaryData.alive = false` 유지.

  - 기존 Actor cleanup/roster freed-reference 제거 유지.

- Enemy:

  - 실제 combat damage로 HP 0 이하 사망한 경우 record 생성.

  - 동일 Enemy type이라도 각 Actor는 독립 `source_uid` 사용.

- 기록 금지:

  - DAY cleanup.

  - FirstEncounterSpawner despawn.

  - scene unload.

  - 테스트 cleanup.

  - navigation recovery.

  - 단순 queue_free.

- 요구사항:

  - DeathLedger 연결 때문에 기존 death/cleanup 순서를 깨뜨리지 않는다.

  - `source_uid`는 `display_name`과 독립.

  - 이름이 같은 두 Mercenary/Enemy도 서로 다른 죽음으로 기록 가능.

  - died signal과 `die()` 내부 양쪽에서 중복 record가 생성되지 않도록 ownership을 명확히 한다.

- 완료조건:

  - Mercenary 실제 사망 → MERCENARY record 정확히 1개.

  - Enemy 실제 사망 → ENEMY record 정확히 1개.

  - cleanup/despawn → record 0개.

  - 기존 TASK-014 death cleanup 회귀 PASS.

### TASK-016-4 Duplicate / Recursive Death Guard

- 상태: QUEUED

- 설명: 동일 실제 죽음의 중복 기록과 향후 Ghost 사망의 재귀 DeathRecord 생성을 방지한다.

- Duplicate:

  - `source_uid` + 실제 death event 기준 중복 방지.

  - 동일 died signal 중복 전달에도 record 1개.

  - `display_name` 기준 dedupe 금지.

- Ghost 준비:

  - 향후 Actor/source에 `NORMAL / GHOST`를 판별할 최소 구조 제공.

  - 또는 동등하게 명확한 ghost source 판별 구조 사용 가능.

- 핵심 규칙:

  - Normal Mercenary/Enemy death → DeathRecord 생성.

  - Ghost death → 신규 DeathRecord 생성 금지.

  - Ghost death → 기존 record RESOLVED 처리는 TASK-017에서 구현.

- 중요:

  - Ghost 전체 architecture를 선행 구현하지 않는다.

  - `is_ghost` 하나 때문에 범용 Entity Framework를 새로 만들지 않는다.

  - 현재 구조에 가장 작은 확장 지점을 사용한다.

- 완료조건:

  - 동일 source death 중복 호출에도 record 1개.

  - 서로 다른 동일 타입 Enemy는 각각 record 생성.

  - ghost source로 가정한 death는 신규 record 생성되지 않음.

### TASK-016-5 Minimal Death Ledger View

- 상태: QUEUED

- 설명: 실제 플레이 중 Death Ledger 기록을 확인하기 위한 최소 검증 UI를 추가한다. 최종 Memorial/Archive UI가 아니다.

- 표시:

  - display_name.

  - source_kind.

  - death_day.

  - status.

- 예시:

  - `Mercenary A / MERCENARY / Day 3 / PENDING`.

  - `Enemy 004 / ENEMY / Day 3 / PENDING`.

- 요구사항:

  - 필요 시 열고 닫을 수 있는 최소 Panel.

  - 현재 좌상단 HUD와 NIGHT Tactical Command UI를 과도하게 가리지 않음.

  - record 삭제 버튼 없음.

  - purification/prevention 기능 없음.

  - Ghost Return을 막는 기능 없음.

  - Ledger signal을 이용해 신규 record/status 변경 시 정상 refresh.

  - Panel을 닫고 다시 열어도 현재 Ledger 상태를 다시 조회해 표시.

- 중요:

  - Death Ledger UI는 정보 확인용.

  - 최종 Memorial/Archive 디자인이 아니다.

  - 이번 태스크에서 대규모 UI polish 금지.

- 완료조건:

  - 실제 사망 후 UI에서 record 확인 가능.

  - Day/Night 전환 후에도 표시 유지.

  - HUD/Tactical UI 회귀 없음.

### TASK-016-6 Death Ledger 통합 검증

- 상태: QUEUED

- 설명: Mercenary/Enemy 실제 전투 사망부터 DeathRecord 생성/유지까지 Death Ledger 전체 흐름을 하나의 headless 시나리오로 검증한다.

- 시나리오:

  1. DAY 시작.

  2. DeathLedger 초기 상태 확인.

  3. Mercenary 고용.

  4. WEST defense assignment.

  5. NIGHT 전환.

  6. Mercenary Actor spawn.

  7. WEST Enemy encounter spawn.

  8. 실제 auto combat.

  9. Enemy lethal death.

  10. ENEMY DeathRecord 생성 확인.

  11. 동일 Enemy 중복 record 없음.

  12. Mercenary lethal death.

  13. MERCENARY DeathRecord 생성 확인.

  14. `MercenaryData.alive == false` 확인.

  15. Actor cleanup/freed-reference 정상 확인.

  16. 두 record `status == PENDING` 확인.

  17. `eligible_day == death_day + 1` 확인.

  18. DAY 전환.

  19. DAY cleanup이 신규 DeathRecord를 생성하지 않음 확인.

  20. 기존 DeathRecord 유지 확인.

  21. 다음 NIGHT 전환.

  22. 기존 record 유지 확인.

  23. 아직 Ghost가 spawn되지 않았는지 확인.

- 추가검증:

  - 같은 이름의 서로 다른 Enemy는 별도 record.

  - duplicate source_uid 차단.

  - get_all_records.

  - get_pending_records.

  - get_active_records.

  - get_resolved_records.

  - mark_active.

  - mark_pending.

  - resolve.

  - RESOLVED 상태 보호.

  - ghost source 신규 death 기록 차단.

  - Actor reference/Node reference가 record 내부에 없는지 확인.

- 회귀:

  - `smoke_test`.

  - Worker / Navigation 핵심 회귀.

  - TASK-012 World.

  - TASK-013 Wall/Gate.

  - TASK-014 Combat.

  - TASK-015 Tactical Combat Vertical Slice.

  - World Visual Composition.

- HUMAN_CHECK:

  - Enemy 사망 직후 Ledger 표시가 자연스러운지.

  - Mercenary 이름/정체성이 사망 후에도 올바르게 남는지.

  - Death Ledger Panel이 플레이 화면을 과도하게 가리지 않는지.

  - 여러 record가 쌓였을 때 최소한 확인 가능한지.

- 완료조건:

  - 실제 lethal death만 기록.

  - Mercenary/Enemy 각각 정확히 1 record.

  - cleanup/despawn 오기록 없음.

  - Day/Night 이후 record 유지.

  - duplicate/recursive guard 정상.

  - Ghost 실제 기능 미구현.

  - 자동검증 PASS.

  - 기존 핵심 회귀 PASS.

---

## OVERNIGHT-STOP-6 TASK-016 종료 경계

- 상태: QUEUED

- 설명: TASK-016 Death Ledger 완료 후 Ghost Return 또는 다른 신규 시스템을 임의로 시작하지 않고 종료한다.

- 확인:

  - TASK-016-1~6 상태 확인.

  - DeathRecord/DeathLedger 정상.

  - Mercenary/Enemy lethal death 연동 정상.

  - cleanup 오기록 없음.

  - duplicate guard 정상.

  - recursive Ghost death guard 준비 정상.

  - Day/Night 이후 record 유지.

- 금지 시스템 미시작 확인:

  - GhostActor.

  - GhostFactory.

  - GhostReturnSpawner.

  - Ghost Shader.

  - Ghost Combat.

  - 실제 Portal Return.

  - WaveManager.

  - Wave progression.

  - Boss.

  - Food/Potion/Morale.

  - Dungeon.

  - Asset 교체.

- 임시 파일:

  - `_diag*`.

  - `_probe*`.

  - `_debug*`.

  - 기타 태스크용 임시 스크립트.

  - 종료 시 모두 제거 확인.

- 종료 회귀:

  - smoke.

  - TASK-015 Tactical Combat Vertical Slice.

  - TASK-016 Death Ledger 통합 테스트.

- 다음 예정:

  - TASK-017 First Ghost Return.

  - 첫 Ghost Vertical Slice는 사망한 Mercenary가 다음 eligible NIGHT에 hostile Ghost로 귀환하는 흐름부터 구현.

  - Food/Potion/Morale보다 Ghost Vertical Slice를 우선한다.

- 완료조건:

  - TASK-016 전체 완료.

  - 금지 시스템 미시작.

  - 임시 파일 없음.

  - 종료 회귀 PASS.

  - 다음 TASK 자동 시작 금지.