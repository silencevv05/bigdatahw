# ДЗ 1. Кластер HDFS

Здесь собраны скрипты и настройки для HDFS на учебных серверах `team-39`. Я использовал Apache Hadoop 3.4.0, Ubuntu 24.04.5 и Java 11. Развёртывание идёт с edge-сервера по SSH. Службы запускаются через systemd от пользователя `hdfs`, а не от root.

В этом же репозитории лежит второе ДЗ с YARN. Его инструкция находится в [README-YARN.md](README-YARN.md). Результаты первого ДЗ записаны в [REPORT.md](REPORT.md).

## Как устроен кластер

| Сервер | Внутренний IP | Что работает |
| --- | --- | --- |
| `team-39-en` | `10.39.0.10` | Точка входа по SSH, запуск скриптов |
| `team-39-nn` | `10.39.0.11` | NameNode, SecondaryNameNode, DataNode |
| `team-39-00` | `10.39.0.12` | DataNode |
| `team-39-01` | `10.39.0.13` | DataNode |

В HDFS три DataNode. Каждая новая запись по умолчанию хранится в трёх копиях. Метаданные NameNode лежат в `/var/lib/hdfs/name`, блоки DataNode в `/var/lib/hdfs/data`. Hadoop установлен в `/opt/hadoop`, логи находятся в `/var/log/hdfs`.

SecondaryNameNode периодически создаёт контрольные точки метаданных. Он не заменяет NameNode при сбое.

## Что нужно до установки

Нужны доступ к `team@111.88.131.73`, SSH-ключ `~/.ssh/team_internal` на edge и возможность выполнить `sudo` на внутренних машинах без ввода пароля. Также нужен интернет для загрузки Java и официального архива Hadoop.

**Важно:** `scripts/deploy.sh` предназначен для первоначальной установки на пустом учебном стенде. Если HDFS уже работает, повторно разворачивать его ради проверки не надо. Запускайте `scripts/check.sh`.

## Установка HDFS с нуля

С Windows можно передать каталог проекта и зайти на edge:

```powershell
scp -r .\hdfs-team39 team@111.88.131.73:~/
ssh team@111.88.131.73
```

На edge:

```bash
cd ~/hdfs-team39
bash scripts/deploy.sh
bash scripts/check.sh
```

Скрипт скачивает Hadoop 3.4.0, проверяет SHA-512 архива, настраивает внутренние машины и systemd. На каждой машине создаётся отдельный пользователь `hdfs`. Для SSH используется пользователь `team`, поэтому пользователю `hdfs` ключи не нужны.

Перед запуском служб скрипт приводит имя каждой машины в `/etc/hosts` к её внутреннему IP. На тестовых VM это важно: первоначально некоторые имена разрешались в `127.0.1.1`, и другие узлы не могли подключиться к Hadoop. Старый файл сохраняется как `/etc/hosts.team39.backup`.

NameNode форматируется только при первом запуске, если каталог метаданных пуст. При обнаружении существующих или непонятных метаданных скрипт не должен продолжать форматирование. **Не запускайте вручную `hdfs namenode -format` на рабочем кластере.**

## Проверка работы

```bash
cd ~/hdfs-team39
bash scripts/check.sh
```

Проверка смотрит состояние служб и число DataNode, загружает тестовый файл, читает его обратно, ждёт три реплики и запускает `hdfs fsck`. На нашем стенде она завершилась сообщением:

```text
PASS: 3 DataNodes healthy, read/write OK, replication=3, fsck HEALTHY.
```

После исправления адресов повторно проверили регистрацию всех узлов:

```text
Live datanodes (3):
Name: 10.39.0.11:9866 (team-39-nn.hse.c.mws)
Name: 10.39.0.12:9866 (team-39-00)
Name: 10.39.0.13:9866 (team-39-01)
```

Это разные проверки: `fsck HEALTHY` был получен при первоначальной проверке HDFS, а список с правильными IP уже после исправления `/etc/hosts`.

## Веб-интерфейс на localhost

Из отдельного окна PowerShell на своём компьютере:

```powershell
ssh -N -L 9870:10.39.0.11:9870 team@111.88.131.73
```

Откройте `http://localhost:9870/dfshealth.html`. В разделе **Datanodes** видны три подключённых узла. Окно с SSH нужно оставить открытым, пока смотришь интерфейс.

## Где искать ошибки

Все команды ниже выполняются на edge:

```bash
ssh -i ~/.ssh/team_internal team@team-39-nn 'sudo systemctl status hdfs-namenode hdfs-secondary hdfs-datanode --no-pager'
ssh -i ~/.ssh/team_internal team@team-39-00 'sudo journalctl -u hdfs-datanode -n 80 --no-pager'
ssh -i ~/.ssh/team_internal team@team-39-nn 'sudo -u hdfs /opt/hadoop/bin/hdfs dfsadmin -report'
```

Службы запускаются автоматически после перезагрузки. Данные HDFS при обычном рестарте не стираются.

## Файлы проекта

- `scripts/deploy.sh` и `scripts/remote-setup.sh`: установка HDFS на внутренние узлы.
- `scripts/check.sh`: проверка чтения, записи и репликации.
- `scripts/fix-hostnames-node.py`: исправление локального разрешения имени машины.
- `configs/`: настройки Hadoop и список узлов.
- `systemd/hdfs-*.service`: службы NameNode, SecondaryNameNode и DataNode.
- `REPORT.md`: что получилось и какие проблемы пришлось исправить.

Стенд учебный, без Kerberos и резервного NameNode в режиме HA. Порты Hadoop не стоит открывать в интернет. Не загружайте в GitHub SSH-ключи, содержимое `/var/lib/hdfs`, логи и архив дистрибутива Hadoop.

Документация Hadoop: <https://hadoop.apache.org/docs/r3.4.0/>.
