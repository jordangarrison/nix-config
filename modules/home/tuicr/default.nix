{ ... }:

{
  # tuicr reads $XDG_CONFIG_HOME/tuicr/config.toml on Linux and macOS, and
  # resolves local themes from the sibling themes/ directory (upstream
  # docs/CONFIG.md). Rose Pine is not among tuicr's built-in themes, so the
  # variants ship here as local theme files.
  xdg.configFile = {
    "tuicr/config.toml".source = ./config.toml;
    "tuicr/themes/rose-pine.toml".source = ./rose-pine.toml;
    "tuicr/themes/rose-pine-dawn.toml".source = ./rose-pine-dawn.toml;
  };
}
