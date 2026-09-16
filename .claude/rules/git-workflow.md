# Git Workflow Rules

## Branches
Never commit directly to main (the pre-commit hook blocks it anyway). Branch naming:
`feat/`, `fix/`, `chore/`, `docs/`, `refactor/`, `test/`, `perf/`, `ci/`, `build/`, `revert/`,
`style/` + short description.

## Worktrees
For extensive changes, use the EnterWorktree tool.

## Completing Work
When implementation is complete and tests pass, invoke the `finishing-a-development-branch`
skill via the Skill tool. It implements this project's merge-commit policy — never run the
push/PR/merge steps by hand.

## Merge Policy
Every PR lands as exactly one commit, merged with an actual merge commit — never GitHub's
squash-merge button. See the `finishing-a-development-branch` skill for the procedure.
Work is complete only when the PR is open and CI is green.
