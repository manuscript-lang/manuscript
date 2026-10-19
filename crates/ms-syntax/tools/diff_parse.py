import os, subprocess
ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
WORK = os.environ.get("MS_DIFF_WORK", "/tmp/ms-syntax-diff")
os.makedirs(WORK, exist_ok=True)
MS = os.path.join(ROOT, "ms")  # Go oracle: `make build`
RS = os.path.join(os.environ.get("CARGO_TARGET_DIR", os.path.join(ROOT, "target")), "debug", "ms-syntax")
ORA = os.path.join(WORK, "oracle")  # go build -mod=vendor -o $MS_DIFF_WORK/oracle crates/ms-syntax/tools/oracle.go
FILES = os.path.join(WORK, "ms-files.txt")
if not os.path.exists(FILES):
    out = subprocess.run(["git", "-C", ROOT, "ls-files", "*.ms"], capture_output=True, text=True).stdout
    open(FILES, "w").write("".join("./" + l + "\n" for l in out.splitlines() if not l.startswith("experiments/")))
import json, random, sys, concurrent.futures as cf
files=[l.strip() for l in open(FILES)]
seed=int(sys.argv[1]) if len(sys.argv)>1 else 1
per=int(sys.argv[2]) if len(sys.argv)>2 else 4
random.seed(seed)
def mutate(b,r):
    k=r.randrange(6)
    if not b: return b
    if k==0: return b[:r.randrange(len(b))]
    if k==1:
        ls=b.split(b"\n"); del ls[r.randrange(len(ls))]; return b"\n".join(ls)
    if k==2:
        i=r.randrange(len(b)); return b[:i]+b[i+1:]
    if k==3:
        i=r.randrange(len(b)); return b[:i]+bytes([r.choice(b"()[]{}:,.\"'`#$@ \t\n=<>|&!?+-*/%^~;\\")])+b[i:]
    if k==4:
        ls=b.split(b"\n"); i=r.randrange(len(ls)); ls[i]=b"    "+ls[i]; return b"\n".join(ls)
    ls=b.split(b"\n"); i=r.randrange(len(ls)); ls[i]=ls[i][1:]; return b"\n".join(ls)
def run(args):
    f,i,s=args
    r=random.Random(f"{seed}-{f}-{i}")
    b=open(ROOT+"/"+f,"rb").read()
    m=mutate(b,r)
    p=f"{WORK}/w{__import__('threading').get_ident()}.ms"
    open(p,"wb").write(m)
    g=subprocess.run([MS,"check",p,"--json"],capture_output=True,text=True,cwd=WORK)
    try: gd=json.loads(g.stdout)["diagnostics"]
    except Exception: return None
    gp=[d for d in gd if d["phase"]=="parse"]
    x=subprocess.run([RS,"parse","--json",p],capture_output=True,text=True)
    out=x.stdout.strip()
    if x.returncode>1 or "panicked" in x.stderr: return (f,i,"PANIC",x.stderr[-200:],m)
    if gp:
        want=gp[0]
        if out.endswith(": ok"): return (f,i,"RS-ok",json.dumps(want),m)
        try: got=json.loads(out)
        except Exception: return (f,i,"RS-bad",out[:300],m)
        k=lambda d:(d["code"],d["message"],d["position"]["line"],d["position"]["column"],d["position"]["offset"])
        if k(want)!=k(got): return (f,i,"DIFF","go="+json.dumps(want)+"\n rs="+out,m)
    else:
        if not out.endswith(": ok"): return (f,i,"RS-extra",out,m)
    return None
jobs=[(f,i,seed) for f in files for i in range(per)]
bad=[]
with cf.ThreadPoolExecutor(4) as ex:
    for r in ex.map(run,jobs):
        if r: bad.append(r)
print(len(jobs),"cases",len(bad),"mismatches")
os.makedirs(WORK+"/bad",exist_ok=True)
for n,(f,i,kind,info,m) in enumerate(bad):
    open(f"{WORK}/bad/{n}.ms","wb").write(m)
    if n<25: print(n,f,i,kind,info[:600])
