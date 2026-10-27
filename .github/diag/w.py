import lldb
t = lldb.debugger.GetSelectedTarget()
p = t.GetProcess()
th = p.GetSelectedThread()
f = th.GetFrameAtIndex(1)
sp = f.GetSP()
err = lldb.SBError()
found = 0
for a in range(sp, sp + 0x800, 8):
    v = p.ReadUnsignedFromMemory(a, 8, err)
    if err.Fail() or v < 0x10000:
        continue
    w1 = p.ReadUnsignedFromMemory(v + 8, 8, err)
    if err.Fail() or w1 != 0x8000000000000001:
        continue
    w3 = p.ReadUnsignedFromMemory(v + 24, 8, err)
    if err.Fail() or w3 != 0x8000000000000002:
        continue
    print("LIST at 0x%x (slot 0x%x)" % (v, a))
    wp = t.WatchAddress(v + 16, 8, False, True, err)
    print("watch", wp.IsValid(), err.GetCString())
    found = v
    break
print("found", found)
