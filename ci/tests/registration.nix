# registration — L1a (acyclicity, name resolution, uniqueness) + L3d (dedupKey/fold pairing) +
# depth/maxDepth golden over the k8s kind set.
{ lib, genDemand, ... }:
let
  inherit (genDemand) mkKind mkKinds folds;
  k8s = import ./_fixtures/k8s.nix { inherit genDemand; };

  didThrow = e: !(builtins.tryEval (builtins.deepSeq e null)).success;
  succeeds = e: (builtins.tryEval (builtins.deepSeq e null)).success;

  leaf =
    name:
    mkKind {
      inherit name;
      resolve = _: _: { };
    };
  # A kind that cascades into `bel`.
  node =
    name: bel:
    mkKind {
      inherit name;
      below = bel;
      resolve = _: _: { };
    };
in
{
  flake.tests.registration = {
    # ── L1a: cycles rejected ──
    test-two-cycle-rejected = {
      expr = didThrow (mkKinds [
        (node "a" [ "b" ])
        (node "b" [ "a" ])
      ]);
      expected = true;
    };
    test-long-cycle-rejected = {
      expr = didThrow (mkKinds [
        (node "a" [ "b" ])
        (node "b" [ "c" ])
        (node "c" [ "a" ])
      ]);
      expected = true;
    };
    test-self-loop-rejected = {
      expr = didThrow (mkKinds [ (node "a" [ "a" ]) ]);
      expected = true;
    };

    # ── L1a: unresolved below name / duplicate name ──
    test-unresolved-below-rejected = {
      expr = didThrow (mkKinds [ (node "a" [ "ghost" ]) ]);
      expected = true;
    };
    test-duplicate-name-rejected = {
      expr = didThrow (mkKinds [
        (leaf "a")
        (leaf "a")
      ]);
      expected = true;
    };

    # A well-formed downward-only DAG registers.
    test-valid-dag-registers = {
      expr = succeeds (mkKinds [
        (leaf "b")
        (leaf "c")
        (node "a" [
          "b"
          "c"
        ])
      ]);
      expected = true;
    };

    # ── L3d: dedupKey/fold pairing ──
    test-dedupkey-without-fold-rejected = {
      expr = didThrow (mkKind {
        name = "x";
        dedupKey = _: "k";
        resolve = _: _: { };
      });
      expected = true;
    };
    test-fold-without-dedupkey-rejected = {
      expr = didThrow (mkKind {
        name = "x";
        fold = folds.same;
        resolve = _: _: { };
      });
      expected = true;
    };
    test-both-dedupkey-and-fold-ok = {
      expr = succeeds (mkKind {
        name = "x";
        dedupKey = _: "k";
        fold = folds.same;
        resolve = _: _: { };
      });
      expected = true;
    };

    # ── depth / maxDepth golden over the k8s kind set ──
    test-k8s-depth-leaves = {
      expr = {
        inherit (k8s.kinds.depth) connect secret storage;
      };
      expected = {
        connect = 0;
        secret = 0;
        storage = 0;
      };
    };
    test-k8s-depth-composites = {
      expr = {
        inherit (k8s.kinds.depth) database route;
      };
      expected = {
        database = 1;
        route = 1;
      };
    };
    test-k8s-max-depth = {
      expr = k8s.kinds.maxDepth;
      expected = 1;
    };

    # Deep synthetic DAG: depth accumulates strictly along `below` edges.
    test-deep-depth = {
      expr =
        (mkKinds [
          (leaf "l0")
          (node "l1" [ "l0" ])
          (node "l2" [ "l1" ])
          (node "l3" [ "l2" ])
          (node "l4" [ "l3" ])
        ]).depth;
      expected = {
        l0 = 0;
        l1 = 1;
        l2 = 2;
        l3 = 3;
        l4 = 4;
      };
    };

    # Attrset input form accepted (values used; kind.name is canonical).
    test-attrset-input-accepted = {
      expr = succeeds (mkKinds {
        b = leaf "b";
        a = node "a" [ "b" ];
      });
      expected = true;
    };
  };
}
