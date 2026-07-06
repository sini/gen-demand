# termination — L1b. Exactly maxDepth+1 strata top-down; each kind resolves only in its stratum;
# leaf kinds emit nothing; sub-demands validated at emission (naming the emitting chain); a deep
# synthetic DAG (depth ≥ 4) quiesces with sub-demands emitted at every level.
{ lib, genDemand, ... }:
let
  inherit (genDemand)
    mkKind
    mkKinds
    demand
    resolveAll
    ;

  didThrow = e: !(builtins.tryEval (builtins.deepSeq e null)).success;

  entry = name: {
    id_hash = "id-${name}";
    inherit name;
  };
  subj = entry "s";

  # ── deep chain l4 → l3 → … → l0, each composite emitting one sub-demand a level down ──
  chainKinds = mkKinds (
    [
      (mkKind {
        name = "l0";
        resolve = _: _: { };
      })
    ]
    ++ map (
      n:
      mkKind {
        name = "l${toString n}";
        below = [ "l${toString (n - 1)}" ];
        resolve = d: _: {
          demands = [
            (demand {
              kind = "l${toString (n - 1)}";
              subject = d.subject;
            })
          ];
        };
      }
    ) [ 1 2 3 4 ]
  );

  chainRes = resolveAll {
    kinds = chainKinds;
    demands = [ (demand { kind = "l4"; subject = subj; }) ];
  };

  # ── leaf-emits-a-sub-demand → error ──
  leafEmitsKinds = mkKinds [
    (mkKind {
      name = "m";
      resolve = _: _: { };
    })
    (mkKind {
      name = "leaf";
      # below = [] — a leaf; emitting ANY sub-demand must throw.
      resolve = d: _: {
        demands = [ (demand { kind = "m"; subject = d.subject; }) ];
      };
    })
  ];

  # ── composite emitting OUTSIDE its below → error ──
  outsideBelowKinds = mkKinds [
    (mkKind {
      name = "b";
      resolve = _: _: { };
    })
    (mkKind {
      name = "c";
      resolve = _: _: { };
    })
    (mkKind {
      name = "a";
      below = [ "b" ]; # c is registered but NOT below a
      resolve = d: _: {
        demands = [ (demand { kind = "c"; subject = d.subject; }) ];
      };
    })
  ];

  # ── emitted sub-demand with a subject lacking id_hash / shadowing a reserved key → error ──
  emitBadKinds =
    badDemand:
    mkKinds [
      (mkKind {
        name = "b";
        resolve = _: _: { };
      })
      (mkKind {
        name = "a";
        below = [ "b" ];
        resolve = _: _: { demands = [ badDemand ]; };
      })
    ];
  runEmit =
    badDemand:
    resolveAll {
      kinds = emitBadKinds badDemand;
      demands = [ (demand { kind = "a"; subject = subj; }) ];
    };
in
{
  flake.tests.termination = {
    # Each kind resolves only in its stratum: every trace demand's stratum equals its kind depth.
    test-chain-strata-descending = {
      expr = map (d: d.stratum) chainRes.trace.demands;
      expected = [
        4
        3
        2
        1
        0
      ];
    };
    # maxDepth+1 = 5 distinct strata, one demand each — the cascade quiesced (no error).
    test-chain-quiesces-count = {
      expr = builtins.length chainRes.trace.demands;
      expected = 5;
    };
    # Every parent chain reaches the root: l0's path is [0,0,0,0,0].
    test-chain-deepest-path = {
      expr = (lib.last chainRes.trace.demands).path;
      expected = [
        0
        0
        0
        0
        0
      ];
    };

    # ── emission-stage errors, each naming the emitting chain ──
    test-leaf-emitting-throws = {
      expr = didThrow (resolveAll {
        kinds = leafEmitsKinds;
        demands = [ (demand { kind = "leaf"; subject = subj; }) ];
      });
      expected = true;
    };
    test-emit-outside-below-throws = {
      expr = didThrow (resolveAll {
        kinds = outsideBelowKinds;
        demands = [ (demand { kind = "a"; subject = subj; }) ];
      });
      expected = true;
    };
    test-emit-subject-without-id-throws = {
      expr = didThrow (runEmit (demand {
        kind = "b";
        subject = { name = "no-id"; };
      }));
      expected = true;
    };
    test-emit-reserved-key-throws = {
      expr = didThrow (runEmit (demand {
        kind = "b";
        subject = subj;
        _path = "hijacked";
      }));
      expected = true;
    };
  };
}
