# Optional gen-select adapter — loaded only when gen-select is injected (core never requires it).
#
# `filterDemands` keeps the demands whose SUBJECT matches a gen-select selector, order-preserving.
# The selector value is opaque here: it is passed verbatim to gen-select's `matches` against a
# single-node context built from each demand's subject entry. The context PROJECTS the subject as an
# identity-bearing node so the whole selector algebra resolves against it: `sel.entity <entry>` matches
# `__identity.id_hash`, `sel.kind <kind-value>` matches `__identity.kind`, and `sel.attrs { … }`,
# `sel.star`, `sel.not` compose over the same node.
{ selectLib, prelude }:
let
  inherit (prelude) filter;

  # A degenerate scope context whose only node is the subject itself — no children/parent/ancestors/
  # siblings (subject matching does not traverse a scope). `data` projects the subject's own attributes
  # PLUS an `__identity` record: `id_hash` for the identity selector (Neron, Tolmach, Visser &
  # Wachsmuth 2015 — references resolve to declarations by content-addressed identity, not name), and
  # `kind` for the type selector (the subject's positional kind tag; gen-schema entries carry no kind of
  # their own). A subject without `id_hash` is a non-entity node (`__identity = null`) that matches
  # nothing; a subject carrying no kind tag projects `kind = null`, so `sel.kind` throws loudly on it (a
  # projection gap, never a silent never-match) rather than the adapter guessing.
  ctxFor = subject: {
    data =
      _:
      subject
      // {
        __identity =
          if subject ? id_hash then
            {
              inherit (subject) id_hash;
              kind = subject.type or null;
              entry = subject;
            }
          else
            null;
      };
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
