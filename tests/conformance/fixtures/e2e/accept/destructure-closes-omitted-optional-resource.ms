// conform: tags=destructuring,scope-cleanup,tier-core
// conform: phase=run
// Destructuring closes the resource fields it does not name, also when the field is an
// `Optional` or a `List` of resources, in a local, a parameter and a returning function.
type Handle:
	id: Int

fn move Handle.close() Void!:
	print(f"close {self.id}")

type Job:
	label: String
	input: Handle
	more: List[Handle]
	spare: Handle?

fn keep(job: Job, var out: List[Handle]) Void:
	{input} := job
	out.append(input)
	print("keep end")

fn take(job: Job) Handle:
	{input} := job
	return input

export fn main() Int:
	var out = List[Handle]()
	print("local")
	local := Job(label: "a", input: Handle(1), spare: Handle(2), more: [Handle(3)])
	{input} := local
	out.append(input)
	print("none")
	empty := Job(label: "b", input: Handle(4), spare: null, more: [])
	{input: kept} := empty
	out.append(kept)
	print("param")
	keep(Job(label: "c", input: Handle(5), spare: Handle(6), more: [Handle(7)]), out)
	print("return")
	moved := take(Job(label: "d", input: Handle(8), spare: Handle(9), more: []))
	print(f"end {out.length()} {moved.id}")
	return 0
