# gen-demand — typed demand cascade (kinds / demand / resolveAll / folds)

[![CI](https://github.com/sini/gen-demand/actions/workflows/ci.yml/badge.svg)](https://github.com/sini/gen-demand/actions/workflows/ci.yml) [![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT) [![Sponsor](https://img.shields.io/badge/Sponsor-%E2%9D%A4-pink?logo=github)](https://github.com/sponsors/sini)

Pure-Nix, `nixpkgs.lib`-free **typed demand cascade**. Graph nodes emit typed **demands**; registered
**kinds** resolve each demand into *resources* (provider-side artifacts), *wiring* (consumer-side
splice data), and *sub-demands* (lower-level demands a composite desugars into). A terminating,
stratified fold resolves the whole multiset until quiescent and returns the resolved artifacts plus a
full provenance trace.

gen-demand is the generalization of the nix-config claim/provide engine: its five k8s kinds
(`connect`/`secret`/`storage`/`database`/`route`) become **one instantiation** — kind registrations
plus a ctx (see [Appendix example](#the-five-kind-k8s-instance)). The engine owns only the cascade
discipline — termination, stratification, grouping/dedup, ordering, and provenance; kinds, subjects,
payloads, resources, and wiring values are all opaque to it.

The library produces **pure data**. It never constructs edges, modules, or configuration; at the
den-hoag layer, `resources`/`wiring` feed gen-edge constructors. It never *collects* demands either —
it takes an already-collected, **ordered** demand list (fan-in is gen-pipe's job).

## Layering

```
gen-prelude ┐
gen-graph   ┼─ gen-demand   (Class B: prelude + graph required)
gen-select ─┘  (injected)   (optional — adapters.select only; core loads without it)
```

gen-demand is a Class-B lib (deps injected per the gen convention). `prelude` (gen-prelude, the pure
utility base) and `graph` ([gen-graph](https://github.com/sini/gen-graph), registration-time DAG
validation) are required; `select` ([gen-select](https://github.com/sini/gen-select)) is injected by
the consumer only to enable the `adapters.select` surface. It depends on **nothing upward** and is
nixpkgs-lib-free (`nixpkgs` enters only in `ci/`).

## Gen Ecosystem

| Library | Role |
|---|---|
| [gen-prelude](https://github.com/sini/gen-prelude) | pure list/attr utilities — the nixpkgs-lib-free base |
| [gen-graph](https://github.com/sini/gen-graph) | accessor-based graph queries — condensation/SCC over the `below` relation |
| [gen-select](https://github.com/sini/gen-select) | selector predicates over graph positions — optional subject matching |
| **gen-demand** | **this library** — the typed demand cascade |

## Why not gen-dispatch

Dispatch fires a *fixed* rule set against *one* context, only enriches keys, and caps each identity at
once-per-fixpoint; it cannot re-dispatch a sub-claim as a new subject. gen-demand's unit of work is a
*demand instance*, and the multiset of demands **grows during resolution** (every composite emits new
sub-demands, each a new subject requiring its own resolution). Three structural mismatches make this
inexpressible as dispatch: a fixed rule set vs a growing subject multiset; a single enriched context
vs **partitioned outputs** resolvers must never observe (law L2); an LFP by monotone enrichment vs
**well-founded recursion over the kind DAG** with stratum-local aggregation. Separate contract,
separate lib — the two compose (policies emit root demands; gen-demand owns the cascade).

## The cascade discipline

Registration (`mkKinds`) computes a per-kind `depth` (`0` for a leaf, else `1 + max` over `below`),
well-defined because the `below` relation is a **downward-only DAG** checked for acyclicity at
registration. `resolveAll` then runs exactly `maxDepth + 1` strata **top-down** (`d = maxDepth … 0`):
at stratum `d` it resolves every pending demand of depth `d` in schedule order, validates and
path-assigns each emitted sub-demand *at emission*, and folds the stratum's resource fragments per
dedup group. Because every `below` edge strictly decreases depth, a stratum's demand set is complete
when it runs, and there is nothing pending after stratum 0.

- **Quiescence in ≤ DAG-depth rounds is a theorem, not an assertion** — no iteration cap, no
  "did anything change" test, no convergence loop.
- **Emission ⊥ consumption, by signature** — a resolver receives the demand's own normalized fields
  plus `_path`, and the caller's static `ctx` verbatim. Nothing else: no accumulator, no
  partial-resolution view, no registry of already-resolved artifacts. The eval-cycle failure mode the
  claim engine policed by review convention is *unexpressible* here.
- **Pinned-order dedup** — grouped fragments fold in schedule order (intake order for roots, emission
  order below them); the engine never sorts, dedups, or reorders. Undeclared duplication is a loud
  resource-key collision, never a silent last-wins.
- **Never silent** — every anomaly (unknown kind, missing `id_hash`, `below` violation, non-string
  dedup key, resource-key collision, fold mismatch) is a `throw` naming the demand path(s), kind(s),
  and rendered subject.

## Identity law

Public APIs pass and receive **registry entries** — any value carrying `id_hash` (gen-schema
identity). gen-demand does not depend on gen-schema; the requirement is structural (duck-typed on
`id_hash` presence). `"kind:name"` strings are never accepted as input; they are internal keys and
rendered display only. Output is keyed by `id_hash`, with the subject entry embedded so downstream
layers can render names without re-resolving.

## Usage

```nix
genDemand = import (fetchTree { ... }) { prelude = ...; graph = ...; };

# 1. Register kinds — a downward-only DAG, validated here.
kinds = genDemand.mkKinds [
  (genDemand.mkKind {
    name = "connect";                       # leaf (below = [])
    dedupKey = d: "${d.subject.id_hash}->${d.to.id_hash}:${toString (d.port or "any")}";
    fold = genDemand.folds.same;            # duplicate edges must agree, provision once
    resolve = d: ctx: {
      resources."cnp:${d.subject.name}->${d.to.name}" = ctx.mkCnpPair d;
      wiring.egress = ctx.mkEgressHalf d;
    };
  })
  (genDemand.mkKind {
    name = "database";
    below = [ "connect" ];                  # composite — desugars into connect
    resolve = d: ctx: {
      resources."cnpg:${d.subject.name}" = ctx.mkRole d;
      wiring.env = ctx.mkPostgresEnvBlock d;
      demands = [ (genDemand.demand { kind = "connect"; subject = d.subject; to = d.provider; port = 5432; }) ];
    };
  })
];

# 2. Resolve an ORDERED list of root demands (subjects are registry entries).
resolution = genDemand.resolveAll {
  inherit kinds;
  ctx = clusterCtx;                         # opaque, passed VERBATIM to every resolver
  demands = [
    (genDemand.demand { kind = "database"; subject = apps.sonarr; provider = apps.media-pg; dbs = [ "main" ]; })
  ];
};

# 3. Read the results.
resolution.resources   # { <kindName>.<resourceKey> = <folded value>; }
resolution.wiring      # { <id_hash> = { subject; byKind = { <kindName> = [ value ]; }; }; }
resolution.trace       # full cascade provenance (global schedule order)

# 4. Splice a subject's wiring into one attrset (per-top-level-key fold).
genDemand.spliceWiring {
  inherit resolution;
  subject = apps.sonarr;
  combine = key: vs:                        # same key:[v]:v signature as resource folds
    if key == "env" then genDemand.folds.mergeAttrs key vs
    else genDemand.folds.one key vs;        # default: single writer per key, loud on collision
};
```

## Optional: subject selection (`adapters.select`)

When gen-select is injected, `adapters.select.filterDemands { select, demands }` keeps the demands
whose **subject** matches a selector, order-preserving — a pre-filter before `resolveAll`. The subject
is projected as an identity-bearing node, so gen-select's identity-law constructors apply directly
(`sel` = the injected gen-select surface):

```nix
inherit (genDemand.adapters.select) filterDemands;

filterDemands { select = sel.entity apps.sonarr; inherit demands; };  # subject IS this entity (id_hash)
filterDemands { select = sel.kind schema.app;    inherit demands; };  # subjects of a kind (__identity.kind)
```

`sel.attrs` / `sel.star` / `sel.not` compose over the same node; a subject carrying no kind tag makes
`sel.kind` throw loudly (a projection gap, never a silent never-match). The core loads without
gen-select — `adapters` is then `{ }`.

## The five-kind k8s instance

`ci/tests/_fixtures/k8s.nix` registers the claim engine's five kinds (`connect`/`secret`/`storage`
= leaves depth 0; `database`/`route` = composites depth 1) and resolves a media-app fleet. The cascade,
observable in `trace.demands` (global schedule order — stratum-major descending, path-lex within):

```
stratum 1:  route(sonarr)    ─► secret(oidc-client) + connect(gateways-ns → sonarr:http)
            database(sonarr) ─► secret(pg-password) + connect(sonarr → media-pg:5432)
stratum 0:  secret   — "media-arr-api-keys" group folds N claimants into one Secret (folds.byKey)
            storage  — "media-data-nfs" group provisions PV+PVC once (folds.same)
            connect  — duplicate edges collapse (folds.same); same-pair-different-port stay distinct
```

A shared api-key secret folds sonarr + radarr into one `Secret` (generator agreed via `folds.same`,
one `stringData` entry per claimant via `folds.mergeAttrs`); two databases' private pg-password
secrets coexist (subject-namespaced resource keys); the shared storage claim provisions once. This is
the `instance-k8s` golden of the test suite.

## Testing

```
cd ci && nix-unit --flake .#tests          # 92 tests, one named group per spec law
```

Or inside the devshell: `ci` (all) / `ci suite.test` (one). Named groups: `registration` (L1a/L3d),
`termination` (L1b), `discipline` (L2), `dedup` (L3a-c), `provenance` (L4), `determinism` (L5), plus
`intake`, `helpers`, `adapters-select`, and `instance-k8s`.

## Theoretical foundations

- **Stratified bottom-up evaluation** — Apt, Blair & Walker, *Towards a Theory of Declarative
  Knowledge* (1988). Each kind-depth is a stratum; the dedup `fold` (aggregation) is applied only once
  a stratum's fact set is complete — the classical reason aggregation demands stratification.
  Registration-time acyclicity is the stratifiability condition made a definition-time error.
- **Termination by well-founded recursion.** Every `below` edge strictly decreases the natural-number
  `depth`, so the cascade terminates by Noetherian induction on ℕ.
- **Why/derivation provenance** — Cheney, Chiticariu & Tan, *Provenance in Databases: Why, How, and
  Where* (2009). The trace realizes witness provenance (each artifact ↦ the demand instances that
  produced it) extended with derivation *paths* (parent chains to roots). The full semiring provenance
  algebra (Green–Karvounarakis–Tannen 2007) is deliberately not implemented — traces are records, not
  algebraic values.
- **Internal provenance.** The cascade model, the five k8s kinds, the leaf/composite split, the
  shared-secret/shared-PVC dedup shapes, and the emission⊥consumption invariant originate in the
  nix-config claim/provide engine design (2026-06-13), including its two negative findings (not
  gen-dispatch; not a scope-engine graph). The pinned-order/associative-only collection discipline is
  HOAG r2 §B5.

See [REFERENCE.md](./REFERENCE.md) for the complete API contract.
