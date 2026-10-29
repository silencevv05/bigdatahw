#!/usr/bin/env python3
"""Compare Hive results with independent decimal aggregates of the input snapshot."""
import csv
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path
import sys


def main():
    groups = {}
    with open(sys.argv[1], encoding="utf-8", newline="") as source:
        for _, customer, amount, day, country in csv.reader(source, delimiter="\t"):
            group = groups.setdefault((day, country), [0, set(), Decimal(0)])
            group[0] += 1
            group[1].add(customer)
            group[2] += Decimal(amount)
    expected = []
    for (day, country), (count, customers, total) in sorted(groups.items()):
        average = (total / count).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
        expected.append((day, country, count, len(customers), total, average))
    actual = []
    for row in csv.reader(Path(sys.argv[2]).read_text(encoding="utf-8").splitlines(), delimiter="\t"):
        if row:
            day, country, count, customers, total, average = row
            actual.append((day, country, int(count), int(customers), Decimal(total), Decimal(average)))
    if actual != expected:
        raise SystemExit(f"HIVE CHECK FAILED\nexpected={expected}\nactual={actual}")
    print(f"HIVE PASS: {len(actual)} partitions, {sum(r[2] for r in actual)} orders, "
          f"amount={sum((r[4] for r in actual), Decimal(0))}")


if __name__ == "__main__":
    main()
