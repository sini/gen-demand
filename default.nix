# Standalone (non-flake) entry. Flake consumers should use the `.lib` output.
#
# gen-demand is a function of `prelude` (gen-prelude) and `graph` (gen-graph), with `select`
# (gen-select) OPTIONAL — every core export works with `select = null`. The default fetches the
# flake-locked revs (content-addressed via narHash, so the plain-import path stays pure and in
# lockstep with the flake output; per the gen root-file convention).
{
  lock ? builtins.fromJSON (builtins.readFile ./flake.lock),
  fetch ? name: builtins.fetchTree lock.nodes.${lock.nodes.root.inputs.${name}}.locked,
  prelude ? import "${fetch "gen-prelude"}/lib",
  graph ? import "${fetch "gen-graph"}/lib" { inherit prelude; },
  select ? null,
}:
import ./lib { inherit prelude graph select; }
