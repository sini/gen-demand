# Stock folds — uniform signature `key: [v]: v`.
#
# The same signature serves two roles: a kind's resource `fold` (`key` = resource key) and a
# `spliceWiring` `combine` (`key` = top-level wiring key). Folds receive fragments in pinned
# schedule order (L3b) and must handle one-element lists (the engine applies a kind's fold even
# to singleton groups). Diagnostics name the `key`; the engine wraps fold calls with path/kind
# context for the offending demands.
#
# THEORY: stratum-local aggregation — an aggregate is applied only once a stratum's fact set is
# complete (Apt, Blair & Walker 1988, "Towards a Theory of Declarative Knowledge"), which is why
# the cascade folds per depth-stratum rather than incrementally.
{ prelude }:
let
  inherit (builtins)
    attrNames
    isAttrs
    length
    toJSON
    ;
  inherit (prelude)
    all
    concatMap
    filter
    foldl'
    head
    listToAttrs
    map
    nameValuePair
    unique
    ;

  # All fragments structurally equal (Nix `==`); returns the first. Not usable on values
  # containing functions (Nix `==` restriction). Duplicate edges that must agree provision once.
  same =
    key: vs:
    if vs == [ ] then
      throw "gen-demand.folds.same: empty fragment list for key '${key}'"
    else if all (v: v == head vs) vs then
      head vs
    else
      throw "gen-demand.folds.same: conflicting values for key '${key}': ${toJSON vs}";

  # Exactly one contributor; a second is a loud error. `spliceWiring`'s default combine.
  one =
    key: vs:
    if length vs == 1 then
      head vs
    else
      throw "gen-demand.folds.one: key '${key}' has ${toString (length vs)} contributors, expected exactly 1";

  # Collect values in pinned order (`key: [v]: [v]`).
  list = _key: vs: vs;

  # Shallow merge of attrset fragments; disjoint sub-keys required.
  mergeAttrs =
    key: vs:
    foldl' (
      acc: v:
      let
        dup = filter (k: acc ? ${k}) (attrNames v);
      in
      if dup != [ ] then
        throw "gen-demand.folds.mergeAttrs: key '${key}' collision on sub-key(s) ${toJSON dup}"
      else
        acc // v
    ) { } vs;

  # Fold CONSTRUCTOR for attrset-shaped fragments: folds each top-level fragment key `k` with its
  # named sub-fold `spec.${k}` (diagnostic sub-key "<key>.<k>"). Fragments not defining `k` are
  # skipped, pinned order preserved among those that do. A fragment key absent from `spec` throws.
  # One declared level of nesting — the stock answer for "shared resource, per-claimant sub-entries".
  byKey =
    spec: key: vs:
    let
      checkAttr =
        v:
        if isAttrs v then
          true
        else
          throw "gen-demand.folds.byKey: key '${key}' has a non-attrset fragment: ${toJSON v}";
      ok = all checkAttr vs; # forces the attrset check on every fragment
      allKeys = unique (concatMap attrNames vs);
      foldKey =
        k:
        if !(spec ? ${k}) then
          throw "gen-demand.folds.byKey: key '${key}': fragment key '${k}' not declared in the fold spec"
        else
          let
            contributors = filter (v: v ? ${k}) vs;
            values = map (v: v.${k}) contributors;
          in
          spec.${k} "${key}.${k}" values;
    in
    if ok then listToAttrs (map (k: nameValuePair k (foldKey k)) allKeys) else { };
in
{
  folds = {
    inherit
      same
      one
      list
      mergeAttrs
      byKey
      ;
  };
}
