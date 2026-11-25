// conform: tags=lists,tier-core
// conform: phase=check
// conform: origin=lent-collection-views
// `slice`, `keys` and `values` lend their receiver: keeping the result needs `.clone()`.
type Page {
	rows List[Int]
}

fn keep_rows(xs List[Int]) Page {
	return Page(xs.slice(0, 2).get())
}

fn kept_keys(hold m Map[String, Int]) &List[String] {
	return m.keys()
}

fn kept_values(hold m Map[String, Int]) &List[Int] {
	return m.values()
}

fn mutate_while_used(m Map[String, Int]) Int {
	var table = m.clone()
	names := table.keys()
	table["x"] = 1
	return names.length()
}
// expect-error: MS3000 10:32 `slice` borrows `xs`, which this position would keep; store `.clone()` of it, or use it in place
// expect-error: MS3000 14:14 `keys` borrows `m`, which this position would keep; store `.clone()` of it, or use it in place
// expect-error: MS3000 18:14 `values` borrows `m`, which this position would keep; store `.clone()` of it, or use it in place
// expect-error: MS3000 24:5 cannot change `table` while `names` borrows it (binding of a part of it, at 23:5); finish using `names` before this, or give `names` its own value by ending its initializer with `.clone()`
