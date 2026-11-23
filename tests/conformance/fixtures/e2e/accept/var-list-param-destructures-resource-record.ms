// conform: tags=control-flow,scope-cleanup,tier-stdlib,testing
// conform: phase=run
import panic from "@std/core.ms"

type Res:
	id: Int

fn move Res.close() Void!:
	print(f"close {self.id}")

type Job:
	input: Res

fn first(var from: List[Job]) Int:
	j := from.pop() or panic("called Optional.get() on null")
	{input} := j
	return input.id

fn moved(var from: List[Job], var to: List[Res]) Int:
	j := from.pop() or panic("called Optional.get() on null")
	{input} := j
	to.append(input)
	return from.length() + to.length()

export fn main() Int:
	var a = [Job(Res(1))]
	print(first(a))
	print(a.length())

	var b = [Job(Res(2)), Job(Res(3))]
	var c: List[Res] = []
	print(moved(b, c))
	print(f"{b.length()} {c.length()}")
	return 0
