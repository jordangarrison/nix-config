{ ... }:

{
  # BB stores the active palette in its database. Select with:
  # bb theme set rose-pine
  # force lets Home Manager adopt the files installed for the initial live preview.
  home.file = {
    ".bb/theme/rose-pine/theme.css" = {
      source = ./theme.css;
      force = true;
    };
    ".bb/theme/rose-pine/pierre-dark.json" = {
      source = ./pierre-dark.json;
      force = true;
    };
    ".bb/theme/rose-pine/pierre-light.json" = {
      source = ./pierre-light.json;
      force = true;
    };
  };
}
