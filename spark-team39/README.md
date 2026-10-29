# ДЗ 4. Apache Spark

Spark 3.5.7 запускается в YARN на кластере из предыдущих заданий. Приложение читает заказы из HDFS, считает показатели по дате и стране и сохраняет результат как таблицу `dz4_team39.daily_orders`. Таблица доступна через HiveServer2 и Beeline из ДЗ3.

## Запуск

Команды выполняются на `team-39-en` от `team` с `sudo` без пароля. Нужны работающие [HDFS и YARN](../hdfs-team39/README-YARN.md), а также [Hive из ДЗ3](../hive-team39/README.md). Ключ для внутренних узлов — `~/.ssh/team_internal`.

Для нового каталога:

```bash
git clone --branch hw_4 https://github.com/silencevv05/bigdatahw.git ~/bigdatahw-dz4
cd ~/bigdatahw-dz4/spark-team39
bash scripts/deploy.sh
bash scripts/run.sh
```

Установщик скачивает официальный дистрибутив, проверяет SHA-512, устанавливает Spark в `/opt/spark-team39` и размещает архив библиотек в HDFS для контейнеров YARN. Конфигурация находится в `/etc/spark-team39`. Установка не требует перезапуска Hadoop. Повторный запуск сохраняет данные предыдущих ДЗ.

Драйвер работает на edge в режиме `client`, два executor — в YARN, по одному ядру и 512 МБ памяти каждый. Используется Java 11. Конфигурация Spark хранится в `config/spark-defaults.conf`, версия и контрольная сумма — в `config/versions.env`.

Для аналогичного стенда с другими адресами изменить `config/cluster.env`: короткое имя и внутренний IP edge, имя и URI NameNode, URI Metastore и JDBC. Затем выполнить те же команды установки и запуска. HDFS, YARN и Hive предыдущих ДЗ должны быть настроены на этот стенд; пользователь `team` и пути установки остаются такими же. Память и число executor можно изменить в `config/spark-defaults.conf`.

## Обработка данных

По умолчанию используется файл `hive-team39/data/orders.tsv` из ДЗ3: 12 заказов, общая сумма `3997.00`. Можно передать другой файл того же формата:

```bash
bash scripts/run.sh /path/to/orders.tsv
```

Входной файл проверяется загрузчиком из ДЗ3 и копируется в HDFS: `/data/team39/spark/input/orders.tsv`. Затем `spark-submit --master yarn --deploy-mode client` запускает `app/orders.py`.

В одной сессии Spark приложение:

1. Читает TSV из HDFS с явной схемой.
2. Приводит идентификаторы к `BIGINT`, сумму к `DECIMAL(12,2)`, дату к `DATE`; обрабатывает строку страны через `trim` и `upper`.
3. Группирует по дате и стране, считает заказы, уникальных покупателей, сумму и средний чек.
4. Сохраняет результат через `partitionBy("order_date", "country").saveAsTable(...)` в формате Parquet со сжатием Snappy.

Таблица `dz4_team39.daily_orders` внешняя, метаданные находятся в общем Metastore из ДЗ3. Данные лежат в HDFS в `/warehouse/team39/external/dz4_daily_orders/order_date=.../country=.../`.

Каждый запуск полностью заменяет результат своим входным набором. При повторной обработке одного файла число строк и суммы остаются прежними.

## Проверка через Hive

В конце `run.sh` стандартный Beeline читает таблицу запросом из `sql/inspect.sql`. Скрипт `verify.py` независимо считает показатели исходного файла и сравнивает все строки с результатом Hive, включая число покупателей и средний чек.

Проверить вручную:

```bash
source scripts/common.sh
beeline_run -f sql/inspect.sql
beeline_run -e 'SHOW PARTITIONS dz4_team39.daily_orders;'
```

Для примера ожидается:

| Дата | Страна | Заказов | Покупателей | Сумма | Средний чек |
| --- | --- | ---: | ---: | ---: | ---: |
| 2026-10-20 | KZ | 2 | 2 | 499.90 | 249.95 |
| 2026-10-20 | RU | 2 | 2 | 350.50 | 175.25 |
| 2026-10-21 | KZ | 2 | 2 | 125.75 | 62.88 |
| 2026-10-21 | RU | 2 | 2 | 920.25 | 460.13 |
| 2026-10-22 | KZ | 2 | 2 | 900.60 | 450.30 |
| 2026-10-22 | RU | 2 | 2 | 1200.00 | 600.00 |

Итого: 6 строк, 6 партиций, 12 исходных заказов, сумма `3997.00`. Журнал Spark с ID приложения YARN и адресами executor сохраняется в `build/spark.log`, ответ Hive — в `build/hive.tsv`. Их можно использовать для проверки на стенде.

На стенде проверены повторный запуск, замена входного файла и чтение результата через Beeline. Таблица заказов из ДЗ3 сохранена.

```bash
yarn application -status <APPLICATION_ID>
hdfs_run fsck /warehouse/team39/external/dz4_daily_orders
```

Запуск в YARN описан в [документации Spark](https://spark.apache.org/docs/3.5.7/running-on-yarn.html). Для сдачи достаточно ссылки на эту папку: инструкция и все скрипты находятся в репозитории.
