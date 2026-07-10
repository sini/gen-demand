# adapters-select — the OPTIONAL gen-select adapter (loaded only when gen-select is injected).
# `filterDemands` keeps demands whose SUBJECT matches a gen-select selector, order-preserving.
# The selector is opaque to gen-demand: it is passed verbatim to gen-select's `matches` against a
# single-node context that projects the subject as an identity-bearing node (id_hash + kind).
{
  lib,
  genDemand,
  genDemandWithSelect,
  genSelect,
  ...
}:
let
  inherit (genDemandWithSelect) demand;
  inherit (genDemandWithSelect.adapters.select) filterDemands;

  # Subjects carry id_hash (identity) + name; `type` is the positional kind tag the adapter projects to
  # `__identity.kind` for `sel.kind`.
  entry = name: type: {
    id_hash = "id-${name}";
    inherit name type;
  };
  # A gen-schema-shaped kind VALUE — what `sel.kind` takes (it validates `? kind && ? options`, rejecting
  # a bare name string). `options` is a stub; only the kind NAME reaches the projection.
  kindVal = k: {
    kind = k;
    options = { };
  };

  demands = [
    (demand {
      kind = "route";
      subject = entry "sonarr" "app";
    })
    (demand {
      kind = "route";
      subject = entry "media-pg" "db";
    })
    (demand {
      kind = "route";
      subject = entry "radarr" "app";
    })
  ];

  names = ds: map (d: d.subject.name) ds;
in
{
  flake.tests.adapters-select = {
    # ── sel.entity <entry> — match one specific entity by content-addressed identity (id_hash) ──
    test-select-entity-by-identity = {
      expr = names (filterDemands {
        select = genSelect.entity (entry "sonarr" "app");
        inherit demands;
      });
      expected = [ "sonarr" ];
    };

    # ── sel.kind <kind-value> — match all entities of a kind (via __identity.kind) ──
    test-select-kind-matches-all-of-kind = {
      expr = names (filterDemands {
        select = genSelect.kind (kindVal "app");
        inherit demands;
      });
      expected = [
        "sonarr"
        "radarr"
      ];
    };

    # ── star matches every subject; order preserved ──
    test-select-star-order-preserved = {
      expr = names (filterDemands {
        select = genSelect.star;
        inherit demands;
      });
      expected = [
        "sonarr"
        "media-pg"
        "radarr"
      ];
    };

    # ── negation composes over sel.kind ──
    test-select-not = {
      expr = names (filterDemands {
        select = genSelect.not (genSelect.kind (kindVal "app"));
        inherit demands;
      });
      expected = [ "media-pg" ];
    };

    # ── sel.kind against a kind-BLIND subject (no `type` tag) THROWS — a projection gap, loud not
    #    silent (gen-select's A1 never-match failure class); the adapter never guesses a missing kind. ──
    test-select-kind-blind-throws = {
      expr =
        let
          noType = demand {
            kind = "route";
            subject = {
              id_hash = "id-x";
              name = "x";
            };
          };
        in
        (builtins.tryEval (
          builtins.deepSeq (filterDemands {
            select = genSelect.kind (kindVal "app");
            demands = [ noType ];
          }) true
        )).success;
      expected = false;
    };

    # ── the adapter surface is absent on the core lib (no gen-select injected) ──
    test-core-has-no-adapters = {
      expr = genDemand.adapters;
      expected = { };
    };
  };
}
