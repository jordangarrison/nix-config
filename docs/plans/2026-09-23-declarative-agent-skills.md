# Declarative agent skills

Status: implemented on endeavour (other hosts: run the migration on next rebuild).

## Goal

Every agent skill Jordan uses is declared in this repo. Nothing is installed
with `npx skills`, `pup skills install`, `readwise skills install`, `flo
skills add`, or by hand-copying into `~/.agents/skills` / `~/.claude/skills`.

## Decisions

- **Extend the in-repo `programs.agent-skills` module.** Do not adopt a
  framework. Rejected alternatives:
  - Home Manager's native `programs.<agent>.skills`: per-agent only, and the
    HM claude-code/codex modules are already disabled here.
  - Kyure-A/agent-skills-nix: its option name collides with ours, and our
    in-repo skills would lose live-edit.
  - z1-0/skills-nix: versions come from a third-party registry, and it can't
    reach private repos.
  - sudosubin/nix-skills: a 1.2 GB input.
- **Pin public skill repos as `flake = false` flake inputs, not npins.** One
  lock file and one updater, and the daily `update-flake-lock.yml` covers
  them. Reviewed with the Hickey and grug lenses; both rejected npins as a
  second pinning system that exists only because some repos are public and
  others private.
- **Take CLI-coupled skills from the Nix package itself**, so the skill
  version always equals the CLI version. Prefer a package's installed output
  over its `.src` when the package ships the skill.
- **pup: build its skills at build time from the binary.** Skills only. The
  48 Claude subagents stay unmanaged (the claude-code module header already
  says so). The `dd-pup-pi` extension is out of scope.
- **Do not add a "CLI ships agent integration" abstraction.** pup is the only
  example. Revisit when a second tool ships subagents or extensions.
- **Trim Google Workspace skills from 67 to 16**, based on real `gws` usage
  in session logs.
- **Drop:** `find-skills`, the stale skills.sh `pup` root skill (replaced by
  `dd-pup`), the 51 trimmed gws/recipe/persona skills, and all Jira skills
  (`jira`, `plan-jira`; Jira is no longer used).
- **Leave alone:** directories managed by other tools. These are
  `~/.claude/skills/synced` (claude.ai), the nodeterm skills
  (`get-linked-context`, `manage-nodeterm-canvas`), `~/.codex/skills/.system`,
  and `~/.claude/agents` (pup subagents).

## Module change: `modules/home/agent-skills`

Add one option:

```nix
external = lib.mkOption {
  type = lib.types.attrsOf lib.types.path;
  default = { };
  description = "Skill name -> directory containing SKILL.md (store paths).";
};
```

- Link each entry into `~/.agents/skills/<name>` and
  `~/.claude/skills/<name>`. Use the same fan-out as the in-repo skills, but
  link to the store (not out-of-store).
- Add an assertion that fails when an external name collides with an in-repo
  skill name.
- Check paths **at build time**, not at eval time. Collect the external
  skills into one `runCommand` bundle that runs `test -f $src/SKILL.md` for
  every entry and links from the bundle. This avoids eval-time fetches (IFD)
  of package sources through `builtins.pathExists`, and a skill folder that
  moves upstream fails the build instead of leaving a dangling link.
- Rewrite the module header. Delete the rule that names must stay disjoint
  from skills.sh installs, because skills.sh goes away.

## Skill sources

Gate each skill on the same flag as its CLI, so no host gets a skill without
its tool.

| Source | Skills | Gate |
|---|---|---|
| `users/jordangarrison/skills/` (live-edit, unchanged) | existing 11 | — |
| `${pkgs.gws.src}/skills/<n>` | `gws-shared`, `gws-gmail`, `gws-gmail-read`, `gws-gmail-reply`, `gws-gmail-reply-all`, `gws-gmail-send`, `gws-gmail-triage`, `gws-drive`, `gws-drive-upload`, `gws-docs`, `gws-docs-write`, `gws-sheets`, `gws-sheets-read`, `gws-calendar`, `gws-calendar-agenda`, `gws-people` | gws package list |
| `${herdr.src}/skills/herdr` | `herdr` | `userApps.herdr` |
| `${pkgs.gh-stack.src}/skills/gh-stack` | `gh-stack` (package 0.0.4 == installed extension) | `programs.gh` |
| `${agent-browser}/share/agent-browser/skills/agent-browser` | `agent-browser` | Linux only: declare in `home-linux.nix` |
| pup build step (below) | 11 `dd-*` | `userApps.pup` |
| `inputs.aws-use-sso` `skills/aws-use-sso` | `aws-use-sso` | — |
| `inputs.floai` `catalog/skills/<n>` | `flo-brand-naming`, `git-update-pr-description` | `userApps.floai` |
| New `flake = false` inputs | see below | — |

