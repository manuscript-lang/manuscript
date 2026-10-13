package msruntime

import (
	"context"
	"testing"
	"time"
)

type shutdownCleanup struct {
	close Function
}

func (resource shutdownCleanup) Operation(string) Function { return resource.close }

func TestCleanupShieldDoesNotReviveCancelledWorkers(t *testing.T) {
	parent := RootExecution()
	ctx, cancel := context.WithCancel(parent.Context)
	defer cancel()
	parent.Context = ctx
	group := NewTaskGroup(parent, nil).(*TaskGroup)
	defer group.close(Shield(parent))
	started := make(chan struct{})
	worker := groupTask(parent, group, NewFunction(nil, "Unit", func(child *Execution, _ []Value) Value {
		close(started)
		<-child.Context.Done()
		CheckCancelled(child)
		return Panic("cancelled worker continued its ordinary body")
	}))
	select {
	case <-started:
	case <-time.After(time.Second):
		t.Fatal("worker did not start")
	}

	// Cancellation and worker completion precede registered parent cleanup.
	// No close() call has been used to cancel the group at this point.
	cancel()
	select {
	case <-worker.done:
	case <-time.After(time.Second):
		t.Fatal("parent cancellation did not stop its worker")
	}
	closed := false
	resource := shutdownCleanup{NewFunction(nil, "Unit", func(cleanup *Execution, _ []Value) Value {
		CheckCancelled(cleanup)
		Invoke(cleanup, StandardFunction("sleep", "Unit"), []Argument{{"duration", Duration(time.Millisecond)}})
		outcome := taskResult(cleanup, worker)
		if outcome.Tag != "error" || outcome.Fields[0].(Alternative).Tag != "Cancelled" {
			return Panic("cleanup revived an already-cancelled worker")
		}
		group.close(cleanup)
		closed = true
		return Unit{}
	})}
	failure := recovered(func() {
		stack := NewCleanupStack()
		defer stack.Unwind()
		stack.Push(parent, resource)
		CheckCancelled(parent)
	})
	if _, ok := failure.(cancelled); !ok || !closed {
		t.Fatalf("registered shielded cleanup did not complete then propagate cancellation: %v, closed %v", failure, closed)
	}
}
