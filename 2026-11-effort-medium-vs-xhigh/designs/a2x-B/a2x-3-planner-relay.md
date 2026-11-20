# A2X step 3 — hostile planner and hostile relay

**Build**: `oc/tests/test_a2x_planner.py` and `hub/tests/test_a2x_relay.py`, plus the
planner/installer refusals K7 and K10 and any byte-exact gap R1–R9 proves in `hub/*`.

## Read first

- `docs/specs/a2x-design.md` §3 and §5 (rows K1–K10, R1–R9, with citations).
- `docs/specs/a2-broker-contract.md` §3 (the broker's config, whose member layout the
  planner mounts) and §12 (the container's view); `docs/specs/a2-design.md` §5 (the
  hardening rows this planner implements, point by point) and §10.
- `docs/specs/a2i-1-planner.md` (every refusal `PlanError` key this step tests, as
  written), `docs/specs/a2h-2-routes-relay.md` and `docs/specs/a2h-design.md` §5/§10
  (X1–X25 — the relay suite this one does **not** repeat: it is the gate-shape and
  identity half), `docs/specs/a2a-10-hostile.md` (the launcher's `/projects/<name>/...`
  and admin halves, owned there).
- `oc/projects.py` — the docstring's three rules (:7–18), `binds` :201–245 (`_home_or_refuse`
  :155–161, the member/home rules :221–231, `_check_not_trusted` :193–200, the socket dir
  :233–235), `_path_or_refuse` :177–187 (`MOUNT_BAD_CHARS`), the tree walk :690–727
  (`is a link or not a directory`, `is not inside`), `plan_project` :363–,
  `create_argv` :441–452 (`--read-only --tmpfs /tmp:exec --cap-drop ALL
  --security-opt no-new-privileges:true --restart no`, `--label` twice, `--user`),
  `network_argv` :447–452 (`--internal`, one /28), `egress_argv` :453–, the proxy env
  :282–296, `pin_hosts` :605–631 (loopback refused), `load_registry` :808–915 (mode 600,
  ownership, symlink, version, `written_by`, spec-is-64-hex), `NAME_RE` :48 and the
  docker-name check :862–863, `CONTAINER_PREFIX` :38, `EGRESS_NAME` :39, `BROKER_DIR_IN`
  :43 / `BROKER_SOCK_IN` :44, the registry dir/env helpers (:121 and friends).
