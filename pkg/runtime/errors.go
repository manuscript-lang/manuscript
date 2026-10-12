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
			if cause.Type == "@std/LogError" && (cause.Tag == "Io" || cause.Tag == "FileSystem") {
				return Invoke(ctx, Bind(cause.Fields[0], "@std/Error", "message"), nil)
			}
			return strings.TrimPrefix(cause.Type, "@std/") + "." + cause.Tag
		})
	}},
}

// StandardRegistration is a checked standard implementation that generated
// programs register as data rather than as one closure each.
type StandardRegistration struct {
	Receiver, Contract, Name, Scope string
	Variables                       []string
	Native                          string
}

func RegisterStandard(entries []StandardRegistration) {
	for _, entry := range entries {
		native := entry.Native
		Register(Implementation{Receiver: entry.Receiver, Contract: entry.Contract, Name: entry.Name, Scope: entry.Scope, Variables: entry.Variables, Build: func(receiver Value, _ map[string]string, _ map[string]TypeScope) Function {
			return StandardImplementation(native, receiver)
		}})
	}
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
