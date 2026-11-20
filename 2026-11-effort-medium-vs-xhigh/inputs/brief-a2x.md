# A2X design: plan A2 step 8 (the A2 hostile suite) and write its step specs (no product code)

## Goal

Step 8 of `docs/specs/a2-design.md` (§8 row 8: "a hostile container suite (reach another
project, the socket, a secret, a host path, `--repo` / path tricks through the broker), plus the
live check"; §10 threat model; ruling 26 at the end of the file). Your job in this task is
**design only**: the slice design, a spec per step, and a `delegate chain` plan that other
workers will run step by step. Write no product code.

This is the acceptance suite of a security boundary. Its value is the hostile cases it names,
each with an expected outcome; "treat as untrusted" alone produces no tests.

## Read first

- `docs/specs/a2-design.md`: §1, §3, §4 (the broker: identity, delegate, GitHub, test
  databases, what it is not), §5 (the per-project container), §5.2, §9 (migration), §10 (threat
  model), §11 (spikes) and all owner rulings including 24–26 at the end. Rulings are binding.
- The hostile suites that already exist, so this slice **covers gaps and the cross-component
  paths, and does not re-type them**: `docs/specs/a2g-4-hostile.md` +
  `broker/tests/test_groups_hostile.py`, `docs/specs/a2-2a-broker-core.md` and
  `docs/specs/a2h-2-routes-relay.md` (their hostile sections), `docs/specs/a2a-10-hostile.md`
  (step 6's suite, being built now on the same branch: plan against its spec). List, in the
  design, every threat row of §10 and of `docs/specs/a2a-design.md` §11 with the existing test
  that covers it and what this slice adds.
- The code under test: `broker/` (`server.py`, `protocol.py`, `paths.py`, `repocheck.py`,
  `mounts.py`, `git_push.py`, `gh.py`, `services.py`, `delegate_rules.py`, `client.py`), `oc/`
  (`projects.py`, `projinstall.py`, `install.sh`, `Dockerfile`, `entrypoint.sh`, `bin/`,
  `proxy/`, `doctor.py`), the hub's `/p/<project>/` relay (`hub/` — find it with
  `grep -rn "/p/" hub/*.py`), `launcher/` (the `oc` target).
- Earlier plans to imitate: `docs/specs/a2-groups-chain.json`, `docs/specs/a2a-chain.json` and
  their specs; the step-spec template `~/{claude-dir}/skills/delegate/spec-template.md` (mounted).

## The repo's gate

`python3 tools/run_tests.py`. Every step's verify ends with it, exactly as written here
(imitate how `docs/specs/a2a-chain.json` writes the verify: the gate's output into
`${DELEGATE_EVIDENCE_DIR:-/tmp}/verify-<step>.log`, then greps that the step's own test modules
ran `ok` and nothing failed).

## Fixed requirements

- **Two layers (ruling 26).**
  1. *In-process layer*, part of the gate: tests that drive the **real** broker server over its
     real Unix socket, the real hub relay over HTTP, and the real `oc/projects.py` /
     `oc/install.sh` planners with temp dirs, with hostile inputs. No mocks of the component
     under test; fakes only for `docker`, `git` remotes and `gh` network, written as executables
     on `PATH` that record their argv.
  2. *Container layer*, a host script (for example `tools/a2-hostile-live.py`, stdlib only)
     that the owner runs at the cutover against the deployed per-project containers with
     `docker exec` **as the container's own user**. Each probe prints `PASS`/`FAIL <id>` with
     what it observed; the script exits non-zero on any FAIL and **never changes state**:
     every probe is a read, a connect or a request that must be refused; no write outside the
     container's own `/tmp`, no container/network/volume create or remove, no restart. It
     refuses to run unless given `--project A --other B` that both exist in the registry, and
     prints its plan with `--dry-run`. Its own unit tests (in the gate) run it against a fake
     `docker` on `PATH` that returns recorded answers, covering PASS, FAIL and "docker missing".
     The worker cannot run it for real (no Docker in the sandbox); say so in the spec.
