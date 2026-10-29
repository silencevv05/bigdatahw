#!/usr/bin/env python3
"""Read orders from HDFS and save daily aggregates in a partitioned Hive table."""
import argparse
from pyspark.sql import SparkSession, functions as F


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    spark = (SparkSession.builder.appName("DZ4-team39-daily-orders")
             .enableHiveSupport().getOrCreate())
    spark.sparkContext.setLogLevel("WARN")
    try:
        if spark.sparkContext.master != "yarn":
            raise RuntimeError("This job must run on YARN")
        print(f"APPLICATION_ID={spark.sparkContext.applicationId}", flush=True)
        print(f"MASTER={spark.sparkContext.master}; INPUT={args.input}", flush=True)
        raw = (spark.read.option("sep", "\t").option("header", "false")
               .option("mode", "FAILFAST")
               .schema("order_id STRING, customer_id STRING, amount STRING, "
                       "order_date STRING, country STRING").csv(args.input))
        orders = raw.select(
            F.col("order_id").cast("bigint").alias("order_id"),
            F.col("customer_id").cast("bigint").alias("customer_id"),
            F.col("amount").cast("decimal(12,2)").alias("amount"),
            F.to_date("order_date", "yyyy-MM-dd").alias("order_date"),
            F.upper(F.trim("country")).alias("country"),
        )
        daily = orders.groupBy("order_date", "country").agg(
            F.count("*").alias("orders_count"),
            F.countDistinct("customer_id").alias("customers_count"),
            F.sum("amount").cast("decimal(22,2)").alias("total_amount"),
        )
        # Avoid the intermediate decimal rounding performed by avg().
        daily = daily.withColumn(
            "average_amount",
            (F.col("total_amount") / F.col("orders_count")).cast("decimal(12,2)"),
        )
        spark.sql("CREATE DATABASE IF NOT EXISTS dz4_team39")
        (daily.write.mode("overwrite").format("parquet")
         .option("path", args.output).option("compression", "snappy")
         .partitionBy("order_date", "country")
         .saveAsTable("dz4_team39.daily_orders"))
        spark.table("dz4_team39.daily_orders").orderBy("order_date", "country").show(truncate=False)
        executors = spark.sparkContext._jsc.sc().getExecutorMemoryStatus().keySet().toString()
        print(f"EXECUTORS={executors}", flush=True)
        print("SPARK PASS: dz4_team39.daily_orders saved to HDFS", flush=True)
    finally:
        spark.stop()


if __name__ == "__main__":
    main()
