# ДЗ 2. YARN и веб-интерфейсы Hadoop

Во втором ДЗ я добавил YARN к HDFS из первой работы. На двух серверах работают NodeManager, на edge находится ResourceManager и сервер истории MapReduce. Через SSH можно открыть веб-интерфейсы на `localhost` своего компьютера.

## Что где работает

| Сервер | IP | Служба | Веб-порт |
| --- | --- | --- | --- |
| `team-39-en` | `10.39.0.10` | ResourceManager | 8088 |
| `team-39-en` | `10.39.0.10` | MapReduce JobHistory Server | 19888 |
| `team-39-00` | `10.39.0.12` | NodeManager | 8042 |
| `team-39-01` | `10.39.0.13` | NodeManager | 8042 |
| `team-39-nn` | `10.39.0.11` | NameNode | 9870 |
| `team-39-nn` | `10.39.0.11` | SecondaryNameNode | 9868 |
| `team-39-nn`, `00`, `01` | `10.39.0.11`, `.12`, `.13` | DataNode | 9864 |

У каждого NodeManager выделено 1536 МБ памяти и два виртуальных ядра. Для MapReduce уменьшил размер контейнеров до 512 МБ. Так задачи помещаются на небольших учебных VM.

## Развёртывание на новом стенде

В этой инструкции предполагается, что HDFS уже установлен по [README.md](README.md) и проходит `bash scripts/check.sh`. С edge нужен SSH-доступ к внутренним узлам через `~/.ssh/team_internal`.

Подключись к edge:

```powershell
ssh team@111.88.131.73
```

Перейди в каталог проекта и подготовь сам edge. Скрипт проверит Hadoop 3.4.0 и Java 11, при необходимости установит их, создаст пользователей `yarn` и `mapred` и исправит локальное разрешение имени `team-39-en`.

```bash
cd ~/hdfs-team39
bash scripts/prepare-edge.sh
```

Затем установи YARN:

```bash
bash scripts/deploy-yarn.sh
bash scripts/check-yarn.sh
```

`deploy-yarn.sh` копирует настройки на edge и оба NodeManager, включает службы systemd и проверяет, что существующий HDFS жив. Он не форматирует NameNode и не перезапускает DataNode. Проверка должна показать два NodeManager в состоянии `RUNNING`.

Следующий шаг, JobHistory Server:

```bash
bash scripts/deploy-history.sh
bash scripts/check-history.sh
```

Скрипт создаст служебные каталоги `/mr-history` в HDFS, обновит `mapred-site.xml` и запустит JobHistory. Для работы он использует порты `10020` и `19888` на edge.

**Если кластер уже настроен, как на нашем стенде, повторно выполнять установку не нужно.** Для проверки достаточно команд из следующего раздела.

## Как проверить всё вместе

На edge:

```bash
cd ~/hdfs-team39
bash scripts/check-all.sh
```

Команда проверяет HDFS, ResourceManager, оба NodeManager, JobHistory и доступность девяти веб-интерфейсов во внутренней сети.

Для дополнительной проверки можно запустить новый WordCount:

```bash
bash scripts/check-all.sh --mapreduce
```

Этот вариант создаёт небольшой входной файл в HDFS, запускает MapReduce через YARN и сравнивает результат с ожидаемым. Каждый запуск использует новый каталог, поэтому предыдущие результаты не перезаписываются. Проверка WordCount может занимать некоторое время.

## Как открыть интерфейсы через localhost

Открой отдельный PowerShell на Windows и выполни одну команду:

```powershell
ssh -N `
  -L 18088:10.39.0.10:8088 `
  -L 19888:10.39.0.10:19888 `
  -L 19870:10.39.0.11:9870 `
  -L 19868:10.39.0.11:9868 `
  -L 19864:10.39.0.11:9864 `
  -L 19865:10.39.0.12:9864 `
  -L 19866:10.39.0.13:9864 `
  -L 18042:10.39.0.12:8042 `
  -L 18043:10.39.0.13:8042 `
  team@111.88.131.73
```

Пока эта SSH-сессия открыта, доступны локальные адреса:

| Интерфейс | Адрес на своём компьютере |
| --- | --- |
| ResourceManager | <http://localhost:18088/cluster> |
| JobHistory | <http://localhost:19888/jobhistory> |
| NameNode | <http://localhost:19870/dfshealth.html> |
| SecondaryNameNode | <http://localhost:19868/> |
| DataNode на NameNode | <http://localhost:19864/> |
| DataNode 00 | <http://localhost:19865/> |
| DataNode 01 | <http://localhost:19866/> |
| NodeManager 00 | <http://localhost:18042/node> |
| NodeManager 01 | <http://localhost:18043/node> |

На некоторых страницах Hadoop есть ссылки с внутренними IP или именами серверов. Они могут не открываться из обычного браузера вне сети, хотя главная страница доступна через туннель. Для проверки самого сервиса достаточно открыть соответствующий локальный URL. Если порт на ноутбуке занят, замени только число слева от двоеточия в `-L`.

## Что получилось у нас

Проверка `check-yarn.sh` показала два узла:

```text
team-39-01:40841: state=RUNNING, memoryMB=1536
team-39-00:34475: state=RUNNING, memoryMB=1536
PASS: ResourceManager + 2 RUNNING NodeManagers
```

`check-history.sh` ответил `PASS`. Затем мы запустили WordCount, и YARN завершил его со статусом `FINISHED / SUCCEEDED`, прогресс `100%`. Слова посчитаны верно:

```text
hadoop     3
hdfs       2
mapreduce  1
yarn       3
```

Одна из первых попыток Map-задачи завершилась ошибкой. YARN повторил её, и само задание завершилось успешно. Это видно в [REPORT-YARN.md](REPORT-YARN.md). Причина первой ошибки отдельно не исследовалась.

Из edge проверили девять веб-интерфейсов. Все ответили на HTTP-запросы. Подробные результаты также есть в отчёте.

## Если что-то не работает

```bash
sudo systemctl status yarn-resourcemanager mapreduce-historyserver --no-pager
sudo journalctl -u mapreduce-historyserver -n 80 --no-pager
ssh -i ~/.ssh/team_internal team@team-39-00 'sudo journalctl -u yarn-nodemanager -n 80 --no-pager'
/opt/hadoop/bin/yarn application -list -appStates ALL
```

У YARN нет Kerberos, поэтому это учебная настройка, а не готовый публичный сервис. Не открывай порты Hadoop напрямую в интернет и не загружай SSH-ключи в GitHub.

Дополнительные сведения о JobHistory Server есть в [README-HISTORY.md](README-HISTORY.md).
