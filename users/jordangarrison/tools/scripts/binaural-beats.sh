#!/usr/bin/env bash

# Binaural Beats for Focus – Lower Carrier Frequency for Comfort
# Left ear: 100 Hz, Right ear: 118 Hz (18 Hz beta wave for focus)
# Duration: 20 minutes (1200 seconds)

DURATION=1200
CARRIER=100
BEAT=18

LEFT_FREQ=$CARRIER
RIGHT_FREQ=$(echo "$CARRIER + $BEAT" | bc)

${pkgs.sox}/bin/play -n synth $DURATION sine $LEFT_FREQ synth $DURATION sine $RIGHT_FREQ channels 2 remix 1v0.5 2v0.5
