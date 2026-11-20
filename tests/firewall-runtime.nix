{ pkgs, host }:

# endeavour's firewall, sshd and forwarding settings, taken from the real host
# config, on a small VM with one network per zone. The expected lists below
# are the policy. If a port moves, change it here on purpose.
#
# Proves: SSH by key works over the tailnet and the LAN; a password login is
# refused; Tailscale's UDP port answers from the LAN; a tailnet client can
# route through endeavour to the uplink (the exit-node path); every other
# port is open only to the zones that need it.
let
  inherit (pkgs) lib;
  fw = host.networking.firewall;
  keys = import (pkgs.path + "/nixos/tests/ssh-keys.nix") pkgs;
  tailscalePort = host.services.tailscale.port;

  lanOpen = [ 22 53 1716 8096 21063 53317 ];
  # Ports nobody outside the tailnet should reach, plus the ones only
  # containers need.
  probed = lib.unique (lanOpen ++ [ 80 443 4319 4431 4444 5432 8053 8888 9187 ]);
  # sshd itself serves 22; a stub listener serves the rest.
  stubbed = lib.remove 22 probed;

  expectOpen = {
    lan = lanOpen;
    tailnet = probed;
    docker = lanOpen ++ [ 80 443 4319 ];
    ci = lanOpen ++ [ 80 443 4431 ];
  };

  listener = pkgs.writeText "listen.py" ''
    import socket, sys, threading

    def tcp(port):
        s = socket.socket()
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.bind(("0.0.0.0", port))
        s.listen()
        while True:
            s.accept()[0].close()

    def udp(port):
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.bind(("0.0.0.0", port))
        while True:
            data, peer = s.recvfrom(512)
            s.sendto(data, peer)

    for port in sys.argv[1].split(","):
        threading.Thread(target=tcp, args=(int(port),), daemon=True).start()
    for port in sys.argv[2].split(","):
        threading.Thread(target=udp, args=(int(port),), daemon=True).start()
    threading.Event().wait()
  '';

  udpProbe = pkgs.writeText "udp-probe.py" ''
    import socket, sys
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.settimeout(2)
    s.sendto(b"ping", (sys.argv[1], int(sys.argv[2])))
    sys.exit(0 if s.recv(512) == b"ping" else 1)
  '';

  client = vlan: {
    virtualisation.vlans = [ vlan ];
    environment.systemPackages = [ pkgs.netcat-openbsd pkgs.python3 pkgs.sshpass ];
    # Clients are probes; only the server's firewall is under test.
    networking.firewall.enable = false;
  };
