# Issue tracker: GitHub

Issues and PRDs for this repo live as GitHub issues. Use the `gh` CLI for all operations.

> 历史票(#1–#25,含 v1.10 收口的 #23/#24/#25)归档在私有仓 `ren2019/LiteOC-old`(archived,只读)。本仓 `ren2019/LiteOC` 是唯一活跃 issue 面;查历史票时用 `gh issue view <N> -R ren2019/LiteOC-old`。

## Conventions

- **Create an issue**: `gh issue create -R ren2019/LiteOC --title "..." --body "..."` (heredoc for multi-line bodies).
- **Read an issue**: `gh issue view <number> --comments`.
- **List issues**: `gh issue list -R ren2019/LiteOC --state open`.
- **Comment**: `gh issue comment <number> --body "..."`.
- **Apply / remove labels**: `gh issue edit <number> --add-label "..."` / `--remove-label "..."`.
- **Close**: `gh issue close <number> --comment "..."`.

`gh` infers the repo from `git remote -v`; pass `-R ren2019/LiteOC` explicitly to be safe.

## Pull requests as a triage surface

**PRs as a request surface: no.** _(Flip to `yes` if external PRs should enter the triage queue.)_

## When a skill says "publish to the issue tracker"

Create a GitHub issue in `ren2019/LiteOC`.

## When a skill says "fetch the relevant ticket"

Run `gh issue view <number> --comments`.
