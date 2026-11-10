import os, subprocess, resource, time, statistics, sys
env=dict(os.environ, ANTHROPIC_API_KEY="k", ANTHROPIC_BASE_URL="http://127.0.0.1:8099")
cwd="/tmp/pi-work"
cli="/tmp/pijs/node_modules/@mariozechner/pi-coding-agent/dist/cli.js"
mockargs=["--provider","mock","--model","mock-model"]
impls={
 "manuscript (native)":["/tmp/pi-ms","-p","--no-session"],
 "node 22":["/opt/node22/bin/node",cli]+mockargs+["-p","--no-session"],
 "bun":["/root/.bun/bin/bun",cli]+mockargs+["-p","--no-session"],
}
cases={"one turn":"hello there","tool loop (bash)":"bash:echo hi"}
def run(cmd):
    t=time.time()
    p=subprocess.Popen(cmd,cwd=cwd,env=env,stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    _,st,ru=os.wait4(p.pid,0)
    return time.time()-t, ru.ru_utime+ru.ru_stime, ru.ru_maxrss/1024
for case,prompt in cases.items():
    print("##",case)
    for name,base in impls.items():
        rs=[run(base+[prompt]) for _ in range(7)]
        w=statistics.median(r[0] for r in rs); c=statistics.median(r[1] for r in rs); m=max(r[2] for r in rs)
        print(f"{name:20s} wall {w*1000:6.0f} ms  cpu {c*1000:6.0f} ms  peak RSS {m:6.1f} MiB")
