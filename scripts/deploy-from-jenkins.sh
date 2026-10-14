#!/bin/sh
# Jenkins supplies Harbor credentials and the selected Vault password file.
set -eu
set +x

case "${DEPLOY_ENV:-}" in
    staging|production) ;;
    *) echo 'DEPLOY_ENV must be staging or production' >&2; exit 2 ;;
esac
: "${IMAGE_TAG:?IMAGE_TAG is required}"
: "${IMAGE_URL:?IMAGE_URL is required}"
: "${IMAGE_REPO:?IMAGE_REPO is required}"
: "${SENA_VAULT_PASSWORD_FILE:?SENA_VAULT_PASSWORD_FILE is required}"

sena_deployment_vars=$(python3 - <<'PY'
import json
import os
import re
from pathlib import Path

if not re.fullmatch(r'[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}', os.environ['IMAGE_TAG']):
    raise SystemExit('IMAGE_TAG is invalid')
if os.environ['IMAGE_TAG'] == 'latest':
    raise SystemExit('Deploy an immutable build tag, not latest')
password_file = Path(os.environ['SENA_VAULT_PASSWORD_FILE'])
if not password_file.is_file() or not os.access(password_file, os.R_OK) or password_file.stat().st_size == 0:
    raise SystemExit('The Jenkins Vault password file must be readable and nonempty')
environment = os.environ['DEPLOY_ENV']
vault_file = Path('ansible/group_vars') / environment / 'vault.yml'
if not vault_file.is_file():
    raise SystemExit('Create an encrypted vault.yml for the selected environment before deploying')
with vault_file.open('rb') as encrypted:
    header = encrypted.readline(128).strip()
if header != ('$ANSIBLE_VAULT;1.2;AES256;' + environment).encode():
    raise SystemExit('vault.yml must be fully encrypted with the selected environment Vault ID')
print(json.dumps({
    'image_tag': os.environ['IMAGE_TAG'],
    'app_image_registry': os.environ['IMAGE_URL'] + '/' + os.environ['IMAGE_REPO'],
    'app_harbor_registry': os.environ['IMAGE_URL'],
}))
PY
)

exec ansible-playbook -i "ansible/inventory/$DEPLOY_ENV.ini" ansible/deploy-app.yml \
    --vault-id "$DEPLOY_ENV@$SENA_VAULT_PASSWORD_FILE" \
    --extra-vars "$sena_deployment_vars"
