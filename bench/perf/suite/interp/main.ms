// A stack bytecode VM running a nested-loop program: enum dispatch, a list as the
// stack.
enum Op:
	Push(v: Int)
	Load(slot: Int)
	Store(slot: Int)
	Add
	Mul
	Mod
	Lt
	Jz(to: Int)
	Jmp(to: Int)
	Halt

fn program(n: Int, m: Int) List[Op]:
	// total = 0; i = 0; while i < n: j = 0; while j < m: total += (i * j) % 7; j += 1;
	// i += 1
	return [
		Op.Push(0),
		Op.Store(0),
		Op.Push(0),
		Op.Store(1),
		Op.Load(1),
		Op.Push(n),
		Op.Lt,
		Op.Jz(33),
		Op.Push(0),
		Op.Store(2),
		Op.Load(2),
		Op.Push(m),
		Op.Lt,
		Op.Jz(28),
		Op.Load(0),
		Op.Load(1),
		Op.Load(2),
		Op.Mul,
		Op.Push(7),
		Op.Mod,
		Op.Add,
		Op.Store(0),
		Op.Load(2),
		Op.Push(1),
		Op.Add,
		Op.Store(2),
		Op.Jmp(10),
		Op.Halt,
		Op.Load(1),
		Op.Push(1),
		Op.Add,
		Op.Store(1),
		Op.Jmp(4),
		Op.Halt,
	]

fn run(code: List[Op]) Int:
	var stack = List[Int]()
	var vars = [0, 0, 0, 0]
	var pc = 0
	var steps = 0

	while true:
		steps += 1

		match code[pc]:
			Push(v):
				stack.append(v)
				pc += 1
			Load(slot):
				stack.append(vars[slot])
				pc += 1
			Store(slot):
				vars[slot] = stack.pop().get(0)
				pc += 1
			Add:
				b := stack.pop().get(0)
				a := stack.pop().get(0)
				stack.append(a + b)
				pc += 1
			Mul:
				b := stack.pop().get(0)
				a := stack.pop().get(0)
				stack.append(a * b)
				pc += 1
			Mod:
				b := stack.pop().get(0)
				a := stack.pop().get(0)
				stack.append(a % b)
				pc += 1
			Lt:
				b := stack.pop().get(0)
				a := stack.pop().get(0)
				stack.append(if a < b: 1 else: 0)
				pc += 1
			Jz(to):
				c := stack.pop().get(0)
				pc = if c == 0: to else: pc + 1
			Jmp(to):
				pc = to
			Halt:
				break

	print("steps {steps}")
	return vars[0]

fn main() Unit:
	print("total {run(program(3000, 2000))}")
