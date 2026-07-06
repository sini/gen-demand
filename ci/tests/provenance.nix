# provenance — L4. Every trace demand's parent chain reaches a root; every resource/wiring artifact
# maps to ≥1 contributing path; wiring trace aligns positionally with `byKind`; global schedule order
# is stratum-major (a sub-demand at [0 0] lists AFTER a root at [1]); traces are pure functions of
# the inputs (equal across repeated evaluation).
#
# THEORY: why/derivation provenance (Cheney, Chiticariu & Tan 2009) — each artifact maps to the
# demand instances that produced it, extended with parent chains to roots.
{ lib, genDemand, ... }:
let
  k8s = import ./_fixtures/k8s.nix { inherit genDemand; };
  r = k8s.resolution;

  inherit (builtins)
    all
    attrNames
    elem
    length
    map
    ;

  demands = r.trace.demands;
  pathsPresent = map (d: d.path) demands;

  # `init` of a non-empty list (drop last element).
  parentPrefix = p: lib.init p;

  # Every demand's parent is either null (a root) or the direct-prefix path of an existing demand.
  parentChainsSound = all (
    d:
    if d.parent == null then length d.path == 1 else d.parent == parentPrefix d.path && elem d.parent pathsPresent
  ) demands;

  # The stratum-major golden: locate route[0], database[1], and the connect sub-demand [0 0].
  idxOfPath =
    p:
    lib.foldl (
      acc: i: if (builtins.elemAt demands i).path == p then i else acc
    ) (throw "path ${builtins.toJSON p} not in trace") (lib.range 0 (length demands - 1));
in
{
  flake.tests.provenance = {
    # ── every parent chain reaches a root ──
    test-parent-chains-reach-root = {
      expr = parentChainsSound;
      expected = true;
    };

    # ── every resource artifact maps to ≥1 contributing path ──
    test-resource-artifacts-have-paths = {
      expr = all (
        kn: all (k: length r.trace.resources.${kn}.${k}.demands >= 1) (attrNames r.trace.resources.${kn})
      ) (attrNames r.trace.resources);
      expected = true;
    };
    # ── every wiring artifact maps to ≥1 contributing demand ──
    test-wiring-artifacts-have-paths = {
      expr = all (id: length r.trace.wiring.${id} >= 1) (attrNames r.trace.wiring);
      expected = true;
    };

    # ── wiring trace aligns positionally with byKind lists (per subject, per kind, same length) ──
    test-wiring-trace-aligns-with-bykind = {
      expr = all (
        id:
        let
          traceKinds = map (e: e.kind) r.trace.wiring.${id};
          byKind = r.wiring.${id}.byKind;
        in
        all (kn: length (builtins.filter (k: k == kn) traceKinds) == length byKind.${kn}) (attrNames byKind)
      ) (attrNames r.trace.wiring);
      expected = true;
    };

    # ── global schedule order: stratum-major, NOT global path-lex ──
    # sub-demand [0 0] (stratum 0) must list AFTER root [1] (stratum 1), even though [0 0] is
    # path-lex-before [1].
    test-substratum-after-higher-root = {
      expr =
        idxOfPath [
          0
          0
        ] > idxOfPath [ 1 ];
      expected = true;
    };
    test-roots-of-higher-stratum-first = {
      expr =
        idxOfPath [ 0 ] < idxOfPath [
          0
          0
        ];
      expected = true;
    };

    # ── full-trace golden: the exact global sequence of (path, kind) ──
    test-full-trace-sequence = {
      expr = map (d: {
        inherit (d) kind;
        p = d.path;
      }) demands;
      expected = [
        {
          kind = "route";
          p = [ 0 ];
        }
        {
          kind = "database";
          p = [ 1 ];
        }
        {
          kind = "connect";
          p = [
            0
            0
          ];
        }
        {
          kind = "secret";
          p = [
            0
            1
          ];
        }
        {
          kind = "secret";
          p = [
            1
            0
          ];
        }
        {
          kind = "connect";
          p = [
            1
            1
          ];
        }
        {
          kind = "secret";
          p = [ 2 ];
        }
        {
          kind = "storage";
          p = [ 3 ];
        }
        {
          kind = "secret";
          p = [ 4 ];
        }
        {
          kind = "storage";
          p = [ 5 ];
        }
      ];
    };

    # ── trace is a pure function of the inputs: byte-identical across repeated evaluation ──
    test-trace-pure-across-eval = {
      expr =
        let
          again = (import ./_fixtures/k8s.nix { inherit genDemand; }).resolution;
        in
        builtins.toJSON again.trace == builtins.toJSON r.trace;
      expected = true;
    };
  };
}
