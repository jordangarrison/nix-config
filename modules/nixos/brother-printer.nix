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
}
