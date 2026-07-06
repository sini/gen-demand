# resolveAll — the stratified demand cascade.
#
# Registration (`mkKinds`) fixes a per-kind `depth`; `resolveAll` runs exactly `maxDepth + 1`
# strata top-down (d = maxDepth … 0). At stratum d it resolves every pending demand of depth d in
# schedule order, validating and path-assigning each emitted sub-demand at emission, then folds the
# stratum's resource fragments per dedup group. Because every `below` edge strictly decreases depth,
# a stratum's demand set is complete when it runs and there is nothing pending after stratum 0.
#
# THEORY: strata-wise bottom-up evaluation with stratum-local aggregation (Apt, Blair & Walker
# 1988) — aggregation (the dedup fold) is applied only when a stratum's fact set is complete, which
# is the classical reason aggregation demands stratification. Termination is Noetherian induction on
# the ℕ-valued `depth` (well-founded recursion), not a runtime convergence test — there is no
# iteration cap. The trace realizes why/derivation provenance (Cheney, Chiticariu & Tan 2009):
# each artifact maps to the demand instances that produced it, extended with parent chains to roots.
{
  prelude,
  kindsLib,
  demandLib,
  foldsLib,
}:
let
  inherit (builtins)
    attrNames
    elem
    groupBy
    isAttrs
    isList
    isString
    length
    removeAttrs
    toJSON
    ;
  inherit (prelude)
    concatLists
    concatMap
    elemAt
    filter
    foldl'
    head
    imap0
    listToAttrs
    map
    mapAttrs
    nameValuePair
    range
    sort
    tail
    unique
    ;

  # Display string for an entry — output-only per the identity law; never travels as identity.
  renderSubject =
    e:
    if !isAttrs e then
      "<non-entity>"
    else if e ? name then
      e.name
    else if e ? rendered then
      e.rendered
    else
      e.id_hash or "<no-id>";

  hasId = e: isAttrs e && e ? id_hash;

  # Lexicographic comparison of integer-list paths (roots by intake order, children by parent path
  # then emission index). A strict total order over the distinct paths of one stratum.
  pathLt =
    a: b:
    if a == [ ] then
      b != [ ]
    else if b == [ ] then
      false
    else
      let
        ha = head a;
        hb = head b;
      in
      if ha < hb then
        true
      else if ha > hb then
        false
      else
        pathLt (tail a) (tail b);

  resolveAll =
    {
      kinds,
      demands,
      ctx ? { },
    }:
    let
      kindSet = kindsLib.asKindSet kinds;
      ks = kindSet.kinds;
      depth = kindSet.depth;
      maxDepth = kindSet.maxDepth;

      # ── validation shared by intake and emission ──
      # `chain` names the emitting demand for sub-demand errors (empty for roots).
      validate =
        { path, chain }:
        d:
        let
          pathStr = toJSON path;
          rendered = renderSubject (d.subject or null);
        in
        if !(isAttrs d && (d._type or null) == demandLib.demandMarker) then
          throw "gen-demand: value at path ${pathStr} is not a demand (build it with `demand`)${chain}"
        else if !(ks ? ${d.kind}) then
          throw "gen-demand: unknown kind '${toString d.kind}' at path ${pathStr}${chain}"
        else if (d._reserved or [ ]) != [ ] then
          throw "gen-demand: demand at path ${pathStr} (kind '${d.kind}', subject '${rendered}') shadows reserved payload key(s) ${toJSON d._reserved}${chain}"
        else if !(hasId (d.subject or null)) then
          throw "gen-demand: demand at path ${pathStr} (kind '${d.kind}') has a subject without id_hash (renders as '${rendered}')${chain}"
        else
          d;

      emittedBy =
        i:
        " (emitted by demand at path ${toJSON i.path}, kind '${i.kind}', subject '${renderSubject i.demand.subject}')";

      # The view a resolver receives: the demand's own fields plus `_path` — nothing else (L2).
      # `_reserved` (engine bookkeeping) is stripped; no resolved state is ever threaded in.
      resolverView = i: removeAttrs i.demand [ "_reserved" ] // { _path = i.path; };

      groupKeyOf =
        i: rv:
        let
          dk = ks.${i.kind}.dedupKey;
        in
        if dk == null then
          null
        else
          let
            r = dk rv;
          in
          if !isString r then
            throw "gen-demand: dedupKey for kind '${i.kind}' at path ${toJSON i.path} returned a non-string: ${toJSON r}"
          else
            r;

      # ── intake ──
      roots = imap0 (
        i: d:
        let
          v = validate {
            path = [ i ];
            chain = "";
          } d;
        in
        {
          demand = v;
          path = [ i ];
          parent = null;
          stratum = depth.${v.kind};
          kind = v.kind;
        }
      ) demands;

      # ── discovery + resolution, stratum-major descending (d = maxDepth … 0) ──
      strataDesc = map (d: maxDepth - d) (range 0 maxDepth);

      step =
        st: d:
        let
          atD = sort (a: b: pathLt a.path b.path) (filter (i: i.stratum == d) st.instances);
          resolvedAtD = map (
            i:
            let
              rv = resolverView i;
              result = ks.${i.kind}.resolve rv ctx;
              childrenRaw = result.demands or [ ];
              below = ks.${i.kind}.below;
              children = imap0 (
                j: sd:
                let
                  cpath = i.path ++ [ j ];
                  v = validate {
                    path = cpath;
                    chain = emittedBy i;
                  } sd;
                in
                if !(elem v.kind below) then
                  throw "gen-demand: kind '${i.kind}' at path ${toString i.path} emitted a sub-demand of kind '${v.kind}' not in its `below` set ${toJSON below}${emittedBy i}"
                else
                  {
                    demand = v;
                    path = cpath;
                    parent = i.path;
                    stratum = depth.${v.kind};
                    kind = v.kind;
                  }
              ) childrenRaw;
            in
            {
              inherit (i) path parent stratum kind;
              subject = i.demand.subject;
              gk = groupKeyOf i rv;
              inherit result children;
            }
          ) atD;
          newChildren = concatMap (r: r.children) resolvedAtD;
        in
        {
          instances = st.instances ++ newChildren;
          resolved = st.resolved ++ resolvedAtD;
        };

      final = foldl' step {
        instances = roots;
        resolved = [ ];
      } strataDesc;

      # Force every instance to WHNF so emission-stage validation (below-membership, subject
      # id_hash, reserved keys) always runs — even for a leaf root whose sub-demands are otherwise
      # never consumed at the lowest stratum (a leaf emitting anything must still be a loud error).
      validatedInstances = foldl' (acc: i: builtins.seq i acc) true final.instances;

      # `resolved` is already in global schedule order (stratum-major descending, path-lex within).
      resolved = final.resolved;
      kindsWithInstances = unique (map (r: r.kind) resolved);

      # ── resource combination (per kind, per dedup group, per key) ──
      combineKind =
        kn:
        let
          insts = filter (r: r.kind == kn) resolved;
          kd = ks.${kn}.dedupKey;
          kf = ks.${kn}.fold;
          # Groups: dedupKey partition, or one singleton group per instance (fold-less).
          groups =
            if kd == null then
              map (i: {
                gkey = null;
                insts = [ i ];
              }) insts
            else
              let
                g = groupBy (i: i.gk) insts;
              in
              map (k: {
                gkey = k;
                insts = g.${k};
              }) (attrNames g);
          foldGroup =
            grp:
            let
              allKeys = unique (concatMap (i: attrNames (i.result.resources or { })) grp.insts);
              keyEntry =
                key:
                let
                  contributors = filter (i: (i.result.resources or { }) ? ${key}) grp.insts;
                  values = map (i: i.result.resources.${key}) contributors;
                  paths = map (i: i.path) contributors;
                in
                {
                  inherit key paths;
                  groupKey = grp.gkey;
                  value =
                    if kf == null then
                      # fold-less: a single group holds one instance ⇒ one value per key
                      head values
                    else
                      kf key values;
                };
            in
            map keyEntry allKeys;
          allEntries = concatLists (map foldGroup groups);
          # Cross-group / fold-less collision: a resource key produced by more than one group.
          byKeyName = groupBy (e: e.key) allEntries;
          collisions = filter (k: length byKeyName.${k} > 1) (attrNames byKeyName);
        in
        if collisions != [ ] then
          throw "gen-demand: kind '${kn}' resource-key collision on ${toJSON collisions} — key(s) contributed by distinct groups at paths ${
            toJSON (map (k: map (e: e.paths) byKeyName.${k}) collisions)
          }"
        else
          {
            resources = listToAttrs (map (e: nameValuePair e.key e.value) allEntries);
            trace = listToAttrs (
              map (
                e:
                nameValuePair e.key {
                  demands = e.paths;
                  folded = kf != null;
                  groupKey = e.groupKey;
                }
              ) allEntries
            );
          };

      combined = listToAttrs (map (kn: nameValuePair kn (combineKind kn)) kindsWithInstances);
      resources = mapAttrs (_: c: c.resources) combined;
      traceResources = mapAttrs (_: c: c.trace) combined;

      # ── wiring accumulation (per subject, per kind, schedule order) ──
      wiringEntriesFor =
        r:
        let
          w = r.result.wiring or { };
        in
        if isList w then
          w
        else if attrNames w == [ ] then
          [ ]
        else
          [
            {
              subject = r.subject;
              wiring = w;
            }
          ];

      flatWiring = concatMap (
        r:
        map (
          e:
          if !hasId (e.subject or null) then
            throw "gen-demand: wiring at path ${toJSON r.path} (kind '${r.kind}') targets a subject without id_hash (renders as '${renderSubject (e.subject or null)}')"
          else
            {
              id = e.subject.id_hash;
              inherit (e) subject wiring;
              inherit (r) kind path;
            }
        ) (wiringEntriesFor r)
      ) resolved;

      byId = groupBy (e: e.id) flatWiring;
      wiring = mapAttrs (_: es: {
        subject = (head es).subject;
        byKind = mapAttrs (_: ek: map (e: e.wiring) ek) (groupBy (e: e.kind) es);
      }) byId;
      traceWiring = mapAttrs (
        _: es:
        map (e: {
          inherit (e) kind;
          demand = e.path;
        }) es
      ) byId;

      # ── trace.demands (global schedule order) ──
      traceDemands = map (r: {
        inherit (r) path parent stratum kind;
        subject = {
          id_hash = r.subject.id_hash;
          rendered = renderSubject r.subject;
        };
        groupKey = r.gk;
      }) resolved;
    in
    builtins.seq validatedInstances {
      inherit resources wiring;
      trace = {
        demands = traceDemands;
        resources = traceResources;
        wiring = traceWiring;
      };
    };
in
{
  inherit resolveAll pathLt renderSubject;
}
