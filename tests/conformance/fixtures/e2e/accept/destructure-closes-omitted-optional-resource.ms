// conform: tags=destructuring,scope-cleanup,tier-core
// conform: phase=run
// Destructuring closes the resource fields it does not name, also when the field is an
// `Optional` or a `List` of resources, in a local, a parameter and a returning function.
type Handle:
	id: Int

fn var Handle.close() Unit!:
	print("close {self.id}")

type Job:
	label: String
	input: Handle
	spare: Handle?
	more: List[Handle]

fn keep(job: Job, var out: List[Handle]) Unit:
	{input} := job
	out.append(input)
	print("keep end")

fn take(job: Job) Handle:
	{input} := job
	return input

export fn main() Int:
	var out = List[Handle]()
	print("local")
	local := Job("a", Handle(1), Handle(2), [Handle(3)])
	{input} := local
	out.append(input)
	print("none")
	empty := Job("b", Handle(4), none, [])
	{input: kept} := empty
	out.append(kept)
	print("param")
	keep(Job("c", Handle(5), Handle(6), [Handle(7)]), var out)
	print("return")
	moved := take(Job("d", Handle(8), Handle(9), []))
	print("end {out.length()} {moved.id}")
	return 0
