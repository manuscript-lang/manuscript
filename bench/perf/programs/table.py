import sys, collections
best = collections.defaultdict(lambda: float("inf")); ops = {}; order = []
for line in open(sys.argv[1]):
    v, name, n, ns = line.split(); n, ns = int(n), int(ns)
    if name not in order: order.append(name)
    ops[name] = n; best[(v, name)] = min(best[(v, name)], ns)
print(f"best of {sys.argv[2]} runs; ns/op\n")
print("| operation | ops | Manuscript | Go | ratio |\n|---|---:|---:|---:|---:|")
for name in order:
    m, g = best[("ms", name)] / ops[name], best[("go", name)] / ops[name]
    print(f"| {name} | {ops[name]} | {m:,.1f} | {g:,.2f} | {m/g:,.1f}x |")
