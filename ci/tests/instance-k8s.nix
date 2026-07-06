# instance-k8s — the five-kind claim cascade (spec Appendix A) as an executable golden: composite
# cascades observed in the trace, shared-group folding, private-secret coexistence, shared-storage
# once, connect dedup + port-distinct groups, and the per-app wiring splice.
{ lib, genDemand, ... }:
let
  inherit (genDemand)
    demand
    resolveAll
    folds
    ;
  k8s = import ./_fixtures/k8s.nix { inherit genDemand; };
  r = k8s.resolution;

  entry = name: {
    id_hash = "id-${name}";
    inherit name;
  };
  a = entry "a";
  b = entry "b";

  # ── two databases sharing a provider: private pg-password secrets must coexist (subject-namespaced) ──
  twoDbs = resolveAll {
    inherit (k8s) kinds ctx;
    demands = [
      (demand {
        kind = "database";
        subject = k8s.apps.sonarr;
        provider = k8s.apps.media-pg;
        dbs = [ "main" ];
      })
      (demand {
        kind = "database";
        subject = k8s.apps.radarr;
        provider = k8s.apps.media-pg;
        dbs = [ "main" ];
      })
    ];
  };

  # ── connect dedup + port-distinctness (folds.same collapses identical edges; port splits groups) ──
  connects = resolveAll {
    inherit (k8s) kinds ctx;
    demands = [
      (demand {
        kind = "connect";
        subject = a;
        to = b;
        port = 80;
      })
      (demand {
        kind = "connect";
        subject = a;
        to = b;
        port = 80;
      }) # identical ⇒ folds.same collapses to one
      (demand {
        kind = "connect";
        subject = a;
        to = b;
        port = 443;
      }) # different port ⇒ distinct group + distinct key
    ];
  };
in
{
  flake.tests.instance-k8s = {
    # ── route → connect(gateways-ns→sonarr) + secret(oidc); database → secret(pg) + connect(→pg) ──
    test-route-cascade-in-trace = {
      expr = lib.filter (d: d.parent == [ 0 ]) (map (d: { inherit (d) kind parent; }) r.trace.demands);
      expected = [
        {
          kind = "connect";
          parent = [ 0 ];
        }
        {
          kind = "secret";
          parent = [ 0 ];
        }
      ];
    };
    test-database-cascade-in-trace = {
      expr = lib.filter (d: d.parent == [ 1 ]) (map (d: { inherit (d) kind parent; }) r.trace.demands);
      expected = [
        {
          kind = "secret";
          parent = [ 1 ];
        }
        {
          kind = "connect";
          parent = [ 1 ];
        }
      ];
    };

    # ── shared api-key group folds N claimants into ONE Secret (byKey: generator same, stringData merge) ──
    test-shared-api-key-single-secret = {
      expr =
        r.resources.secret."media-arr-api-keys" == {
          generator = "hex-secret";
          stringData = {
            sonarr = "secret://sonarr/arr-api-key";
            radarr = "secret://radarr/arr-api-key";
          };
        };
      expected = true;
    };

    # ── two databases' private pg-password secrets coexist (subject-namespaced keys, no collision) ──
    test-private-secrets-coexist = {
      expr = builtins.attrNames twoDbs.resources.secret;
      expected = [
        "radarr-pg-password"
        "sonarr-pg-password"
      ];
    };

    # ── shared storage claim provisioned once ──
    test-shared-storage-once = {
      expr = builtins.attrNames r.resources.storage;
      expected = [ "media-data-nfs" ];
    };
    test-shared-storage-single-contributor-list = {
      # folds.same over two claimants (sonarr + radarr) ⇒ one provisioned value, both paths traced.
      expr = r.trace.resources.storage."media-data-nfs".demands;
      expected = [
        [ 3 ]
        [ 5 ]
      ];
    };

    # ── connect dedup via folds.same; same-pair different-port stays distinct ──
    test-connect-dedup-and-port-distinct = {
      expr = builtins.attrNames connects.resources.connect;
      expected = [
        "cnp:a->b:443"
        "cnp:a->b:80"
      ];
    };
    test-connect-dedup-collapses-identical = {
      # the two identical :80 edges collapse to one group; both intake paths traced.
      expr = connects.trace.resources.connect."cnp:a->b:80".demands;
      expected = [
        [ 0 ]
        [ 1 ]
      ];
    };

    # ── per-app wiring splice golden (Appendix A explicit per-key combine) ──
    test-sonarr-wiring-splice = {
      expr = genDemand.spliceWiring {
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
      expected = {
        backendRef = {
          name = "sonarr";
          port = "http";
        };
        egress = [
          {
            to = "media-pg";
            port = 5432;
          }
        ];
        env = {
          OIDC_CLIENT_SECRET = {
            secretKeyRef = "sonarr-oidc-client";
            key = "sonarr";
          };
          SONARR__AUTH__APIKEY = {
            secretKeyRef = "media-arr-api-keys";
            key = "sonarr";
          };
          sonarr__POSTGRES__HOST = "media-pg";
          sonarr__POSTGRES__PORT = "5432";
          sonarr__POSTGRES__PASSWORD = {
            secretKeyRef = "sonarr-pg-password";
            key = "sonarr";
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
  };
}