- `broker/config.py:55` — `RESERVED_PROJECT_NAMES`, the set the planner does not consult
  (case K4's second half, and a finding to name if it should).
- `oc/projinstall.py` — the pin guard :252–254 (`refuse` → :139 `Usage` → :1130 exit 2),
  `--project` filter :407, `makedirs(mode=0o700)` :693, `make_real_dir(…, 0o700)` :703,
  `require_ours` :319– (the label check: an existing object of a name must carry this
  install's label), and `oc/install.sh` :54–72 (where `projects` and `migrate` dispatch).
- `review/h3_hostile.py` :20–150 — the orchestrator's own hostile hub probes (origin
  rules, duplicate headers, upgrade refusals): the R-rows here are the byte-exact-shape and
  identity half; if one of these cases and that probe disagree, report it rather than
  picking a side.
- `hub/tests/httputil.py` — `HubTestCase` (:739, `request` :883), `FakeOpenCode` (:332,
  `received_bytes` :377 — the side-effect oracle), `write_projects` (:556).
- `hub/gate.py` :49–60 (the fixed bodies), `hub/routes.py` — `RESERVED_HOME_NAMES` :79,
  `classify` :247, the P-rows :408–440, `PTY_ID_RE` :193, the reserved-name check
  :316–319; `hub/proxy.py` — `PROJECT_DROP` :102, `is_active` :200, `upstream_for` :370
  (one project's password never rides to another's container), `access_host_slot` :261;
  `hub/wsrelay.py` — `is_websocket_upgrade` :64–75.

## Files owned

- `oc/tests/test_a2x_planner.py`, `hub/tests/test_a2x_relay.py` — the suites.
- `oc/projects.py` — `pin_hosts` (K7's extension) only.
- `oc/projinstall.py` / `oc/install.sh` — K10's refusal only (the relative-`HOME`/
  pre-flight shape it names, in one place each).
- `hub/gate.py`, `hub/proxy.py`, `hub/routes.py` — only where an R-case pins a real gap:
  the drop of an identity header, the ordering that lets `503` answer a reserved name, a
  response header that should be in `PROJECT_DROP`. A drop-list edit is the whole expected
  change; anything larger is a finding to report, not to refactor here.
- `docs/specs/a2x-design.md` — corrected cells.

## Behaviour and edge cases

**Planner (K1–K7).** Every case calls the real functions; assertions are on the `PlanError`
key and message and on the argv lists, never on a re-derived plan shape. Temp roots are
built the way `oc/tests/test_projects.py` builds them.

- K1/K2: a config whose second project binds a path under the *first* project's tree, and
  one that binds the first's layout config dir → key `mount` for the not-inside case
  (`is not inside` :683–688) and key `projects.<P>` for the trusted-layout case
  (`_check_not_trusted` :193–200). The counter-assertion — the point of the row, not the
  refusal — is that neither plan's `binds` tuple contains a path of the other project at
  all: the cross-project refusal is a fact about the list, not only an exception.
- K3: `home` that is another project's directory; a home carrying `..`; a home whose parent
  is a symlink; a home that *is* a member's directory and one whose child is (`binds`
  refuses both: `holds the container's home … never a mount` :225–228, and `_under` the
  other way). Each with its key: `home` :155–161, `mount` :683–688, `projects.<P>`
  :221–228.
- K4: names `web-app;rm -rf /`, `web app`, `--privileged`, `-x`, `""`, a 200-character
  string → `NAME_RE`/the docker-name rule (`not one docker can take` :862–863, key
  `registry`); and the reserved set (`p`, `api`, `static`, `broker/config.py:55`) — the
  finding is that the planner *takes* them while the broker config and the hub route table
  refuse them. One readable case pins the three-way disagreement (raises at the broker,
  `404` at the hub, plans here) so whoever closes it has a fence to update, not a mystery.
- K5: a registry entry whose `spec` is the recomputed hash minus one character, and one
  whose `spec` is deleted → key `registry` (`spec is not 64 hex digits` :876; the
  wrong-keys arm :773). The half that matters for anyone who can write the registry at
  all: `load_registry` compares, it never recomputes-to-trust (module docstring :7–9), and
  the fake-docker call-log stays empty — a mismatched entry cannot reach `docker create`.
