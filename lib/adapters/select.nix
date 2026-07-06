# Optional gen-select adapter — loaded only when gen-select is injected (core never requires it).
#
# `filterDemands` keeps the demands whose SUBJECT matches a gen-select selector, order-preserving.
# The selector value is opaque here: it is passed verbatim to gen-select's `matches` against a
# single-node context built from each demand's subject entry (its own attributes as `data`). The
# roadmap §8 constructors (`sel.entity <entry>`, `sel.kind <schema-kind>`) match through this
# subject context; if the pinned gen-select predates them, any selector `matches` understands works.
{ selectLib, prelude }:
let
  inherit (prelude) filter;

  # A degenerate scope context whose only node is the subject itself (`data` returns its attrs;
  # no children/parent/ancestors/siblings — subject matching does not traverse a scope).
  ctxFor = subject: {
    data = _: subject;
    children = _: [ ];
    parent = _: null;
    ancestors = _: [ ];
    siblings = _: [ ];
  };

  filterDemands =
    { select, demands }:
    filter (d: selectLib.matches select (d.subject.id_hash or "<no-id>") (ctxFor d.subject)) demands;
in
{
  inherit filterDemands;
}
