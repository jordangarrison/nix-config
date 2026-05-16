{ config, lib, pkgs, ... }:

{
  # Home Assistant on endeavour
  # Spec: docs/superpowers/specs/2026-05-15-home-assistant-design.md

  services.home-assistant = {
    enable          = true;
    openFirewall    = false;             # nginx will be the only ingress (added in Task 3)
    configWritable  = true;              # HA can edit configuration.yaml at runtime;
                                         # nh os switch reasserts the Nix-rendered version.
    extraComponents = [
      "default_config"
      "met"
      "backup"
      # Apple-ecosystem deps: HomePods / Apple TVs on the LAN trigger zeroconf
      # discovery flows. Without these, HA logs ERRORs every scan even though
      # the integrations aren't configured. Pulling them in keeps logs clean
      # and lets us configure them via UI when ready.
      "apple_tv"
      "homekit_controller"   # adopt existing HomeKit devices into HA
      "thread"               # Thread integration shell (Border Router hardware deferred)
      "brother"              # Brother printer (matches the OS-level printer module)
      "ipp"                  # Internet Printing Protocol — companion to brother
    ];
    config = {
      homeassistant = {
        name         = "GarrisonsByGrace Home";
        time_zone    = config.time.timeZone;
        unit_system  = "us_customary";
        internal_url = "https://hass.garrisonsbygrace.com";
        external_url = "https://hass.garrisonsbygrace.com";
        # HomeKit Bridge YAML will land in /var/lib/hass/packages/ via tmpfiles symlink in Task 4
        packages     = "!include_dir_named packages";
      };
      default_config = {};
      http = {
        server_host         = [ "127.0.0.1" "::1" ];   # loopback only
        use_x_forwarded_for = true;
        trusted_proxies     = [ "127.0.0.1" "::1" ];
      };
      recorder = {
        purge_keep_days = 10;
      };
    };
  };

  # Bootstrap dirs that later tasks (and HA itself) will populate.
  # /var/lib/hass-secrets exists now so secrets.yaml has a home in Task 4.
  # /var/lib/hass/packages will be made a symlink in Task 4 (don't pre-create as a dir).
  systemd.tmpfiles.rules = [
    "d /var/lib/hass-secrets 0750 hass hass -"
  ];
}
