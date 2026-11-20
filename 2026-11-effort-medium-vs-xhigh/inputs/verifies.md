# {orb-project}-integration-4-lead-i4-6-b3-fix (base 4f872bb01e)
set -o pipefail; export GOFLAGS=-buildvcs=false PATH=/usr/local/go/bin:$PATH; cd tools/{orb-tool} && go test -race -count=300 -run "^TestThePassParksForADemandAndResumesItsOwnQueue$" . 2>&1 | tail -3 && go test ./... 2>&1 | tail -4; [ ${PIPESTATUS[0]} -eq 0 ] || exit 1; cd ../..; if { git diff --name-only $(git merge-base HEAD 4f872bb01e9d0dba9bca189f12f4c9962cb62df0); git ls-files --others --exclude-standard; } | sort -u | grep -vE \^\(tools/{orb-tool}/.\*\|docs/bugs\\.md\)\$; then echo OUT OF SCOPE; exit 1; fi

# {project}-a2x-design (base 4c607321a8)
python3 -c "import json,os;p=json.load(open('docs/specs/a2x-chain.json'));assert p['steps'];[open(s['spec']) for s in p['steps']];assert all(s.get('hard') for s in p['steps']);assert os.path.getsize('docs/specs/a2x-design.md')>3000;print('ok',len(p['steps']),'steps')"; if { git diff --name-only $(git merge-base HEAD 4c607321a81871b28ffedaaa73c004cd1d6e6669); git ls-files --others --exclude-standard; } | sort -u | grep -vE \^docs/specs/; then echo OUT OF SCOPE; exit 1; fi

# {project}-a2p-design (base 4c607321a8)
python3 -c "import json,os;p=json.load(open('docs/specs/a2p-chain.json'));assert p['steps'];[open(s['spec']) for s in p['steps']];assert os.path.getsize('docs/specs/a2p-design.md')>3000;print('ok',len(p['steps']),'steps')"; if { git diff --name-only $(git merge-base HEAD 4c607321a81871b28ffedaaa73c004cd1d6e6669); git ls-files --others --exclude-standard; } | sort -u | grep -vE \^docs/specs/; then echo OUT OF SCOPE; exit 1; fi

