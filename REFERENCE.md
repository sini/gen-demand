# gen-demand -- Canonical Reference

**Source of truth:** [github:sini/gen-demand](https://github.com/sini/gen-demand)
**Spec lineage:** `den-architecture/specs/2026-07-05-gen-demand-component-spec.md` (component of the
den-hoag component roadmap §6, `2026-07-05-den-hoag-component-roadmap.md`)
**Last audited:** 2026-07-05

## Purpose

gen-demand is a pure library implementing a **typed demand cascade**. Graph nodes emit typed
**demands**; registered **kinds** resolve each demand into *resources* (provider-side artifacts),
*wiring* (consumer-side splice data), and *sub-demands* (lower-level demands a composite desugars
into); a terminating, stratified fold resolves the whole multiset until quiescent and returns the
resolved artifacts plus a full provenance trace. The engine owns only the cascade discipline —
termination, stratification, grouping/dedup, ordering, and provenance. Kinds, subjects, payloads,
resources, and wiring values are all opaque to it.

It is the generalization of the nix-config claim/provide engine (2026-06-13): that engine's five k8s
kinds become one instantiation (kind registrations plus a ctx), its phased rollout becomes data
(which kinds are registered), not architecture.

gen-demand occupies an L2 (contract-library) position: it depends only on gen-prelude and gen-graph
(both L1), with gen-select injected optionally for the `adapters.select` surface. It depends on
nothing upward and is `nixpkgs.lib`-free.

### Non-goals

- **No delivery** — produces pure data; never constructs edges/modules/configuration (that is
  gen-edge at the den-hoag layer).
- **No collection** — takes an already-collected, ordered demand list (fan-in is gen-pipe's job).
- **No rendering** — resource/wiring construction happens inside caller-supplied `resolve` functions.
- **No general fixpoint** — this is not gen-dispatch and not a re-entrant rule engine; the cascade is
  well-founded structural recursion over a registration-time-checked DAG (no convergence loop, no
  iteration cap).

## Academic Provenance

| Feature | Source | Relationship |
|---|---|---|
| Depth-stratified schedule + stratum-local aggregation | Apt, Blair & Walker (1988) "Towards a Theory of Declarative Knowledge" | Implements: each kind-depth is a stratum; the dedup `fold` is applied only when a stratum's fact set is complete. Registration-time acyclicity = the stratifiability condition as a definition-time error. (No negation semantics realized.) |
| Termination by well-founded recursion | Noetherian induction on ℕ | Implements: every `below` edge strictly decreases the `depth` measure ⇒ the cascade terminates; "exactly maxDepth+1 strata" verifies a theorem, not a heuristic |
| Why/derivation provenance | Cheney, Chiticariu & Tan (2009) "Provenance in Databases: Why, How, and Where" | Implements: the trace maps each artifact to the demand instances that produced it (witness provenance) extended with parent chains (derivation paths). Semiring provenance (Green–Karvounarakis–Tannen 2007) deliberately **not** implemented — traces are records, not algebraic values |
| Cascade model, five k8s kinds, emission⊥consumption invariant, shared-secret/shared-PVC dedup | nix-config claim/provide engine design (2026-06-13) | Implements: the primitive that engine lacked; its two negative findings preserved (not gen-dispatch; not a scope-engine graph) |
| Pinned-order / associative-only collection | HOAG r2 (2026-06-09) §B5 | Implements: `fold` receives fragments in pinned schedule order; no silent reorder/dedup |

## Layering & Entry Points

**`flake.nix`** exports `lib = import ./lib { prelude = gen-prelude.lib; graph = gen-graph.lib; }`.
gen-select is *not* a flake input of the library; the consumer injects it (see `ci/flake.nix`, which
wires `genDemandWithSelect`).

**`default.nix`** (standalone, non-flake) accepts `{ prelude ? …; graph ? …; select ? null }`,
fetching the flake-locked revs by default.

**`lib/default.nix`** accepts `{ prelude, graph, select ? null }` and returns the flat public
attrset. When `select == null`, `adapters` is `{ }` (the core loads without gen-select).

```
{
  mkKind, mkKinds,          # kind registration (lib/kind.nix)
  demand,                   # demand construction (lib/demand.nix)
  resolveAll,               # the cascade (lib/resolve.nix)
  wiringFor, spliceWiring,  # consumer accessors (lib/helpers.nix)
  folds,                    # stock folds (lib/folds.nix)
  adapters = {              # optional (gen-select injected)
    select = { filterDemands; };
  };
}
```

## API Surface

### `mkKind` (`lib/kind.nix`)

```
mkKind : { name, below ? [], resolve, dedupKey ? null, fold ? null } -> kind
```

Builds a single kind record `{ _type = "gen-demand/kind"; name; below; resolve; dedupKey; fold; }`.

- `name` — string, unique within a kind set (internal key + display).
- `below` — list of kind-name strings this kind may cascade into. Downward-only DAG over the whole
  kind set, checked at registration. `below == []` ⇔ leaf kind.
- `resolve` — `demand: ctx: { resources ? {}; wiring ? {}; demands ? []; }` (see
  [Resolver contract](#resolver-contract)).
- `dedupKey` — `demand: <string>` grouping shared demands of this kind (N apps → one Secret / PVC);
  `null` = no grouping.
- `fold` — `key: [value]: value` merging grouped fragments under a shared resource key, in pinned
  schedule order. **Required iff `dedupKey != null`** (either-without-the-other is a registration
  error, law L3d — checked here).

### `mkKinds` (`lib/kind.nix`)

```
mkKinds : ([kind] | { <name> = kind; }) -> kindSet
```

Registration. Validates name uniqueness, `below`-name resolution, DAG acyclicity (incl. self-loops,
via gen-graph condensation over kind names), and `dedupKey`/`fold` pairing (via `mkKind`); computes
per-kind `depth` and `maxDepth`. Throws with a diagnostic naming the offending kinds on any violation.
Returns `{ _type = "gen-demand/kind-set"; kinds = { <name> = kind; }; depth = { <name> = int; }; maxDepth = int; }`.

`depth(k) = 0` if `below(k) == []` (leaf), else `1 + max { depth(b) | b ∈ below(k) }`. Well-defined
because `below` is acyclic; every `below` edge strictly decreases depth.

### `demand` (`lib/demand.nix`)

```
demand : { kind, subject, ... } -> demand
```

- `kind` — a kind value (`mkKind` result) or a kind-name string (escape hatch for recursive kind
  sets); canonicalized to the name.
- `subject` — a **registry entry** per the identity law: any value carrying `id_hash`. `"kind:name"`
  strings are never accepted.
- `...` — arbitrary payload fields, stored flat and opaque. Reserved keys (`kind`, `subject`, `_type`,
  `_path`, `_reserved`) may not appear in the payload; a violation is recorded and thrown by the
  engine **with a path** (at intake for roots, at emission for sub-demands) — never here, because the
  constructor has no path context.

Returns `{ _type = "gen-demand/demand"; kind = <name>; subject; <payload flat>; _reserved = [ … ]; }`.
The resolver never sees `_reserved`; it is stripped and replaced by `_path` at resolution.

### `resolveAll` (`lib/resolve.nix`)

```
resolveAll : { kinds, demands, ctx ? {} } -> { resources; wiring; trace; }
```

- `kinds` — a `kindSet` (`mkKinds` output) or a raw list/attrset (auto-registered).
- `demands` — **ordered** list of demand values; list order is the pinned intake order (B5). The
  caller is responsible for a deterministic order.
- `ctx` — opaque static context, passed **verbatim** to every resolver. The engine never adds to,
  removes from, or derives `ctx`.

Runs exactly `maxDepth + 1` strata top-down (`d = maxDepth … 0`). At each stratum: collect pending
demands of depth `d` (complete by construction), order by schedule order (path-lex), group by
`(kind, dedupKey)`, `resolve` each once, validate + path-assign emitted sub-demands *at emission*
(naming the emitting chain), fold resource fragments per group, accumulate wiring. There is no
iteration cap; termination is a registration-time constant.

**Output.**

```nix
{
  resources = { <kindName> = { <resourceKey> = <folded value>; }; };
  wiring    = { <id_hash>  = { subject; byKind = { <kindName> = [ value ]; }; }; };  # schedule order
  trace     = { demands; resources; wiring; };                                       # §Trace below
}
```

Resource keys are namespaced under the kind name, so cross-kind collisions are impossible by
construction. **Corollary — resource keys must be group-unique:** a key must vary at least as finely
as the kind's dedup group (private keys namespaced by subject; edge keys carry every
group-distinguishing field). A key constant across distinct groups is a guaranteed cross-group
collision (a loud error).

#### Resolver contract

```
resolve = demand: ctx: {
  resources ? { };   # { <resourceKey> = value; } — provider-side artifacts (namespaced under kind)
  wiring    ? { };   # attrset (sugar for [ { subject = demand.subject; wiring = <attrset>; } ])
                     #   OR the general list form [ { subject; wiring; } ] to wire other subjects
  demands   ? [ ];   # [ <demand> ] — sub-demands; every emitted kind MUST be in this kind's `below`
}
```

The resolver receives **exactly two arguments**: the normalized demand record (its own fields plus
`_path`, nothing else) and the caller's static `ctx`, verbatim. There is no accumulator, no
partial-resolution view, no registry of already-resolved artifacts — **emission ⊥ consumption is a
property of this signature** (law L2). Composites desugar from their *own fields*, never from resolved
state.

### `folds` (`lib/folds.nix`)

Uniform signature `key: [v]: v` — used both as kind `fold`s (`key` = resource key) and as
`spliceWiring` `combine`s (`key` = top-level wiring key). Folds receive fragments in pinned schedule
order and must handle one-element lists (a kind's fold is applied even to singleton groups).

| Fold | Signature | Semantics |
|---|---|---|
| `folds.same` | `key: [v]: v` | asserts all values structurally equal (Nix `==`), returns the first; throws on mismatch. Not usable on values containing functions (Nix `==` restriction) |
| `folds.one` | `key: [v]: v` | exactly one contributor; a second throws naming the key. `spliceWiring`'s default combine |
| `folds.list` | `key: [v]: [v]` | collects values in pinned order |
| `folds.mergeAttrs` | `key: [v]: <attrset>` | shallow merge of attrset fragments; disjoint sub-keys required, collision throws |
| `folds.byKey` | `spec: <fold>` | **fold constructor** for attrset-shaped fragments: `byKey { generator = same; stringData = mergeAttrs; }` folds each top-level fragment key `k` with its named sub-fold (diagnostic sub-key `"<key>.<k>"`); fragments not defining `k` are skipped (pinned order preserved among those that do); a fragment key absent from `spec` throws; a non-attrset fragment throws |

### `wiringFor` (`lib/helpers.nix`)

```
wiringFor : resolution -> subject -> [ { kind; wiring; demand; } ]
```

Wiring entries for one subject across all kinds, with provenance (`demand` = the contributing path),
in **global schedule order** (stratum-major descending, path-lex within a stratum).

### `spliceWiring` (`lib/helpers.nix`)

```
spliceWiring : { resolution, subject, combine ? folds.one } -> <attrset>
```

Splices a subject's wiring entries (each an attrset) into one attrset, **per top-level key**: for each
key appearing in any entry, the values contributed under it are collected in global schedule order and
passed to `combine key [values]` — the same `key: [v]: v` signature as resource folds. Default
`folds.one`: exactly one contributor per key (disjoint splice); a second is a loud error. The claim
spec's read-and-splice idiom.

### `adapters.select.filterDemands` (`lib/adapters/select.nix`, optional)

```
filterDemands : { select, demands } -> [ demand ]
```

Loaded only when gen-select is injected (`select != null`). Keeps the demands whose **subject** matches
a gen-select selector, order-preserving. The selector is passed verbatim to gen-select's `matches`
against a single-node context built from each demand's subject entry (its own attributes as `data`);
the roadmap §8 constructors (`sel.entity <entry>`, `sel.kind <schema-kind>`) match through this
subject context.

## Trace

`resolveAll … .trace` is a pure function of `(kinds, demands, ctx)`; equal inputs yield byte-identical
traces.

```nix
trace = {
  demands = [                # GLOBAL schedule order — one entry per instance
    { path; kind; subject = { id_hash; rendered; }; parent; stratum; groupKey; }
  ];
  resources = {              # provenance mirror, namespaced under kind
    <kindName>.<key> = { demands = [ <path> … ]; folded = <bool>; groupKey; };
  };
  wiring = {                 # per subject, GLOBAL schedule order; kind-filtered sublists align
    <id_hash> = [ { kind; demand = <path>; } … ];   #   positionally with `wiring.<id>.byKind.<kind>`
  };
};
```

Paths are integer lists (data): the i-th root demand gets path `[ i ]`; a sub-demand emitted at index
`j` by a demand at path `p` gets path `p ++ [ j ]`. **Global schedule order is stratum-major
descending, path-lex within a stratum** — a sub-demand `[0 0]` lists *after* a root `[1]` when their
strata differ, deliberately diverging from a raw global path-lex order.

## Error Taxonomy

Every anomaly is a `throw` whose message names the demand path(s), kind(s), and rendered subject.

| Stage | Error |
|---|---|
| registration | duplicate kind name; unresolved `below` name; `below` cycle (incl. self-loop); `dedupKey`/`fold` pairing violation |
| intake | value is not a demand; unknown demand kind; subject without `id_hash`; reserved payload key |
| resolution (at emission) | emitted sub-demand kind ∉ emitter's `below`; emitted sub-demand subject without `id_hash`; emitted sub-demand shadowing a reserved key — all caught when the emitting resolver returns (error names the full emitting chain), never deferred to the sub-demand's own stratum |
| resolution | non-string `dedupKey` result; wired subject without `id_hash` |
| combination | resource-key collision (cross-group, or within a fold-less kind); `folds.same` mismatch; `folds.one` second contributor; `folds.mergeAttrs`/`spliceWiring` key collision; `folds.byKey` fragment key absent from spec / non-attrset fragment |

## Laws (test-group mapping)

| Group | Law | Covers |
|---|---|---|
| `registration` | L1a, L3d | cycle/self-loop rejection; unresolved `below`; duplicate name; `dedupKey`/`fold` pairing; depth/maxDepth golden |
| `termination` | L1b | exactly maxDepth+1 strata; each kind resolved only in its stratum; leaf-emits/outside-below/bad-subject → emission error; deep DAG quiesces |
| `discipline` | L2 | resolver receives `ctx` verbatim (attrNames included); resources/wiring/trace absent from resolver input; input is exactly demand + `_path` |
| `dedup` | L3a-c | group membership; fold-order = schedule order; permutation reflected (no silent sort); `folds.same` conflict, cross-group collision, fold-less duplicate → error; singleton passes through fold |
| `provenance` | L4 | parent chains reach roots; every artifact ↦ ≥1 path; wiring trace aligns with `byKind`; stratum-major golden; full-trace golden; trace equality across eval |
| `determinism` | L5 | byte-identical repeated output; structurally-equal inputs → equal output; values pass through untouched; order significance |
| `helpers` | — | stock fold semantics; `folds.byKey` dispatch/skip/unknown/non-attrset; `wiringFor` order; `spliceWiring` disjoint/collision/explicit-combine |
| `intake` | — | root-demand error taxonomy |
| `adapters-select` | — | (gen-select present) `filterDemands` with entity/kind selectors, order preservation |
| `instance-k8s` | all | Appendix A executable golden |

## Compat / purity

- `lib/` is `nixpkgs.lib`-free; `nixpkgs` enters only in `ci/` (nix-unit harness + treefmt).
- No dependency on gen-schema (subject identity is duck-typed on `id_hash`), gen-dispatch, gen-edge,
  or gen-pipe (den-hoag composes those *around* gen-demand — no lib depends upward).
- Payloads may contain functions and are not required to be serializable; the trace records payloads
  by reference to the path, not by value copy.
