import subprocess, sys, glob, os
llvm = glob.glob(os.environ['RUNNER_TEMP'] + '/ms-cache/ms/llvm/*/')[0]
opt, llc = llvm + 'opt', llvm + 'llc'
tri = '-mtriple=arm64-apple-darwin'
def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    return r.returncode, (r.stderr or '')[-300:]
os.makedirs('keep', exist_ok=True)
print(run([opt, tri, '-passes=default<O3>', 'ms-keep.ll', '-o', 'keep/p.bc']))
print(run([llc, '-O3', '-filetype=asm', '-relocation-model=pic', tri, 'keep/p.bc', '-o', 'keep/plain.s']))
lines = open('keep/plain.s', encoding='latin1').read().split('\n')
# function starts: a line `.cfi_startproc` preceded by its label line
starts = [i for i, l in enumerate(lines) if l.strip() == '.cfi_startproc']
ends = [i for i, l in enumerate(lines) if l.strip() == '.cfi_endproc']
print(len(starts), 'functions')
def ok(text):
    mod = '\n'.join('module asm "' + l.replace('\\', '\\5C').replace('"', '\\22') + '"' for l in text.split('\n')) + '\n'
    open('keep/t.ll', 'w').write(mod)
    code, err = run([llc, '-filetype=obj', '-relocation-model=pic', tri, 'keep/t.ll', '-o', 'keep/t.o'])
    return code == 0, err
whole, err = ok('\n'.join(lines))
print('whole', whole, err)
if not whole:
    # each function alone, with the preamble (everything before the first function's label line)
    head = '\n'.join(lines[:starts[0] - 1])
    bad = []
    for k, (s, e) in enumerate(zip(starts, ends)):
        body = '\n'.join(lines[s - 1:e + 1])
        good, err = ok(head + '\n' + body)
        if not good:
            bad.append((e - s, lines[s - 1], err))
    print('failing functions alone:', len(bad))
    for b in sorted(bad, reverse=True)[:5]:
        print(b)
    if bad:
        s = [i for i, l in enumerate(lines) if l == bad[0][1]][0]
        open('keep/bad.s', 'w').write('\n'.join(lines[s:s + bad[0][0] + 3]))
    else:
        # grow a prefix of functions until it fails
        lo, hi = 0, len(starts)
        while lo + 1 < hi:
            mid = (lo + hi) // 2
            good, _ = ok('\n'.join(lines[:ends[mid] + 1]))
            if good: lo = mid
            else: hi = mid
        print('first failing prefix ends at function', hi, lines[starts[hi] - 1], 'size', ends[hi] - starts[hi])
