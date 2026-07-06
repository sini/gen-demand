# helpers — the stock folds + consumer accessors (`wiringFor`, `spliceWiring`).
{ lib, genDemand, ... }:
let
  inherit (genDemand)
    folds
    wiringFor
    spliceWiring
    ;
  k8s = import ./_fixtures/k8s.nix { inherit genDemand; };
  r = k8s.resolution;

  didThrow = e: !(builtins.tryEval (builtins.deepSeq e null)).success;

  # api-key secret fold spec, exercised directly.
  secretByKey = folds.byKey {
    generator = folds.same;
    stringData = folds.mergeAttrs;
  };
in
{
  flake.tests.helpers = {
    # ── stock fold semantics ──
    test-folds-list = {
      expr = folds.list "k" [
        1
        2
        3
      ];
      expected = [
        1
        2
        3
      ];
    };
    test-folds-same-agrees = {
      expr = folds.same "k" [
        7
        7
        7
      ];
      expected = 7;
    };
    test-folds-same-conflict-throws = {
      expr = didThrow (
        folds.same "k" [
          1
          2
        ]
      );
      expected = true;
    };
    test-folds-one-single = {
      expr = folds.one "k" [ 42 ];
      expected = 42;
    };
    test-folds-one-second-throws = {
      expr = didThrow (
        folds.one "k" [
          1
          2
        ]
      );
      expected = true;
    };
    test-folds-mergeattrs-disjoint = {
      expr = folds.mergeAttrs "k" [
        { a = 1; }
        { b = 2; }
      ];
      expected = {
        a = 1;
        b = 2;
      };
    };
    test-folds-mergeattrs-collision-throws = {
      expr = didThrow (
        folds.mergeAttrs "k" [
          { a = 1; }
          { a = 2; }
        ]
      );
      expected = true;
    };

    # ── folds.byKey: per-key dispatch, skipped-key, unknown-key, non-attrset ──
    test-bykey-per-key-dispatch = {
      expr = secretByKey "media-arr-api-keys" [
        {
          generator = "hex-secret";
          stringData.sonarr = "s";
        }
        {
          generator = "hex-secret";
          stringData.radarr = "r";
        }
      ];
      expected = {
        generator = "hex-secret";
        stringData = {
          sonarr = "s";
          radarr = "r";
        };
      };
    };
    # A fragment omitting a spec key is skipped (pinned order preserved among those that define it).
    test-bykey-skipped-key = {
      expr = secretByKey "k" [
        { generator = "g"; }
        {
          generator = "g";
          stringData.a = 1;
        }
      ];
      expected = {
        generator = "g";
        stringData = {
          a = 1;
        };
      };
    };
    # `generator` disagreement inside byKey routes to folds.same → throws.
    test-bykey-subfold-conflict-throws = {
      expr = didThrow (
        secretByKey "k" [
          { generator = "g1"; }
          { generator = "g2"; }
        ]
      );
      expected = true;
    };
    test-bykey-unknown-fragment-key-throws = {
      expr = didThrow (secretByKey "k" [ { rogue = 1; } ]);
      expected = true;
    };
    test-bykey-non-attrset-fragment-throws = {
      expr = didThrow (secretByKey "k" [ 7 ]);
      expected = true;
    };

    # ── wiringFor: global schedule order across kinds for one subject ──
    test-wiringfor-global-order = {
      expr = map (e: e.kind) (wiringFor r k8s.apps.sonarr);
      expected = [
        "route"
        "database"
        "secret"
        "secret"
        "connect"
        "secret"
        "storage"
      ];
    };
    # each wiringFor entry carries its contributing demand path.
    test-wiringfor-carries-demand-path = {
      expr = map (e: e.demand) (wiringFor r k8s.apps.sonarr);
      expected = [
        [ 0 ]
        [ 1 ]
        [
          0
          1
        ]
        [
          1
          0
        ]
        [
          1
          1
        ]
        [ 2 ]
        [ 3 ]
      ];
    };

    # ── spliceWiring: default folds.one is single-writer-per-key (disjoint splice) ──
    test-splice-default-disjoint = {
      expr = spliceWiring {
        resolution = r;
        subject = k8s.apps.radarr;
      };
      # radarr has only storage (persistence) + secret(api-key env) wiring — disjoint top-level keys.
      expected = {
        env = {
          RADARR__AUTH__APIKEY = {
            secretKeyRef = "media-arr-api-keys";
            key = "radarr";
          };
        };
        persistence = {
          "/data" = {
            mount = "/data";
            claim = "media-data-nfs";
          };
        };
      };
    };
    # default folds.one collision: sonarr multi-writes `env` (database + secret) ⇒ loud error.
    test-splice-default-collision-throws = {
      expr = didThrow (spliceWiring {
        resolution = r;
        subject = k8s.apps.sonarr;
      });
      expected = true;
    };
    # explicit per-key combine (Appendix A): env/persistence merged, egress list-collected.
    test-splice-explicit-combine = {
      expr =
        let
          s = spliceWiring {
            resolution = r;
            subject = k8s.apps.sonarr;
            combine =
              key: vs:
              if key == "env" || key == "persistence" then
                folds.mergeAttrs key vs
              else if key == "egress" then
                folds.list key vs
              else
                folds.one key vs;
          };
        in
        {
          keys = builtins.attrNames s;
          envKeys = builtins.attrNames s.env;
          egressLen = builtins.length s.egress;
          backendRef = s.backendRef;
        };
      expected = {
        keys = [
          "backendRef"
          "egress"
          "env"
          "persistence"
        ];
        envKeys = [
          "OIDC_CLIENT_SECRET"
          "SONARR__AUTH__APIKEY"
          "sonarr__POSTGRES__HOST"
          "sonarr__POSTGRES__PASSWORD"
          "sonarr__POSTGRES__PORT"
        ];
        egressLen = 1;
        backendRef = {
          name = "sonarr";
          port = "http";
        };
      };
    };
  };
}
