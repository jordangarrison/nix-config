# Workspace additions: dev/jordangarrison

Read after `ROUTER.md` (this folder's `AGENTS.md`). Personal-projects
workspace — independent hobby/tooling repos.

## Conventions

- **Remote**: most repos live at `git@github.com:jordangarrison/<repo>.git`.
- **Branch naming**: short conventional slug (`fix-pool-leak`,
  `feat-new-cli-flag`) — the router default; no ticket prefixes here.
- **Workspace labels**: short task description (e.g. "sweet-nothings hotkey
  rework").
- **PRs**: use the GitHub MCP server when available.
- **Nix**: many repos ship a `flake.nix` — `nix develop`, `nix build`,
  `nix run`; `direnv` + `.envrc` auto-loads dev shells in some.
- **AWS**: the `aws-use-sso` skill handles auth.

## Notable repo quirks

- **`brain`** — Obsidian vault (PARA method, periodic notes). Prefer the
  Obsidian MCP tools when available.
- **`greenlight`** — use the `greenlight-debugging` skill when investigating.
- **`nix-config`** — NixOS system config; always `nh ... --no-nom`, and
  `nh os test` (not `switch`) when verifying.

## Per-language quick commands

```bash
# Nix flake projects
nix develop && nix build && nix run

# Go
go mod download && go build && go test ./... -v

# Node
npm install && npm run dev; npm test

# Elixir / Phoenix
mix deps.get && mix test && mix phx.server

# Rust
cargo build && cargo test

# Ruby
bundle install && bundle exec <command>
```

## skills.sh agent skills

Some repos ship [agent skills](https://skills.sh) at
`skills/<skill-name>/SKILL.md` (e.g. **`aws-use-sso`**).

- Skill directory name must match the `name:` field in SKILL.md frontmatter.
- SKILL.md uses YAML frontmatter (`name`, `description` required) + markdown
  body; version tracks the project's package version.
- Install with `npx skills add <owner>/<repo>`.
- Spec: https://agentskills.io/specification
