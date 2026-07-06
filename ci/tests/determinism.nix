# determinism — L5. `resolveAll` output is a pure, deterministic function of its inputs with the
# demand list order significant; repeated evaluation is byte-identical; structurally-equal inputs
# yield equal outputs; the engine manufactures no value (resources/wiring pass through untouched).
{ lib, genDemand, ... }:
let
  inherit (genDemand) mkKinds mkKind demand resolveAll;
  k8s = import ./_fixtures/k8s.nix { inherit genDemand; };
  r = k8s.resolution;

  entry = name: {
    id_hash = "id-${name}";
    inherit name;
  };

  # A small deterministic set, resolved twice from independently-constructed but structurally-equal
  # inputs. Values pass straight through — the engine adds nothing.
  simpleKinds = mkKinds [
    (mkKind {
      name = "leaf";
      resolve = d: _: {
        resources.${d.subject.name} = { tag = d.tag; };
        wiring.env.${d.subject.name} = d.tag;
      };
    })
  ];
  buildDemands = tags: map (t: demand { kind = "leaf"; subject = entry t; tag = t; }) tags;
  resA = resolveAll { kinds = simpleKinds; demands = buildDemands [ "x" "y" ]; };
  resB = resolveAll { kinds = simpleKinds; demands = buildDemands [ "x" "y" ]; };
in
{
  flake.tests.determinism = {
    # ── byte-identical output on repeated resolveAll (k8s fixture) ──
    test-k8s-repeated-eval-identical = {
      expr =
        let
          again = (import ./_fixtures/k8s.nix { inherit genDemand; }).resolution;
        in
        builtins.toJSON again == builtins.toJSON r;
      expected = true;
    };

    # ── structurally-equal input sets → equal outputs ──
    test-structurally-equal-inputs-equal-output = {
      expr = builtins.toJSON resA == builtins.toJSON resB;
      expected = true;
    };

    # ── the engine manufactures no value: resources pass through untouched ──
    test-resource-value-passes-through = {
      expr = resA.resources.leaf.x;
      expected = {
        tag = "x";
      };
    };
    test-wiring-value-passes-through = {
      expr = resA.wiring."id-x".byKind.leaf;
      expected = [
        { env = { x = "x"; }; }
      ];
    };

    # ── golden {resources; wiring} shape on the k8s fixture ──
    test-k8s-resource-kinds-golden = {
      expr = builtins.attrNames r.resources;
      expected = [
        "connect"
        "database"
        "route"
        "secret"
        "storage"
      ];
    };
    test-k8s-shared-secret-golden = {
      expr = r.resources.secret."media-arr-api-keys";
      expected = {
        generator = "hex-secret";
        stringData = {
          radarr = "secret://radarr/arr-api-key";
          sonarr = "secret://sonarr/arr-api-key";
        };
      };
    };
    # storage shared claim provisioned ONCE (folds.same across sonarr + radarr).
    test-k8s-shared-storage-golden = {
      expr = r.resources.storage."media-data-nfs";
      expected = {
        claim = "media-data-nfs";
        path = "/data";
      };
    };

    # ── demand list order is significant: swapping two roots reorders the trace ──
    test-order-significant = {
      expr = map (d: d.subject.rendered) (resolveAll {
        kinds = simpleKinds;
        demands = buildDemands [ "y" "x" ];
      }).trace.demands;
      expected = [
        "y"
        "x"
      ];
    };
  };
}
