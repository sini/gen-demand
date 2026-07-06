# The five k8s claim kinds (spec Appendix A) as an executable fixture: connect/secret/storage are
# leaves (depth 0), database/route composites (depth 1). Resource bodies are simplified stand-ins
# for the real derivers — they exercise the cascade discipline (grouping, folds, dedup, sub-demand
# emission, wiring) without a live cluster ctx. Subjects are registry entries carrying `id_hash`.
{ genDemand }:
let
  inherit (genDemand) mkKind mkKinds demand folds;

  # ── entity fixtures (registry entries: id_hash + name) ──
  entry = name: {
    id_hash = "id-${name}";
    inherit name;
  };
  apps = {
    sonarr = entry "sonarr";
    radarr = entry "radarr";
    media-pg = entry "media-pg";
  };
  gatewaysNs = entry "gateways-ns";

  # A minimal static ctx passed verbatim to every resolver.
  ctx = {
    marker = "CTX-VERBATIM";
    optional = cond: v: if cond then [ v ] else [ ];
  };

  kinds = mkKinds [
    # ── floor: connect (leaf) ──
    (mkKind {
      name = "connect";
      dedupKey = d: "${d.subject.id_hash}->${d.to.id_hash}:${toString (d.port or "any")}";
      fold = folds.same; # duplicate edges must agree, provision once
      resolve = d: _ctx: {
        resources."cnp:${d.subject.name}->${d.to.name}:${toString (d.port or "any")}" = {
          from = d.subject.name;
          to = d.to.name;
          port = d.port or null;
        };
        wiring.egress = {
          to = d.to.name;
          port = d.port or null;
        };
      };
    })

    # ── leaf fabric: secret ──
    (mkKind {
      name = "secret";
      dedupKey = d: d.shared or "private:${d.subject.id_hash}:${d.name}";
      fold = folds.byKey {
        generator = folds.same; # all claimants must agree on the generator
        stringData = folds.mergeAttrs; # one stringData entry per claimant
      };
      resolve = d: _ctx: {
        resources.${d.shared or "${d.subject.name}-${d.name}"} = {
          generator = d.generator;
          stringData.${d.subject.name} = "secret://${d.subject.name}/${d.name}";
        };
        wiring.env.${d.consumeAs.env} = {
          secretKeyRef = d.shared or "${d.subject.name}-${d.name}";
          key = d.subject.name;
        };
      };
    })

    # ── leaf fabric: storage ──
    (mkKind {
      name = "storage";
      dedupKey = d: d.claim or "provision:${d.subject.id_hash}:${d.path}";
      fold = folds.same; # shared PV+PVC provisioned once
      resolve = d: _ctx: {
        resources.${d.claim or "pvc:${d.subject.name}:${d.path}"} = {
          claim = d.claim or null;
          path = d.path;
        };
        wiring.persistence.${d.path} = {
          mount = d.path;
          claim = d.claim or "pvc:${d.subject.name}:${d.path}";
        };
      };
    })

    # ── composite: database (depth 1) ──
    (mkKind {
      name = "database";
      below = [
        "secret"
        "connect"
      ];
      resolve = d: _ctx: {
        resources."cnpg:${d.subject.name}" = {
          role = d.subject.name;
          dbs = d.dbs;
        };
        wiring.env = {
          "${d.subject.name}__POSTGRES__HOST" = d.provider.name;
          "${d.subject.name}__POSTGRES__PORT" = "5432";
        };
        demands = [
          (demand {
            kind = "secret";
            subject = d.subject;
            name = "pg-password";
            generator = "rfc3986-secret";
            consumeAs.env = "${d.subject.name}__POSTGRES__PASSWORD";
          })
          (demand {
            kind = "connect";
            subject = d.subject;
            to = d.provider;
            port = 5432;
          })
        ];
      };
    })

    # ── composite: route (depth 1) ──
    (mkKind {
      name = "route";
      below = [
        "secret"
        "connect"
      ];
      resolve = d: c: {
        resources."httproute:${d.subject.name}" = {
          domain = d.domain;
          backendPort = d.backendPort;
        };
        wiring.backendRef = {
          name = d.subject.name;
          port = d.backendPort;
        };
        demands = [
          (demand {
            kind = "connect";
            subject = gatewaysNs;
            to = d.subject;
            port = d.backendPort;
          })
        ]
        ++ c.optional (d.oidc or false) (demand {
          kind = "secret";
          subject = d.subject;
          name = "oidc-client";
          generator = "rfc3986-secret";
          consumeAs.env = "OIDC_CLIENT_SECRET";
        });
      };
    })
  ];

  # The canonical root-demand list (spec Appendix A usage): sonarr route + database + shared api-key
  # secret + storage claim; radarr shares the api-key group and the storage claim.
  demands = [
    (demand {
      kind = "route";
      subject = apps.sonarr;
      domain = "sonarr";
      backendPort = "http";
      oidc = true;
    })
    (demand {
      kind = "database";
      subject = apps.sonarr;
      provider = apps.media-pg;
      dbs = [
        "main"
        "log"
      ];
    })
    (demand {
      kind = "secret";
      subject = apps.sonarr;
      name = "arr-api-key";
      generator = "hex-secret";
      shared = "media-arr-api-keys";
      consumeAs.env = "SONARR__AUTH__APIKEY";
    })
    (demand {
      kind = "storage";
      subject = apps.sonarr;
      claim = "media-data-nfs";
      path = "/data";
    })
    (demand {
      kind = "secret";
      subject = apps.radarr;
      name = "arr-api-key";
      generator = "hex-secret";
      shared = "media-arr-api-keys";
      consumeAs.env = "RADARR__AUTH__APIKEY";
    })
    (demand {
      kind = "storage";
      subject = apps.radarr;
      claim = "media-data-nfs";
      path = "/data";
    })
  ];

  resolution = genDemand.resolveAll { inherit kinds demands ctx; };
in
{
  inherit
    kinds
    demands
    ctx
    apps
    gatewaysNs
    resolution
    ;
}
