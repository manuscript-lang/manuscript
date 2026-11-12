// conform: tags=strings,tier-core
// conform: phase=run
// conform: origin=string-edit-take
// trim, upper, lower and replace of a String that is never used again edit its allocation in
// place; every shape must produce exactly what the copying call produces.

fn edit_last(s: String) String:
	return s.trim().upper().replace("WORLD", "there")

fn borrowed_twice(s: String) Int:
	a := s.trim()
	b := s.upper()
	return a.length() + b.length()

fn shrink_to_short(s: String) String:
	return s.replace("a long run of text", "x")

export fn main() Int:
	print("[" + edit_last("   hello world, a heap string past the inline size   ") + "]")
	print("[" + edit_last("   héllo world, non ascii past the inline size   ") + "]")
	print("[" + edit_last("  short  ") + "]")
	print(borrowed_twice("   kept by the caller, longer than the inline size   "))
	print(shrink_to_short("a long run of text and a long run of text"))
	print(shrink_to_short("no match here, but a string past the inline size"))
	print("ABC def GHI jkl MNO pqr STU".lower().replace(" ", ""))
	print("ABC def GHI jkl MNO pqr STU".lower().replace("", "-"))
	print("ΑΣ ΟΔΥΣΣΕΥΣ and more text".lower())
	print("straße and more text past inline".upper())
	print("  left only, a heap string past the inline size".trim_start())
	print("right only, a heap string past the inline size   ".trim_end() + "|")
	print("[" + "      ".trim() + "]")
	print("[" + "   a heap string of only whitespace padding past inline   ".trim().length().to_string() + "]")
	print("aaaa bbbb aaaa bbbb aaaa bbbb".replace("aaaa", "cc").replace("bbbb", "ddd"))
	print("grow the text, a heap string past inline".replace("text", "much longer text"))
	var total = 0
	for i in 0..1000:
		line := "  Hello, World number {i}  "
		total += line.trim().replace("World", "there").upper().length()
	print(total)
	return 0
