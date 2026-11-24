// conform: tags=testing,tier-stdlib
// conform: phase=check
import stringify from "@std/data/json.ms"

fn show[T](value T) String {
	return stringify(value).get_or("")
}

export fn main() Int {
	return show(1).length()
}
