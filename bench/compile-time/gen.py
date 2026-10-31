import sys, os, random, shutil
P, F, K = int(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3])
out = sys.argv[4]
random.seed(1)
shutil.rmtree(out, ignore_errors=True)
def fid(p,f): return p*F+f
def deps(p,f):
    i=fid(p,f); r=[]
    for _ in range(3):
        if i==0: break
        j=random.randrange(max(0,i-60) if random.random()<.7 else 0, i)
        r.append((j//F, j%F))
    return sorted(set(r))
def ms_fn(p,f,k,d):
    n=f"w_{p}_{f}_{k}"
    dp,df=d[k%len(d)] if d else (None,None)
    call = f"w_{dp}_{df}_0(acc % 1000)" if d else "0"
    s=k%4
    b=[f"export fn {n}(x: Int) Int:"]
    if s==0:
        b+=["    var acc = x","    for i in 0..10:","        if i % 2 == 0:","            acc += i * 3","        else:","            acc -= 1",f"    return acc % 100000 + {call}"]
    elif s==1:
        b+=["    var xs = List[Int]()","    for i in 0..8:","        xs.append(i + x)","    var t = 0","    for v in xs:","        t += v % 7",f"    let acc = t + xs.length()",f"    return acc + {call}"]
    elif s==2:
        b+=[f"    let r = R_{p}_{f}(x, \"n{{x}}\", [x, 1, 2])","    var acc = r.score()","    while acc > 1000:","        acc = acc / 2",f"    return acc + {call}"]
    else:
        b+=["    let s = \"v{x}\"","    var acc = s.length()","    if x > 50:","        acc += x / 3","    else if x > 10:","        acc += x * 2","    else:","        acc += 1",f"    return acc + {call}"]
    return "\n".join(b)+"\n"
def go_fn(p,f,k,d):
    n=f"W_{p}_{f}_{k}"
    dp,df=d[k%len(d)] if d else (None,None)
    pk = "" if (d and dp==p) else (f"p{dp}." if d else "")
    call = f"{pk}W_{dp}_{df}_0(acc % 1000)" if d else "0"
    s=k%4
    b=[f"func {n}(x int) int {{"]
    if s==0:
        b+=["\tacc := x","\tfor i := 0; i < 10; i++ {","\t\tif i%2 == 0 {","\t\t\tacc += i * 3","\t\t} else {","\t\t\tacc -= 1","\t\t}","\t}",f"\treturn acc%100000 + {call}"]
    elif s==1:
        b+=["\txs := []int{}","\tfor i := 0; i < 8; i++ {","\t\txs = append(xs, i+x)","\t}","\tt := 0","\tfor _, v := range xs {","\t\tt += v % 7","\t}","\tacc := t + len(xs)",f"\treturn acc + {call}"]
    elif s==2:
        b+=[f"\tr := R_{p}_{f}{{x, fmt.Sprintf(\"n%d\", x), []int{{x, 1, 2}}}}","\tacc := r.Score()","\tfor acc > 1000 {","\t\tacc = acc / 2","\t}",f"\treturn acc + {call}"]
    else:
        b+=["\ts := fmt.Sprintf(\"v%d\", x)","\tacc := len(s)","\tif x > 50 {","\t\tacc += x / 3","\t} else if x > 10 {","\t\tacc += x * 2","\t} else {","\t\tacc += 1","\t}",f"\treturn acc + {call}"]
    b.append("}")
    return "\n".join(b)+"\n"
os.makedirs(out+"/ms/src",exist_ok=True); os.makedirs(out+"/go",exist_ok=True)
open(out+"/go/go.mod","w").write("module bigprog\n\ngo 1.21\n")
for p in range(P):
    os.makedirs(f"{out}/ms/src/pkg{p}",exist_ok=True); os.makedirs(f"{out}/go/p{p}",exist_ok=True)
    for f in range(F):
        d=deps(p,f)
        m=[]
        for (dp,df) in d:
            path = f"./f{df}.ms" if dp==p else f"../pkg{dp}/f{df}.ms"
            m.append(f'import w_{dp}_{df}_0 from "{path}"\n')
        m.append(f"\nexport type R_{p}_{f}:\n    a: Int\n    b: String\n    c: List[Int]\n\nimpl R_{p}_{f}:\n    fn score() Int:\n        var t = self.a + self.b.length()\n        for v in self.c:\n            t += v\n        return t\n\n")
        for k in range(K): m.append(ms_fn(p,f,k,d)+"\n")
        m.append(f"export fn all_{p}_{f}(x: Int) Int:\n    var t = 0\n"+"".join(f"    t += w_{p}_{f}_{k}(x)\n" for k in range(K))+"    return t % 100000\n")
        open(f"{out}/ms/src/pkg{p}/f{f}.ms","w").write("".join(m))
        g=[f"package p{p}\n\nimport \"fmt\"\n"]
        for dpk in sorted({dp for dp,_ in d if dp!=p}): g.append(f"import \"bigprog/p{dpk}\"\n")
        g.append(f"\nvar _ = fmt.Sprint\n\ntype R_{p}_{f} struct {{\n\tA int\n\tB string\n\tC []int\n}}\n\nfunc (r R_{p}_{f}) Score() int {{\n\tt := r.A + len(r.B)\n\tfor _, v := range r.C {{\n\t\tt += v\n\t}}\n\treturn t\n}}\n\n")
        for k in range(K): g.append(go_fn(p,f,k,d)+"\n")
        g.append(f"func All_{p}_{f}(x int) int {{\n\tt := 0\n"+"".join(f"\tt += W_{p}_{f}_{k}(x)\n" for k in range(K))+"\treturn t % 100000\n}\n")
        open(f"{out}/go/p{p}/f{f}.go","w").write("".join(g))
# mains
last=[(p,f) for p in range(P) for f in range(F)]
ms=["import stdout from \"@std/io.ms\"\n"]+[f'import all_{p}_{f} from "./pkg{p}/f{f}.ms"\n' for p,f in last]
ms.append("\nexport fn main() Int:\n    var t = 0\n")
for p,f in last: ms.append(f"    t += all_{p}_{f}(7)\n")
ms.append('    stdout().write("{t}\\n").get()\n    return 0\n')
open(out+"/ms/src/main.ms","w").write("".join(ms))
open(out+"/ms/ms.toml","w").write(open("/home/user/manuscript/bench/ms/ms.toml").read() if os.path.exists("/home/user/manuscript/bench/ms/ms.toml") else "")
g=["package main\n\nimport \"fmt\"\n"]+[f'import "bigprog/p{p}"\n' for p in range(P)]
g.append("\nfunc main() {\n\tt := 0\n")
for p,f in last: g.append(f"\tt += p{p}.All_{p}_{f}(7)\n")
g.append("\tfmt.Println(t)\n}\n")
open(out+"/go/main.go","w").write("".join(g))
