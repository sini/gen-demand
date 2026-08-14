# gen-demand — agent capability sheet

> **⚠ ARCHIVED — this library has retired; its successor is `gen-scope`.** ADR-0008 §4 retires
> gen-demand as a library (its demand/kind folds re-express over scope) and ADR-0006 makes gen-scope
> the sole execution engine. The repository is **orphaned for reference** under ADR-0031's F3 pattern:
> no content is deleted, nothing is maintained, and gen-demand is off the `mkGenLibs` roster and no
> longer a `gen` hub input. **Do not route new work here and do not add a consumer.** The cascade is
> gen-scope's `lib/cascade.nix` + `lib/folds.nix`, under claim vocabulary (`mkClaim`,
> `resolveClaims`); the export map is `gen-specs/gen-scope/gen-demand-retirement.md` in the
> den-architecture papers repository. `adapters` retires with its construct and moves nowhere.
>
> **It stays readable because the re-expression is unfinished** — the stratification driver has not
> landed, and that work reads this repository as its source. Everything below describes the retiring
> surface, not a surface to build on.

## Scope

Typed demand cascade: registered **kinds** resolve **demand** values (`{ _type = "gen-demand/demand"; kind; subject; … }`) into resources + wiring + sub-demands, and a stratified, terminating fold over a registration-time kind DAG resolves the whole multiset with a provenance trace.

## Not this library's job

Quoted text is the owner's own `flake.nix` `description` field, verbatim.

| Responsibility | Owner |
|---|---|
| Demand-driven **attribute** evaluation — where "demand" means a forced attribute, not a demand value | `gen-scope` — "gen-scope: demand-driven attribute grammar evaluator over algebraic scope graphs". Measured seam: gen-scope's evaluator is memoized per node via a co-located `_eval` cache and takes its scheduling, memoization and cycle detection from Nix's native laziness (`gen-scope/lib/eval.nix:1-10`). gen-demand's schedule is an explicit `maxDepth + 1` descending fold computed at registration (`lib/resolve.nix:161`), never derived from forcing order; `git grep -cn "equation\|_eval\|priorResults\|isClean" -- lib/` is empty here and reports 17 in `gen-scope/lib/eval.nix` |
| The static attribute-dependency schedule and the cold/warm resolution fold over a scope graph | `gen-resolve` — "gen-resolve — demand-driven higher-order RAG evaluator over algebraic scope graphs (Knuth 1968 attribute schedule + Vogt 1989 HOAG)". Measured seam: gen-resolve's own header states it "owns ONLY the static attribute-dependency schedule (schedule.nix) and the cold/warm fold (resolve.nix / override.nix)", delegating every instrument to a sibling (`gen-resolve/lib/default.nix:5-9`); its unit is an attribute equation over graph nodes. gen-demand's unit is a demand value with its own marker (`lib/demand.nix:18`) and its stratification comes from the `below` relation over kind NAMES (`lib/kind.nix:83-89`), not from an attribute-dependency graph. Same grep as the row above: 7 files in `gen-resolve/lib/`, 0 in `gen-demand/lib/` |
| Choosing a winner among matched rules; the guard→effect step | `gen-dispatch` — "gen-dispatch: relational rule dispatch over ordered groups (the dispatch STEP)". `README.md:44-53` records the mismatch as a design finding; no code contact (`git grep -n 'gen-dispatch' -- lib/` empty) |
| Collecting / fanning in the demand list — gen-demand takes an already-ordered list | `gen-pipe` — "gen-pipe — scoped channels + dataflow algebra (map/filter/fold/scan/route/join/tee) with B5 determinism, provenance, dedup, and class-aware contributions" |
| Turning `resources`/`wiring` into edges, modules, or configuration | `gen-edge` — "gen-edge — the content-movement contract: the (S,T,P,M) edge algebra, toposorted materialization fold, and the frozen edge-trace parity oracle" |
| Minting identity (`id_hash`), kinds, instances, registries | `gen-schema` — "gen-schema: typed record registry with extension points for the pure-gen module system". gen-demand only *reads* `id_hash` (duck-typed, no gen-schema dep); `git grep -n "hashString\|builtins\.hash" -- lib/` returns nothing |
| Graph traversal, condensation/SCC, phase ordering | `gen-graph` — "gen-graph: accessor-based graph query combinators". Consumed at exactly one call site: `graph.condensation` (`lib/kind.nix:83`) |
| Building/evaluating selectors | `gen-select` — "gen-select: selector algebra for attributed graph positions". Consumed at exactly one call site: `selectLib.matches` (`lib/adapters/select.nix:44`), and only when injected |
| General list/attr utilities | `gen-prelude` — "gen-prelude: vendored, nixpkgs-lib-free pure utilities for the gen ecosystem". The hub roster records gen-demand's deps as `demand: prelude+graph` (`gen/lib/mkGenLibs.nix:24-26`) |
| Type checking / `verify` — validation here is bespoke throw-chains | `gen-types` — "gen-types: pure, nixpkgs-lib-free structural type checker for the gen ecosystem" |
| Layered/precedence resolution of a settings value | `gen-settings` — "gen-settings — stratified settings resolution as a pure layered fold, with refs-as-data, structured provenance, and the graduated injection construct". Both stratify and fold; gen-settings folds layers of one value, gen-demand folds resource fragments across dedup groups of one kind |

