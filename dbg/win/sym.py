import re, sys, bisect
syms = []
for line in open('syms.txt', errors='replace'):
    p = line.split()
    if len(p) >= 3 and re.fullmatch(r'[0-9a-fA-F]{8,16}', p[0]) and p[1] in 'tTwWdDrRbB':
        syms.append((int(p[0], 16), p[2]))
syms.sort()
keys = [a for a, _ in syms]
base = int(sys.argv[1], 16)
for off in sys.argv[2:]:
    a = base + int(off, 16)
    i = bisect.bisect_right(keys, a) - 1
    print(f"+{off} -> {syms[i][1]} +{a - syms[i][0]:x}" if i >= 0 else f"+{off} -> ?")
