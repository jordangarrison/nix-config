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
      deviceUri = "ipp://192.168.68.73/ipp/print";
      # Use a local generic IPP Everywhere PPD instead of model = "everywhere".
      # "everywhere" makes lpadmin contact the printer at activation to fetch its
      # capabilities, so a powered-off printer fails ensure-printers.service and
      # aborts the whole `nh os switch/test` activation. The local PPD registers
      # the queue without touching the network; jobs simply queue when it's offline.
      model = "drv:///cupsfilters.drv/pwgrast.ppd";
    }];
    ensureDefaultPrinter = "Brother_MFC_L3760CDW";
  };
}
