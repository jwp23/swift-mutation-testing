---
name: finishing-a-development-branch
description: Use when implementation is complete and all tests pass - handles push, PR creation, and CI verification for this project's merge-commit, one-commit-per-PR policy.
---

# Finishing a Development Branch

This project merges every PR as **one commit via an actual merge commit** — never GitHub's
squash-merge button. Follow these steps in order.

## 1. Collapse the branch to one commit
```bash
git fetch origin main
git reset --soft $(git merge-base origin/main HEAD)
git commit -m "<type>: <single-line conventional commit message>"
```
Never use `git rebase -i` — interactive input isn't supported in this environment.
The message must be single-line, Conventional-Commits-typed, no body, no `Co-Authored-By`
trailer — the `no-coauthor-no-description` pre-commit hook rejects both.

## 2. Push
```bash
git push --force-with-lease
```
History was just rewritten, so a plain push will be rejected — this is expected, not a
shortcut. Only ever targets the feature branch, never `main`.

## 3. Open the PR
```bash
gh pr create
```

## 4. Wait for CI, then merge
```bash
gh pr checks   # confirm green
gh pr merge --merge --delete-branch
```
`--merge`, not `--squash` — the branch already carries exactly one commit, so the resulting
merge commit on `main` gets exactly one parent contribution from this PR.

Work is not done until the PR is open and CI is green.
