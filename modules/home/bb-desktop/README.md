# BB desktop in Home Manager

The root flake exports this module as `homeManagerModules.bb-desktop`.
The bundled package supports x86_64 Linux.

```nix
programs.bb-desktop = {
  enable = true;
  defaultServerUrl = "https://bb.jordangarrison.dev";
};
```

The module installs `bb-desktop`, its desktop entry, and its icon. It does
not start the app at login or manage a BB server service. Use `package` to
provide a different desktop package.

When `defaultServerUrl` is set, activation seeds
`${xdg.configHome}/bb/server-target.json` only if no file or symlink exists.
The new file has mode `0600` and remains writable by the app. Later changes
to the default do not replace a saved selection. With `defaultServerUrl = null`
(the default), the module leaves server selection to the app.

Jordan's `users.jordangarrison.apps.bb-desktop.enable` flag enables this module
on `endeavour`, with `https://bb.jordangarrison.dev` as the initial server.
