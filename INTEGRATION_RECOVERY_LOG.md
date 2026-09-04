# Integration Recovery Log

Baseline: `f4f9933c7a35fc393a0e46bd8dc58e0716ffeebe`
Worktree: `D:/game-wt/integration-recovery`

## TASK-017

- Source worktree: `D:/game-wt/f-ghost`
- Candidate files selected: `scripts/ghost_return_candidate.gd`, `scripts/ghost_return.gd`, `scripts/ghost_actor_3d.gd`, `scripts/ghost_spawner_3d.gd`, `scenes/ghost_3d.tscn`, the required `enemy_actor_3d.gd`/`main_3d.tscn`/`project.godot` deltas, and `tests/task0171_test.gd` through `tests/task0174_test.gd`.
- Discarded candidates: visual capture scripts/images and unrelated task files; `death_record.gd` and `death_ledger.gd` were unchanged against the integration baseline and were not duplicated.
- Test result: `task0171_test.gd` executed with Godot 4.7.1. Assertions for the candidate/ledger contract passed, but the test ended `TASK0171_RESULT=FAIL` at `main scene intact`.
- Blocker: the clean `f4f9933` checkout lacks ignored generated Tiny Swords assets required by the existing main scene (`grass_tile.png`, `path_tile.png`, tree/rock/building textures). Godot stderr also reports dependent scene/script parse errors. The candidate source itself was not treated as PASS.
- Commit hash: none; no TASK/System commit is created until the required test and relevant regression pass.
- Dependency status: TASK-017 remains blocked. TASK-018 onward must not be integrated as a false-success chain until the baseline asset dependency is resolved or the test is reconstructed to isolate the tested contract without changing game rules.

No other worktree was modified. No merge, cherry-pick, reset, clean, deletion of candidate production files, or auto_lane restart was performed.

## Baseline Health Verification

- Temporary worktree: `D:/game-wt/baseline-health-f4`
- Source: pristine detached `f4f9933c7a35fc393a0e46bd8dc58e0716ffeebe`; no TASK-017 files or integration changes.
- Command: Godot 4.7.1 headless `--path D:/game-wt/baseline-health-f4 --script tests/smoke_test.gd`.
- Observed stdout: `PASS: main.tscn loads`, `FAIL: lumberjack present`, `FAIL: trees present (0)`.
- Observed stderr: repeated pre-existing baseline parse errors such as missing `WorkerData`/`MercenaryData` class declarations in dependent scripts. The bounded 15-second run did not exit, so it was terminated as a timeout after recording output.
- Result: pristine baseline is not healthy; this is `PREEXISTING_BASELINE_FAILURE` for baseline smoke health, not evidence of `TASK-017_REGRESSION`.
- Qualification: the exact `task0171` `main scene intact` failure cannot be replayed on pristine f4 because TASK-017's `GhostReturn` classes/autoload are intentionally absent. The integration failure also emitted Tiny Swords/texture dependency errors after asset import, while pristine smoke's immediately observed failures were script-cache/class-load failures. Therefore “same failure” is confirmed at the baseline-health level, but not as byte-for-byte identical error output.
- Asset provenance: the Tiny Swords/generated and Tiny Swords texture files exist physically in `D:/game`, `D:/game-wt/visual`, `visual2`, `building`, `worker`, `combat`, `f-ghost`, and the integration worktree only because they are ignored by `.gitignore` (`assets/tiny_swords/`). `git ls-files` and `git log --all -- assets/tiny_swords` show no Git provenance. They are source assets in working directories, not canonical `.import` production provenance. Generated `.import` files are cache artifacts and are excluded from canonical selection.
- Script provenance: `scripts/worker_data.gd`, `scripts/mercenary_data.gd`, and `scripts/decoration.gd` are tracked at f4, but the main working tree has later uncommitted variants. The pristine smoke class-load failure must not be repaired by copying main's dirty files wholesale.
- Recovery disposition: `f4f9933 -> BASELINE-REPAIR -> TASK-017`. TASK-017 remains `SOURCE_VALIDATED / WAIT_BASELINE_REPAIR`, not INTEGRATED or DONE. No TASK-017 commit was created.

