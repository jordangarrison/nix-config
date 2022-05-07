#!/usr/bin/env sed -f

s/@ENVSUB_USER@/nixos/g
s/@ENVSUB_PASSWORD@/nixos/g
s/@ENVSUB_SSID@/wifi/g
s/@ENVSUB_SSID_PASSWORD@/password/g
s/@ENVSUB_INTERFACE@/wlan0/g
s/@ENVSUB_HOSTNAME@/nixos-pi/g
s/@ENVSUB_PI_VERSION@/4/g
