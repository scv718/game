# Worktree Cleanup Candidates

> Read-only audit refreshed: 2026-09-04
>
> Canonical main: `69967151ebd690de3735616851c0a299d742b0a1`
>
> No worktree was removed or modified. Unique commits are `ahead/behind`
> relative to canonical main. Untracked production excludes `.godot`,
> `.import`, and generated `.uid` cache files.

| Worktree | Branch | HEAD | Dirty | Unique | Untracked prod | Related TASK/System | Classification | Reason |
|---|---|---|---|---|---:|---|---|---|
| `D:\game-wt\baseline-health-f4` | detached | `f4f9933c` | yes | 0/22 | 0 | baseline forensic | KEEP_PRESERVATION | Pristine baseline reproduction; generated UID state only. |
| `D:\game-wt\building` | `ai/3d-building` | `abeefd72` | no | 0/43 | 0 | TASK-3D-BLD-001 | REMOVE_SAFE | Clean and integrated in main. |
| `D:\game-wt\combat` | `ai/3d-combat` | `1e4c3c65` | no | 0/43 | 0 | TASK-3D-CMB-001 | REMOVE_SAFE | Clean and integrated in main. |
| `D:\game-wt\e-balance` | `ai/e-balance` | `ba06ef9c` | yes | 0/24 | 1 | TASK-050 | REVIEW_REQUIRED | Untracked balance candidate. |
| `D:\game-wt\e-boss` | `ai/e-boss` | `ba06ef9c` | yes | 0/24 | 0 | TASK-041 | REVIEW_REQUIRED | Dirty active-task lane. |
| `D:\game-wt\e-boss2` | `ai/e-boss2` | `ba06ef9c` | yes | 0/24 | 1 | TASK-045 | REVIEW_REQUIRED | Untracked tutorial candidate. |
| `D:\game-wt\e-craft` | `ai/e-craft` | `ba06ef9c` | yes | 0/24 | 0 | TASK-030 | REVIEW_REQUIRED | Broad tracked changes. |
| `D:\game-wt\e-demo` | `ai/e-demo` | `ba06ef9c` | no | 0/24 | 0 | TASK-052 | REVIEW_REQUIRED | Mapped future task; no removal proof. |
| `D:\game-wt\e-dungeon` | `ai/e-dungeon` | `bd18c89b` | yes | 1/24 | 4 | TASK-027 | REVIEW_REQUIRED | Unique commit and untracked production. |
| `D:\game-wt\e-dungeon-codex-0275` | `codex/task-027-5` | `a4d27076` | yes | 2/24 | 0 | TASK-027-5 | REVIEW_REQUIRED | Forensic branch with unique commits. |
| `D:\game-wt\e-dungeon-next` | `ai/e-dungeon-next` | `7fb5e2a9` | yes | 0/7 | 0 | TASK-027 | KEEP_ACTIVE | Configured current Dungeon lane; dirty state is import/cache and design drift, preserve for active lane review. |
| `D:\game-wt\e-equipment` | `ai/e-equipment` | `ba06ef9c` | yes | 0/24 | 3 | TASK-029 | REVIEW_REQUIRED | Untracked equipment candidates. |
| `D:\game-wt\e-expedition` | `ai/e-expedition` | `ba06ef9c` | yes | 0/24 | 3 | TASK-026 | REVIEW_REQUIRED | Untracked Expedition candidates. |
| `D:\game-wt\e-faction` | `ai/e-faction` | `ba06ef9c` | yes | 0/24 | 1 | TASK-036 | REVIEW_REQUIRED | Untracked upgrade candidate. |
| `D:\game-wt\e-follower` | `ai/e-follower` | `ba06ef9c` | no | 0/24 | 0 | TASK-035 | REVIEW_REQUIRED | Mapped future task. |
| `D:\game-wt\e-house` | `ai/e-house` | `ba06ef9c` | yes | 0/24 | 2 | TASK-034 | REVIEW_REQUIRED | Untracked elite candidates. |
| `D:\game-wt\e-item` | `ai/e-item` | `ba06ef9c` | yes | 0/24 | 0 | TASK-032 | REVIEW_REQUIRED | Dirty task lane. |
| `D:\game-wt\e-load` | `ai/e-load` | `ba06ef9c` | yes | 0/24 | 3 | TASK-048 | REVIEW_REQUIRED | Untracked tutorial/save candidates. |
| `D:\game-wt\e-loot` | `ai/e-loot` | `ba06ef9c` | yes | 0/24 | 3 | TASK-044 | REVIEW_REQUIRED | Untracked NPC candidates. |
| `D:\game-wt\e-merc` | `ai/e-merc` | `ba06ef9c` | yes | 0/24 | 0 | TASK-031 | REVIEW_REQUIRED | Broad dirty task lane. |
| `D:\game-wt\e-meta` | `ai/e-meta` | `ba06ef9c` | yes | 0/24 | 1 | TASK-049 | REVIEW_REQUIRED | Untracked audio candidate. |
| `D:\game-wt\e-npc` | `ai/e-npc` | `ba06ef9c` | yes | 0/24 | 1 | TASK-037 | REVIEW_REQUIRED | Untracked building-upgrade candidate. |
| `D:\game-wt\e-persist` | `ai/e-persist` | `ba06ef9c` | yes | 0/24 | 0 | TASK-046 | REVIEW_REQUIRED | Dirty persistence lane. |
| `D:\game-wt\e-potion2` | `ai/e-potion2` | `ba06ef9c` | no | 0/24 | 0 | TASK-040 | REVIEW_REQUIRED | Mapped future Potion task. |
| `D:\game-wt\e-quest` | `ai/e-quest` | `ba06ef9c` | yes | 0/24 | 0 | TASK-038 | REVIEW_REQUIRED | Dirty task lane. |
| `D:\game-wt\e-save` | `ai/e-save` | `ba06ef9c` | yes | 0/24 | 1 | TASK-047 | REVIEW_REQUIRED | Untracked candidate. |
| `D:\game-wt\e-shop` | `ai/e-shop` | `ba06ef9c` | yes | 0/24 | 0 | TASK-039 | REVIEW_REQUIRED | Dirty task lane. |
| `D:\game-wt\e-siege` | `ai/e-siege` | `ba06ef9c` | yes | 0/24 | 0 | TASK-042 | REVIEW_REQUIRED | Dirty task lane. |
| `D:\game-wt\e-stress` | `ai/e-stress` | `ba06ef9c` | yes | 0/24 | 0 | TASK-051 | REVIEW_REQUIRED | Dirty stress lane. |
| `D:\game-wt\e-threat-next` | `ai/e-threat-next` | `7fb5e2a9` | no | 0/2 | 0 | TASK-028 | KEEP_ACTIVE | Configured current Threat/Dungeon lane. |
| `D:\game-wt\e-threat2` | `ai/e-threat2` | `ba06ef9c` | yes | 0/24 | 2 | TASK-024 | REVIEW_REQUIRED | Divergent Threat candidate. |
| `D:\game-wt\e-village` | `ai/e-village` | `ba06ef9c` | yes | 0/24 | 0 | TASK-033 | REVIEW_REQUIRED | Dirty task lane. |
| `D:\game-wt\e-world` | `ai/e-world` | `ba06ef9c` | yes | 0/24 | 0 | TASK-043 | REVIEW_REQUIRED | Broad dirty task lane. |
| `D:\game-wt\f-cooking` | `ai/f-cooking` | `ba06ef9c` | yes | 0/24 | 4 | TASK-020 | REVIEW_REQUIRED | Untracked cooking candidates. |
| `D:\game-wt\f-farm` | `ai/f-farm` | `ba06ef9c` | yes | 0/24 | 9 | TASK-019 | REVIEW_REQUIRED | Untracked Farm candidates. |
| `D:\game-wt\f-food` | `ai/f-food` | `ba06ef9c` | yes | 0/24 | 1 | TASK-018 | REVIEW_REQUIRED | Untracked Food candidate. |
| `D:\game-wt\f-ghost` | `ai/f-ghost` | `ba06ef9c` | yes | 0/24 | 5 | TASK-017 | REVIEW_REQUIRED | Untracked Ghost candidates. |
| `D:\game-wt\f-inn` | `ai/f-inn` | `ba06ef9c` | yes | 0/24 | 1 | TASK-022 | REVIEW_REQUIRED | Untracked Inn candidate. |
| `D:\game-wt\f-morale` | `ai/f-morale` | `ba06ef9c` | yes | 0/24 | 6 | TASK-023 | REVIEW_REQUIRED | Untracked Morale candidates. |
| `D:\game-wt\f-portal` | `ai/f-portal` | `ba06ef9c` | yes | 0/24 | 3 | TASK-025 | REVIEW_REQUIRED | Untracked Portal candidates. |
| `D:\game-wt\f-potion` | `ai/f-potion` | `ba06ef9c` | yes | 0/24 | 6 | TASK-021 | REVIEW_REQUIRED | Untracked Potion candidates. |
| `D:\game-wt\f-threat` | `ai/f-threat` | `ba06ef9c` | yes | 0/24 | 2 | TASK-024 | REVIEW_REQUIRED | Divergent Threat candidate. |
| `D:\game-wt\integration-recovery` | `codex/integration-recovery` | `85f9d9d3` | yes | 0/10 | 0 | Recovery provenance | KEEP_PRESERVATION | Salvage source for promoted baseline; attached audit document remains untracked and untouched. |
| `D:\game-wt\main-pre-recovery-preserved` | `codex/preserve-main-pre-recovery-20260904` | `a6a4c24b` | no | 1/22 | 0 | Main preservation | KEEP_PRESERVATION | Explicit pre-promotion preservation. |
| `D:\game-wt\visual` | `ai/3d-visual` | `db8c462a` | no | 0/44 | 0 | TASK-3D-VIS-001 | REMOVE_SAFE | Clean and integrated in main. |
| `D:\game-wt\visual2` | `ai/3d-visual-002` | `6fb86189` | yes | 0/26 | 3 | TASK-3D-VIS-002 | REVIEW_REQUIRED | Dirty visual candidates. |
| `D:\game-wt\worker` | `ai/3d-worker` | `5dfc7b5c` | no | 0/44 | 0 | TASK-3D-WRK-001 | REMOVE_SAFE | Clean and integrated in main. |

## Summary

- Total `D:\game-wt` worktrees: **47**
- `KEEP_ACTIVE`: **2** — `e-dungeon-next`, `e-threat-next`
- `KEEP_PRESERVATION`: **3** — `baseline-health-f4`, `integration-recovery`, `main-pre-recovery-preserved`
- `REMOVE_SAFE`: **4** — `building`, `combat`, `visual`, `worker`
- `REVIEW_REQUIRED`: **38**

Unique commit counts above are measured against current main `6996715`.
The four `REMOVE_SAFE` entries are candidates only. This pass performed no
`git worktree remove`, filesystem deletion, reset, or clean.
