# discipline — L2 (emission ⊥ consumption, by signature). A resolver receives EXACTLY the demand's
# own normalized fields plus `_path`, and the caller's static `ctx` verbatim — never resources,
# wiring, trace, or any partial-resolution view. Resolvers embed what they saw into their resources
# so the test can assert the input shape at every stratum.
{ lib, genDemand, ... }:
let
  inherit (genDemand)
    mkKind
    mkKinds
    demand
    resolveAll
    ;

  subj = {
    id_hash = "id-s";
    name = "s";
  };
  ctxIn = {
    alpha = 1;
    beta = {
      nested = true;
    };
  };

  probe = d: ctx: {
    ctxNames = builtins.attrNames ctx;
    ctxAlpha = ctx.alpha;
    ctxHasResources = ctx ? resources;
    ctxHasWiring = ctx ? wiring;
    ctxHasTrace = ctx ? trace;
    demandNames = builtins.attrNames d;
  };

  kinds = mkKinds [
    (mkKind {
      name = "leaf";
      resolve = d: ctx: { resources.leafSeen = probe d ctx; };
    })
    (mkKind {
      name = "comp";
      below = [ "leaf" ];
      resolve = d: ctx: {
        resources.compSeen = probe d ctx;
        demands = [ (demand { kind = "leaf"; subject = d.subject; }) ];
      };
    })
  ];

  res = resolveAll {
    inherit kinds;
    ctx = ctxIn;
    demands = [
      (demand {
        kind = "comp";
        subject = subj;
        extra = "payload";
      })
    ];
  };

  comp = res.resources.comp.compSeen;
  leaf = res.resources.leaf.leafSeen;
in
{
  flake.tests.discipline = {
    # ── ctx verbatim at the composite (stratum 1) ──
    test-comp-ctx-names-verbatim = {
      expr = comp.ctxNames;
      expected = [
        "alpha"
        "beta"
      ];
    };
    test-comp-ctx-value-verbatim = {
      expr = comp.ctxAlpha;
      expected = 1;
    };
    test-comp-ctx-no-resources = {
      expr = comp.ctxHasResources;
      expected = false;
    };
    test-comp-ctx-no-wiring = {
      expr = comp.ctxHasWiring;
      expected = false;
    };
    test-comp-ctx-no-trace = {
      expr = comp.ctxHasTrace;
      expected = false;
    };
    # Resolver input is exactly the demand's own fields + `_path` — no _reserved / parent / stratum.
    test-comp-demand-names = {
      expr = comp.demandNames;
      expected = [
        "_path"
        "_type"
        "extra"
        "kind"
        "subject"
      ];
    };

    # ── ctx verbatim at the leaf (stratum 0) — same static ctx threaded down ──
    test-leaf-ctx-names-verbatim = {
      expr = leaf.ctxNames;
      expected = [
        "alpha"
        "beta"
      ];
    };
    test-leaf-ctx-no-resolution-view = {
      expr = [
        leaf.ctxHasResources
        leaf.ctxHasWiring
        leaf.ctxHasTrace
      ];
      expected = [
        false
        false
        false
      ];
    };
    # Sub-demand input shape: own fields + `_path`, nothing engine-injected.
    test-leaf-demand-names = {
      expr = leaf.demandNames;
      expected = [
        "_path"
        "_type"
        "kind"
        "subject"
      ];
    };
  };
}
