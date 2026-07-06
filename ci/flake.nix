{
  inputs = {
    gen.url = "github:sini/gen";
    gen-prelude.url = "github:sini/gen-prelude";
    gen-graph.url = "github:sini/gen-graph";
    gen-graph.inputs.gen-prelude.follows = "gen-prelude";
    # gen-select is the OPTIONAL adapter dep — it enters ONLY here (a value wired into the lib for
    # the `adapters.select` surface + the adapters-select suite), never a `lib/` flake input.
    gen-select.url = "github:sini/gen-select";
    # nixpkgs is the CI runner's dependency (nix-unit harness, treefmt) and supplies the `lib` the
    # test modules use. It enters ONLY here — the library (../lib) is nixpkgs-lib-free.
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
  };

  outputs =
    inputs@{
      gen,
      gen-prelude,
      gen-graph,
      gen-select,
      ...
    }:
    let
      # Core surface: gen-demand with prelude + graph only (no adapters).
      genDemand = import ../lib {
        prelude = gen-prelude.lib;
        graph = gen-graph.lib;
      };
      # Adapter surface: the SAME lib wired with the injected gen-select (adapters.select).
      genDemandWithSelect = import ../lib {
        prelude = gen-prelude.lib;
        graph = gen-graph.lib;
        select = gen-select.lib;
      };
    in
    gen.lib.mkCi {
      inherit inputs;
      name = "gen-demand";
      testModules = ./tests;
      specialArgs = {
        inherit genDemand genDemandWithSelect;
        genSelect = gen-select.lib;
      };
    };
}
