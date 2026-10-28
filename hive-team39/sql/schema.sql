CREATE DATABASE IF NOT EXISTS dz3_team39
COMMENT 'Homework 3: remote Hive and automated partitioned ingestion';

CREATE EXTERNAL TABLE IF NOT EXISTS dz3_team39.orders_stage (
  order_id BIGINT,
  customer_id BIGINT,
  amount DECIMAL(12,2),
  order_date STRING,
  country STRING
)
ROW FORMAT DELIMITED FIELDS TERMINATED BY '\t'
STORED AS TEXTFILE
LOCATION '${hivevar:stage_uri}'
TBLPROPERTIES ('external.table.purge'='false');

CREATE EXTERNAL TABLE IF NOT EXISTS dz3_team39.orders (
  order_id BIGINT,
  customer_id BIGINT,
  amount DECIMAL(12,2)
)
PARTITIONED BY (order_date STRING, country STRING)
STORED AS ORC
LOCATION '${hivevar:warehouse_uri}'
TBLPROPERTIES ('transactional'='false', 'external.table.purge'='false', 'orc.compress'='SNAPPY');
