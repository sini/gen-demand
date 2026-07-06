# Consumer helpers — pure accessors over `resolveAll` output.
#
# `wiringFor` reconstructs a subject's wiring entries across all kinds in global schedule order
# (aligning `trace.wiring` with the per-kind `byKind` lists). `spliceWiring` folds those entries
# into one attrset per top-level key, using the same `key: [v]: v` fold signature as resource folds.
{ prelude, foldsLib }:
let
  inherit (builtins) attrNames elemAt;
  inherit (prelude)
    concatMap
    head
    listToAttrs
    map
    nameValuePair
    tail
    unique
    ;

  # Wiring entries for one subject across all kinds, with provenance, in global schedule order.
  wiringFor =
    resolution: subject:
    let
      id = subject.id_hash;
      traceEntries = resolution.trace.wiring.${id} or [ ];
      byKind = (resolution.wiring.${id} or { byKind = { }; }).byKind;
      # `trace.wiring` is a flat global-order list; `byKind.<kind>` aligns positionally with the
      # trace's kind-filtered sublist. Walk the trace, drawing successive per-kind wiring values.
      walk =
        counts: entries:
        if entries == [ ] then
          [ ]
        else
          let
            e = head entries;
            c = counts.${e.kind} or 0;
          in
          [
            {
              inherit (e) kind;
              wiring = elemAt byKind.${e.kind} c;
              inherit (e) demand;
            }
          ]
          ++ walk (counts // { ${e.kind} = c + 1; }) (tail entries);
    in
    walk { } traceEntries;

  # Splice a subject's wiring entries (each an attrset) into one attrset, per top-level key: for
  # each key, the values contributed under it (global schedule order) are passed to `combine`.
  # Default `folds.one`: exactly one contributor per key (disjoint splice), a second is a loud error.
  spliceWiring =
    {
      resolution,
      subject,
      combine ? foldsLib.folds.one,
    }:
    let
      entries = map (x: x.wiring) (wiringFor resolution subject);
      allKeys = unique (concatMap attrNames entries);
      keyVal =
        k:
        let
          vs = concatMap (e: if e ? ${k} then [ e.${k} ] else [ ]) entries;
        in
        combine k vs;
    in
    listToAttrs (map (k: nameValuePair k (keyVal k)) allKeys);
in
{
  inherit wiringFor spliceWiring;
}
