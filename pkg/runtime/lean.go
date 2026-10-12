//go:build ms_lean

package msruntime

// The lean runtime omits network, TLS, HTTP, WebSocket, system, and process
// control implementations and their native dependencies. The compiler selects
// it only for programs that import none of those standard modules, so these
// host values exist but their operations are unreachable.

const leanUnavailable = "this operation requires the full native runtime"

type network struct{}

// Every execution closes its host network root on exit.
func (*network) Operation(name string) Function {
	if name == "close" {
		return NewFunction(nil, "Unit", func(*Execution, []Value) Value { return Unit{} })
	}
	return NewFunction(nil, "Never", func(*Execution, []Value) Value { return Panic(leanUnavailable) })
}

type httpService struct{}

type libraryProcessControl struct{}

func (libraryProcessControl) Operation(string) Function {
	return NewFunction(nil, "Never", func(*Execution, []Value) Value { return Panic(leanUnavailable) })
}

func (*librarySystem) extended(*Execution, string, string, []Value) Value {
	return Panic(leanUnavailable)
}
