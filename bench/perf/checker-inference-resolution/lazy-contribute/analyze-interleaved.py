"""Paired medians and round-level AA/AB uncertainty; no subtraction from wins."""
import collections
import argparse
import json
import math
from pathlib import Path
import random
import statistics

parser = argparse.ArgumentParser()
parser.add_argument('results', type=Path, help='Local interleaved measurement JSON')
data = json.loads(parser.parse_args().results.read_text())
groups = collections.defaultdict(lambda: collections.defaultdict(dict))
for sample in data['samples']:
    if sample['round'] >= 0:
        groups[sample['case']][sample['condition']][sample['round'], sample['label']] = sample
result = {}
for name, conditions in sorted(groups.items()):
    count = data['rounds']
    k = max(k for k in range(1, count // 2 + 1)
            if sum(math.comb(count, i) for i in range(k)) / 2 ** count <= .025)
    ratios = {}
    summary = {}
    for condition, values in sorted(conditions.items()):
        paired = [values[r, 'candidate']['wall_ns'] / values[r, 'base']['wall_ns'] for r in range(count)]
        ratios[condition] = paired
        ordered = sorted(paired)
        summary[condition] = {'paired_median': statistics.median(paired),
                              'slower_pairs': sum(r > 1 for r in paired), 'pairs': count,
                              'median_interval': [ordered[k - 1], ordered[count - k]]}
    differences = [math.log(b) - math.log(a) for a, b in zip(ratios['AA'], ratios['AB'])]
    rng = random.Random(7731)
    bootstrap = sorted(math.exp(statistics.median(rng.choices(differences, k=count))) for _ in range(10_000))
    summary['within_round_AB_over_AA'] = {
        'median': math.exp(statistics.median(differences)),
        'bootstrap95_interval': [bootstrap[249], bootstrap[9749]],
        'assumption': 'Rounds are independent; shared-VM temporal dependence may weaken coverage.'}
    result[name] = summary
print(json.dumps(result, indent=2))
