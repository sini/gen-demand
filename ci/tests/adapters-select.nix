# adapters-select — the OPTIONAL gen-select adapter (loaded only when gen-select is injected).
# `filterDemands` keeps demands whose SUBJECT matches a gen-select selector, order-preserving.
# The selector is opaque to gen-demand: it is passed verbatim to gen-select's `matches` against a
# single-node context built from each demand's subject entry.
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

  # Subjects carry id_hash (identity), name, and a kind tag `type` for sel.kind / entityKind.
  entry = name: type: {
    id_hash = "id-${name}";
    inherit name type;
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
    # ── sel.entity <entry> — match one specific entity by identity (id_hash) ──
    test-select-entity-by-identity = {
      expr = names (filterDemands {
        select = genSelect.attrs { id_hash = "id-sonarr"; };
        inherit demands;
      });
      expected = [ "sonarr" ];
    };

    # ── sel.kind <schema-kind> — match all entities of a kind ──
    test-select-kind-matches-all-of-kind = {
      expr = names (filterDemands {
        select = genSelect.entityKind "app";
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

    # ── negation composes ──
    test-select-not = {
      expr = names (filterDemands {
        select = genSelect.not (genSelect.entityKind "app");
        inherit demands;
      });
      expected = [ "media-pg" ];
    };

    # ── the adapter surface is absent on the core lib (no gen-select injected) ──
    test-core-has-no-adapters = {
      expr = genDemand.adapters;
      expected = { };
    };
  };
}
