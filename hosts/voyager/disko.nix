# Declarative disk layout for voyager (MacBookPro12,1).
#
# Plain function, NOT a NixOS module: the module system ignores arg
# defaults, so the flake imports this as `import ./disko.nix { }`.
# The same file works standalone with the disko CLI, which is the
# escape hatch if device names differ at install time:
#
#   disko --mode destroy,format,mount \
#     --arg ssdDevice '"/dev/sdX"' --arg sdDevice '"/dev/sdY"' \
#     ./disko.nix
{ ssdDevice ? "/dev/sda", sdDevice ? "/dev/sdb", ... }:
{
  disko.devices.disk = {
    # 256 GB internal SSD: ESP + swap + root
    main = {
      type = "disk";
      device = ssdDevice;
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            priority = 1;
            size = "1G";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "fmask=0077" "dmask=0077" ];
            };
          };
          swap = {
            priority = 2;
            size = "8G";
            content.type = "swap";
          };
          root = {
            priority = 3;
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
              extraArgs = [ "-L" "nixos" ];
              mountpoint = "/";
            };
          };
        };
      };
    };

    # 256 GB permanently-inserted SD card: single data partition.
    # nofail: boot proceeds if the card is ever removed.
    sdcard = {
      type = "disk";
      device = sdDevice;
      content = {
        type = "gpt";
        partitions.data = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            extraArgs = [ "-L" "sdcard" ];
            mountpoint = "/data";
            mountOptions = [ "nofail" ];
          };
        };
      };
    };
  };
}