## BASELINE-REPAIR audit

### Smoke contract

`tests/smoke_test.gd` is `LEGACY_SMOKE_CONTRACT`. Its history points to `9bd6c3a`
and `993bf11`, and it explicitly loads `res://scenes/main.tscn`, expects 2D
`lumberjacks`, `interactable` trees, `TileMapLayer`, and 2D sprite animations.
At f4, `project.godot` selects `res://scenes/main_3d.tscn` as the runtime main
scene, and f4 contains the merged 3D building/worker/combat/visual foundation.
The old smoke test must not be used to define or repair the 3D baseline.

Proposed canonical health contract: run the existing committed 3D integration
tests (`task3dint0011_test.gd` / `task3dint0012_test.gd` / `task3dint0013_test.gd`)
against `main_3d.tscn`, plus a bounded boot/parser/import check. Required checks
are main_3d load, no parser/import errors, one input/camera/navigation owner,
3D worker/mercenary/enemy lifecycle, existing Control UI wiring, DAY/NIGHT
transition, and no runtime Player combat actor. No test was changed in this phase.

### Tiny Swords classification

Raw Tiny Swords pack files are `EXTERNAL_ASSET_BOOTSTRAP_REQUIRED`: `.gitignore`
and `tools/download_tiny_swords.ps1` explicitly document Pixel Frog's no-redistribution
policy and local installation under `assets/tiny_swords/`. The repository already
contains the deterministic bootstrap script and local license note workflow.
The same required raw files were found in D:/game, visual, visual2, building,
worker, combat, and f-ghost; representative SHA-256 hashes are identical across
those copies: `grass_tile.png` begins `A9EB6E36BC0CD9C`, `path_tile.png` begins
`E8E9C12D482D4B5`, `deco_rock1.png` begins `6C0CEE986789A79`, and Tree1.png begins
`EE3F285F9928429`.

The `generated/` derivatives are `GENERATED_ASSET`, not source provenance:
`grass_tile.png` is cropped by `download_tiny_swords.ps1` and `path_tile.png` /
decorative crops are produced by the checked-in generation tools. `.import`
files are Godot cache artifacts and are not canonical source. A fresh worktree
must run the checked-in Tiny Swords bootstrap (with the required external license
rights) and the generation tools; it must not copy dirty main or commit the pack.
There is no Git commit history for `assets/tiny_swords`.

### WorkerData / MercenaryData class-load

Direct load diagnostic in the pristine temporary worktree reported:
`WORKER_LOAD=OK`, `WORKER_CLASS=WorkerData`, `MERCENARY_LOAD=OK`, and
`MERCENARY_CLASS=MercenaryData`. The declarations are present in tracked f4
source. Therefore these are not confirmed `PRODUCTION_PARSE_ERROR`s in the
source files themselves.

The same run emitted dependent roster parse errors because project startup
autoloads were parsed before the generated Godot global class cache had settled.
Bounded headless editor startup did not exit within 10 seconds, so it was not
hidden by increasing a timeout. Classification: `GODOT_BOOTSTRAP_REQUIRED` plus
`LEGACY_TEST_EXECUTION_METHOD` for tests that invoke the project before class
cache/import bootstrap. The old smoke test additionally targets 2D nodes and is
not a valid 3D health gate.

### 3D commit graph / baseline candidate

The 3D commits are already ancestors of f4 through the committed merge chain:

`TASK-3D-WRK-001 (5dfc7b5) -> 948cc0b -> TASK-3D-CMB-001 (1e4c3c6) ->
9071bf8 -> TASK-3D-VIS-001 (db8c462) -> b566922 -> f4f9933`.

`TASK-3D-BLD-001 (abeefd7)` is also already contained in the f4 graph. The
building/worker/combat/visual worktree tips are behind f4, not unique commits
that need to be merged into it. Their clean status does not represent a missing
f4 integration commit. Thus no additional migration commit is baseline-required
at this point; the missing reproducibility contract is the external Tiny Swords
bootstrap and Godot import/class-cache bootstrap.

