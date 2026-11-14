// conform: tags=scope-cleanup,tier-core
// conform: phase=run
type Handle:
	id: Int

fn var Handle.close() Unit!:
	print("close {self.id}")

// The callee owns the handle only on the path that returns it; the other paths close it.
fn keep(h: Handle, flag: Bool) Handle?:
	if flag: return h
	return none

fn id_or_zero(h: Handle, flag: Bool) Int:
	if flag:
		moved := h
		return moved.id
	return 0

export fn main() Int:
	print("keep none")
	a := keep(Handle(1), false)
	print(a.is_none())
	print("keep some")
	b := keep(Handle(2), true)
	print(b.is_some())
	print("id_or_zero")
	print(id_or_zero(Handle(3), false))
	print(id_or_zero(Handle(4), true))
	print("end")
	return 0
