{ config, pkgs, ... }:

{
  users.users.mattwilliams = {
    isNormalUser = true;
    initialHashedPassword = "";
    extraGroups = [
      "wheel" # Enable ‘sudo’ for the user.
      "docker"
    ];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC+oebBdFiGA+bAfSsy4CypRsyqB7gTHuCMIH9adpIl8Nqg/bDnl957PR0GeYiJOTJ3dTNniPOOdNHLw0XO3htkIid1x4xdBp3do43e7uiJ8hRcr8XQEK7dytUKfHVmKwX68AweT869qQJ+WwgVFFe3rZywq1HnMkl2O90RDRpjgoOfgOdToGYEK6qL4LsUD9Psd0GXL6Qfic1sokHXD9tgCKVSzj3QaYvJ74vKxIbE0uOgRpaZUJAxewcxjtc9V3ViabpsuadXgEOl9ctOK3siCSfSjioeo2ZAka5cNtsLtJaP/dDU+yDyJ5kxua8bxQgIRzPm6FC5KFEULeubQwg7 matt@williams-tech.net"
    ];
  };
}
