{ pkgs, firewall }:

# endeavour's firewall rules, as built from the real host config, on a small
# VM with one network per zone. Each client tries every port; the expected
# lists below are the policy. If a port moves, change it here on purpose.
let
  inherit (pkgs) lib;

  lanOpen = [ 22 53 1716 8096 21063 53317 ];
  # Listeners for ports nobody outside the tailnet should reach, plus the ones
  # that only containers need.
  probed = lib.unique (lanOpen ++ [ 80 443 4319 4431 4444 5432 8053 8888 9187 ]);

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
    for port in (53, 5000):
        threading.Thread(target=udp, args=(port,), daemon=True).start()
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
    environment.systemPackages = [ pkgs.netcat-openbsd pkgs.python3 ];
  };
in
pkgs.testers.runNixOSTest {
  name = "endeavour-firewall";

  nodes = {
    server = {
      # vlan 1 = LAN, 2 = tailnet, 3 = docker0, 4 = a per-job CI bridge.
      virtualisation.vlans = [ 1 2 3 4 ];
      networking.firewall = {
        enable = true;
        inherit (firewall) trustedInterfaces interfaces
          allowedTCPPorts allowedUDPPorts allowedTCPPortRanges allowedUDPPortRanges;
      };
      systemd.services.listeners = {
        wantedBy = [ "multi-user.target" ];
        serviceConfig.ExecStart = "${pkgs.python3}/bin/python3 ${listener} ${lib.concatMapStringsSep "," toString probed}";
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

    start_all()
    server.wait_for_unit("listeners.service")
    server.wait_for_open_port(22)

    def address(dev):
        out = server.wait_until_succeeds(f"ip -4 -o addr show dev {dev} | grep -q inet && ip -4 -o addr show dev {dev}")
        return out.split()[3].split("/")[0]

    # Give the zone interfaces endeavour's names. The rules match by name.
    targets = {}
    for dev, name, node in [("eth1", None, lan), ("eth2", "tailscale0", tailnet),
                            ("eth3", "docker0", docker), ("eth4", "br-ci", ci)]:
        targets[node.name] = address(dev)
        if name:
            server.succeed(f"ip link set {dev} down", f"ip link set {dev} name {name}",
                           f"ip link set {name} up")

    for node in (lan, tailnet, docker, ci):
        ip = targets[node.name]
        node.wait_until_succeeds(f"ping -c1 -W1 {ip}")
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
