// conform: tags=testing,tier-stdlib
// conform: phase=check
import stringify from "@std/data/json.ms"

fn show[T](value T) String {
	return stringify(value).get_or("")
}

export fn main() Int {
	return show(1).length()
}
// expect-error: MS3000 6:12 T does not satisfy Data; it is a type parameter with no Data bound; add `T: Data` to the type parameter
