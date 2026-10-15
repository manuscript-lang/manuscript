package msruntime

import (
	"context"
	"reflect"
	"sync"
	"testing"
)

func TestHostAccessorsRetainRootsAcrossExecutionContexts(t *testing.T) {
	root := RootExecution()
	if err := root.Host.initialize(); err != nil {
		t.Fatal(err)
	}
	contexts := []*Execution{root, inherit(root, context.Background()), Shield(root), newExecution(root, context.Background()), owned(root, context.Background(), &Scheduler{})}
	for _, spec := range Library {
		if _, ok := root.Host.values[spec.Name]; !ok {
			continue
		}
		f, ok := libraryFunction(spec.Module+"/"+spec.Name, libraryRuntimeType(spec.Result))
		if !ok {
			t.Fatal(spec.Name)
		}
		for _, ctx := range contexts {
			value := Invoke(ctx, f, nil)
			if !reflect.DeepEqual(value, root.Host.values[spec.Name]) {
				t.Fatalf("%s did not return the execution's root", spec.Name)
			}
		}
	}
}

func TestConcurrentHostAccessorInitialization(t *testing.T) {
	root := RootExecution()
	var work sync.WaitGroup
	values := make([]Value, 16)
	for i := range values {
		work.Add(1)
		go func() {
			defer work.Done()
			values[i] = hostValue(inherit(root, context.Background()), "stdout")
		}()
	}
	work.Wait()
	for _, value := range values {
		if value.(View).Receiver != values[0].(View).Receiver {
			t.Fatal("concurrent access created different roots")
		}
	}
}

func TestSourceTestsReceiveFreshHostRootsAndCleanup(t *testing.T) {
	var roots []*Execution
	first := NewFunction(nil, "Unit", func(ctx *Execution, _ []Value) Value {
		roots = append(roots, ctx)
		Invoke(ctx, hostValue(ctx, "stdout").(View).Receiver.(*stream).Operation("close"), nil)
		return Panic("expected failure")
	})
	second := NewFunction(nil, "Unit", func(ctx *Execution, _ []Value) Value {
		roots = append(roots, ctx)
		result := Invoke(ctx, hostValue(ctx, "stdout").(View).Receiver.(*stream).Operation("write"), []Argument{{"data", Bytes{}}}).(Alternative)
		if result.Tag != "ok" {
			return Panic("previous test closed this test's stdout")
		}
		return Unit{}
	})
	if failed := RunTestsWith([]Test{{Name: "close and fault", Run: first}, {Name: "fresh root", Run: second}}, TestOptions{}); failed != 1 {
		t.Fatalf("failed=%d, want exactly the intentional failure", failed)
	}
	if len(roots) != 2 || roots[0].Host == roots[1].Host {
		t.Fatal("tests share host roots")
	}
	for _, ctx := range roots {
		if !hostValue(ctx, "network").(View).Receiver.(*network).closed || !hostValue(ctx, "stdout").(View).Receiver.(*stream).closed {
			t.Fatal("test roots survived joined test cleanup")
		}
		if len(hostValue(ctx, "arguments").(*List).Boxed()) != 0 {
			t.Fatal("source test received CLI arguments")
		}
	}
}
