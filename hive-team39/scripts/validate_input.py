#!/usr/bin/env python3
"""Validate before touching HDFS; emit normalized TSV and exact expected aggregates."""
import csv
from datetime import date
from decimal import Decimal
import hashlib
import json
from pathlib import Path
import re
import sys


def validate(source):
    rows, seen, groups = [], set(), {}
    with open(source, encoding='utf-8', newline='') as incoming:
        for line, fields in enumerate(csv.reader(incoming, delimiter='\t'), 1):
            if len(fields) != 5:
                raise ValueError(f'line {line}: expected 5 tab-separated fields')
            order_id, customer_id, amount, day, country = fields
            for name, value in (('order_id', order_id), ('customer_id', customer_id)):
                if not re.fullmatch(r'[1-9][0-9]{0,18}', value) or int(value) > 2**63 - 1:
                    raise ValueError(f'line {line}: invalid positive BIGINT {name}')
            if order_id in seen:
                raise ValueError(f'line {line}: duplicate order_id {order_id}')
            seen.add(order_id)
            if not re.fullmatch(r'(0|[1-9][0-9]{0,9})\.[0-9]{2}', amount):
                raise ValueError(f'line {line}: amount must be non-negative DECIMAL(12,2)')
            if not re.fullmatch(r'[0-9]{4}-[0-9]{2}-[0-9]{2}', day):
                raise ValueError(f'line {line}: expected ISO date')
            date.fromisoformat(day)
            if not re.fullmatch(r'[A-Z]{2}', country):
                raise ValueError(f'line {line}: country must contain two uppercase ASCII letters')
            group = groups.setdefault((day, country), {'count': 0, 'amount': Decimal(0)})
            group['count'] += 1
            group['amount'] += Decimal(amount)
            rows.append(fields)
    if not rows:
        raise ValueError('empty input is not a partition snapshot')
    text = ''.join('\t'.join(row) + '\n' for row in rows)
    manifest = {
        'rows': len(rows), 'sha256': hashlib.sha256(text.encode()).hexdigest(),
        'amount': str(sum((g['amount'] for g in groups.values()), Decimal(0))),
        'partitions': [dict(order_date=k[0], country=k[1], rows=g['count'], amount=str(g['amount']))
                       for k, g in sorted(groups.items())],
    }
    return text, manifest


def main():
    try:
        text, manifest = validate(sys.argv[1])
    except (ValueError, OSError) as error:
        print(f'INPUT REJECTED: {error}', file=sys.stderr)
        return 2
    Path(sys.argv[2]).write_text(text, encoding='utf-8')
    Path(sys.argv[3]).write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    print(f"INPUT PASS: {manifest['rows']} rows, {len(manifest['partitions'])} partitions, amount={manifest['amount']}")
    return 0


if __name__ == '__main__':
    sys.exit(main())
