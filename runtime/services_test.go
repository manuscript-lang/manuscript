package msruntime

import (
	"context"
	"sync"
	"testing"
	"time"
)

func TestQueueWaitCancellationCloseAndOrdering(t *testing.T) {
	root := RootExecution()
	q := ConstructWithContext(root, "@std/Queue[Int]", []Argument{{"capacity", int64(1)}}).(*Queue)
	Invoke(root, q.Operation("send"), []Argument{{"value", int64(1)}})
	ctx, cancel := context.WithCancel(context.Background())
	waiter := inherit(root, ctx)
	finished := make(chan any, 1)
	go func() {
		finished <- recovered(func() { Invoke(waiter, q.Operation("send"), []Argument{{"value", int64(2)}}) })
	}()
	cancel()
	select {
	case fault := <-finished:
		if _, ok := fault.(cancelled); !ok {
			t.Fatal(fault)
		}
	case <-time.After(time.Second):
		t.Fatal("cancelled sender remained blocked")
	}
	go func() {
		finished <- recovered(func() {
			result := Invoke(root, q.Operation("send"), []Argument{{"value", int64(3)}}).(Alternative)
			if result.Tag != "error" {
				panic("closed send succeeded")
			}
		})
	}()
	Invoke(root, q.Operation("close"), nil)
	select {
	case fault := <-finished:
		if fault != nil {
			t.Fatal(fault)
		}
	case <-time.After(time.Second):
		t.Fatal("close did not wake sender")
	}
	value := Invoke(root, q.Operation("receive"), nil).(Alternative)
	if value.Tag != "some" || value.Fields[0] != int64(1) || Invoke(root, q.Operation("receive"), nil).(Alternative).Tag != "none" {
		t.Fatal("close lost buffered data or EOF")
	}
	empty := ConstructWithContext(root, "@std/Queue[Int]", []Argument{{"capacity", int64(1)}}).(*Queue)
	go func() { finished <- Invoke(root, empty.Operation("receive"), nil).(Alternative).Tag }()
	Invoke(root, empty.Operation("close"), nil)
	select {
	case tag := <-finished:
		if tag != "none" {
			t.Fatal(tag)
		}
	case <-time.After(time.Second):
		t.Fatal("close did not wake receiver")
	}
}
func TestBuilderSealAndSnapshot(t *testing.T) {
	root := RootExecution()
	builder := newBuilder("@std/ListBuilder[Int]")
	Invoke(root, builder.Operation("append"), []Argument{{"value", int64(1)}})
	snapshot := Invoke(root, builder.Operation("freeze"), nil).(List)
	failure := recovered(func() { Invoke(root, builder.Operation("append"), []Argument{{"value", int64(2)}}) })
	if _, ok := failure.(Fault); !ok || len(snapshot.Items) != 1 {
		t.Fatal("sealed builder mutation changed snapshot")
	}
}

type leasedProbe struct{ entered, finished chan struct{} }

func (p *leasedProbe) Operation(name string) Function {
	if name == "close" {
		return NewFunction(nil, "Unit", func(_ *Execution, _ []Value) Value { close(p.finished); return Unit{} })
	}
	return NewFunction(nil, "Unit", func(ctx *Execution, _ []Value) Value {
		close(p.entered)
		<-ctx.Context.Done()
		CheckCancelled(ctx)
		return Unit{}
	})
}
func TestPoolCloseCancelsAndJoinsLeaseOperations(t *testing.T) {
	root := RootExecution()
	probe := &leasedProbe{make(chan struct{}), make(chan struct{})}
	pool := newPool("@std/Pool[Test]", List{Items: []Value{ViewOf("Test", probe)}})
	lease := Invoke(root, pool.Operation("acquire"), nil).(Alternative).Fields[0].(*Lease)
	alias := Invoke(root, lease.Operation("get"), nil).(Alternative).Fields[0]
	ended := make(chan any, 1)
	go func() { ended <- recovered(func() { Invoke(root, Bind(alias, "", "wait"), nil) }) }()
	<-probe.entered
	Invoke(root, pool.Operation("close"), nil)
	select {
	case <-probe.finished:
	default:
		t.Fatal("resource not closed")
	}
	select {
	case fault := <-ended:
		if _, ok := fault.(Fault); !ok {
			t.Fatal(fault)
		}
	case <-time.After(time.Second):
		t.Fatal("lease operation did not join")
	}
	if len(pool.leases) != 0 {
		t.Fatal("closed pool retained leases")
	}
}
func TestPoolConcurrentReleaseReturnsOneResource(t *testing.T) {
	root := RootExecution()
	probe := &leasedProbe{make(chan struct{}), make(chan struct{})}
	pool := newPool("@std/Pool[Test]", List{Items: []Value{ViewOf("Test", probe)}})
	lease := Invoke(root, pool.Operation("acquire"), nil).(Alternative).Fields[0].(*Lease)
	var wait sync.WaitGroup
	for i := 0; i < 20; i++ {
		wait.Add(1)
		go func() { defer wait.Done(); Invoke(root, lease.Operation("close"), nil) }()
	}
	wait.Wait()
	if len(pool.available) != 1 || pool.available[0] == nil {
		t.Fatal("concurrent release duplicated or lost resource")
	}
	Invoke(root, pool.Operation("close"), nil)
}
