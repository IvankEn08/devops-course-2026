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
