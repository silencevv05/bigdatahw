# ДЗ 3. Apache Hive

В третьем ДЗ к готовому кластеру HDFS и YARN добавлен Apache Hive 4.0.0-alpha-2.
HiveServer2 принимает JDBC-подключения нескольких клиентов. Metastore работает отдельным сервисом и хранит метаданные в PostgreSQL 16, а данные таблиц — в HDFS. Embedded Derby не используется.

## Что где работает

| Сервер | Служба | Порт |
| --- | --- | --- |
| `team-39-en` (`10.39.0.10`) | HiveServer2 | 10000 |
| `team-39-en` (`10.39.0.10`) | Metastore | 9083 |
| `team-39-en` | PostgreSQL | 5432, только localhost |

## Установка

Скрипты запускаются на `team-39-en` от пользователя `team` с `sudo` без пароля. HDFS и YARN должны быть уже установлены в `/opt/hadoop` и запущены по [инструкции второго ДЗ](../hdfs-team39/README-YARN.md). Для подключения к внутренним узлам используется ключ `~/.ssh/team_internal`.

Если каталога проекта ещё нет, сначала скачать репозиторий:

```bash
git clone --branch hw_3 https://github.com/silencevv05/bigdatahw.git ~/bigdatahw
```

```bash
cd ~/bigdatahw/hive-team39
bash scripts/deploy.sh
```

Скрипт скачивает Hive и Java 8, проверяет контрольные суммы, устанавливает PostgreSQL и JDBC-драйвер. Затем создаёт пользователя и базу `hive_team39`, инициализирует схему через `schematool`, подготавливает каталоги HDFS и запускает Metastore и HiveServer2 через systemd. В конце проверяется подключение с запросом `SELECT 1`.

Java 8 используется для Hive и задач MapReduce; Hadoop-демоны работают на Java 11. Адреса узлов заданы в `config/hosts.tsv`, версии и ссылки на дистрибутивы — в `config/versions.env`. Установщик также исправляет разрешение имён узлов и добавляет разрешение на служебный вызов `hive → hive` в Hadoop. Перед изменениями сохраняются копии `/etc/hosts` и `core-site.xml`.

Повторный запуск установки сохраняет базу и данные. Пароль PostgreSQL создаётся на сервере, в репозиторий он не записывается.

## Загрузка данных

В `data/orders.tsv` лежит пример из 12 заказов. Формат файла — UTF-8, поля разделены табуляцией, строка заголовка отсутствует. Порядок полей: `order_id`, `customer_id`, `amount`, `order_date`, `country`. Сумма указывается с двумя знаками после точки, дата — в формате `YYYY-MM-DD`, страна — двумя заглавными латинскими буквами.

```bash
bash scripts/load-data.sh
# Для своего файла:
bash scripts/load-data.sh /path/to/orders.tsv
```

Загрузчик проверяет входной файл и копирует его в staging-каталог HDFS. Затем SQL из `sql/schema.sql` и `sql/load.sql` создаёт таблицы и выполняет `INSERT OVERWRITE` в `dz3_team39.orders`. Данные сохраняются в ORC с партициями по `order_date` и `country`. Запись выполняется через MapReduce в YARN. После загрузки для каждой партиции сверяются число строк и сумма заказов.

Каждый файл должен содержать полный набор строк для затронутых партиций. При повторной загрузке эти партиции заменяются, поэтому дубликаты не накапливаются. Остальные партиции сохраняются.

## Проверка

```bash
source scripts/common.sh
beeline_run -f sql/inspect.sql
```

Для приложенного файла должно получиться 6 партиций, 12 строк и сумма `3997.00`. Повторный запуск `bash scripts/load-data.sh` даёт тот же результат.

Для проверки нескольких клиентов открыть два терминала на edge и выполнить в каждом:

```bash
cd ~/bigdatahw/hive-team39
source scripts/common.sh
beeline_run -e 'SELECT count(*), sum(amount) FROM dz3_team39.orders;'
```

Оба клиента должны получить `12` и `3997.00`. На стенде проверены одновременные запросы, повторная загрузка и сохранение таблицы после перезапуска сервисов.

## Подключение и сервисы

JDBC-адрес: `jdbc:hive2://10.39.0.10:10000/default`. Metastore слушает порт `9083`, PostgreSQL — `127.0.0.1:5432`. Конфигурация находится в `/etc/hive-team39/`, данные — в `/warehouse/team39/external/orders` в HDFS.

На учебном стенде используется `hive.server2.enable.doAs=false`: запросы выполняются от сервисного пользователя `hive`. Hive доступен по внутренней сети, вход на edge — по SSH.

```bash
systemctl status hive-team39-metastore hive-team39-server postgresql --no-pager
sudo journalctl -u hive-team39-server -n 50 --no-pager
```

Для сдачи нужна ссылка на этот публичный репозиторий. Инструкция находится в README, скрипты установки и загрузки — в `scripts/`, SQL — в `sql/`, файлы сервисов — в `systemd/`.
