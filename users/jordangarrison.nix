{ config, pkgs, ... }:

{
  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.jordangarrison = {
    isNormalUser = true;
    initialHashedPassword = "";
    extraGroups = [
      "wheel" # Enable ‘sudo’ for the user.
      "docker"
      "plugdev"
    ];
    shell = pkgs.zsh;
  };

  programs.zsh.enable = true;

  # Let me use the moonlander plz
  hardware.keyboard.zsa.enable = true;
}