## Exports

Entry: `inputs.gen-demand.lib` (flake) — `import ./lib { prelude = gen-prelude.lib; graph = gen-graph.lib; }`, with `select` left unset, so `adapters` is `{ }` there. Root `default.nix` is a **function** `{ prelude ? …, graph ? …, select ? null } -> lib` (defaults fetch the flake-locked revs); `import ./lib` is the same function without the default fetches.

**Kind registration** — `lib/kind.nix`

| Export | Signature |
|---|---|
| `mkKind` | `{ name, below ? [], resolve, dedupKey ? null, fold ? null } -> kind` (`{ _type = "gen-demand/kind"; name; below; resolve; dedupKey; fold; }`) |
| `mkKinds` | `([kind] \| { <any> = kind; }) -> kindSet` (`{ _type = "gen-demand/kind-set"; kinds; depth; maxDepth; }`) |

**Demand construction** — `lib/demand.nix`

| Export | Signature |
|---|---|
| `demand` | `{ kind, subject, …payload } -> demand` — `kind` is a kind value or a kind-name string; `subject` is any value carrying `id_hash` |

**The cascade** — `lib/resolve.nix`

| Export | Signature |
|---|---|
| `resolveAll` | `{ kinds, demands, ctx ? {} } -> { resources; wiring; trace; }` — `kinds` accepts a `kindSet` or a raw list/attrset (auto-registered) |

**Consumer accessors** — `lib/helpers.nix`

| Export | Signature |
|---|---|
| `wiringFor` | `resolution -> subject -> [ { kind; wiring; demand; } ]` (global schedule order) |
| `spliceWiring` | `{ resolution, subject, combine ? folds.one } -> attrset` |

**Stock folds** — `lib/folds.nix`. Uniform signature `key -> [v] -> v`, serving both a kind's resource `fold` and a `spliceWiring` `combine`.

| Export | Signature |
|---|---|
| `folds.same` | `key -> [v] -> v` — all fragments `==`, returns the first |
| `folds.one` | `key -> [v] -> v` — exactly one contributor |
| `folds.list` | `key -> [v] -> [v]` — collect in pinned order (see traps: this one returns a list) |
| `folds.mergeAttrs` | `key -> [attrset] -> attrset` — shallow merge, disjoint sub-keys |
| `folds.byKey` | `spec -> key -> [attrset] -> attrset` — fold **constructor**; folds fragment key `k` with `spec.${k}` |

**Optional adapter** — `lib/adapters/select.nix`, present only when `select != null`

| Export | Signature |
|---|---|
| `adapters.select.filterDemands` | `{ select, demands } -> [demand]` — keeps demands whose SUBJECT matches, order-preserving |

