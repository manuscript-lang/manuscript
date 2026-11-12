// conform: tags=lists,tier-core
// conform: phase=check
// conform: origin=lent-collection-views
// `slice`, `keys` and `values` lend their receiver: keeping the result needs `.clone()`.
type Page:
	rows: List[Int]

fn keep_rows(xs: List[Int]) Page:
	return Page(xs.slice(0, 2).get())

fn kept_keys(m: Map[String, Int]) List[String]:
	return m.keys()

fn kept_values(m: Map[String, Int]) List[Int]:
	return m.values()

fn mutate_while_used(m: Map[String, Int]) Int:
	var table = m.clone()
	names := table.keys()
	table["x"] = 1
	return names.length()
