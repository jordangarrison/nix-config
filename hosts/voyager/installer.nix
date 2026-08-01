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
      echo "Targets:"
      echo "  internal 256 GB SSD  -> NixOS: ESP + swap + root"
      echo "  256 GB SD card       -> /data"
      echo
      echo "NOTE: the installer USB you booted from also appears in the"
      echo "list above (TRAN usb, label VOYAGER) - do NOT select it."
      echo
      read -rp "SSD device to wipe [/dev/sda]: " ssd
      if [ -z "$ssd" ]; then ssd=/dev/sda; fi
      read -rp "SD card device to wipe [/dev/sdb]: " sd
      if [ -z "$sd" ]; then sd=/dev/sdb; fi

      if [ ! -b "$ssd" ] || [ ! -b "$sd" ]; then
        echo "Not a block device: $ssd and/or $sd" >&2
        exit 1
      fi
      if [ "$ssd" = "$sd" ]; then
        echo "SSD and SD card devices must differ." >&2
        exit 1
      fi
      for dev in "$ssd" "$sd"; do
        if lsblk -no LABEL "$dev" | grep -q VOYAGER; then
          echo "$dev is the installer USB you booted from - refusing." >&2
          exit 1
        fi
      done

      echo
      echo "About to DESTROY ALL DATA on $ssd (SSD) and $sd (SD card)."
      read -rp "Type WIPE to continue: " confirm
      if [ "$confirm" != "WIPE" ]; then
        echo "Aborted."
        exit 1
      fi

      if [ "$ssd" = "/dev/sda" ] && [ "$sd" = "/dev/sdb" ]; then
        # Fast path: pre-built partition script, no evaluation needed.
        ${voyagerDiskoScript}
      else
        # Retargeted devices: small offline nix evaluation against the
        # ISO's bundled nixpkgs channel.
        disko --mode destroy,format,mount \
          --arg ssdDevice "\"$ssd\"" \
          --arg sdDevice "\"$sd\"" \
          ${./disko.nix}
      fi

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
