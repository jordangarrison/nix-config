{ config, lib, pkgs, ... }:

{
  services.printing = {
    enable = true;
    drivers = with pkgs; [ brlaser brgenml1lpr brgenml1cupswrapper ];
  };

  hardware.sane = {
    enable = true;
    extraBackends = with pkgs; [ sane-airscan ];
  };

  hardware.printers = {
    ensurePrinters = [{
      name = "Brother_3765";
      location = "Office";
      deviceUri = "ipp://192.168.68.73/ipp/print";
      model = "everywhere";
    }];
    ensureDefaultPrinter = "Brother_3765";
  };

  # The `everywhere` driverless model makes lpadmin query the live printer over
  # IPP at activation time. On a laptop that roams (or whenever the printer is
  # simply powered off), that query times out, ensure-printers.service exits
  # non-zero, and the whole `nixos-rebuild switch` aborts (exit 4). Treat that
  # connection failure (exit 1) as success so an unreachable printer never
  # blocks activation — the queue registers normally once the printer is online.
  systemd.services.ensure-printers.serviceConfig.SuccessExitStatus = "0 1";
}
