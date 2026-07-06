# Demand construction — a typed request whose `subject` is a registry entry (identity law: any
# value carrying `id_hash`; strings are never accepted). Payload fields are stored flat and are
# opaque to the engine.
#
# Reserved keys (`kind`, `subject`, `_type`, `_path`, `_reserved`) may not appear in the payload;
# a violation is recorded in `_reserved` and thrown WITH a path by the engine (at intake for roots,
# at emission for sub-demands), never here — the constructor has no path context.
{ prelude }:
let
  inherit (builtins)
    attrNames
    elem
    isAttrs
    isString
    ;
  inherit (prelude) filter;

  demandMarker = "gen-demand/demand";
  kindMarker = "gen-demand/kind";

  # Reserved against payload shadowing. `kind`/`subject` are the semantic fields; `_type`/`_path`/
  # `_reserved` are engine-internal. A payload attempting any of these is a shadow error.
  reserved = [
    "kind"
    "subject"
    "_type"
    "_path"
    "_reserved"
  ];

  # A kind value or a kind-name string, canonicalized to the name (the internal key).
  canonKind =
    k:
    if isAttrs k && (k._type or null) == kindMarker then
      k.name
    else if isString k then
      k
    else
      throw "gen-demand.demand: `kind` must be a kind value (mkKind result) or a kind-name string";

  demand =
    args:
    let
      payload = builtins.removeAttrs args [
        "kind"
        "subject"
      ];
      badKeys = filter (k: elem k reserved) (attrNames payload);
    in
    if !(args ? kind) then
      throw "gen-demand.demand: missing required field `kind`"
    else if !(args ? subject) then
      throw "gen-demand.demand: missing required field `subject`"
    else
      # Payload first, fixed fields last: the marker/kind/subject are authoritative; `_reserved`
      # carries any shadow violation for the engine to report with a path.
      payload
      // {
        _type = demandMarker;
        kind = canonKind args.kind;
        subject = args.subject;
        _reserved = badKeys;
      };
in
{
  inherit
    demand
    canonKind
    demandMarker
    reserved
    ;
}
