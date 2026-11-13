#!/bin/sh
# Builds the Secret Message image on drop from this repo's committed code and restarts the
# Portainer stack "secretmessage" with it. Run from your Mac (SSH to drop over Tailscale as the
# hubble user, and 1Password CLI for the Portainer login):
#   deploy/build-on-drop.sh
# The build runs the Go tests. The restart goes through Portainer's own API, reached on its
# internal HTTP port through an SSH tunnel, so the stack keeps its file and environment
# variables. The database lives in the volume and survives. If the stack does not exist yet,
# the script only builds the image; create the stack in Portainer from deploy/compose.yml.
set -eu
cd "$(dirname "$0")/.."
test -z "$(git status --porcelain main.go pkg go.mod go.sum Dockerfile)" || { echo "Commit dine ændringer først"; exit 1; }
rev=$(git rev-parse --short HEAD)
git archive --format=tar HEAD main.go pkg go.mod go.sum Dockerfile \
  | ssh hubble@drop "set -e; rm -rf ~/docker/secretmessage/src && mkdir -p ~/docker/secretmessage/src && tar -x -C ~/docker/secretmessage/src && docker build -q -t secretmessage:latest -t secretmessage:$rev ~/docker/secretmessage/src >/dev/null"
echo "Bygget secretmessage:$rev på drop."

# Portainer login: 1Password item "drop [Docker] - Portainer" (vault hubble)
ip=$(ssh hubble@drop 'docker inspect portainer --format "{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}"' | cut -d' ' -f1)
ssh -f -N -o ExitOnForwardFailure=yes -L 19000:"$ip":9000 hubble@drop
trap 'pkill -f "19000:$ip:9000" || true' EXIT
python3 -c "
import json,subprocess
g=lambda r: subprocess.run(['op','read',r,'--account','wearehubble.1password.com'],capture_output=True,text=True,check=True).stdout.strip()
print(json.dumps({'u':g('op://hubble/74gtvkuqyt4hmayk34freg5mjm/username'),'p':g('op://hubble/74gtvkuqyt4hmayk34freg5mjm/password')}))" | python3 -c "
import json, sys, urllib.request
B = 'http://127.0.0.1:19000/api'
cfg = json.load(sys.stdin)
def call(method, path, body=None, tok=None):
    req = urllib.request.Request(B + path, method=method, data=json.dumps(body).encode() if body is not None else None,
        headers={'Content-Type': 'application/json', **({'Authorization': f'Bearer {tok}'} if tok else {})})
    with urllib.request.urlopen(req, timeout=120) as r: return json.loads(r.read() or b'null')
jwt = call('POST', '/auth', {'username': cfg['u'], 'password': cfg['p']})['jwt']
st = next((s for s in call('GET', '/stacks', tok=jwt) if s['Name'] == 'secretmessage'), None)
if st is None:
    print('Stacken secretmessage findes ikke endnu; opret den i Portainer fra deploy/compose.yml.')
    sys.exit(0)
f = call('GET', f\"/stacks/{st['Id']}/file\", tok=jwt)['StackFileContent']
call('PUT', f\"/stacks/{st['Id']}?endpointId={st['EndpointId']}\", {'stackFileContent': f, 'env': st['Env'], 'prune': False, 'pullImage': False}, tok=jwt)
print('Stacken secretmessage er genstartet.')
"
echo "Færdig med secretmessage:$rev."
