# despertaferro

`despertaferro` is a personal configuration runtime built around a Git-backed
dotfiles repository, bootstrap workflows, host migration, and future agentic
automation.

The project is intentionally opinionated and personal. It is not trying to be a
generic dotfiles manager. The CLI is the only user-facing interface; Git remains
the storage and synchronization backend, but day-to-day interaction should not
depend on invoking the `git` binary directly.

## Current Scope

- Clean project branch with no legacy Ansible or historical implementation files.
- Functional definition in `planning/purpose.md`.
- Implementation plan in `planning/plan.md`.
- Feature task lists under `planning/*/tasks.md`.
- Initial Zig CLI with:
  - `status`
  - `track`
  - `ignore`
  - `sync`
  - `doctor`

## Build

```sh
zig build
```

## Run

```sh
zig build run -- status
zig build run -- doctor
zig build run -- track ~/.config/nvim
zig build run -- ignore ".config/zsh/.zsh_history"
zig build run -- sync
```

