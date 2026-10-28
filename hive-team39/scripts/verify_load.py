#!/usr/bin/env python3
"""Generate a safe affected-partition predicate or verify Beeline TSV output."""
import csv
from decimal import Decimal
import json
import sys

manifest = json.load(open(sys.argv[1], encoding='utf-8'))
parts = manifest['partitions']
if len(sys.argv) == 2:
    print('SELECT order_date, country, count(*), sum(amount) FROM dz3_team39.orders WHERE ' +
          ' OR '.join(f"(order_date='{p['order_date']}' AND country='{p['country']}')" for p in parts) +
          ' GROUP BY order_date,country;')
else:
    with open(sys.argv[2], encoding='utf-8') as result:
        actual = list(csv.reader((line for line in result if line.strip()), delimiter='\t'))
    expected = [(p['order_date'], p['country'], p['rows'], Decimal(p['amount'])) for p in parts]
    parsed = sorted((row[0], row[1], int(row[2]), Decimal(row[3])) for row in actual)
    if parsed != expected:
        raise SystemExit(f'LOAD FAIL: expected {expected!r}; got {parsed!r}')
    print(f"LOAD PASS: {manifest['rows']} rows, {len(parts)} partitions, sum={manifest['amount']}; exact partition aggregates match")
