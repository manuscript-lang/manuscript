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
import os, random, subprocess, sys, shutil
ROOT="/home/user/manuscript"; ORA=ORA; RS=ROOT+"/target-rs/debug/ms-syntax"
files=[l.strip() for l in open(FILES)]
seed=int(sys.argv[1]); per=int(sys.argv[2]); mode=sys.argv[3]
src=open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "diff_parse.py")).read().split("def run(args)")[0]
# reuse mutate()
ns={"__file__":__file__}
exec(src.replace("seed=int(sys.argv[1]) if len(sys.argv)>1 else 1","seed=%d"%seed).replace("per=int(sys.argv[2]) if len(sys.argv)>2 else 4","per=%d"%per),ns)
mutate=ns["mutate"]
d=WORK+"/tree"; shutil.rmtree(d,ignore_errors=True); os.makedirs(d)
paths=[]
for f in files:
    b=open(ROOT+"/"+f,"rb").read()
    for i in range(per):
        r=random.Random(f"{seed}-{f}-{i}")
        m=mutate(b,r) if i>0 or mode=="partial" else b
        m=m.decode("utf8","ignore").encode()  # invalid UTF-8 is covered by diff_parse.py
        p=f"{d}/{len(paths):05d}.ms"; open(p,"wb").write(m); paths.append(p)
def sections(out):
    res={};cur=None
    for line in out.split("\n"):
        if line.startswith("file "): cur=line[5:]; res[cur]=[]
        elif cur is not None: res[cur].append(line)
    return res
def run(cmd):
    out=b""
    for i in range(0,len(paths),400):
        out+=subprocess.run(cmd+paths[i:i+400],capture_output=True).stdout
    return sections(out.decode("utf8","replace"))
g=run([ORA,mode]); r=run([RS,"dump-"+mode])
bad=0
for p in paths:
    if g.get(p)!=r.get(p):
        bad+=1
        if bad<=8:
            a,b=g.get(p) or [],r.get(p) or []
            print("MISMATCH",p)
            for x,y in zip(a,b):
                if x!=y:
                    k=next(i for i in range(min(len(x),len(y))) if x[i]!=y[i]) if x[:min(len(x),len(y))]!=y[:min(len(x),len(y))] else min(len(x),len(y))
                    print(" go:",x[max(0,k-150):k+250]); print(" rs:",y[max(0,k-150):k+250]); break
            else: print(" len",len(a),len(b))
print(len(paths),"files",bad,"mismatches")