### BASELINE-REPAIR disposition

Recommended order:

1. retain f4 as the code baseline;
2. document/run external Tiny Swords bootstrap and deterministic generated-asset steps;
3. perform bounded Godot editor/import bootstrap and verify global class cache;
4. replace the legacy 2D smoke gate with a separately named 3D health contract;
5. rerun the committed 3D integration health suite;
6. only then revalidate TASK-017.

Minimum health gate after repair: `main_3d.tscn` boots with exit 0, stdout has
an explicit PASS result, stderr has no parser/import/resource errors, and the
3D integration checks pass. TASK-017 can return to integration validation only
after that gate passes and its feature-specific Candidate/Ledger plus Ghost
spawn regressions pass. TASK-017 remains `SOURCE_VALIDATED / WAIT_BASELINE_REPAIR`.

## Repository-wide salvage integration

The baseline bootstrap and 3D health gate made the recovery worktree runnable.
The legacy 2D smoke test was not used as a production contract. Raw Tiny Swords
files remain an external, ignored runtime dependency and are not part of any
commit.

| System | Canonical source | Discarded/secondary candidate | Verification | Commit |
|---|---|---|---|---|
| BASELINE-3D-HEALTH | tracked f4 3D runtime + existing bootstrap tools | legacy 2D smoke contract | baseline health PASS | `756c560` |
| FOOD | `f-food` VillageResources/PopulationConsumption | wholesale Food-system rewrite | 0181-0184 PASS | `9436c19` |
| FARM | `f-farm` | generated captures/logs | 0191-0194 PASS | `eeef383` |
| COOKING | `f-cooking` with Food/Meal HUD integration | overwriting Food HUD | 0201-0204 PASS | `1c9d350` |
| POTION | full `f-potion` TASK-021 service/API | minimal `a4d2707` service; its 0275 test retained later | 0211-0214 PASS | `61a08ae` |
| INN | `f-inn` data/roster/UI owner | aggregate alternate UI implementation | 0221-0224 PASS | `e43148c` |
| MORALE | `f-morale` | no duplicate stat owner | 0231-0233 PASS | `238d87a` |
| THREAT | `e-threat2` WaveManager strict superset + common ThreatSystem | `f-threat` base WaveManager | 0241-0244 PASS | `bdf979b` |
| GHOST source | `f-ghost` TASK-017 source | none at source-validation point | 0171-0174 PASS before downstream replacement | `bbe8638` |
| PORTAL/GHOST | downstream `f-portal` DeathLedger + GhostSpawnMix owner | TASK-017-only GhostReturn/GhostSpawner duplicate | 0251-0254 PASS | `53c9849` |
| EXPEDITION | `e-expedition` | no competing implementation found | 0261-0264 PASS | `f06e6a0` |
| DUNGEON 0271-0275 | `bd18c89` runtime/preparation + `a4d2707` forensic 0275 test | legacy `task0275_test.gd`; dummy 0276-0278 | 0271-0275 PASS | `dcb1fb5` |
| THREAT/DUNGEON API | `e-threat2` | corrupted 0283 test loading nonexistent `res://src` files | 0281-0282 PASS | `8735610` |
| 3D visual salvage | identical aggregate runtime candidates in main/visual worktrees | unverified TASK-037 building-upgrade changes | baseline/main load PASS | `eed1c7b` |

### Integration repairs and test reconstruction

- TASK-019-2 waited for an extra 4,000-frame post-reassign production cycle
  outside its assignment/cleanup contract. The reconstructed test retains the
  one- and two-farmer production assertions and verifies the re-created actor
  after a bounded stabilization. Actual result: exit 0, `TASK0192_RESULT=PASS`.
- TASK-022-1 froze the worker candidate count at four although TASK-019 had
  canonically added two farmers. It now verifies preservation of the four
  original identities while allowing downstream candidates.
- TASK-022-3 exposed a real integration display defect: max-level upgrade cost
  was empty rather than the specified unavailable marker. The canonical
  f-inn display path uses `비용: -`.
