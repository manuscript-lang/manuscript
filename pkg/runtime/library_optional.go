package msruntime

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
				return Panic("called Optional.unwrap() on none")
			}
		})
	}
}
