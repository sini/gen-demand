# intake — root-demand validation (error taxonomy §4.6 intake row): unknown kind, subject without
# id_hash, reserved payload key. Every anomaly is a loud throw (never silent).
{ lib, genDemand, ... }:
let
  inherit (genDemand)
    mkKinds
    mkKind
    demand
    resolveAll
    ;

  didThrow = e: !(builtins.tryEval (builtins.deepSeq e null)).success;
  succeeds = e: (builtins.tryEval (builtins.deepSeq e null)).success;

  kinds = mkKinds [
    (mkKind {
      name = "leaf";
      resolve = _: _: { };
    })
  ];
  run = d: resolveAll { inherit kinds; demands = [ d ]; };

  goodSubject = {
    id_hash = "id-x";
    name = "x";
  };
in
{
  flake.tests.intake = {
    test-unknown-kind-throws = {
      expr = didThrow (run (demand { kind = "ghost"; subject = goodSubject; }));
      expected = true;
    };
    test-subject-without-id-throws = {
      expr = didThrow (run (demand { kind = "leaf"; subject = { name = "no-id"; }; }));
      expected = true;
    };
    test-reserved-payload-key-throws = {
      expr = didThrow (run (demand {
        kind = "leaf";
        subject = goodSubject;
        _type = "hijack";
      }));
      expected = true;
    };
    # A well-formed root demand intakes cleanly.
    test-valid-root-ok = {
      expr = succeeds (run (demand { kind = "leaf"; subject = goodSubject; }));
      expected = true;
    };
    # `demand` requires kind and subject.
    test-missing-kind-throws = {
      expr = didThrow (demand { subject = goodSubject; });
      expected = true;
    };
    test-missing-subject-throws = {
      expr = didThrow (demand { kind = "leaf"; });
      expected = true;
    };
  };
}
