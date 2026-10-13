package msruntime

// OptionalUnwrap is the checked direct-call path for Optional.unwrap. Bound
// methods and ordinary dispatch use the same extraction and fault behavior.
func OptionalUnwrap(ctx *Execution, receiver Value) Value {
	CheckCancelled(ctx)
	value := receiver.(Alternative)
	if value.Tag != "some" {
		return Panic("called Optional.unwrap() on none; check is_some() first, or use unwrap_or(fallback: ...) to supply a default")
	}
	result := value.Fields[0]
	CheckCancelled(ctx)
	return result
}

func init() {
	variables := []LibraryParam{{"T", ""}}
	for _, name := range []string{"is_some", "is_none", "unwrap", "unwrap_or", "unwrap_or_else"} {
		params := []LibraryParam{{"value", "Optional[T]"}}
		result := "T"
		switch name {
		case "is_some", "is_none":
			result = "Bool"
		case "unwrap_or":
			params = append(params, LibraryParam{"fallback", "T"})
		case "unwrap_or_else":
			params = append(params, LibraryParam{"create", "fn()->T"})
		}
		libraryGeneric("optional", name, result, variables, params, func(ctx *Execution, _ string, args []Value) Value {
			value := args[0].(Alternative)
			switch name {
			case "unwrap":
				return OptionalUnwrap(ctx, value)
			case "is_some":
				return value.Tag == "some"
			case "is_none":
				return value.Tag == "none"
			}
			if value.Tag == "some" {
				return value.Fields[0]
			}
			switch name {
			case "unwrap_or":
				return args[1]
			case "unwrap_or_else":
				return Invoke(ctx, args[1], nil)
			default:
				return OptionalUnwrap(ctx, value)
			}
		})
	}
	libraryGeneric("optional", "map", "Optional[U]", []LibraryParam{{"T", ""}, {"U", ""}}, []LibraryParam{{"value", "Optional[T]"}, {"transform", "fn(value:T)->U"}}, func(ctx *Execution, result string, args []Value) Value {
		value := args[0].(Alternative)
		if value.Tag == "none" {
			return Alternative{Type: result, Tag: "none"}
		}
		return Alternative{Type: result, Tag: "some", Fields: []Value{Invoke(ctx, args[1], []Argument{{"value", value.Fields[0]}})}}
	})
	libraryGeneric("optional", "and_then", "Optional[U]", []LibraryParam{{"T", ""}, {"U", ""}}, []LibraryParam{{"value", "Optional[T]"}, {"transform", "fn(value:T)->Optional[U]"}}, func(ctx *Execution, result string, args []Value) Value {
		value := args[0].(Alternative)
		if value.Tag == "none" {
			return Alternative{Type: result, Tag: "none"}
		}
		return Invoke(ctx, args[1], []Argument{{"value", value.Fields[0]}})
	})
	libraryGeneric("optional", "or_else", "Optional[T]", variables, []LibraryParam{{"value", "Optional[T]"}, {"create", "fn()->Optional[T]"}}, func(ctx *Execution, _ string, args []Value) Value {
		if args[0].(Alternative).Tag == "some" {
			return args[0]
		}
		return Invoke(ctx, args[1], nil)
	})
}
