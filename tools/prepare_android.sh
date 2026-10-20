#!/usr/bin/env bash
# Gera a pasta android/ a partir do template oficial do Flutter instalado
# e aplica as configurações do X-METER (permissões, rede local, nome e ícone).
# Usado pelo GitHub Actions; também funciona em qualquer PC com Flutter.
set -euo pipefail
cd "$(dirname "$0")/.."
if [ ! -f android/app/src/main/AndroidManifest.xml ]; then
  flutter create --org br.com.unitech --project-name unitech_xmeter_connect \
    --platforms=android --no-pub .
fi
python3 tools/patch_android.py
