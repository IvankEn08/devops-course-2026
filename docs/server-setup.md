# Конфигурация виртуальной машины devops-vm

## 1. Параметры машины
- Гипервизор: VirtualBox 7.2.22, ОС: Ubuntu Server 24.04.5 LTS (64-bit), имя узла `devops-vm` (FQDN `devops-vm.devops.local`)
- Оперативная память: 2048 МБ
- Процессор: 2 ядра
- Диск: 25 ГБ, динамически расширяемый (VDI)

## 2. Сетевые интерфейсы
| Адаптер | Тип | Интерфейс | Адрес | Назначение |
|---|---|---|---|---|
| 1 | NAT | enp0s3 | 10.0.2.15/24 | доступ в Интернет (репозитории пакетов), проброс SSH |
| 2 | Host-only | enp0s8 | 192.168.56.101/24 (DHCP VirtualBox, диапазон .101–.254) | доступ с хостовой системы (SSH, веб-сервер) |

## 3. Правило проброса портов
Адаптер 1, правило `ssh`, TCP: адрес хоста 127.0.0.1, порт хоста 2222 -> порт гостя 2222 (адрес гостя не заполняется).
Первоначально порт гостя был 22, после перевода sshd на порт 2222 изменён на 2222.

## 4. Учётные записи
| Имя | Группы | Способ аутентификации |
|---|---|---|
| student | student, sudo, users | пароль (только консоль ВМ, по SSH вход запрещён директивой AllowUsers) |
| devops | devops, sudo, users | SSH-ключ ed25519 (`~/.ssh/devops_vm` на хосте, открытый ключ в `~/.ssh/authorized_keys`), пароль нужен только для sudo |

Права: `~/.ssh` — 700, `authorized_keys` — 600. На хосте ключ создан командой `ssh-keygen -t ed25519 -C "devops-vm-key" -f ~/.ssh/devops_vm`, в `~/.ssh/config` описан хост `devops` (127.0.0.1:2222, IdentitiesOnly yes) и `devops.local`.

## 5. Служба SSH
- Основной файл `/etc/ssh/sshd_config` не изменялся, копия: `/etc/ssh/sshd_config.backup`
- Дополняющий файл: `/etc/ssh/sshd_config.d/99-hardening.conf`:
  `Port 2222`, `PermitRootLogin no`, `PasswordAuthentication no`, `PubkeyAuthentication yes`, `PermitEmptyPasswords no`, `MaxAuthTries 3`, `LoginGraceTime 30`, `AllowUsers devops`, `X11Forwarding no`, `ClientAliveInterval 300`, `ClientAliveCountMax 2`
- Активация по сокету отключена: `sudo systemctl disable --now ssh.socket`, `sudo systemctl enable --now ssh.service`, затем `sudo systemctl restart ssh`
- Проверка: `sudo sshd -t`, `sudo sshd -T`, `sudo ss -tlnp | grep sshd` (0.0.0.0:2222)

## 6. Правила межсетевого экрана
Политики: `default deny incoming`, `default allow outgoing`. Журнал: `ufw logging medium` (`/var/log/ufw.log`).
```
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 80/tcp  comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
sudo ufw limit 2222/tcp comment 'SSH rate-limited'
sudo ufw enable
```
Порядок существенен: разрешающее правило для 2222 создаётся до `ufw enable`; при замене allow на limit добавлять limit нужно ДО удаления allow (иначе доступ по SSH теряется).
Имя узла: `sudo hostnamectl set-hostname devops-vm`, в `/etc/hosts`: `127.0.1.1 devops-vm.devops.local devops-vm`. На хосте в hosts: `192.168.56.101 devops.local`.

## 7. Снимки состояния
| Наименование | Состояние |
|---|---|
| 01-clean-install | чистая установка Ubuntu Server, обновления применены, установлен openssh-server, ВМ выключена |
| 02-keys-configured | создан пользователь devops, настроена ключевая аутентификация, `~/.ssh/config` на хосте |
| 03-ssh-hardened | усилена защита sshd (порт 2222), правило проброса приведено к 2222 |
| 04-nginx-https | установлен Nginx, ресурс devops.local опубликован по HTTPS, HTTP перенаправляется на HTTPS |
| 05-docker-compose | установлен Docker Engine, проект ~/app (приложение + PostgreSQL) запущен через Docker Compose |

