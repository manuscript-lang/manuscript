import pty, os, sys, time, select, struct, fcntl, termios, signal
N=int(sys.argv[1]) if len(sys.argv)>1 else 40
cli="/tmp/pijs/node_modules/@mariozechner/pi-coding-agent/dist/cli.js"
mock=["--provider","mock","--model","mock-model","--no-session"]
impls={
 "manuscript (native)":["/tmp/pi-ms","--no-session"],
 "node 22":["/opt/node22/bin/node",cli]+mock,
 "bun":["/root/.bun/bin/bun",cli]+mock,
}
def quiet(fd,idle,maxwait):
    got=0; last=time.time(); start=last
    while time.time()-start<maxwait:
        r,_,_=select.select([fd],[],[],0.05)
        if r:
            try: d=os.read(fd,65536)
            except OSError: return got
            if not d: return got
            got+=len(d); last=time.time()
        elif time.time()-last>idle: break
    return got
for name,cmd in impls.items():
    pid,fd=pty.fork()
    if pid==0:
        os.chdir("/tmp/pi-work")
        os.environ.update(ANTHROPIC_API_KEY="k",ANTHROPIC_BASE_URL="http://127.0.0.1:8099",TERM="xterm-256color",COLUMNS="100",LINES="30")
        os.execv(cmd[0],cmd)
    fcntl.ioctl(fd,termios.TIOCSWINSZ,struct.pack("HHHH",30,100,0,0))
    t0=time.time()
    quiet(fd,0.8,20)
    out=0
    for i in range(N):
        text=f"bash:echo turn {i}" if i%3==0 else f"message {i} about something"
        os.write(fd,text.encode()); quiet(fd,0.1,2)
        os.write(fd,b"\r"); out+=quiet(fd,0.4,15)
    for b in (b"\x03",b"\x03",b"\x04"):
        os.write(fd,b); quiet(fd,0.3,1)
    try: os.kill(pid,signal.SIGTERM)
    except ProcessLookupError: pass
    _,st,ru=os.wait4(pid,0)
    print(f"{name:20s} {N} turns  cpu {ru.ru_utime+ru.ru_stime:6.2f} s  peak RSS {ru.ru_maxrss/1024:6.1f} MiB  terminal bytes out {out/1024:8.1f} KiB")