- K6: registry 0644, (where the sandbox can make one) 0600 owned by another uid, and a
  symlink at the path → :820 `is a link`, :824 `is not mode 600`, :826 `is not owned by
  this user`; a 0777 *parent* is not a refusal (the file's own mode is the guarantee) and
  the test says so in one line, because the reader will wonder.
- K7: pins — `example.com → 127.0.0.1` (refused today: `resolves to loopback` :626–628);
  `169.254.169.254`, `169.254.1.1`, `100.100.100.200`, `::1`, `0.0.0.0`, and
  `metadata.google.internal → 169.254.169.254`: `pin_hosts` refuses loopback only, and this
  step extends that arm to `is_link_local`, `is_multicast` and `is_unspecified`
  (`ipaddress` predicates, one branch) with the message shape kept; `site-local` is
  deliberately **not** refused — a LAN model host is a legitimate site choice and
  `oc/tests/test_proxy_templates.py` pins private pins today, so the arm is written against
  the metadata ranges by name plus those three predicates. The fake resolver argument keeps
  it deterministic: no DNS is touched. A positive case (a public pin plans fine, and a
  private one still plans) rides in the same test, so the extension cannot strand a real
  provider host.
- K8: `install.sh projects start` on a config with egress disabled → `network_argv`'s
  `--internal` present, no egress container name anywhere in the call-log, and
  `create_argv` carries no `HTTP_PROXY` pair (:282–296: the proxy environment is the egress
  branch and only that branch); enabled with `allow_hosts: ["*.example.com",
  "203.0.113.7"]` → both appear verbatim in the squid config's arguments, the planner
  passing rather than interpreting (contract §3.4's division).
- K9: `python3 -m oc.projinstall` with the pin environment stripped → the guard's own
  message (:252–254, "run this through …") and exit 2 (`Usage` → :1130), call-log empty;
  `projects stop --project nosuch` → the usage refusal (:407's contract); `stop` twice →
  the second call's log shows no `start`/`run`/`create`; and a container carrying the name
  without this install's label is never stopped — `require_ours`'s rule (:319–), asserted
  on the call-log (`stop` asked for the label, read the answer, and refused).
- K10: a registry written at 0644 → K6's message arrives through the dispatch as a nonzero
  exit with the `registry` key's text on stderr and the call-log empty; a symlinked
  registry → :820's text, same shape; a registry dir pre-created 0775 by a hostile umask →
  what the code guarantees is 0700 must *be* 0700 (:693, :703): the mode is asserted after
  the run, which is the umask-002 trap `handoff.md` §9 records as this host's own failure
  mode. A relative `HOME` refuses before anything is created (`_home_or_refuse` :155–161 is
  the place; if the dispatch reaches it at all, that is the gap the step's fix closes).

**Relay (R1–R9).** `HubTestCase` with two projects live (`write_projects` :556); the oracle
for "nothing proxied" is `FakeOpenCode`'s received list (`received_bytes` :377), and the
oracle for the answer is byte equality against `gate.py`'s own constants (:49–60).

- R1: no cookie → `401` + `BODY_401`, no `Set-Cookie`; a `Cookie: sid=…` the `FakeVerifier`
  does not know → identical bytes; `X-Project-User`/`X-Project-Session`/`Cookie` forged on
  a *valid* request → the proxied request carries none of them; and the pair that makes the
  answer non-probing: `/p/<anything>/..` answers byte-identically whether the project is
  live or removed — the wire cannot query the registry.
- R2: the trick set (`/p/web.app/`, `/p/web%2Fapp/`, `/p/web-app/./a`,
  `/p/web-app/../api`, `/p/web-app/%2e%2e/api`, `//p/web-app/`, `/p//web-app/`, and a
  case-varying `/P/web-app/`) → `BODY_404`/`BODY_400` per `classify` (:247) with the
  nothing-proxied oracle, and **never** `503`, which would confirm a registered project —
  a fact about the owner's config the wire is not allowed to give. One test asserts
  offline-live vs never-known give identical bytes for the whole set.
- R3: the reserved names — `RESERVED_HOME_NAMES` (routes.py:79–80) is the set, and
  `broker/config.py:55` is the same set at the config boundary (the test imports both and
  asserts the equality too: two copies of a deny list is how a boundary drifts) → each
  refused with the unknown-project bytes. `routes.py:434–438` (P4's "a reserved name is not
  a home even when the registry holds it") is the cite the docstring carries.
- R4: `GET /p/web-app/api/pty` (no id) and `…/api/pty/<bad>` (`../x`, 65 chars, empty) →
  the table's answer per `PTY_ID_RE` (:193); `Connection: Upgrade` + `Upgrade: websocket`
  on `/p/web-app/` and on a row off the upgrade list → no `101` bytes ever, on the wire or
  in the fake upstream's received head (`is_websocket_upgrade` :64–75 decides the shape;
  the row table decides the permission, a2h-2's list — this case is only the absence).
- R5: the three framing failures (`Content-Length: 314572800`, none on a `POST`,
  `Transfer-Encoding: chunked`) → `BODY_413`/`BODY_411`/`BODY_501` byte-exact, received list
  empty — the body never read off the wire (framing before identity before route,
  `gate.py:43–47`; `_declared_body` is the reader, `proxy.py:425–`). The shaped
  counter-case: a 1 MiB body on a row that does take one gets its route's answer, which is
  what proves the cap is a cap and not a blanket refusal.
- R6: `/p/web-app/api/fs/read?path=/etc/passwd`, `?path=../../etc/passwd`,
  `?path=%2e%2e%2f%2e%2e%2fetc%2fpasswd`, and a `file=` query on a non-fs P-row. The hub
  relays and the container answers (a2h-2's design), so the assertions are the hub-side
  pair that must hold however that answer arrives: the refusal's bytes carry no path
  (`_sanitise`, the discipline R2 pins at the gate), and the relabel exception
  (`proxy.py:728–736` — `is_fs_read`, exact `/api/fs/read/` prefix on the forwarded target)
  fires for that shape **only**: an escaped or look-alike target is not relabelled, and the
  test asserts the answer's `Content-Type` is the hardening path's, not `text/plain`.
- R7: `OPTIONS`/`TRACE`/`DELETE`/`PATCH` across the P-rows → `BODY_405` + `Allow` where the
  method table says (routes.py:169–178's class rules), `BODY_501` for TRACE, and the one
  method a row does take is proxied — proven by the received list, the only way "proxied"
  and "answered by the gate" are told apart.
- R8: the container answers `Set-Cookie: sid=stolen`, `WWW-Authenticate: Basic realm=x`,
  `Location: http://evil/`, `Refresh: 0; url=http://evil/`, its own `Cache-Control` and CSP →
  the client sees `relay_response_headers`'s list exactly (:387–420): `RESPONSE_DROP` (:78)
  takes hop-by-hop, `Set-Cookie`, `WWW-Authenticate`; the project kind's
  `is_project_dropped` (:219–222 with `PROJECT_DROP` :102–107) takes `Location`, `Refresh`,
  the report-only CSP, `X-Frame-Options` and every `access-control-*`; `Cache-Control` is
  replaced rather than kept; `PROJECT_ADD` (:111–116 — `nosniff`, the sandbox CSP,
  `same-origin`, `no-store`) is appended. Assert the list in order: "dropped" and "present
  once" are both invisible to a substring assertion, and a redirect that survives is the
  open-redirect this row exists for.
- R9: two projects live, one hub: principal B's cookie on project A's URL, and a `Host:`
  that is the site's second name → `BODY_421` for the misdirection (the host step precedes
  identity) and `classify`'s answer for the session mismatch, each byte-exact, nothing
  proxied. `upstream_for` (:370–384: the URL and the credential come from the same object)
  is why a cross-project password ride is impossible; this is the case that fails first if
  it ever stops being true.

## Acceptance criteria

- `python3 tools/run_tests.py oc.tests.test_a2x_planner hub.tests.test_a2x_relay` exits 0;
  the chain's verify shows both `^ok` lines inside a full green gate run.
- K7's fix: `oc` green, and the positive pins in the same test still plan — an extension
  that strands a legitimate provider host is the failure mode of exactly this kind of fix.
- K10's refusal: `oc.tests.test_install` green too; the dispatch contract unchanged.
- R-rows: `hub.tests.test_relay`, `test_proxy_hardening`, `test_projects` green; every
  byte-exact assertion compares against a `gate.py`/`routes.py`/`proxy.py` constant, never
  a re-typed literal (a re-typed literal is a test that passes while the product changes).
- Scope guard: `git diff --name-only <base>` touches only Files owned.
- Report: per R-row whether the gate's bytes changed (they should not; a changed answer is
  the finding and goes to a2x-5's handoff line), per K-row the key and message as observed.

## Out of scope

The launcher's `/projects/…` proxy and the admin surface (A2A-10 owns those), the migration
CLI (step 4), `hub/wsrelay.py`'s pump and framing (X-rows in `test_relay.py`), the broker
(steps 1–2), and every other `install.sh` command.
