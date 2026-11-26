// conform: tags=diagnostics
// conform: phase=check
fn probe() String {
	var b = List[String]()
	var i = 0

	while i < 321 {
		b.append("x")
		i += 1
	}

	return b.freeze()
}
// expect-error: MS2001 12:14 unknown or ambiguous member freeze on List[String]; available starting with 'f': fill, filter, find, find_index, find_last, find_last_index, first, flat_map, fold, fold_right, for_each; 70 members in total
