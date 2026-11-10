import os, subprocess, time, json, sys, threading
N=int(sys.argv[1]) if len(sys.argv)>1 else 200
cli="/tmp/pijs/node_modules/@mariozechner/pi-coding-agent/dist/cli.js"
mock=["--provider","mock","--model","mock-model","--mode","rpc"]
impls={
 "manuscript (native)":(["/tmp/pi-ms","--mode","rpc"],{}),
 "node 22":(["/opt/node22/bin/node",cli]+mock,{}),
 "bun":(["/root/.bun/bin/bun",cli]+mock,{}),
}
for name,(cmd,extra) in impls.items():
    cwd=f"/tmp/long-{name.split()[0]}"; os.makedirs(cwd,exist_ok=True)
    env=dict(os.environ,ANTHROPIC_API_KEY="k",ANTHROPIC_BASE_URL="http://127.0.0.1:8099")
    t0=time.time()
    p=subprocess.Popen(cmd,cwd=cwd,env=env,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True,bufsize=1)
    peak=0
    def rss():
        try:
            for l in open(f"/proc/{p.pid}/status"):
                if l.startswith("VmHWM"): return int(l.split()[1])/1024
        except Exception: return 0
    done=0
    for i in range(N):
        msg=f"bash:echo turn {i}" if i%3==0 else f"message number {i} " + "lorem ipsum "*20
        p.stdin.write(json.dumps({"type":"prompt","message":msg})+"\n"); p.stdin.flush()
        while True:
            line=p.stdout.readline()
            if not line: break
            if '"agent_end"' in line:
                # pi emits agent_end once per prompt; mine emits it after each turn too
                if '"type":"agent_end"' in line: break
        done+=1
        if i%20==0: peak=max(peak,rss())
    peak=max(peak,rss())
    p.stdin.close()
    _,st,ru=os.wait4(p.pid,0)
    wall=time.time()-t0
    print(f"{name:20s} {done} prompts  wall {wall:6.1f} s  cpu {ru.ru_utime+ru.ru_stime:6.2f} s  peak RSS {ru.ru_maxrss/1024:6.1f} MiB  per-prompt {wall/done*1000:6.0f} ms")
