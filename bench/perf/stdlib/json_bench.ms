import JsonValue, parse, stringify from "@std/data/json.ms"

fn json_doc(count: Int) String:
	var sb = ""
	sb += "["

	for i in 0..count:
		if i > 0: sb += ","
		sb += f"\{\"id\":{i},\"name\":\"user{i}\",\"tags\":[\"a\",\"b\"],\"score\":{i}.5,\"ok\":true\}"

	sb += "]"
	return sb

fn encoded_length(value: JsonValue) Int:
	if text := stringify(value): return text.length()
	return 0

// Reads three nested fields of one row in place, without copying any subtree.
fn row_weight(tree: JsonValue, index: Int) Int:
	row := tree.get_index(index)

	if row != null:
		var weight = 0
		id := row.get("id")
		if id != null:
			weight += id.as_int() or 0

		tags := row.get("tags")

		if tags != null:
			last := tags.get_index(-1)

			if last != null:
				tag := last.as_string()
				if tag != null:
					weight += tag.length()

		return weight

	return 0

type BenchData:
	doc: String
	doc_2: String
	tree: JsonValue

fn make_fixture() BenchData:
	doc := json_doc(5000)
	doc_2 := json_doc(5000)
	tree := parse(json_doc(5000)).get()
	return BenchData(doc: doc, doc_2: doc_2, tree: tree)

bench "json.parse" per 5000:
	parse(fixture.doc).is_ok()

bench "json.roundtrip" per 5000:
	encoded_length(parse(fixture.doc_2).get())

bench "json.navigate" per 100000:
	var total = 0
	for i in 0..100000:
		total += row_weight(fixture.tree, i % 5000)
	total
