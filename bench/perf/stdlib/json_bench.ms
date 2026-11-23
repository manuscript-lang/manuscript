import (
	JsonValue, parse, stringify from "@std/data/json.ms",
	StringBuilder from "@std/string_builder.ms",
)

fn json_doc(count: Int) String:
	var sb = StringBuilder()
	sb.append("[")

	for i in 0..count:
		if i > 0: sb.append(",")
		sb.append(
			f"\{\"id\":{i},\"name\":\"user{i}\",\"tags\":[\"a\",\"b\"],\"score\":{i}.5,\"ok\":true\}"
		)

	sb.append("]")
	return sb.build()

fn encoded_length(value: JsonValue) Int:
	if text := stringify(value): return text.length()
	return 0

// Reads three nested fields of one row in place, without copying any subtree.
fn row_weight(tree: JsonValue, index: Int) Int:
	if row := tree.get_index(index):
		var weight = 0
		if id := row.get("id"):
			weight += id.as_int().get_or(0)
		if tags := row.get("tags"):
			if last := tags.get_index(-1):
				if tag := last.as_string():
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
