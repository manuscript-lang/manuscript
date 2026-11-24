import (
	SortedMap from "@std/collections/sorted.ms",
	sqrt from "@std/math/math.ms",
	monotonic from "@std/time.ms",
)

enum Instr {
	Load(r, v Int)
	AddR(a, b Int)
	SubR(a, b Int)
	MulR(a, b Int)
	Jnz(r, target Int)
	Dec(r Int)
	Xor(a, b Int)
	Halt
}

enum State {
	Idle
	Running(ticks Int)
	Blocked(on Int)
	Done
}

type Shape2 {
	w, h Int
}

fn Shape2.area() Int {
	return self.w * self.h
}

interface Sized {
	fn area() Int
}

type Inventory {
	name String
	counts List[Int]
	tags List[String]
}

fn lcg(x Int) Int {
	return (x * 1103515245 + 12345) % 2147483648
}

fn stop(name String, t0, chk Int) Void {
	now := monotonic().tick
	print(f"{name} {(now - t0) / 1000} {chk}")
}

fn y_vm() Int {
	prog := [
		Instr.Load(0, 3000000),
		Instr.Load(1, 0),
		Instr.AddR(1, 0),
		Instr.Load(2, 7),
		Instr.MulR(1, 2),
		Instr.Load(3, 1000003),
		Instr.Xor(1, 3),
		Instr.Dec(0),
		Instr.Jnz(0, 2),
		Instr.Halt,
	]
	var regs List[Int] = [0, 0, 0, 0]
	var pc = 0
	var steps = 0

	while true {
		steps += 1

		match prog[pc] {
			Load(r, v) => {
				regs[r] = v
				pc += 1
			}
			AddR(a, b) => {
				regs[a] = (regs[a] + regs[b]) % 1000000007
				pc += 1
			}
			SubR(a, b) => {
				regs[a] -= regs[b]
				pc += 1
			}
			MulR(a, b) => {
				regs[a] = (regs[a] * regs[b]) % 1000000007
				pc += 1
			}
			Jnz(r, target) => {
				if regs[r] != 0 {
					pc = target
				} else {
					pc += 1
				}
			}
			Dec(r) => {
				regs[r] -= 1
				pc += 1
			}
			Xor(a, b) => {
				regs[a] = (regs[a] + regs[b]) % 1000000007
				pc += 1
			}
			Halt => break
		}
	}

	return regs[1] + steps
}

fn y_state_machine() Int {
	var s = State.Idle
	var t = 0

	for i in 0..20000000 {
		match s {
			Idle => s = State.Running(0)
			Running(k) => {
				if k > 5 {
					s = State.Blocked(i % 7)
				} else {
					s = State.Running(k + 1)
				}
			}
			Blocked(on) => {
				t += on
				s = if i % 3 == 0 {
					State.Done
				} else {
					State.Blocked(on + 1)
				}
			}
			Done => {
				t += 1
				s = State.Idle
			}
		}
	}

	return t
}

fn cmd_code(s String) Int {
	match s {
		"push" => return 1
		"pop" => return 2
		"add" => return 3
		"sub" => return 4
		"dup" => return 5
		"swap" => return 6
		"jump" => return 7
		_ => return 0
	}
}

fn y_match_string() Int {
	words := ["push", "pop", "add", "sub", "dup", "swap", "jump", "nop"]
	var t = 0
	for i in 0..10000000 {
		t += cmd_code(words[i % 8])
	}
	return t
}

fn y_matmul() Int {
	n := 200
	var a List[List[Float]] = []
	var b List[List[Float]] = []

	for i in 0..n {
		var ra List[Float] = []
		var rb List[Float] = []

		for j in 0..n {
			ra.append((i + j).to_float() * 0.5)
			rb.append((i - j).to_float() * 0.25)
		}

		a.append(ra)
		b.append(rb)
	}

	var c List[List[Float]] = []

	for i in 0..n {
		var rc List[Float] = []

		for j in 0..n {
			var s = 0.0
			for k in 0..n {
				s += a[i][k] * b[k][j]
			}
			rc.append(s)
		}

		c.append(rc)
	}

	return (c[17][33].truncate_to_int() or 0 + (c[199][199].truncate_to_int() or 0))
}

fn y_sieve() Int {
	n := 20000000
	var sieve List[Bool] = []
	for i in 0..n + 1 {
		sieve.append(true)
	}

	var i = 2

	while i * i <= n {
		if sieve[i] {
			var j = i * i

			while j <= n {
				sieve[j] = false
				j += i
			}
		}

		i += 1
	}

	var c = 0
	for k in 2..n + 1 {
		if sieve[k] { c += 1 }
	}
	return c
}

fn y_sorted_map() Int {
	var m = SortedMap[Int, Int]()
	var x = 1

	for i in 0..200000 {
		x = lcg(x)
		m.add(x % 1000000, i)
	}

	var t = 0
	for i in 0..200000 {
		t += m.get_or(i * 5, 0)
	}
	return t + m.length()
}

fn total_area[T Sized](xs List[T]) Int {
	var t = 0
	for v in xs {
		t += v.area()
	}
	return t
}

fn y_generic_bound() Int {
	var xs List[Shape2] = []
	for i in 0..1000000 {
		xs.append(Shape2(i % 10, i % 7))
	}

	var t = 0
	for r in 0..20 {
		t += total_area(xs)
	}
	return t
}

fn y_clone_records() Int {
	var base = Inventory("widget", [1, 2, 3, 4, 5, 6, 7, 8], ["a", "b", "c"])
	var t = 0

	for i in 0..1000000 {
		var c = base.clone()
		c.counts[i % 8] = c.counts[i % 8] + i
		t += c.counts[i % 8] + c.tags.length()
	}

	return t
}

fn y_optional_ints() Int {
	var xs List[Int?] = []

	for i in 0..2000000 {
		if i % 3 == 0 {
			xs.append(null)
		} else {
			xs.append(i)
		}
	}

	var t = 0

	for r in 0..10 {
		for v in xs {
			x := v
			if x != null {
				t += x
			}
		}
	}

	return t
}

fn y_stats() Int {
	var xs List[Float] = []
	var x = 1

	for i in 0..2000000 {
		x = lcg(x)
		xs.append((x % 10000).to_float() / 100.0)
	}

	var t = 0.0

	for r in 0..10 {
		mean := xs.sum() / xs.length().to_float()
		v := (
			xs.fold(0.0, (acc, e) => acc + (e - mean) * (e - mean))
			/ xs.length().to_float()
		)
		t += sqrt(v)
	}

	return t.truncate_to_int() or 0
}

fn run(name String, f fn() Int) Void {
	t0 := monotonic().tick
	c := f()
	stop(name, t0, c)
}

fn main() Void {
	run("y_vm", y_vm)
	run("y_state_machine", y_state_machine)
	run("y_match_string", y_match_string)
	run("y_matmul", y_matmul)
	run("y_sieve", y_sieve)
	run("y_sorted_map", y_sorted_map)
	run("y_generic_bound", y_generic_bound)
	run("y_clone_records", y_clone_records)
	run("y_optional_ints", y_optional_ints)
	run("y_stats", y_stats)
}
