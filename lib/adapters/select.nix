# Optional gen-select adapter — loaded only when gen-select is injected (core never requires it).
#
# `filterDemands` keeps the demands whose SUBJECT matches a gen-select selector, order-preserving.
# The selector value is opaque here: it is passed verbatim to gen-select's `matches` against a
# single-node context built from each demand's subject entry (its own attributes as `data`). Entity
# matching (`genSelect.attrs { id_hash = …; }`) and kind matching (`genSelect.entityKind
# <schema-kind>`) both resolve through this subject context; any selector `matches` understands works.
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
