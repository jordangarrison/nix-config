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
      name = "Brother_MFC_L3760CDW";
      location = "Office";
      # Address the printer by its stable mDNS name, not a DHCP-assigned IP.
      # The lease changes (e.g. .73 -> .58) silently break a hardcoded-IP queue;
      # BRWD8B32FCE8935.local always resolves to the printer via Avahi.
      deviceUri = "ipp://BRWD8B32FCE8935.local/ipp/print";
      # This printer rejects the generic pwgrast.ppd raster ("Print job canceled
      # at printer"). model = "everywhere" queries the printer's real IPP
      # capabilities so the job format is one it accepts. Tradeoff: lpadmin
      # contacts the printer at activation, so a powered-off printer fails
      # ensure-printers.service and aborts `nh os switch/test`. Keep the printer
      # on when rebuilding, or temporarily comment this host out if it's offline.
      model = "everywhere";
    }];
    ensureDefaultPrinter = "Brother_MFC_L3760CDW";
  };

  # A roaming laptop often can't reach the printer, and model = "everywhere"
  # makes lpadmin contact it during activation. Treat lpadmin's exit 1
  # (connection failure) as success so an unreachable printer doesn't abort
  # `nh os switch/test`; the queue is (re)created on the next rebuild at home.
  systemd.services.ensure-printers.serviceConfig.SuccessExitStatus = "1";
}
