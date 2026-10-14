package msruntime

import "strings"

// OptionalUnwrap is the checked direct-call path for Optional.unwrap. Bound
// methods and ordinary dispatch use the same extraction and fault behavior.
const unwrapNoneMessage = "called Optional.unwrap() on none; check is_some() first, or use unwrap_or(fallback: ...) to supply a default"

func OptionalUnwrap(ctx *Execution, receiver Value) Value {
	CheckCancelled(ctx)
	value := receiver.(Alternative)
	if value.Tag != "some" {
		return Panic(unwrapNoneMessage)
	}
	result := value.Fields[0]
	CheckCancelled(ctx)
	return result
}

// OptionalIsSome and OptionalUnwrapOr are the direct-call paths for the
// members of the same names; they share the library bodies' semantics.
func OptionalIsSome(ctx *Execution, receiver Value) bool {
	CheckCancelled(ctx)
	return receiver.(Alternative).Tag == "some"
}

func OptionalUnwrapOr(ctx *Execution, receiver, fallback Value) Value {
	CheckCancelled(ctx)
	if value := receiver.(Alternative); value.Tag == "some" {
		return value.Fields[0]
	}
	return fallback
}

func init() {
	variables := []LibraryParam{{"T", ""}}
	for _, name := range []string{"ok_or", "ok_or_else"} {
		params := []LibraryParam{{"value", "Optional[T]"}, {"cause", "Optional[E]"}}
		if name == "ok_or_else" {
			params[1] = LibraryParam{"create", "fn()->E"}
		}
		libraryGeneric("optional", name, "Result[T][E]", []LibraryParam{{"T", ""}, {"E", ""}}, params, func(ctx *Execution, result string, args []Value) Value {
			value := args[0].(Alternative)
			if value.Tag == "some" {
				return libraryOK(result, value.Fields[0])
			}
			cause := args[1]
			if name == "ok_or_else" {
				cause = Invoke(ctx, cause, nil)
			} else {
				cause = okOrCause(result, cause)
			}
			return Alternative{Type: result, Tag: "error", Fields: []Value{cause}}
		})
	}
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

// okOrCause unwraps an explicit cause. An omitted one becomes a MissingValue
// naming the calling source position, which only the absent path pays for.
func okOrCause(result string, cause Value) Value {
	if option, ok := cause.(Alternative); ok && strings.HasPrefix(option.Type, "@std/Optional[") {
		if option.Tag == "some" {
			return option.Fields[0]
		}
		cause = nil
	}
	if cause != nil {
		return cause
	}
	if !strings.HasSuffix(result, "MissingValue]") {
		return Panic("called Optional.ok_or() without a cause for an error type other than MissingValue")
	}
	location := "unknown location"
	if frames, _ := captureFrames(); len(frames) > 0 {
		location, _, _ = strings.Cut(frames[0], " in ")
	}
	return Alternative{Type: "@std/MissingValue", Tag: "Missing", Fields: []Value{location}}
}
