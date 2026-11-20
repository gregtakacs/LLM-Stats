# Bench verifies, one per slice, each pinned to the slice's exact base commit (sourced by run.sh).
# The scope guard compares against BASE (the merge-base with that commit), never a moving branch.
scope() { # REGEX — fail if any changed or untracked path is outside it
  printf 'if { git diff --name-only $(git merge-base HEAD %s); git ls-files --others --exclude-standard; } | sort -u | grep -vE %q; then echo OUT OF SCOPE; exit 1; fi' "$BASE" "$1"
}
verify_for() { # SLICE BASE -> the verify command on stdout
  local BASE=$2
  case $1 in
    {project}-a1-adddirs) printf '%s; %s' \
      'set -o pipefail; timeout 900 python3 tools/run_tests.py launcher.tests.test_install launcher.tests.test_audit_hook 2>&1 | grep -E "^FAIL|^run_tests:" | tail -5; [ ${PIPESTATUS[0]} -eq 0 ] || exit 1' \
      "$(scope '^(launcher/templates/admin-settings\.json|launcher/install\.sh|launcher/tests/test_install\.py|docs/specs/c1a1-design\.md)$')" ;;
    delegate-step-gate) printf '%s; %s' \
      'set -o pipefail; f=0; for t in tests/test_chain.sh tests/test_step_gate.sh tests/test_skill_frontmatter.sh; do [ -f "$t" ] || continue; bash "$t" > /tmp/b-$(basename $t).log 2>&1 || { echo "FAIL $t"; tail -5 /tmp/b-$(basename $t).log; f=1; }; done; [ -f tests/test_step_gate.sh ] || { echo "no tests/test_step_gate.sh"; f=1; }; [ $f -eq 0 ] || exit 1' \
      "$(scope '^(lib/chain\.py|tests/.*|claude/skills/delegate/(SKILL|design-template)\.md|docs/.*\.md)$')" ;;
    {project}-singles-scope) printf '%s; %s' \
      'set -o pipefail; timeout 900 python3 tools/run_tests.py hub.tests.test_wv_browser hub.tests.test_ui hub.tests.test_anonymity 2>&1 | grep -E "^FAIL|^run_tests:" | tail -6; [ ${PIPESTATUS[0]} -eq 0 ] || exit 1' \
      "$(scope '^hub/(static/views/work\.js|tests/test_wv_browser\.py)$')" ;;
    {orb-project}-integration-4-lead-i4-6-b3-fix) printf '%s; %s' \
      'set -o pipefail; export GOFLAGS=-buildvcs=false PATH=/usr/local/go/bin:$PATH; cd tools/{orb-tool} && go test -race -count=300 -run "^TestThePassParksForADemandAndResumesItsOwnQueue$" . 2>&1 | tail -3 && go test ./... 2>&1 | tail -4; [ ${PIPESTATUS[0]} -eq 0 ] || exit 1; cd ../..' \
      "$(scope '^(tools/{orb-tool}/.*|docs/bugs\.md)$')" ;;
    {project}-a2x-design) printf '%s; %s' \
      "python3 -c \"import json,os;p=json.load(open('docs/specs/a2x-chain.json'));assert p['steps'];[open(s['spec']) for s in p['steps']];assert all(s.get('hard') for s in p['steps']);assert os.path.getsize('docs/specs/a2x-design.md')>3000;print('ok',len(p['steps']),'steps')\"" \
      "$(scope '^docs/specs/')" ;;
    {project}-a2p-design) printf '%s; %s' \
      "python3 -c \"import json,os;p=json.load(open('docs/specs/a2p-chain.json'));assert p['steps'];[open(s['spec']) for s in p['steps']];assert os.path.getsize('docs/specs/a2p-design.md')>3000;print('ok',len(p['steps']),'steps')\"" \
      "$(scope '^docs/specs/')" ;;
  esac
}
