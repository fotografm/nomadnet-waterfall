#!/bin/sh
# Wrapper: renders index.mu in "part" mode -- ruler and waterfall only, no
# banner or footer. This is what live.mu embeds and the browser re-requests.
PAGES="${PAGES:-/root/.nomadnetwork/storage/pages}"
exec env var_part=1 "$PAGES/index.mu"