in
pkgs.testers.runNixOSTest {
  name = "endeavour-firewall";

  nodes = {
    server = {
      # vlan 1 = LAN (and the uplink), 2 = tailnet, 3 = docker0,
      # 4 = a per-job CI bridge.
      virtualisation.vlans = [ 1 2 3 4 ];
      networking.firewall = {
        enable = true;
        inherit (fw) trustedInterfaces interfaces checkReversePath filterForward
          allowedTCPPorts allowedUDPPorts allowedTCPPortRanges allowedUDPPortRanges;
      };
      boot.kernel.sysctl."net.ipv4.conf.all.forwarding" =
        host.boot.kernel.sysctl."net.ipv4.conf.all.forwarding";

      services.openssh = {
        enable = true;
        # The firewall lists above already carry endeavour's ports.
        openFirewall = false;
        settings = {
          inherit (host.services.openssh.settings)
            PasswordAuthentication KbdInteractiveAuthentication PermitRootLogin;
        };
      };
      users.users.jordangarrison = {
        isNormalUser = true;
        # A real password, so a refused password login proves sshd refuses it.
        password = "not-a-real-password";
        openssh.authorizedKeys.keys = [ keys.snakeOilPublicKey ];
      };

      systemd.services.listeners = {
        wantedBy = [ "multi-user.target" ];
        serviceConfig.ExecStart = lib.concatStringsSep " " [
          "${pkgs.python3}/bin/python3" "${listener}"
          (lib.concatMapStringsSep "," toString stubbed)
          (lib.concatMapStringsSep "," toString [ 53 5000 tailscalePort ])
        ];
      };
    };
    lan = client 1;
    tailnet = client 2;
    docker = client 3;
    ci = client 4;
  };

  testScript = ''
    import json

    probed = json.loads('${builtins.toJSON probed}')
    expect_open = json.loads('${builtins.toJSON expectOpen}')
    ssh_opts = "-n -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5"

    start_all()
    server.wait_for_unit("listeners.service")
    server.wait_for_unit("sshd.service")

    def address(machine, dev):
        out = machine.wait_until_succeeds(f"ip -4 -o addr show dev {dev} | grep -q inet && ip -4 -o addr show dev {dev}")
        return out.split()[3].split("/")[0]

    # Give the zone interfaces endeavour's names. The rules match by name.
    targets = {}
    for dev, name, node in [("eth1", None, lan), ("eth2", "tailscale0", tailnet),
                            ("eth3", "docker0", docker), ("eth4", "br-ci", ci)]:
        targets[node.name] = address(server, dev)
        if name:
            server.succeed(f"ip link set {dev} down", f"ip link set {dev} name {name}",
                           f"ip link set {name} up")

    for node in (lan, tailnet, docker, ci):
        node.wait_until_succeeds(f"ping -c1 -W1 {targets[node.name]}")
        node.succeed("install -m600 ${keys.snakeOilPrivateKey} /root/key")

    for node in (lan, tailnet):
        ip = targets[node.name]
        with subtest(f"{node.name}: SSH by key works"):
            node.succeed(f"ssh {ssh_opts} -i /root/key jordangarrison@{ip} true >&2", timeout=60)
        with subtest(f"{node.name}: sshd offers keys only and refuses a password"):
            status, out = node.execute(f"ssh -v {ssh_opts} -o PubkeyAuthentication=no jordangarrison@{ip} true 2>&1", timeout=60)
            assert status != 0, out
            offered = [l for l in out.splitlines() if "Authentications that can continue" in l]
            assert offered and all(l.rstrip().endswith(": publickey") for l in offered), out
            node.fail(f"sshpass -p not-a-real-password ssh {ssh_opts.replace('BatchMode=yes', 'BatchMode=no')} "
                      f"-o PubkeyAuthentication=no -o PreferredAuthentications=password,keyboard-interactive "
                      f"jordangarrison@{ip} true >&2", timeout=60)

    with subtest("lan: Tailscale's UDP port answers (direct paths, not only relays)"):
        lan.succeed(f"python3 ${udpProbe} {targets['lan']} ${toString tailscalePort}")

    with subtest("tailnet: traffic routes through endeavour to the uplink (exit node)"):
        lan_client = address(lan, "eth1")
        tailnet_client = address(tailnet, "eth1")
        # The lan node stands in for the internet behind endeavour's uplink.
        tailnet.succeed(f"ip route add {lan_client}/32 via {targets['tailnet']}")
        lan.succeed(f"ip route add {tailnet_client}/32 via {targets['lan']}")
        lan.succeed("systemd-run --unit=web ${pkgs.python3}/bin/python3 -m http.server 8000")
        lan.wait_for_open_port(8000)
        tailnet.succeed(f"ping -c1 -W2 {lan_client}")
        tailnet.succeed(f"nc -z -w 3 {lan_client} 8000")

    for node in (lan, tailnet, docker, ci):
        ip = targets[node.name]
        opened = set(expect_open[node.name])
        with subtest(f"{node.name}: TCP"):
            for port in probed:
                if port in opened:
                    node.succeed(f"nc -z -w 3 {ip} {port}")
                else:
                    node.fail(f"nc -z -w 2 {ip} {port}")
        with subtest(f"{node.name}: UDP"):
            node.succeed(f"python3 ${udpProbe} {ip} 53")
            if node.name == "tailnet":
                node.succeed(f"python3 ${udpProbe} {ip} 5000")
            else:
                node.fail(f"python3 ${udpProbe} {ip} 5000")
  '';
}
