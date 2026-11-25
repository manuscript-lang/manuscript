// conform: tags=testing,tier-core
// conform: phase=check
// A view cannot be stored where an owner is needed: `.clone()` keeps the text.
export fn main() Int {
	text := "hello world"
	var words = List[String]()
	words.append(text.view(0, 5))
	return words.length()
}
// expect-error: MS3000 7:23 `view` borrows `text`, which this position would keep; store `.clone()` of it, or use it in place
