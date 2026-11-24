// Guard: `String` order inlined for short strings of any form (static, inline, heap).
fn main() Void {
	words := ["apple", "banana", "cherry", "date", "elder", "fig", "grape"]
	var n = 0

	for i in 0..1000000 {
		w := words[i % 7]

		if w == "cherry" {
			n += 1
		} else if w < "c" {
			n += 2
		}
	}

	print(f"{n}")
}
