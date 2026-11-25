// conform: tags=mutation,lists,control-flow,diagnostics,tier-core
// conform: phase=check
// A `for` loop keeps the list it walks unchangeable until the body ends: growing it, reassigning it, or
// changing it behind a nested loop's `break` all invalidate the elements the loop reads.
fn grow() Int {
	var xs = ["a", "b"]
	for x in xs {
		xs.append(x.clone())
	}
	return xs.length()
}

fn replace() Void {
	var xs = ["aaaaaaaaaaaaaaaaaaaaaaaa", "bbbbbbbbbbbbbbbbbbbbbbbbbbb"]
	for x in xs {
		xs = ["z"]
		print(x)
	}
}

fn inner_break() Void {
	var xs = ["a", "b"]
	for x in xs {
		for j in 0..2 {
			if j == 1 {
				xs.append("z")
				break
			}
		}
	}
}

fn use_before_exit() Void {
	var xs = ["a", "b"]
	for x in xs {
		if x == "a" {
			xs.append("z")
			print(x)
			break
		}
	}
}
