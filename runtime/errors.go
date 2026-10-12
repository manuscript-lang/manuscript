package msruntime

import "strings"

// NativeImplementationSpec describes a source-declared native implementation.
// The checker verifies its method signature alongside native functions.
type NativeImplementationSpec struct {
	Name, Result string
	Params       []LibraryParam
	Build        func(Value) Function
}

var NativeImplementations = []NativeImplementationSpec{
	{"errors/message", "String", nil, func(receiver Value) Function {
		return NewFunction(nil, "String", func(ctx *Execution, _ []Value) Value {
			cause := receiver.(Alternative)
			if cause.Tag == "Failed" && len(cause.Fields) == 1 {
				return cause.Fields[0].(string)
			}
			if cause.Tag == "Crashed" && len(cause.Fields) == 2 {
				return cause.Fields[1].(string)
			}
			if cause.Type == "@std/LogError" && cause.Tag == "Io" {
				return Invoke(ctx, Bind(cause.Fields[0], "@std/Error", "message"), nil)
			}
			return strings.TrimPrefix(cause.Type, "@std/") + "." + cause.Tag
		})
	}},
}

func StandardImplementation(name string, receiver Value) Function {
	for _, spec := range NativeImplementations {
		if spec.Name == name {
			return spec.Build(receiver)
		}
	}
	Panic("unavailable standard implementation " + name)
	return Function{}
}

func init() {
	libraryGeneric("errors", "as_error", "Error", []LibraryParam{{"E", "Error"}}, []LibraryParam{{"cause", "E"}}, func(_ *Execution, _ string, args []Value) Value {
		return ViewOf("@std/Error", args[0])
	})
}
