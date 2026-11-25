// conform: tags=testing,tier-core
// conform: phase=check
interface Copier {
	fn copies() List[Self]
}

export fn main() Int {
	return 0
}
// expect-error: MS3000 4:8 Self can only be a whole parameter or result type of an interface operation; write 'other: Self', not 'List[Self]'
