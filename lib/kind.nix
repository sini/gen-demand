# Kind registration — the downward-only DAG whose depth stratifies the cascade.
#
# `mkKind` builds a single kind record, rejecting a `dedupKey` without a `fold` and vice versa
# (grouping and merging are only meaningful together — a registration-time pairing check). `mkKinds`
# validates the whole set — name uniqueness, `below`-name resolution, acyclicity — and computes
# per-kind `depth` and `maxDepth`.
#
# THEORY: acyclicity is the stratifiability condition made a definition-time error; every `below`
# edge strictly decreases the natural-number `depth` measure, so the cascade terminates by
# Noetherian induction on ℕ (well-founded recursion). Cycle detection uses gen-graph condensation
# over kind names — the same throw-on-cycle discipline as `gen-graph.phaseOrder`.
{ prelude, graph }:
let
  inherit (builtins)
    attrNames
    elem
    isAttrs
    isList
    isString
    length
    toJSON
    ;
  inherit (prelude)
    attrValues
    concatMap
    filter
    genAttrs
    listToAttrs
    map
    max
    nameValuePair
    unique
    ;

  kindMarker = "gen-demand/kind";
  kindSetMarker = "gen-demand/kind-set";

  mkKind =
    {
      name,
      below ? [ ],
      resolve,
      dedupKey ? null,
      fold ? null,
    }:
    let
      hasDedup = dedupKey != null;
      hasFold = fold != null;
    in
    if !isString name then
      throw "gen-demand.mkKind: `name` must be a string"
    else if hasDedup && !hasFold then
      throw "gen-demand.mkKind: kind '${name}' declares `dedupKey` without `fold` (a fold is required to merge grouped fragments)"
    else if hasFold && !hasDedup then
      throw "gen-demand.mkKind: kind '${name}' declares `fold` without `dedupKey` (a fold has nothing to merge without grouping)"
    else
      {
        _type = kindMarker;
        inherit
          name
          below
          resolve
          dedupKey
          fold
          ;
      };

  mkKinds =
    kindsArg:
    let
      kindList = if isList kindsArg then kindsArg else attrValues kindsArg;
      names = map (k: k.name) kindList;

      duplicates = unique (filter (n: length (filter (m: m == n) names) > 1) names);

      kinds = listToAttrs (map (k: nameValuePair k.name k) kindList);

      allBelow = unique (concatMap (k: k.below) kindList);
      unresolved = filter (b: !(kinds ? ${b})) allBelow;

      # Acyclicity via gen-graph condensation over kind names: a cycle surfaces as a non-singleton
      # SCC, a self-loop as a singleton SCC caught directly.
      cond = graph.condensation {
        nodes = names;
        edges = n: kinds.${n}.below;
      };
      nonSingleton = filter (r: length (cond.members r) > 1) cond.reps;
      selfLoops = filter (n: elem n kinds.${n}.below) names;
      cyclic = map cond.members nonSingleton ++ map (n: [ n ]) selfLoops;

      # depth(k) = 0 for a leaf, else 1 + max over below. Well-founded because `below` is acyclic.
      depthOf =
        name:
        let
          b = kinds.${name}.below;
        in
        if b == [ ] then 0 else 1 + prelude.foldl' max 0 (map depthOf b);

      depth = genAttrs names depthOf;
      maxDepth = prelude.foldl' max 0 (map depthOf names);
    in
    if duplicates != [ ] then
      throw "gen-demand.mkKinds: duplicate kind name(s): ${toJSON duplicates}"
    else if unresolved != [ ] then
      throw "gen-demand.mkKinds: `below` names with no registered kind: ${toJSON unresolved}"
    else if nonSingleton != [ ] || selfLoops != [ ] then
      throw "gen-demand.mkKinds: the `below` relation is cyclic (downward-only DAG required): ${toJSON cyclic}"
    else
      {
        _type = kindSetMarker;
        inherit kinds depth maxDepth;
      };

  # Accept a kind-set verbatim, or auto-register a raw list/attrset of kinds.
  asKindSet =
    kinds: if isAttrs kinds && (kinds._type or null) == kindSetMarker then kinds else mkKinds kinds;
in
{
  inherit
    mkKind
    mkKinds
    asKindSet
    kindMarker
    kindSetMarker
    ;
}
