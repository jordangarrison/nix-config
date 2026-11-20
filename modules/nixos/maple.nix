{ config, inputs, pkgs, ... }:

let
  host = "maple.jordangarrison.dev";
  secrets = "/var/lib/maple-secrets";
in
{
  imports = [
    inputs.maple.nixosModules.maple
    # Storage provider: replace only this import when moving to a dedicated
    # filesystem. It must mount /var/lib/maple; the service fails without it.
    ./maple/gemini-storage.nix
  ];

  # The upstream package uses its own narrowly scoped unfree predicate, not
  # this host's global policy. No overlay or additional unfree allowance.
  services.maple = {
    enable = true;
    host = "127.0.0.1";
    port = 4318;
    advertiseHost = host;
    openFirewall = false;
    ingestKeyFile = "${secrets}/ingest-key";
    accessTokenFile = "${secrets}/access-token";
    checkpointInterval = "30m";
    # Fail closed after a crash instead of wiping data before the first
    # checkpoint. Recovery is an operator decision (see the runbook).
    onDirtyStore = "fail";
    # Keep schema TTLs: upstream's retention flag can only LENGTHEN them.
  };

  systemd.services.maple-secrets = {
    description = "Create Maple credentials if missing";
    before = [ "maple.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      StateDirectory = "maple-secrets";
      StateDirectoryMode = "0700";
      UMask = "0077";
    };
    path = [ pkgs.coreutils pkgs.openssl ];
    script = ''
      set -euo pipefail
      for name in access-token ingest-key; do
        file="${secrets}/$name"
        if [[ ! -e "$file" ]]; then
          tmp=$(mktemp "${secrets}/.$name.XXXXXX")
          trap 'rm -f "$tmp"' EXIT
          openssl rand -hex 32 > "$tmp"
          mv -T "$tmp" "$file"
          trap - EXIT
        fi
        # Never replace a malformed credential with a new one silently.
        if [[ ! -f "$file" || -L "$file" ]] || ! grep -Eq '^[0-9a-f]{64}$' "$file"; then
          echo "Invalid Maple credential file; refusing to start." >&2
          exit 1
        fi
        chmod 0600 "$file"
      done
    '';
  };

  systemd.services.maple = {
    requires = [ "maple-secrets.service" ];
    after = [ "maple-secrets.service" ];
    # This also orders shutdown: cleanly stop chDB before unmounting.
    # A failed mount must never fall back to writing on the root filesystem.
    unitConfig.RequiresMountsFor = "/var/lib/maple";
  };

  security.acme.certs.${host} = {
    group = "nginx";
    dnsResolver = "1.1.1.1:53";
  };

  services.nginx.virtualHosts.${host} = {
    forceSSL = true;
    useACMEHost = host;
    listen = [
      { addr = "100.118.65.11"; port = 80; }
      { addr = "100.118.65.11"; port = 443; ssl = true; }
    ];
    # One origin serves the offline UI, authenticated reads and /v1/* OTLP
    # writes. No nginx basic auth: exporters use Maple's separate ingest key.
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString config.services.maple.port}";
      proxyWebsockets = true;
      extraConfig = ''
        allow 127.0.0.1;
        allow ::1;
        allow 100.64.0.0/10;
        allow fd7a:115c:a1e0::/48;
        deny all;
        client_max_body_size 10m;
        proxy_read_timeout 120s;
        add_header X-Robots-Tag "noindex, nofollow" always;
      '';
    };
  };
}
