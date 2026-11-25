// `ms emit --opt` verifies the module after every pass (the ctest `mir_verify`); `ms build` does not, so a call whose
// declared parameter types disagree with its arguments only shows here. Map operations
// that lower to inline probes.
fn main() Void {
	var by_word Map[String, Int] = {}
	var by_id Map[Int, Int] = {}
	var wide Map[Int, List[Int]] = {}

	for word in "a b a".fields_by(c => c == " ") {
		by_word.update(word, 0, v => v + 1)
		by_id.update(word.length(), 0, v => v + 1)
	}

	wide[1] = [1, 2]
	print(by_word.get_or("a", 0) + by_id.get_or(1, 0) + wide.get_or(1, []).length())
	print(by_word.contains("b"))
}