- **Hostile cases, each an acceptance item with its expected outcome** (add every other one
  §10 implies):
  - From project A: reach project B's broker socket, OpenCode port, data dirs, worktrees, its
    secret files; reach the egress proxy's LAN side or a LAN address through it; reach the
    host's Docker socket, `/run/user/1000`, the launcher socket, the helper socket; read the
    GitHub token; read `~/.ssh` of the host.
  - Through A's broker: `--repo` and path arguments naming B's repo, `..`, an absolute host
    path, a symlink planted inside A's worktree pointing into B or `/`, a symlink swapped in
    after the check (TOCTOU: the request must still be confined), a hard link, a FIFO or
    device where a file is expected, NUL / newline / bidi / 10 000-character arguments, a
    trailing newline past a `^…$` check, non-finite and huge numbers in JSON, oversized
    request bodies and lines, a half-written request then a close, 50 concurrent requests,
    one bad request among good ones (refused, the others answered), a git config in A's repo
    with `core.fsmonitor` / `core.hooksPath` / a filter / `diff.external` / `credential.helper`
    that would run on the host side (must not run; the marker file stays absent).
  - Through the hub relay: `/p/B/` with A's credentials, `/p/%2e%2e/`, `/p/A%2fB/`,
    double-encoded paths, a reserved name (`broker/config.py` `RESERVED_PROJECT_NAMES`),
    mixed case, a trailing dot or slash, a WebSocket upgrade to another project, a header that
    claims a different project or identity (`X-Forwarded-*`, `Host`).
  - Migration (§9): a session export from the shared container whose JSON carries hostile
    ids, titles and paths (it must land only in its own project's store, or be refused).
- Every refusal asserts the **error shape** the component documents (cite it), not just
  "failed", and every case asserts the side effect is absent (marker files, recorded argv).
- Tests create their own temp dirs with explicit modes and set `HOME`, `XDG_CONFIG_HOME`,
  `XDG_DATA_HOME`, `XDG_STATE_HOME` themselves: the host runs umask 002 and exports
  `XDG_CONFIG_HOME`; the sandbox has neither. Never read or write the real home. Workers never
  run `git merge`/`git commit`/`git rebase`/`git stash`.
- A test that finds a real bug: the step's spec says the worker fixes it in the component under
  the narrowest change and names it in its report; the fix file joins that step's scope only if
  the design lists it. **Never loosen a test to make it pass.** Put the files a fix may touch in
  the scope of the step whose tests target them, and say so.
- No site values (host names, domains, addresses) anywhere: `hub/tests/test_anonymity.py`.

## What to write

1. `docs/specs/a2x-design.md`: the coverage table (threat → existing test → this slice), the
   two layers, the fake executables, each hostile case with expected outcome, the live
   script's probes and its never-change-state rule, and `## Owner questions` (pick an option
   and mark it; don't stop).
2. One spec per step, `docs/specs/a2x-<n>-<slug>.md`, from the template. 2–5 steps. Each under
   ~1500 lines and ~90 minutes.
3. `docs/specs/a2x-chain.json`:
   `{"name":"a2x","repo":"../..","base":"a2-steps-6-8","gate":"python3 tools/run_tests.py","retries":2,"steps":[…]}`.
   Every step of this slice guards a boundary: `"hard": true` on all of them. Every step gets
   `"scope"`: exactly the files its spec lists under "Files owned". Write each verify by hand,
   literally; `set -o pipefail` when it pipes.

## Rules

- Use real names from the code you read. Never invent an API or an error code.
- No secrets and nothing from `.env` in a spec.

## Out of scope

Any change outside `docs/specs/`. In the planned slice: new features, the cutover itself,
running anything against live containers, the picker UI (step 7).

## Acceptance (verify)

`python3 -c "import json,os;p=json.load(open('docs/specs/a2x-chain.json'));assert p['steps'];[open(s['spec']) for s in p['steps']];assert all(s.get('hard') for s in p['steps']);assert os.path.getsize('docs/specs/a2x-design.md')>3000;print('ok',len(p['steps']),'steps')" && git diff --name-only HEAD | grep -v '^docs/specs/' | (! grep .)`
