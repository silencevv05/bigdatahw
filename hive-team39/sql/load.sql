SET hive.exec.dynamic.partition=true;
SET hive.exec.dynamic.partition.mode=nonstrict;
SET hive.execution.engine=mr;
SET hive.exec.mode.local.auto=false;
-- Input is a complete snapshot for each submitted (order_date, country).
-- Only those partitions are replaced. Repeating the same batch is idempotent.
INSERT OVERWRITE TABLE dz3_team39.orders PARTITION (order_date, country)
SELECT order_id, customer_id, amount, order_date, country
FROM dz3_team39.orders_stage;
