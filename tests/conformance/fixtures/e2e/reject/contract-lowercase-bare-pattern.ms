// conform: tags=testing,tier-core
// conform: phase=check
type item {
	n Int
}

interface Get {
	fn get() Int
}

fn item.get() Int => self.n

fn read(value Get) Int {
	match value {
		item => return 0
		_ => return 0
	}
}
// expect-error: MS3000 15:9 concrete type pattern requires exactly one receiver binding; write 'Type(name) => ...' or 'Type(_) => ...'
