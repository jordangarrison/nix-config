{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.virtualization.virt-manager;
in
{
  options.virtualization.virt-manager = {
    enable = mkEnableOption "virt-manager and virtualization support";
    
    users = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "List of users to add to the libvirtd group";
    };
  };

  config = mkIf cfg.enable {
    # Enable virt-manager and related virtualization services
    programs.virt-manager.enable = true;
    
    # Enable libvirtd daemon
    virtualisation.libvirtd = {
      enable = true;
      qemu = {
        # Enable TPM emulation (useful for Windows 11 VMs)
        swtpm.enable = true;
        # Run as unprivileged user
        runAsRoot = false;
      };
    };
    
    # Enable SPICE USB redirection for better USB device support in VMs
    virtualisation.spiceUSBRedirection.enable = true;
    
    # Add specified users to libvirtd group
    users.groups.libvirtd.members = cfg.users;
    
    # Install additional virtualization tools
    environment.systemPackages = with pkgs; [
      virt-viewer    # Simple remote display client
      qemu          # QEMU emulator
      OVMF          # UEFI firmware for virtual machines
    ];
    
    # Configure networking for VMs
    # This ensures the default libvirt network is available
    virtualisation.libvirtd.onBoot = "start";
    virtualisation.libvirtd.onShutdown = "shutdown";
    
    # Enable polkit for libvirt access
    security.polkit.enable = true;
  };
}
