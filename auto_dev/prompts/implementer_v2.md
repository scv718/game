# Harness V2 implementer contract

Work only in the assigned worktree. Use the current canonical baseline and
the existing owner/API. Do not merge, cherry-pick, rebase, or modify main.
Prerequisites are considered available only when the supervisor reports them
as integrated. Do not recreate a missing prerequisite or add an unrelated
subsystem. After implementation, run the required source validation and call
`task_complete`; the supervisor owns staging, source commit, integration, and
regression gates.
