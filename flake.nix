{
  description = "gen-demand — typed demand cascade (kinds resolve demands into resources + wiring + sub-demands; a stratified, terminating fold resolves the multiset with full provenance)";

  # Class layering: gen-prelude + gen-graph → gen-demand (Class B, L1-only deps, nothing upward).
  # gen-graph supplies registration-time DAG validation (condensation over the `below` relation).
  # gen-select is the OPTIONAL adapter dependency (subject matching) — injected by the consumer for
  # the `adapters.select` surface only; the core loads without it. The library (./lib) is
  # nixpkgs-lib-free — nixpkgs enters only in ci/ (the nix-unit harness + treefmt).
  inputs = {
    gen-prelude.url = "github:sini/gen-prelude";
    gen-graph.url = "github:sini/gen-graph";
    gen-graph.inputs.gen-prelude.follows = "gen-prelude";
  };

  outputs =
    { gen-prelude, gen-graph, ... }:
    {
      lib = import ./lib {
        prelude = gen-prelude.lib;
        graph = gen-graph.lib;
      };
    };
}
