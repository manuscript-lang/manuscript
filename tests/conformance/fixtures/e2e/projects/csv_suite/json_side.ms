import JsonValue, parse from "@std/data/json.ms"

// The records of a csv-spectrum `.json` file as string maps.
export fn records(text: String) List[Map[String, String]]!:
	var out: List[Map[String, String]] = []
	root := parse(text)?
	list := root.as_list().get_or([])

	for item in list:
		var record = Map[String, String]()
		for entry in item.as_map().get_or(Map[String, JsonValue]()).entries():
			record.add(entry.key.clone(), entry.value.as_string().get_or("").clone())
		out.append(record)

	return ok(out)
