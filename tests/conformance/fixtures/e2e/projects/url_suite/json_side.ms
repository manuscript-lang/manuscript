import JsonValue, parse from "@std/data/json.ms"

// One test case of the Go table dump: its string and bool fields, and for query cases
// its expected map as `key=v1,v2` pairs.
export type Case:
	fields: Map[String, String]
	flags: Map[String, Bool]
	expected: Map[String, List[String]]

export fn cases(source: String, table: String) List[Case]!:
	root := parse(source)?
	var out: List[Case] = []
	items := (root.get(table).clone() or JsonValue.Null).as_list() or []

	for item in items:
		var fields = Map[String, String]()
		var flags = Map[String, Bool]()
		var expected = Map[String, List[String]]()

		for entry in (item.as_map() or Map[String, JsonValue]()).entries():
			str := entry.value.as_string()

			if str != null:
				fields.add(entry.key.clone(), str.clone())
			else if flag := entry.value.as_bool():
				flags.add(entry.key.clone(), flag)
			else if members := entry.value.as_map():
				for member in members.entries():
					var values: List[String] = []
					for value in (member.value.as_list() or []):
						values.append((value.as_string() or "").clone())
					expected.add(member.key.clone(), values)

		out.append(Case(fields: fields, flags: flags, expected: expected))

	return ok(out)
