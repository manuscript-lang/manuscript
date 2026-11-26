// conform: tags=strings,tier-core
// conform: phase=run
fn size(text String) Int {
	return text.length()
}

fn main() Void {
	// A name bound to a `var` that is not assigned again reads that variable in a loop.
	var json = ""
	json += "["

	for i in 0..3 {
		if i > 0 { json += "," }
		json += "1"
	}

	json += "]"

	text := json
	var total = 0
	for i in 0..3 {
		total += size(text)
	}
	print(total)
}
// expect-exit: 0
// expect-stdout: 21