**Resolver contract** (consumed, not exported). `resolve = demand: ctx: { resources ? {}; wiring ? {}; demands ? []; }`. `wiring` is either an attrset (targets the demand's own subject) or the list form `[ { subject; wiring; } ]` (targets any subject). Every emitted sub-demand's kind must be in the emitting kind's `below`.

**`resolveAll` output shape**: `resources.<kindName>.<resourceKey>`, `wiring.<id_hash> = { subject; byKind.<kindName> = [ value ]; }`, `trace = { demands; resources; wiring; }`. Paths are integer lists: root `i` ⇒ `[ i ]`, sub-demand `j` of path `p` ⇒ `p ++ [ j ]`.

**Not re-exported** by `lib/default.nix:36-43`, though their modules return them: `canonKind` / `demandMarker` / `reserved` (`lib/demand.nix:66-71`), `asKindSet` / `kindMarker` / `kindSetMarker` (`lib/kind.nix:119-125`), `pathLt` / `renderSubject` (`lib/resolve.nix:374`).

## Entry points by task

| Task | Reach for |
|---|---|
| Declare a resolvable concern | `mkKind { name; below; resolve; }` |
| Group N claimants onto one artifact | `mkKind` with `dedupKey` **and** `fold` (both or neither) |
| Register + validate the whole kind DAG | `mkKinds` — throws on duplicate name, unresolved `below`, cycle, self-loop |
| Build a request | `demand { kind; subject; …payload }` (subject must carry `id_hash`) |
| Run the cascade | `resolveAll { kinds; demands; ctx; }` |
| Desugar a composite | return `demands = [ … ]` from `resolve`; every kind must be in `below` |
| Merge grouped fragments | `folds.same` / `folds.one` / `folds.list` / `folds.mergeAttrs` |
| Merge attrset fragments per sub-key | `folds.byKey { <fragKey> = <fold>; … }` |
| Read one subject's wiring with provenance | `wiringFor resolution subject` |
| Collapse a subject's wiring to one attrset | `spliceWiring { resolution; subject; combine; }` |
| Pre-filter demands by subject | `adapters.select.filterDemands { select; demands; }` (requires injected gen-select) |
| Answer "what produced this artifact" | `trace.resources.<kind>.<key>.demands` / `trace.wiring.<id_hash>` |

## Measured traps

Each row verified in this run at rev `9039928` by evaluating against `import ./. { select = <gen-select from ci/flake.lock>; }`. Fixtures: `A = { name = "a"; id_hash = "ha"; type = "app"; }`, `B = { name = "b"; id_hash = "hb"; type = "db"; }`, `C = { name = "c"; id_hash = "hc"; }` (id_hash, no `type`), `N = { name = "n"; }` (no `id_hash`); `ok x = (builtins.tryEval (builtins.deepSeq x true)).success`.

| Trap | Evidence |
|---|---|
| `demand` canonicalizes `kind` **lazily** — a bad `kind` builds a fine value and throws only when forced | `lib/demand.nix:32-39,58-62`; `demand { kind = 42; subject = A; }` at WHNF ⇒ `success = true`, same value under `deepSeq` ⇒ `false`. Positive control, same constructor: missing `kind` and missing `subject` are eager if-branches, both ⇒ `false` at WHNF |
| `demand` never checks the subject — a string subject survives `deepSeq`; the throw comes from `resolveAll` intake | `lib/demand.nix:41-63` vs `lib/resolve.nix:112-113`; `(demand { kind = "leaf"; subject = "axon-01"; }).subject` ⇒ `"axon-01"`, `ok` ⇒ `true`; the same demand through `resolveAll` ⇒ `false`. Test: `test-subject-without-id-throws` (`ci/tests/intake.nix`) |
| A reserved payload key is **recorded, not thrown**, at construction; a payload `_type` is silently overwritten by the marker | `lib/demand.nix:55-63`; `(demand { …; _path = 1; })._reserved` ⇒ `["_path"]` with `ok` ⇒ `true`; `(demand { …; _type = "hijack"; })._type` ⇒ `"gen-demand/demand"`. Clean control: `_reserved` ⇒ `[]` for a `port` payload. Through `resolveAll` ⇒ `false`. Test: `test-reserved-payload-key-throws` (`ci/tests/intake.nix`) |
| The resolver's demand view keeps `_type` — only `_reserved` is stripped, so it is demand fields **+ `_path` + `_type`** | `lib/resolve.nix:124`; `builtins.attrNames d` inside `resolve` ⇒ `["_path","_type","kind","port","subject"]`. `ctx` is verbatim: `attrNames ctx` ⇒ `["mk","other"]`. Test: `test-comp-demand-names` (`ci/tests/discipline.nix`) |
| `mkKinds` on an attrset **ignores the attribute names** — `k.name` is the key | `lib/kind.nix:76`; `attrNames (mkKinds { zzz = leafKind; }).kinds` ⇒ `["leaf"]`. Test: `test-attrset-input-accepted` (`ci/tests/registration.nix`) |
| `mkKind` does not resolve `below` names or detect cycles — that is `mkKinds` alone | `lib/kind.nix:38-66` vs `79,104-107`; `mkKind { below = [ "nope" ]; … }` ⇒ `true`, the same kind through `mkKinds` ⇒ `false`; self-loop and 2-cycle ⇒ `false`. Tests: `test-unresolved-below-rejected`, `test-self-loop-rejected`, `test-two-cycle-rejected` (`ci/tests/registration.nix`) |
| `dedupKey` and `fold` must be declared together — either alone is a registration error | `lib/kind.nix:52-55`; `dedupKey` alone ⇒ `false`, `fold` alone ⇒ `false`, both ⇒ `true`. Tests: `test-dedupkey-without-fold-rejected`, `test-fold-without-dedupkey-rejected` |
| Schedule order is stratum-major **descending**, so a sub-demand lists *before* a later root | `lib/resolve.nix:161-166`; roots `[ comp A, leaf B ]` (comp depth 1, leaf depth 0) ⇒ `trace.demands` paths `[[0],[0,0],[1]]`, strata `[1,0,0]`. Test: `test-substratum-after-higher-root` (`ci/tests/provenance.nix`) |
| A leaf kind that emits sub-demands is a loud error **even though stratum 0 consumes nothing** — every instance is forced | `lib/resolve.nix:220-222`; leaf emitting one sub-demand ⇒ `false`. Positive control, identical kind minus the emission ⇒ `true`. Test: `test-leaf-emitting-throws` (`ci/tests/termination.nix`) |
| A sub-demand of a kind outside the emitter's `below` throws, naming the emitting chain | `lib/resolve.nix:183-184`; ⇒ `false`. Test: `test-emit-outside-below-throws` (`ci/tests/termination.nix`) |
| Fold-less kinds never last-wins: two instances producing the same resource key **collide** | `lib/resolve.nix:275-281`; two demands both writing `resources.same` ⇒ `false`. Positive control, same two demands with subject-namespaced keys ⇒ `{"a":1,"b":1}`. Test: `test-foldless-duplicate-throws` (`ci/tests/dedup.nix`) |
| A kind's `fold` is applied to **singleton** groups too, so the fold changes the value shape even with one contributor | `lib/resolve.nix:264-269`; one instance, `fold = folds.list` ⇒ `resources.d.shared` = `["a"]` (not `"a"`); two ⇒ `["a","b"]`. Test: `test-singleton-passes-through-fold` (`ci/tests/dedup.nix`) |
| `trace.…folded` reports that the KIND declares a fold, not that more than one fragment merged | `lib/resolve.nix:288-292`; the singleton above ⇒ `{"demands":[[0]],"folded":true,"groupKey":"g"}` |
| Two distinct dedup groups contributing the same resource key collide; a non-string `dedupKey` result throws | `lib/resolve.nix:126-140,275-281`; distinct-group shared key ⇒ `false`, `dedupKey = _: 7` ⇒ `false`. Tests: `test-cross-group-collision-throws`, `test-nonstring-dedupkey-throws` (`ci/tests/dedup.nix`) |
| A registered kind with no instance is **absent** from `resources`, not `{ }` | `lib/resolve.nix:226,297`; kinds `[ leaf, idle ]` with one `leaf` demand ⇒ `attrNames resources` = `["leaf"]`, `resources ? idle` ⇒ `false`. `demands = [ ]` ⇒ `{"resources":{},"wiring":{},"demands":[]}` |
| An empty `wiring` (`{ }` **or** `[ ]`) drops the subject from `resolution.wiring` entirely | `lib/resolve.nix:302-317`; both ⇒ `attrNames wiring` = `[]`. Non-empty attrset form targets the demand's own subject (`wiring.ha.byKind.w` ⇒ `[{"env":{"X":"1"}}]`); the list form targets another (`attrNames wiring` ⇒ `["hb"]`); a list-form subject without `id_hash` ⇒ `false` |
| `folds.same` on function-bearing fragments fails **uncatchably** — `tryEval` does not contain it | `lib/folds.nix:38-41`; `builtins.tryEval (folds.same "k" [ f f ])` with the *same* binding twice aborts the whole eval with `error: cannot convert a function to JSON`, because Nix `==` is false for functions (`f == f` ⇒ `false`), so the mismatch branch runs and its own `toJSON` diagnostic dies. Control: `folds.same "k" [ 1 1 1 ]` ⇒ `1`, `[ 1 2 ]` ⇒ `false`, `[ ]` ⇒ `false` |
| `folds.list` breaks the uniform `key: [v]: v` signature — it returns a list | `lib/folds.nix:52`; `folds.list "k" [ 1 ]` ⇒ `[1]`. Test: `test-folds-list` (`ci/tests/helpers.nix`) |
| `folds.byKey` is a fold **constructor** (arity 3), not a fold | `lib/folds.nix:73-94`; `builtins.isFunction (folds.byKey { })` ⇒ `true`; dispatch ⇒ `{"g":"gen","s":{"x":1,"y":2}}`; a fragment lacking a key is skipped ⇒ `{"g":"gen","s":{"y":2}}`; an undeclared fragment key ⇒ `false`; a non-attrset fragment ⇒ `false`. Its `else { }` at `lib/folds.nix:94` is unreachable (`ok` either forces `true` or throws) — read, not exercised. Tests: `test-bykey-per-key-dispatch`, `test-bykey-skipped-key`, `test-bykey-unknown-fragment-key-throws`, `test-bykey-non-attrset-fragment-throws` |
| `spliceWiring` defaults to `folds.one`, so two kinds writing the same top-level wiring key throw | `lib/helpers.nix:51-56`; two kinds both writing `wiring.env` ⇒ `false`; `combine = folds.mergeAttrs` ⇒ `{"env":{"X":"1","Y":"2"}}`; `wiringFor` on the same subject ⇒ `[{"demand":[0],"kind":"w1"},{"demand":[1],"kind":"w2"}]`; on a subject with no wiring ⇒ `[]`. Tests: `test-splice-default-collision-throws`, `test-splice-explicit-combine` (`ci/tests/helpers.nix`) |
| With `select = null` the whole `adapters` attrset is `{ }` — `adapters.select` is absent, not a throwing stub | `lib/default.nix:25-34`; drift output `adaptersWhenSelectNull` ⇒ `[]`. Test: `test-core-has-no-adapters` (`ci/tests/adapters-select.nix`) |
| `filterDemands` projects the subject's `type` attribute as gen-select's kind: no `type` ⇒ `sel.kind` **throws**; no `id_hash` ⇒ `__identity = null` and every identity selector is **silently false** | `lib/adapters/select.nix:21-40`; `sel.kind { kind = "app"; options = { }; }` on `C` ⇒ `false`, positive control same selector same run on `A` ⇒ `["a"]`. On `N`: `sel.entity A` ⇒ `[]` with `ok` ⇒ `true` (no throw), and `sel.not (sel.entity A)` **keeps** it ⇒ `["b","n"]`. `sel.star` ⇒ `["a","b","n"]`, `sel.attrs { name = "b"; }` ⇒ `["b"]`. Test: `test-select-kind-blind-throws` (`ci/tests/adapters-select.nix`) |
| `resolveAll` output is byte-stable across evaluations | `toJSON` of two independent `resolveAll` calls on equal inputs ⇒ `true`. Test: `test-k8s-repeated-eval-identical` (`ci/tests/determinism.nix`) |

## Theory

The reference spec — papers `gen-specs/gen-demand/REFERENCE.md:36-44` — states its sources as a **Feature / Source / Relationship** table whose relationship column reads "Implements" throughout, plus one explicit non-implementation and an internal-provenance row; `README.md:184-201` restates the same set.

**Implements**

- **Apt, Blair & Walker (1988), *Towards a Theory of Declarative Knowledge*** — depth-stratified schedule with stratum-local aggregation: each kind-depth is a stratum, the dedup `fold` runs only when a stratum's fact set is complete. Registration-time acyclicity is the stratifiability condition made a definition-time error (`lib/kind.nix:8-11`, `lib/folds.nix:9-11`, `lib/resolve.nix:10-12`). No negation semantics realized.
- **Termination by Noetherian induction on ℕ** — every `below` edge strictly decreases `depth`, so `maxDepth + 1` strata is a theorem, not a convergence heuristic; there is no iteration cap (`lib/kind.nix:91-100`, `lib/resolve.nix:12-13`).
- **Cheney, Chiticariu & Tan (2009), *Provenance in Databases: Why, How, and Where*** — the trace realizes witness provenance (artifact ↦ producing demand instances) extended with derivation paths (parent chains to roots) (`lib/resolve.nix:13-14`).
- **gen-graph condensation** — cycle detection over kind names reuses the same throw-on-cycle discipline as `gen-graph.phaseOrder` (`lib/kind.nix:81-89`).

**Deliberately not implemented**: the semiring provenance algebra of Green–Karvounarakis–Tannen (2007) — traces are records, not algebraic values (papers `gen-specs/gen-demand/REFERENCE.md:42`).

**Internal provenance**: the cascade model, the five k8s kinds, the leaf/composite split, the shared-secret/shared-PVC dedup shapes and the emission ⊥ consumption invariant originate in the nix-config claim/provide engine design (2026-06-13), carrying its two negative findings (not gen-dispatch; not a scope-engine graph). Pinned-order, associative-only collection is HOAG r2 §B5 (`lib/folds.nix:6-7`).

**Checked invariant**: `lib/` is `nixpkgs.lib`-free — nixpkgs enters only in `ci/` (nix-unit harness + treefmt, `ci/flake.nix:10-12`). `git grep -nE 'hashString|builtins\.hash|evalModules|mkOption|mkIf|\.fix\b' -- lib/` returns nothing. Two positive controls in the same run: `git grep -cE 'id_hash|prelude\.' -- lib/` reports hits in 5 of the 7 `lib/` files, and the same ERE pattern run against `gen-scope/lib/` matches `prelude.fix (` at `gen-scope/lib/eval.nix:21`, so the `\.fix\b` alternative is live rather than a dead predicate.

## Drift check

```sh
nix eval --impure --json --expr '
let
  lock = builtins.fromJSON (builtins.readFile ./ci/flake.lock);
  fetch = n: builtins.fetchTree lock.nodes.${lock.nodes.root.inputs.${n}}.locked;
  core = import ./. { };
  full = import ./. { select = import "${fetch "gen-select"}/lib"; };
in {
  top = builtins.attrNames full;
  folds = builtins.attrNames full.folds;
  adapters = builtins.mapAttrs (_: a: builtins.attrNames a) full.adapters;
  adaptersWhenSelectNull = builtins.attrNames core.adapters;
}'
```

gen-select is injected from `ci/flake.lock` because it is not a `lib/` flake input; the core surface is evaluated in the same command so the optional-adapter branch is covered.

Current output (verbatim):

```json
{"adapters":{"select":["filterDemands"]},"adaptersWhenSelectNull":[],"folds":["byKey","list","mergeAttrs","one","same"],"top":["adapters","demand","folds","mkKind","mkKinds","resolveAll","spliceWiring","wiringFor"]}
```

**Checks.** Test-runner invocation (from the repo root; CI runs the same command with `working-directory: ci`, `.github/workflows/ci.yml:13,18`):

```sh
nix flake check ./ci
```
