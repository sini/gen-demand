# gen-demand public API — typed demand cascade (kinds / demand / resolveAll / folds / helpers).
#
# Class layering: consumes gen-prelude (list/attr folds) and gen-graph (registration-time DAG
# validation). gen-select is injected ONLY for the optional `adapters.select` surface — the core
# loads without it (`select = null`). nixpkgs-lib-free throughout.
{
  prelude,
  graph,
  select ? null,
}:
let
  foldsLib = import ./folds.nix { inherit prelude; };
  kindsLib = import ./kind.nix { inherit prelude graph; };
  demandLib = import ./demand.nix { inherit prelude; };
  resolveLib = import ./resolve.nix {
    inherit
      prelude
      kindsLib
      demandLib
      foldsLib
      ;
  };
  helpersLib = import ./helpers.nix { inherit prelude foldsLib; };

  adapters =
    if select == null then
      { }
    else
      {
        select = import ./adapters/select.nix { inherit prelude; selectLib = select; };
      };
in
{
  inherit (kindsLib) mkKind mkKinds;
  inherit (demandLib) demand;
  inherit (resolveLib) resolveAll;
  inherit (helpersLib) wiringFor spliceWiring;
  inherit (foldsLib) folds;
  inherit adapters;
}
