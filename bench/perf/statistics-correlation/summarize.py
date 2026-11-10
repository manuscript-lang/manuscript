"""Medians over paired runs and a sign count of per-pair ratios (after/before)."""
import re, statistics, sys, glob
pairs = int(sys.argv[1])  # run directory: raw/<backend>.<before|after>.<pair>.txt
rx = re.compile(r'(corr|reg)\s+(\S+) n=(\d+) (\d+)ns (\S+)')
def load(be, v):
    d = {}
    for i in range(1, pairs + 1):
        for line in open(f'raw/{be}.{v}.{i}.txt'):
            m = rx.match(line)
            if m: d.setdefault((m[1], m[2], int(m[3])), []).append((int(m[4]), m[5]))
    return d
for be in ('llvm', 'cranelift'):
    b, a = load(be, 'before'), load(be, 'after')
    print(f'\n### {be}\n')
    print('| case | n | before median ns | after median ns | ratio | pairs slower | result before -> after |')
    print('|---|--:|--:|--:|--:|--:|---|')
    for k in b:
        bs = [x[0] for x in b[k]]; as_ = [x[0] for x in a[k]]
        slower = sum(1 for x, y in zip(bs, as_) if y > x)
        rb, ra = b[k][0][1], a[k][0][1]
        note = rb if rb == ra else f'{rb} -> {ra}'
        mb, ma = statistics.median(bs), statistics.median(as_)
        print(f'| {k[0]} {k[1]} | {k[2]} | {mb:.0f} | {ma:.0f} | {ma/mb:.2f} | {slower}/{len(bs)} | {note} |')
