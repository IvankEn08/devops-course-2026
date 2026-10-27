#!/usr/bin/env bash
# Доставка статического ресурса на devops-vm
# Использование: scripts/deploy.sh [--dry-run]
set -euo pipefail

REMOTE="devops"                     # псевдоним из ~/.ssh/config (ПР № 5, шаг 1.6)
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://devops.local"
CA_CERT="${HOME}/devops.crt"
REPO_DIR="$(git rev-parse --show-toplevel)"
LOCAL_DIR="${REPO_DIR}/site/"
cd "${REPO_DIR}"                    # работа одинакова из любого каталога репозитория

# 1. Разбор аргумента --dry-run
DRY_RUN=0
case "${1:-}" in
    "")        ;;
    --dry-run) DRY_RUN=1 ;;
    *)         echo "Использование: $0 [--dry-run]" >&2; exit 1 ;;
esac

# 2. Проверки по требованиям 4 и 5
if [[ ! -f "${LOCAL_DIR}index.html" ]]; then
    echo "Ошибка: файл ${LOCAL_DIR}index.html отсутствует, доставка отменена" >&2
    exit 1
fi
if [[ -n "$(git -C "${REPO_DIR}" status --porcelain)" ]]; then
    echo "Ошибка: в репозитории есть незафиксированные изменения, доставка отменена" >&2
    exit 1
fi

# 3. Синхронизация каталога ${LOCAL_DIR} на ${REMOTE}:${REMOTE_DIR}
RSYNC_OPTS=(-avz --delete --chmod=D755,F644 -e "ssh -o BatchMode=yes -o ConnectTimeout=5")
if [[ ${DRY_RUN} -eq 1 ]]; then
    RSYNC_OPTS+=(--dry-run)
fi
# источник задан относительным путём: путь вида C:/... в Git Bash принимается rsync за адрес удалённого узла
rsync "${RSYNC_OPTS[@]}" "site/" "${REMOTE}:${REMOTE_DIR}/"

# 4. При --dry-run — завершение с кодом 0 без проверки доступности
if [[ ${DRY_RUN} -eq 1 ]]; then
    echo "Пробный запуск: состояние сервера не изменено"
    exit 0
fi

# 5. Проверка доступности ${SITE_URL} и завершение с корректным кодом возврата
if ! curl -fsS --cacert "${CA_CERT}" -o /dev/null "${SITE_URL}/"; then
    echo "Ошибка: ресурс ${SITE_URL} недоступен после доставки" >&2
    exit 1
fi
echo "Доставка выполнена, коммит $(git -C "${REPO_DIR}" rev-parse --short HEAD)"
