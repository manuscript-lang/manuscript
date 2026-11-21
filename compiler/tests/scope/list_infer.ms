type Item:
	id: Int

fn empty_unannotated() Int:
	xs := []
	return 1

fn empty_in_return() List[Int]:
	return []

fn records() Int:
	items := [Item(id: 1), Item(id: 2)]
	first := items[0]
	return first.id

fn names() String:
	words := ["a", "b"]
	return words[1]

fn main() Int:
	return (
		records()
		+ names().length()
		+ empty_in_return().length()
		+ empty_unannotated()
	)
