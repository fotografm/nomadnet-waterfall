#!/bin/sh
# Wrapper: renders index.mu in "live" mode -- a thin page that embeds the
# waterfall as an auto-refreshing Micron partial. One implementation, so the
# renderer and its options stay in index.mu.
PAGES="${PAGES:-/root/.nomadnetwork/storage/pages}"
exec env var_live=1 "$PAGES/index.mu"
