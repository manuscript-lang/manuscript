// conform: tags=ownership,control-flow,tier-core
// conform: phase=run
// A loop whose body moves its item on takes the local list's elements: no copy is made, and the list is consumed.
fn keep(move text String, var kept List[String]) Void {
	kept.append(text)
}

fn main() Void {
	var kept List[String] = []
	words := ["first heap text longer than any inline text", "second heap text longer than any inline text"]
	for word in words {
		keep(word, kept)
	}
	print(kept.length())
}
// expect-exit: 0
// expect-stdout: 2
