"""Splice C entries into `ms emit` output (prototype harness).

usage: splice.py <emitted.go> <cgen-dir> <out-dir>

Writes main.go: the emitted program with each compiled function replaced by a
cgo wrapper, the C source as its cgo preamble, and the fault helpers.
Build with CGO_ENABLED=1 inside the module so internal imports resolve.
"""
import json, re, sys

emitted, cdir, out = sys.argv[1:4]
go = open(emitted).read()
c = open(f"{cdir}/kernels.c").read()
entries = json.load(open(f"{cdir}/entries.json"))
GO = {"Int": ("int", "C.int64_t", "int(out)"), "Float": ("float64", "C.double", "float64(out)"), "Bool": ("bool", "C.bool", "bool(out)")}

for e in entries:
    name = e["Name"]
    m = re.search(r"^func %s\(ctx \*Execution([^)]*)\)([^{]*)\{\n" % re.escape(name), go, re.M)
    if not m:
        print("no Go function for", name, file=sys.stderr)
        continue
    end = go.index("\n}\n", m.end()) + 3
    params = "".join(f", {p['Name']} {GO[p['Type']][0]}" for p in e["Params"])
    args = ", ".join(f"{GO[p['Type']][1]}({p['Name']})" for p in e["Params"])
    if e["Result"] == "Unit":
        sig, body = " Unit", f"\tf := C.{e['CName']}(cancel{', ' + args if args else ''})\n\tcFault(ctx, f)\n\treturn Unit{{}}\n"
    else:
        t, ct, conv = GO[e["Result"]]
        sig = " " + t
        body = f"\tvar out {ct}\n\tf := C.{e['CName']}(cancel{', ' + args if args else ''}, &out)\n\tcFault(ctx, f)\n\treturn {conv}\n"
    wrapper = f"func {name}(ctx *Execution{params}){sig} {{\n\tcancel, stop := cCancel(ctx)\n\tdefer stop()\n{body}}}\n"
    go = go[: m.start()] + wrapper + go[end:]

go = go.replace("package main\n", "package main\n\n/*\n" + c.replace("*/", "* /") + "*/\nimport \"C\"\n", 1)
HELPERS = '''
// cCancel gives C a flag that turns on when ctx is cancelled.
func cCancel(ctx *Execution) (*C.int, func()) {
	flag := new(int32)
	stop := func() {}
	if ctx != nil && ctx.Context != nil && ctx.Context.Done() != nil {
		unstop := context.AfterFunc(ctx.Context, func() { atomic.StoreInt32(flag, 1) })
		stop = func() { unstop() }
	}
	return (*C.int)(unsafe.Pointer(flag)), stop
}

// cFault raises the fault a C entry reported, with the Go backend's message.
func cFault(ctx *Execution, f C.ms_fault) {
	switch f.code {
	case 0:
		return
	case 1:
		intOverflow()
	case 2:
		panic(cancelled{})
	case 3:
		IntDivide(int(f.a), int(f.b))
	case 4:
		IntRemainder(int(f.a), int(f.b))
	case 5:
		Raise("index " + FormatInt(int(f.a)) + " out of range for length " + FormatInt(int(f.b)) + "; pass a default: get(index:, default: ...)")
	case 6:
		indexFault("List.set", int(f.b), int(f.a))
	case 7:
		Raise("call depth limit exceeded (200000 nested calls)")
	}
	Raise("C backend fault")
}
'''
for needed in ("sync/atomic", "unsafe", "context"):
    if '\t"%s"\n' % needed not in go:
        go = go.replace('import (\n', 'import (\n\t"%s"\n' % needed, 1)
open(f"{out}/main.go", "w").write(go + HELPERS)
