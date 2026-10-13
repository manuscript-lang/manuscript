package msruntime

func init() {
	libraryAdd("http", "header_values", "Optional[List[String]]", []LibraryParam{{"headers", "Map[String][List[String]]"}, {"name", "String"}}, func(_ *Execution, result string, args []Value) Value {
		values := NewList("@std/List[String]", nil)
		present := false
		for _, entry := range args[0].(*Map).Entries {
			if httpHeaderNameEqual(entry.Key.(string), args[1].(string)) {
				present = true
				values.appendList(entry.Value.(*List))
			}
		}
		if !present {
			return Alternative{result, "none", nil}
		}
		return Alternative{result, "some", []Value{values}}
	})
	libraryAdd("http", "request_header", "Optional[Bytes]", []LibraryParam{{"request", "HttpRequest"}, {"name", "String"}}, func(_ *Execution, result string, args []Value) Value {
		headers := args[0].(Record).Fields["headers"].(*Map)
		for _, entry := range headers.Entries {
			if httpHeaderNameEqual(entry.Key.(string), args[1].(string)) {
				return Alternative{result, "some", []Value{entry.Value}}
			}
		}
		return Alternative{result, "none", nil}
	})
}

// HTTP field names use ASCII folding, not Unicode case equivalence.
func httpHeaderNameEqual(left, right string) bool {
	if len(left) != len(right) {
		return false
	}
	for i := range len(left) {
		a, b := left[i], right[i]
		if a >= 'A' && a <= 'Z' {
			a += 'a' - 'A'
		}
		if b >= 'A' && b <= 'Z' {
			b += 'a' - 'A'
		}
		if a != b {
			return false
		}
	}
	return true
}
