package msruntime

func init() {
	variables := []LibraryParam{{"T", ""}, {"E", ""}}
	for _, name := range []string{"is_ok", "is_error", "unwrap", "unwrap_error", "unwrap_or", "unwrap_or_else"} {
		params := []LibraryParam{{"value", "Result[T][E]"}}
		result := "T"
		switch name {
		case "is_ok", "is_error":
			result = "Bool"
		case "unwrap_error":
			result = "E"
		case "unwrap_or":
			params = append(params, LibraryParam{"fallback", "T"})
		case "unwrap_or_else":
			params = append(params, LibraryParam{"create", "fn(cause:E)->T"})
		}
		libraryGeneric("result", name, result, variables, params, func(ctx *Execution, _ string, args []Value) Value {
			value := args[0].(Alternative)
			switch name {
			case "is_ok":
				return value.Tag == "ok"
			case "is_error":
				return value.Tag == "error"
			case "unwrap_error":
				if value.Tag != "error" {
					return Panic("called Result.unwrap_error() on ok; check is_error() first")
				}
				return value.Fields[0]
			}
			if value.Tag == "ok" {
				return value.Fields[0]
			}
			switch name {
			case "unwrap_or":
				return args[1]
			case "unwrap_or_else":
				return Invoke(ctx, args[1], []Argument{{"cause", value.Fields[0]}})
			default:
				return Panic("called Result.unwrap() on error; check is_ok() first, or use unwrap_or(fallback: ...) to supply a default")
			}
		})
	}
	for _, name := range []string{"map", "and_then"} {
		callbackResult := "U"
		if name == "and_then" {
			callbackResult = "Result[U][E]"
		}
		libraryGeneric("result", name, "Result[U][E]", []LibraryParam{{"T", ""}, {"E", ""}, {"U", ""}}, []LibraryParam{{"value", "Result[T][E]"}, {"transform", "fn(value:T)->" + callbackResult}}, func(ctx *Execution, result string, args []Value) Value {
			value := args[0].(Alternative)
			if value.Tag == "error" {
				// Only the success type changes; retain the exact error payload.
				return Alternative{Type: result, Tag: "error", Fields: value.Fields}
			}
			mapped := Invoke(ctx, args[1], []Argument{{"value", value.Fields[0]}})
			if name == "and_then" {
				return mapped
			}
			return libraryOK(result, mapped)
		})
	}
}
