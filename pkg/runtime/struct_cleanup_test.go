package msruntime

import (
	"reflect"
	"testing"
)

type cleanupProbeStruct struct{ testPoint }

func (*cleanupProbeStruct) StructType() string { return "cleanup-review#Resource" }

func TestCleanupSelectsCloseableWithCompetingClose(t *testing.T) {
	const typ = "cleanup-review#Resource"
	events := []string{}
	register := func(contract, event string) {
		Register(Implementation{Receiver: typ, Contract: contract, Name: "close", Build: func(Value, map[string]string, map[string]TypeScope) Function {
			return NewFunction(nil, "Unit", func(*Execution, []Value) Value { events = append(events, event); return Unit{} })
		}})
	}
	// The competing interface is registered first, so wildcard lookup is an
	// independently observable failure rather than a shared dispatch oracle.
	register("cleanup-review#Other", "other")
	register("@std/Closeable", "closeable")
	ctx := RootExecution()
	defer FinishExecution(ctx)
	for name, resource := range map[string]Value{
		"typed record":      &cleanupProbeStruct{},
		"map-backed record": Record{Type: typ, Fields: map[string]Value{}},
		"alternative":       Alternative{Type: typ, Tag: "resource"},
	} {
		t.Run(name, func(t *testing.T) {
			for _, route := range []string{"operation", "cleanup", "stack"} {
				events = nil
				switch route {
				case "operation":
					Invoke(ctx, CleanupOperation(resource, ""), nil)
				case "cleanup":
					Cleanup(ctx, resource)
				case "stack":
					NewCleanupStack().Push(ctx, resource).Run()
				}
				if !reflect.DeepEqual(events, []string{"closeable"}) {
					t.Fatalf("%s selected %v, want only Closeable", route, events)
				}
			}
		})
	}
}
