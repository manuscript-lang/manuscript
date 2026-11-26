// conform: tags=scope-cleanup,control-flow,records,tier-io
// conform: phase=run
// conform: origin=close-gap-probes
import Closeable from "@std/core.ms"

type Door {
	name String
}

fn move Door.close() Void! {
	print(f"closed {self.name}")
}

fn Door.id() Int {
	return 1
}

type Pair {
	left Door
	n Int
}

fn open_handle(name String) Door {
	return Door(name.clone())
}

fn consume(move d Door) Int {
	owned := d
	return owned.id()
}

fn ret_or_fall(c Bool) Int {
	h := open_handle("ret-or-fall")
	if c {
		return consume(h)
	}

	return 0
}

fn arg_in_branch(c Bool) Int {
	h := open_handle("arg-branch")
	if c {
		consume(h)
	}
	return 0
}

fn into_record(c Bool) Int {
	h := open_handle("into-record")

	if c {
		p := Pair(h, 1)
		return p.n
	}

	return 0
}

fn in_loop(n Int) Int {
	var total = 0

	for i in 0..n {
		h := open_handle(f"loop-{i}")
		if i % 2 == 0 {
			total += consume(h)
		}
	}

	return total
}

fn moved_always() Int {
	h := open_handle("always")
	return consume(h)
}

fn returned(c Bool) Door {
	h := open_handle("returned")
	if c {
		return h
	}

	return open_handle("other")
}

fn else_branch(c Bool) Int {
	h := open_handle("else")

	if c {
		return 0
	} else {
		return consume(h)
	}
}

fn main() Void {
	ret_or_fall(true)
	print("--ret_or_fall false")
	ret_or_fall(false)
	print("--arg_in_branch true")
	arg_in_branch(true)
	print("--arg_in_branch false")
	arg_in_branch(false)
	print("--into_record true")
	into_record(true)
	print("--into_record false")
	into_record(false)
	print("--in_loop")
	in_loop(4)
	print("--moved_always")
	moved_always()
	print("--returned true")

	_r := returned(true)
	print("--returned false")

	_r2 := returned(false)
	print("--else true")
	else_branch(true)
	print("--else false")
	else_branch(false)
	print("--end")
}
// expect-exit: 0
// expect-stdout: closed ret-or-fall
// expect-stdout: --ret_or_fall false
// expect-stdout: closed ret-or-fall
// expect-stdout: --arg_in_branch true
// expect-stdout: closed arg-branch
// expect-stdout: --arg_in_branch false
// expect-stdout: closed arg-branch
// expect-stdout: --into_record true
// expect-stdout: closed into-record
// expect-stdout: --into_record false
// expect-stdout: closed into-record
// expect-stdout: --in_loop
// expect-stdout: closed loop-0
// expect-stdout: closed loop-1
// expect-stdout: closed loop-2
// expect-stdout: closed loop-3
// expect-stdout: --moved_always
// expect-stdout: closed always
// expect-stdout: --returned true
// expect-stdout: --returned false
// expect-stdout: closed returned
// expect-stdout: --else true
// expect-stdout: closed else
// expect-stdout: --else false
// expect-stdout: closed else
// expect-stdout: --end
// expect-stdout: closed other
// expect-stdout: closed returned