- TASK-023-3 initially looped on a null MoraleSystem because production files
  had been recovered without scene/UI wiring. The f-morale owner was merged
  into the current main/HUD scenes without removing Ghost.
- TASK-024 HUD wiring was merged into the Food/Meal/Morale HUD rather than
  replacing it. `e-threat2` was selected because its WaveManager is a strict
  API superset used by TASK-028.
- TASK-025 supersedes the TASK-017-only GhostReturn queue with DeathLedger as
  authoritative candidate owner. GhostSpawnMix consumes the existing wave
  budget and the TASK-024 WaveManager remains the sole NIGHT trigger owner.
- The original TASK-017 tests directly imported the superseded
  GhostReturnCandidate/GhostReturn owner and became invalid after TASK-025.
  They were reconstructed against the current DeathLedger/GhostSpawnMix
  contract. Post-Portal results are 0171-0174 exit 0 / PASS; 0173 emits only
  a bounded scene-teardown leak warning.
- TASK-026-3 was updated to provision the already-canonical Inn capacity for its
  ten independent mercenary fixtures. The production Expedition owner was not
  changed.
- TASK-027-5 uses the existing full PotionData/MercenaryPotionService and
  MercenaryActor hooks. Food remains preparation-only, empty/false conditions
  consume zero, true consumes one, repeated trigger is guarded, and DeathRecord
  excludes temporary potion/combat state.

### Final health evidence

Godot 4.7.1 was used for all runs. Headless editor bootstrap exited 0 and
registered new global classes. Main project load exited 0. The final representative
suite was run after all committed production changes:

- `baseline_3d_health_test.gd`: exit 0, PASS.
- `task0184`, `task0194`, `task0204`, `task0214`, `task0224`,
  `task0233`, `task0244`, `task0254`, `task0264`, `task0275`,
  and `task0282`: exit 0, PASS.
- Some scene-instantiating tests and bounded main shutdown emit only Godot
  teardown RID/ObjectDB leak warnings; no parser, missing-resource, or runtime
  script error was present in the final representative suite.

The subsequent full 017-028 test pass executed all 46 retained tests with no
timeout and all 46 result markers PASS. A separate stderr audit then caught two
false-positive legacy behaviors that marker-only gating had hidden:

- `task0272` indexed an empty scene group and aborted before setting failure;
  it now resolves/instantiates the canonical preparation UI safely and
  provisions TASK-022 Inn capacity for its five fixtures.
- `task0274` could execute stale cached bytecode while reporting a compile
  error from `tactical_command_ui.gd` direct autoload identifiers. The UI now
  resolves the existing GameTime/MercenaryRoster owners from `/root`, without
  changing command values or behavior.

Both tests were rerun after editor bootstrap and now reach their PASS result
without SCRIPT ERROR or parse error. Legacy TASK-015 tests still assert the old
2D floor dimensions and exact 2D rally coordinates; those failures are
`LEGACY_SMOKE_CONTRACT`, not a 3D tactical regression.

### Remaining blockers / baseline status

- No valid TASK-027-6/7/8 implementation exists in the audited worktrees.
  Their e-dungeon tests are dummy booleans/always-PASS and were not imported.
  Death/retreat/party-wipe outcome arbitration, clear reward exactly-once, and
  full return integration therefore remain unproven.
- The e-threat2 TASK-028-3 test is legacy-corrupted and preloads nonexistent
  `res://src/Threat.gd` and `res://src/Dungeon.gd`; it was removed from the
  candidate. 0281/0282 verify the authoritative Threat API, but no recovered
  Dungeon outcome owner calls it end-to-end.
- Tiny Swords remains `EXTERNAL_ASSET_BOOTSTRAP_REQUIRED`; a fresh checkout
  requires the documented licensed bootstrap/generation step.
- Consequently HEAD is a reproducible recovery candidate for the recovered
  017-0275 and 0281-0282 scope, but it is **not yet eligible** for the
  `INTEGRATION-BASELINE-V1` tag. No tag was created and auto_lane remains
  stopped.
