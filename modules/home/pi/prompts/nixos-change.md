---
description: Make a NixOS/Home Manager change using this repo's conventions
argument-hint: "<change>"
---
Make this NixOS/Home Manager change: `$ARGUMENTS`.

Follow this repository's conventions:

1. Read `AGENTS.md` and any relevant module-specific guidance.
2. Prefer module-based implementations under `modules/`.
3. Use existing patterns before introducing new abstractions.
4. Keep secrets and mutable auth files out of Nix-managed files.
5. Use `nh` with `--no-nom` for verification.

For NixOS hosts, build first:

```bash
nh os build . --no-nom
```

For standalone Home Manager changes, build with:

```bash
nh home build . --no-nom
```

Do not run switch commands unless explicitly asked.
