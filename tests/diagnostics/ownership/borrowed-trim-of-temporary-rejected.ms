// conform: tags=ownership
// conform: phase=check
// A trim borrows its receiver, and the receiver here is built by `slice` and dropped at the end
// of the statement, so the list would keep a view of freed text.
fn firsts(lines List[String]) List[String] {
	var out = List[String]()

	for line in lines {
		out.append(line.slice(1, line.length()).trim())
	}

	return out
}

fn main() Void {
	print(firsts([" a ", " b "]).length())
}
// expect-error: MS3000 9:49 `line.slice(..).trim(..)` borrows a temporary value that is gone when this statement ends; store `.clone()` of it