## 8. Веб-сервер
- Пакет: `nginx` (1.24.0, Ubuntu 24.04), установка `sudo apt update && sudo apt install -y nginx`; главный процесс от root, рабочие — от www-data. Правила UFW для 80 и 443 уже существуют (профиль `Nginx Full` не применяется).
- Конфигурация ресурса: `/etc/nginx/sites-available/devops-site`, активирована ссылкой `/etc/nginx/sites-enabled/devops-site`; стандартный ресурс отключён (`sudo rm /etc/nginx/sites-enabled/default`, файл `default` в sites-available сохранён). Два блока server: порт 80 (`server_name devops.local`, `return 301 https://$host$request_uri;`) и порт 443 (`listen 443 ssl; listen [::]:443 ssl;`, `ssl_certificate /etc/ssl/certs/devops.crt;`, `ssl_certificate_key /etc/ssl/private/devops.key;`, `ssl_protocols TLSv1.2 TLSv1.3;`, `root /var/www/devops-site;`, `index index.html;`, `location / { try_files $uri $uri/ =404; }`, `error_page 404 /404.html;`, журналы `/var/log/nginx/devops-site.access.log` и `devops-site.error.log`). HSTS не добавляется.
- Каталог ресурса: `/var/www/devops-site`, владелец `devops:devops`, каталог 755, файлы 644; содержимое доставляется с хоста `scripts/deploy.sh` (`rsync -avz --delete --chmod=D755,F644 site/ devops:/var/www/devops-site/`); создание: `sudo mkdir -p /var/www/devops-site && sudo chown -R devops:devops /var/www/devops-site`.
- Сертификат: `/etc/ssl/certs/devops.crt` (права 644, владелец root, самоподписанный, CN=devops.local, SAN `DNS:devops.local`, срок 365 дней); закрытый ключ `/etc/ssl/private/devops.key` (права 600, владелец root, за пределы каталога не копируется, в репозиторий не добавляется).
- Команда формирования: `sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/devops.key -out /etc/ssl/certs/devops.crt -subj "/CN=devops.local" -addext "subjectAltName=DNS:devops.local"`. Сертификат копируется на хост командой `scp devops:/etc/ssl/certs/devops.crt ~/devops.crt` и указывается клиенту через `curl --cacert`.
- Применение конфигурации: только `sudo nginx -t && sudo systemctl reload nginx` (не `restart`).

## 9. Контейнеризация
- Docker Engine установлен из официального репозитория download.docker.com (не пакет docker.io): пакеты `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, `docker-compose-plugin`; версия Docker Engine 29.9.2, Docker Compose v5.6.1. Репозиторий: `/etc/apt/sources.list.d/docker.list`, ключ `/etc/apt/keyrings/docker.asc`. Служба `docker` включена и запускается автоматически.
- Группа `docker`: участник — `devops` (команда `sudo usermod -aG docker devops`, после неё нужна новая SSH-сессия); участник группы фактически имеет права root, поэтому в группу включаются только учётные записи с правом sudo.
- Проект на сервере: `/home/devops/app` (доставляется с хоста `rsync -avz --delete --exclude=.env app/ devops:app/`); файлы: `Dockerfile`, `.dockerignore`, `app.py`, `requirements.txt`, `docker-compose.yml`, `.env.example`; имя проекта Compose — `app` (контейнеры `app-app-1` и `app-db-1`).
- Файл `.env`: `/home/devops/app/.env`, права 600, владелец devops, формируется только на сервере (`cp .env.example .env`, пароль PostgreSQL — `openssl rand -hex 16`), в репозиторий и образ не попадает (`.gitignore`, `.dockerignore`, `--exclude=.env` при rsync).
- Образы: `devops-app:1.0` (сборка из `Dockerfile` на основе `python:3.12-slim`, процесс от пользователя `app`, CMD в exec-форме) и `postgres:16-alpine` (тег фиксирует основную версию).
- Публикуемые порты и адреса: приложение — только `127.0.0.1:5000` (`"127.0.0.1:5000:5000"`); порт PostgreSQL 5432 не публикуется, приложение обращается к СУБД по имени сервиса `db` внутри пользовательской сети `backend` (`app_backend`). Порт, опубликованный на `0.0.0.0`, доступен из сети в обход UFW (Docker добавляет правила iptables в цепочку DOCKER).
- Именованные тома: `app_db_data` (каталог данных PostgreSQL `/var/lib/postgresql/data`); `docker compose down` том сохраняет, `docker compose down -v` удаляет вместе с данными.
- Обратный прокси-сервер: в блок HTTPS `/etc/nginx/sites-available/devops-site` добавлено `location /app/ { proxy_pass http://127.0.0.1:5000/; proxy_set_header Host $host; proxy_set_header X-Real-IP $remote_addr; proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for; proxy_set_header X-Forwarded-Proto $scheme; }`; статический ресурс `location /` сохранён. Применение: `sudo nginx -t && sudo systemctl reload nginx`. При остановленном приложении Nginx возвращает 502 (`connect() failed (111: Connection refused) while connecting to upstream` в `/var/log/nginx/devops-site.error.log`).
- Запуск и остановка проекта: `cd ~/app && docker compose up -d --build`, `docker compose ps`, `docker compose down`; перезапуск при перезагрузке сервера обеспечивает `restart: unless-stopped`.