New public inputs (8). Tracking the default branch is enough; skill text
needs no tag tracking.

| Input | Skills |
|---|---|
| `kepano/obsidian-skills` | `obsidian-bases`, `obsidian-cli`, `obsidian-markdown` |
| `tt-a1i/archify` | `archify` (repo root layout: `archify/`) |
| `kunchenguid/lavish-axi` | `lavish` (the CLI runs via `npx`, so there's no package to couple to) |
| `JuliusBrussee/caveman` | `caveman` |
| `boristane/agent-skills` | `logging-best-practices` |
| `anthropics/skills` | `frontend-design` |
| `readwiseio/readwise-skills` | 10 Readwise skills (`readwise skills install` downloads at run time, so it can't run in the build) |
| `jordangarrison/ash-kindle` | `ash-kindle` |

### pup skills (build time, agent-agnostic)

```nix
# pup ships its skills inside the binary. The platform arg is required
# but only picks a target dir, which --dir overrides; SKILL.md output is
# byte-identical across platforms. Verified offline with an empty HOME.
pupSkills = pkgs.runCommand "pup-skills-${pkgs.pup.version}" {
  nativeBuildInputs = [ pkgs.pup ];
} ''
  export HOME=$TMPDIR
  pup skills install codex --type=skill --dir $out --no-agent
'';
```

## CI

- No new private inputs.
- `ci/stubs/floai` gains a `catalog/skills/<name>/SKILL.md` placeholder for
  every floai skill we consume, and its header comment describes the new
  interface.
- The new public inputs need no stubs.

## Migration (per host)

1. `nh os build . --no-nom` (or the darwin/home equivalent) must pass first.
2. Remove the hand-installed copies, which Home Manager would refuse to
   overwrite:
   - Every non-symlink directory in `~/.agents/skills`.
   - The relative symlinks in `~/.claude/skills` that point into
     `~/.agents/skills`.
   - `~/.claude/skills/dd-*` and the 10 Readwise directories.
   - The 10 Readwise directories in `~/.codex/skills` (codex reads
     `~/.agents/skills`).
   - All of `~/.pi/agent/skills` (pi reads `~/.agents/skills`; two links are
     already dangling).
   - `~/.agents/.skill-lock.json`.

   Keep a tarball backup of the removed directories until the switch is
   verified.
   The list and backup script used on endeavour (review the list before
   deleting):

   ```bash
   cd ~ && L=/tmp/skills-migration.txt && : > $L
   for d in .agents/skills/*; do [ -L "$d" ] || echo "$d" >> $L; done
   for d in .claude/skills/*; do
     case "$(basename "$d")" in synced|get-linked-context|manage-nodeterm-canvas) continue;; esac
     if [ -L "$d" ]; then case "$(readlink "$d")" in /nix/store/*) ;; *) echo "$d" >> $L;; esac
     else echo "$d" >> $L; fi
   done
   for d in .codex/skills/* .pi/agent/skills/*; do [ -e "$d" ] || [ -L "$d" ] && echo "$d" >> $L; done
   [ -f .agents/.skill-lock.json ] && echo .agents/.skill-lock.json >> $L
   tar -czf ~/skills-backup-$(date +%F).tar.gz -T $L
   while IFS= read -r p; do rm -rf -- "$HOME/$p"; done < $L
   ```

3. Run `nh os test . --no-nom`, then `switch` after approval.
4. Hosts: endeavour, opportunity, voyager, discovery, H952L3DPHH (darwin) and
   normandy (WSL). Check each host's actual state before deleting, because
   manual installs differ per machine.

## Docs

- `users/jordangarrison/skills/CLAUDE.md` gets the rule, stated once: add a
  skill by adding an `external` entry (a package path, an input, or the
  in-repo directory), and never with an imperative installer.
- The root `AGENTS.md` Skills row points there.
- Rewrite the `modules/home/agent-skills/default.nix` header.

## Resolved questions

1. **Flo skills all come from the existing `floai` input.**
   `flocasts/agent-skills` is deprecated in favor of floai.
   - `update-pr-description` is replaced by floai's `git-update-pr-description`.
   - `setup-helm-deployment` is dropped. It is deprecated in favor of
     `ship-a-service`, which is not adopted.
   - No other floai skills or packs for now.
2. **`flo skills update/remove` will fail on the Nix-managed links.** This is
   accepted: Nix owns these skills now, and updates arrive through the
   `floai` flake input.
