# Self-contained installer ISO for voyager. Embeds the full voyager
# system closure and a pre-built disko partition script, so the install
# needs no network and no evaluation on the laptop.
#
#   nix build .#voyager-iso
{ pkgs, inputs, voyagerToplevel, voyagerDiskoScript, ... }:
let
  install-voyager = pkgs.writeShellApplication {
    name = "install-voyager";
    text = ''
      if [ "$(id -u)" -ne 0 ]; then
        echo "Run as root: sudo install-voyager" >&2
        exit 1
      fi

      echo "=== Voyager NixOS installer ==="
      echo
      lsblk -o NAME,SIZE,MODEL,TRAN,TYPE
      echo
      echo "This will DESTROY ALL DATA on:"
      echo "  /dev/sda  (internal 256 GB SSD  -> NixOS: ESP + swap + root)"
      echo "  /dev/sdb  (256 GB SD card       -> /data)"
      echo
      echo "NOTE: the installer USB you booted from also appears in the"
      echo "list above (TRAN usb, label VOYAGER) - do NOT select it."
      echo
      echo "If the lsblk output above does NOT match those devices, ABORT"
      echo "and partition manually with the disko CLI instead:"
      echo "  disko --mode destroy,format,mount \\"
      echo "    --arg ssdDevice '\"/dev/sdX\"' --arg sdDevice '\"/dev/sdY\"' \\"
      echo "    ${./disko.nix}"
      echo "then run: nixos-install --system ${voyagerToplevel} --no-root-passwd"
      echo
      read -rp "Type the SSD device to wipe (expected: /dev/sda): " ssd
      read -rp "Type the SD card device to wipe (expected: /dev/sdb): " sd
      if [ "$ssd" != "/dev/sda" ] || [ "$sd" != "/dev/sdb" ]; then
        echo
        echo "Devices differ from the pre-built script's targets."
        echo "Use the disko CLI escape hatch shown above with your actual"
        echo "devices, then run the nixos-install command it printed."
        exit 1
      fi
      echo
      read -rp "Type WIPE to continue: " confirm
      if [ "$confirm" != "WIPE" ]; then
        echo "Aborted."
        exit 1
      fi

      ${voyagerDiskoScript}

      nixos-install --system ${voyagerToplevel} --no-root-passwd

      echo
      echo "Set Jordan's login password:"
      nixos-enter --root /mnt -c 'passwd jordangarrison' || {
        echo "passwd failed - set it on first boot from a console instead."
      }

      echo
      echo "Install complete. Set the other users' passwords after first"
      echo "boot with: sudo passwd mikayla   (etc.)"
      read -rp "Reboot now? [y/N] " answer
      case "$answer" in
        y|Y) reboot ;;
        *) echo "Not rebooting." ;;
      esac
    '';
  };
in
{
  isoImage.volumeID = "VOYAGER";
  # The script's references already pull the voyager closure into the
  # ISO store; listing it here makes the intent explicit.
  isoImage.storeContents = [ voyagerToplevel ];
  # Default zstd level is very slow on a ~10-15 GB closure; level 6 is
  # a sane build-time/size trade-off for a throwaway installer image.
  isoImage.squashfsCompression = "zstd -Xcompression-level 6";

  environment.systemPackages = [
    install-voyager
    inputs.disko.packages.${pkgs.stdenv.hostPlatform.system}.disko
  ];
}
