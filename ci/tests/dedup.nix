# dedup — L3a–c. Grouping is a pure function of the demand's own fields; folds receive fragments in
# pinned schedule order (never sorted/reordered); no silent dedup (undeclared duplication is a loud
# collision); singleton groups still pass through the fold.
{ lib, genDemand, ... }:
let
  inherit (genDemand)
    mkKind
    mkKinds
    demand
    resolveAll
    folds
    ;
  k8s = import ./_fixtures/k8s.nix { inherit genDemand; };

  didThrow = e: !(builtins.tryEval (builtins.deepSeq e null)).success;

  entry = name: {
    id_hash = "id-${name}";
    inherit name;
  };

  # An `item` kind: group by `d.group`, one resource key per group, fold = list (records order).
  itemKinds = mkKinds [
    (mkKind {
      name = "item";
      dedupKey = d: d.group;
      fold = folds.list;
      resolve = d: _: { resources.${d.group} = d.tag; };
    })
  ];
  runItems =
    tags:
    resolveAll {
      kinds = itemKinds;
      demands = map (
        t:
        demand {
          kind = "item";
          subject = entry t;
          group = "g";
          tag = t;
        }
      ) tags;
    };

  # A `same`-folded kind that produces a group-CONSTANT resource key ⇒ cross-group collision when
  # two distinct groups both write it.
  collideKinds = mkKinds [
    (mkKind {
      name = "c";
      dedupKey = d: d.group;
      fold = folds.same;
      resolve = d: _: { resources.constant = d.v; };
    })
  ];

  # A fold-less kind: two demands writing the same resource key is a loud error.
  foldlessKinds = mkKinds [
    (mkKind {
      name = "f";
      resolve = _: _: { resources.dup = 1; };
    })
  ];
in
{
  flake.tests.dedup = {
    # ── L3a: group membership golden (shared group folds N claimants into one resource) ──
    test-shared-group-single-key = {
      expr = builtins.attrNames k8s.resolution.resources.secret;
      expected = [
        "media-arr-api-keys"
        "sonarr-oidc-client"
        "sonarr-pg-password"
      ];
    };
    test-shared-group-contributors = {
      expr = k8s.resolution.trace.resources.secret."media-arr-api-keys".demands;
      expected = [
        [ 2 ]
        [ 4 ]
      ];
    };

    # ── L3b: fold receives fragments in schedule (intake) order ──
    test-fold-order-is-schedule-order = {
      expr =
        (runItems [
          "a"
          "b"
          "c"
        ]).resources.item.g;
      expected = [
        "a"
        "b"
        "c"
      ];
    };
    # ── L3b: permuting the input permutes the fold order (no silent sort) ──
    test-fold-order-follows-permutation = {
      expr =
        (runItems [
          "c"
          "a"
          "b"
        ]).resources.item.g;
      expected = [
        "c"
        "a"
        "b"
      ];
    };

    # ── singleton group still passes through the fold (one-element list) ──
    test-singleton-passes-through-fold = {
      expr = (runItems [ "solo" ]).resources.item.g;
      expected = [ "solo" ];
    };

    # ── L3c: no silent dedup — folds.same conflict is a loud error ──
    test-folds-same-conflict-throws = {
      expr = didThrow (resolveAll {
        kinds = collideKinds;
        demands = [
          (demand {
            kind = "c";
            subject = entry "x";
            group = "same-group";
            v = 1;
          })
          (demand {
            kind = "c";
            subject = entry "y";
            group = "same-group";
            v = 2; # differs ⇒ folds.same throws
          })
        ];
      });
      expected = true;
    };
    # ── L3c: cross-group resource-key collision is a loud error ──
    test-cross-group-collision-throws = {
      expr = didThrow (resolveAll {
        kinds = collideKinds;
        demands = [
          (demand {
            kind = "c";
            subject = entry "x";
            group = "g1";
            v = 1;
          })
          (demand {
            kind = "c";
            subject = entry "y";
            group = "g2"; # distinct group, same "constant" key ⇒ collision
            v = 1;
          })
        ];
      });
      expected = true;
    };
    # ── L3c: fold-less duplicate resource key is a loud error ──
    test-foldless-duplicate-throws = {
      expr = didThrow (resolveAll {
        kinds = foldlessKinds;
        demands = [
          (demand {
            kind = "f";
            subject = entry "x";
          })
          (demand {
            kind = "f";
            subject = entry "y";
          })
        ];
      });
      expected = true;
    };
    # A non-string dedupKey result is a loud error.
    test-nonstring-dedupkey-throws = {
      expr = didThrow (resolveAll {
        kinds = mkKinds [
          (mkKind {
            name = "b";
            dedupKey = _: 42;
            fold = folds.same;
            resolve = _: _: { resources.k = 1; };
          })
        ];
        demands = [
          (demand {
            kind = "b";
            subject = entry "x";
          })
        ];
      });
      expected = true;
    };
  };
}
