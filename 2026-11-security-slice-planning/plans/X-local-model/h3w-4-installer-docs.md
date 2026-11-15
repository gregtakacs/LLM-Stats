# H3w step 4: installer emits `sites`, doctor checks each role, with/without-hub proxy snippets and docs

## Goal

Bring the operator surface in line with the two-origin model. `install.sh` gains
`--hub-host` and `--opencode-host` (replacing/augmenting `--public-host`) and writes the
config's new `sites` array; an existing config with `public_hosts` is **migrated** to
`sites` (each former host becoming a `hub` entry) with a printed note. The printed
reverse-proxy snippet is generated **per role**: for a hub host, proxying at the root to
the hub; for an OpenCode host, the **with-hub** snippet (proxy to the hub, which relays)
and the **without-hub** snippet (proxy straight to OpenCode), both shown so an operator can
choose R-H3-2's deployment. `doctor.py` checks each site's roles and routes. Both docs
(`docs/hub-install.md` and the OpenCode-side install/run doc) describe the two-origin
layout with generic example names only (`hub.example.com` / `code.example.com`).

Binds: `docs/h3-design.md` §6.3–6.5 (installer, snippets, doctor), §6.1–6.2 (config it
writes), §10.1 (drop old layout), §10.2 (generic names only — R-H3-3). This step touches no
request-path logic; step 1's config validation is what actually refuses a bad `sites`.

## Read first

- `docs/h3-design.md` §6 (whole), §10.1, §10.2.
- `docs/specs/h3w-1-roles-routing.md` (the `sites` schema and its validation) and
  `h3w-3-opencode-renew.md` (what the renewal needs from the proxy snippets).
- `hub/install.sh` — the current `--public-host` / `--auth-frame-origin` parsing,
  `public_host_normalized`, `auth_frame_origin_ok`, and the JSON + snippet generation.
- `hub/config.py` after step 1 — the `sites` shape you must emit exactly (the installer's
  output must pass `load_hub_config`).
- `hub/doctor.py` — `check_config`, `check_gate` (~line 374), `CHECK_ORDER`, the `Result`
  tuple shape, and the fix-line idiom.
- `hub/tests/test_install.py`, `test_doctor.py`, `daemon/tests/test_install_docs.py`.
- `docs/hub-install.md` and the OpenCode install/run doc it links (find both via
  `git ls-files 'docs/*install*' 'docs/*run*'`).

## Contract

### Files

Modify: `hub/install.sh`, `hub/doctor.py`, `docs/hub-install.md`, the OpenCode run/install
doc, `hub/tests/test_install.py`, `hub/tests/test_doctor.py`,
`daemon/tests/test_install_docs.py`. Do not change `config.py`/`gate.py`/`proxy.py`/`api.py`
(request-path files are frozen after step 3); if the installer needs a validation the
config doesn't already do, that is a bug in step 1 — note it, don't fix it here.

### `install.sh`

- New flags: `--hub-host <name>` (repeatable) and `--opencode-host <name>` (repeatable);
  pair them positionally into `sites` entries (`{hub, opencode?}`), reusing the existing
  name-normalising/validating helper for each value. Keep `--public-host` accepted as an
  **alias** that maps to `--hub-host` (migration aid) with a deprecation line, or refuse it
  with a fix pointing at the new flags — pick one, be consistent with the migration rule
  below, and test the choice.
- Output `hub.json` writes `sites` (never `public_hosts`).
- **Migration mode**: given an existing config dir whose `hub.json` has `public_hosts`,
  rewrite it to `sites` (each host → `{"hub": host}`), print one line naming the change,
  keep file mode 0600, and re-validate through the same normaliser. Refuse to migrate if
  the result would duplicate a host.
- **Printed snippets** (config-derived, generic placeholders only): for each hub host, a
  root-proxy block to the hub; for each paired opencode host, **two** labelled blocks —
  `# (a) route via the hub (R-H3-2 with-hub)` proxying to the hub, and `# (b) route direct
  to OpenCode (without hub)` — with the same generic hostnames the config holds.

### `doctor.py`

- Replace the single `public_hosts` checks with **per-site** checks: config validity (via
  step 1's loader, unchanged message), each `hub` host's gate probe (cookie-less 401,
  foreign-Host 421 as `check_gate` does today, now run against a hub host), and each
  `opencode` host's route probe (a cookie-less `GET /` to the opencode host reaches
  OpenCode — expect the upstream's status, not a gate 401, i.e. the relay is transparent; a
  foreign Host still 421). New `Result` names in `CHECK_ORDER`: e.g. `sites`, per-role gate
  lines. Fix lines follow the existing prose idiom. No secrets, no value echoes.

### Docs

- `docs/hub-install.md`: the two-origin layout, the new flags, a worked example writing
  `sites` with `hub.example.com`/`code.example.com`, both proxy snippets, and a paragraph
  stating the old single-origin `/hub/` layout is retired and how to migrate.
- The OpenCode run doc: the with-hub vs direct-OpenCode choice, the renewal frame on the
  OpenCode origin (points at step 3's `/h/_hub/renew.html`), the same generic names.

### Tests

- `test_install.py`: flags parse; `sites` emitted validates through `load_hub_config`; a
  duplicate across hub/opencode fields is refused by the installer; migration of a
  `public_hosts` config produces a `sites` config that round-trips and is still 0600; the
  snippets contain both `hub.example.com` and `code.example.com` and both with-hub and
  direct blocks; no real domain string appears anywhere in the installer output.
- `test_doctor.py`: a two-site config yields the per-role checks in `CHECK_ORDER`; a
  mis-routed opencode host fails the opencode route check with a fix line; a hub host gate
  probe still yields cookie-less-401/foreign-421.
- `daemon/tests/test_install_docs.py`: doc expectations updated for the new filenames/
  anchors/flags you introduced (no other `daemon/` change).

## Acceptance

`python3 tools/run_tests.py hub.tests.test_install hub.tests.test_doctor
daemon.tests.test_install_docs` each matching `^ok +…tests…<module>…OK$`, plus the scope
guard. No UI change → no screenshots.

## Out of scope

Any request-path behaviour (steps 1, 3), the acceptance matrix (step 5). Do not add a
`public_hosts`→`sites` runtime fallback in the config loader (that is deliberately refused,
R-10.1); migration is an installer action only.

## Notes

The snippets are **printed for the operator to paste**, never executed here; they must be
self-evidently generic (R-H3-3) — a test greps the installer stdout for the absence of any
non-`example.com` dotted host to hold that line.
