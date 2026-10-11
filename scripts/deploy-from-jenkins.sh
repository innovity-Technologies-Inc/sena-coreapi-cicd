#!/bin/sh
# Credentials arrive through Jenkins bindings, never command-line extra vars.
set -eu
set +x

case "${DEPLOY_ENV:-}" in
    staging|production) ;;
    *) echo 'DEPLOY_ENV must be staging or production' >&2; exit 2 ;;
esac
: "${IMAGE_TAG:?IMAGE_TAG is required}"
: "${IMAGE_URL:?IMAGE_URL is required}"
: "${IMAGE_REPO:?IMAGE_REPO is required}"

sena_deployment_vars=$(python3 - <<'PY'
import json
import os
import re

if not re.fullmatch(r'[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}', os.environ['IMAGE_TAG']):
    raise SystemExit('IMAGE_TAG is invalid')
if os.environ['IMAGE_TAG'] == 'latest':
    raise SystemExit('Deploy an immutable build tag, not latest')
print(json.dumps({
    'image_tag': os.environ['IMAGE_TAG'],
    'app_image_registry': os.environ['IMAGE_URL'] + '/' + os.environ['IMAGE_REPO'],
    'app_harbor_registry': os.environ['IMAGE_URL'],
}))
PY
)

exec ansible-playbook -i "ansible/inventory/$DEPLOY_ENV.ini" ansible/deploy-app.yml \
    --extra-vars "$sena_deployment_vars"
