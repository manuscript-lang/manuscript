// conform: tags=scope-cleanup,tier-core
// conform: phase=run
type Handle {
	id Int
}

fn move Handle.close() Void! {
	print(f"close {self.id}")
}

// The callee owns the handle only on the path that returns it; the other paths close
// it.
fn keep(move h Handle, flag Bool) Handle? {
	if flag { return h }
	return null
}

fn id_or_zero(move h Handle, flag Bool) Int {
	if flag {
		moved := h
		return moved.id
	}

	return 0
}

export fn main() Int {
	print("keep none")

	a := keep(Handle(1), false)
	print(a == null)
	print("keep some")

	b := keep(Handle(2), true)
	print(b != null)
	print("id_or_zero")
	print(id_or_zero(Handle(3), false))
	print(id_or_zero(Handle(4), true))
	print("end")
	return 0
}
// expect-exit: 0
// expect-stdout: keep none
// expect-stdout: close 1
// expect-stdout: true
// expect-stdout: keep some
// expect-stdout: true
// expect-stdout: id_or_zero
// expect-stdout: close 3
// expect-stdout: 0
// expect-stdout: close 4
// expect-stdout: 4
// expect-stdout: end
// expect-stdout: close 2
