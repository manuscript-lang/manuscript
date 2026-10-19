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
import os, random, subprocess, sys, threading, concurrent.futures as cf
files=[l.strip() for l in open(FILES) if "cranelift-spike" not in l]
seed=int(sys.argv[1]); per=int(sys.argv[2])
def strip_code(line):
    # crude: returns line without comment and strings
    out=[];i=0;ins=False
    while i<len(line):
        c=line[i]
        if ins:
            if c=="\\": i+=2; continue
            if c=='"': ins=False
        else:
            if c=='"': ins=True
            elif c=="#": break
            else: out.append(c)
        i+=1
    return "".join(out)
def variant(text,r):
    k=r.randrange(7)
    ls=text.split("\n")
    if k==0: return "\n".join(l for l in ls if l.strip())+"\n"
    if k==1: return "\n".join(l+("  " if r.random()<.3 else "")+("\n" if r.random()<.2 else "") for l in ls)
    if k in(2,3,6):
        # join lines inside delimiters
        out=[];depth=0;cur=None
        for l in ls:
            code=strip_code(l)
            if cur is not None and "#" not in l:
                cur+=" "+l.strip()
            else:
                if cur is not None: out.append(cur)
                cur=l
            d=sum(code.count(c) for c in "([{")-sum(code.count(c) for c in ")]}")
            depth+=d
            if depth<=0 or "#" in l:
                depth=max(depth,0)
                out.append(cur); cur=None
        if cur is not None: out.append(cur)
        return "\n".join(out)
    if k==4:
        # break after commas in long-ish lines inside delimiters
        out=[]
        for l in ls:
            if r.random()<.3 and "," in l and "#" not in l and '"' not in l and "(" in l:
                i=l.index(",")
                ind=len(l)-len(l.lstrip())
                out.append(l[:i+1]); out.append(" "*(ind+r.choice([0,2,4,8]))+l[i+1:].strip())
            else: out.append(l)
        return "\n".join(out)
    # k==5 random indentation noise of continuation inside parens: strip leading ws of lines starting with ) or ]
    return "\n".join((l.lstrip() if l.lstrip()[:1] in ")]}" else l) for l in ls)
def run(a):
    f,i=a
    r=random.Random(f"{seed}-{f}-{i}")
    t=variant(open(ROOT+"/"+f).read(),r)
    d=f"{WORK}/f{threading.get_ident()}"
    os.makedirs(d,exist_ok=True)
    p=d+"/x.ms"; open(p,"w").write(t)
    g=subprocess.run([MS,"fmt",p],capture_output=True,text=True,cwd=d)
    gok=g.returncode==0
    gout=open(p).read() if gok else None
    open(p,"w").write(t)
    x=subprocess.run([RS,"fmt",p],capture_output=True,text=True)
    if x.returncode>1 or "panicked" in x.stderr: return (f,i,"PANIC",x.stderr[-300:],t)
    rok=x.returncode==0
    if gok!=rok: return (f,i,"STATUS go=%s rs=%s"%(gok,rok),(g.stdout+g.stderr)[:200]+"|"+x.stderr[:200],t)
    if gok and gout!=t: CH.append(1)
    if gok and gout!=x.stdout: return (f,i,"OUT","",t,gout,x.stdout)
    return None
CH=[]
jobs=[(f,i) for f in files for i in range(per)]
bad=[]
with cf.ThreadPoolExecutor(4) as ex:
    for r in ex.map(run,jobs):
        if r: bad.append(r)
print(len(CH),"changed by go fmt");print(len(jobs),"cases",len(bad),"mismatches")
os.makedirs(WORK+"/fbad",exist_ok=True)
import difflib
for n,r in enumerate(bad):
    open(f"{WORK}/fbad/{n}.in.ms","w").write(r[4])
    if len(r)>5:
        open(f"{WORK}/fbad/{n}.go.ms","w").write(r[5]); open(f"{WORK}/fbad/{n}.rs.ms","w").write(r[6])
    if n<12:
        print("##",n,r[0],r[1],r[2],r[3])
        if len(r)>5: print("".join(list(difflib.unified_diff(r[5].splitlines(1),r[6].splitlines(1),"go","rs",n=1))[:25]))
