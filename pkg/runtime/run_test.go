package msruntime

import (
	"strings"
	"testing"
)

func capture[T any](t *testing.T, f func() T) (result T, recovered any) {
	t.Helper()
	defer func() { recovered = recover() }()
	return f(), nil
}

func TestEnterExitDepth(t *testing.T) {
	ctx := RootExecution()
	for i := 0; i < 10; i++ {
		Enter(ctx)
	}
	if Depth(ctx) != 10 {
		t.Fatalf("depth = %d", Depth(ctx))
	}
	for i := 0; i < 10; i++ {
		Exit(ctx)
	}
	if Depth(ctx) != 0 {
		t.Fatal("depth not restored")
	}
	ctx.calls.depth = MaxCallDepth + 1
	ctx.calls.ticks = 255
	_, r := capture(t, func() Unit { Enter(ctx); return Unit{} })
	if f, ok := r.(Fault); !ok || !strings.Contains(f.Message, "call depth limit exceeded (200000 nested calls)") {
		t.Fatalf("recovered %v", r)
	}
	if Depth(ctx) != MaxCallDepth+1 {
		t.Fatalf("depth after refusal = %d", Depth(ctx))
	}
	cancelledCtx, cancel := cancelledExecution()
	cancel()
	cancelledCtx.calls.ticks = 255
	_, r = capture(t, func() Unit { Enter(cancelledCtx); return Unit{} })
	if _, ok := r.(cancelled); !ok {
		t.Fatalf("recovered %v", r)
	}
	RestoreDepth(ctx, 3)
	if Depth(ctx) != 3 || Depth(nil) != 0 {
		t.Fatal("RestoreDepth/Depth")
	}
}

//go:noinline
func namedSourceFunction(ctx *Execution) { Raise("deep") }

func TestFaultFramesNameRegisteredSources(t *testing.T) {
	RegisterSource(namedSourceFunction, "explode")
	_, r := capture(t, func() Unit { namedSourceFunction(RootExecution()); return Unit{} })
	f, ok := r.(Fault)
	if !ok || len(f.Frames) != 1 || !strings.HasSuffix(f.Frames[0], " in explode") {
		t.Fatalf("fault = %#v", r)
	}
	if !strings.Contains(f.Error(), "\n  at ") {
		t.Fatal("frames missing from Error()")
	}
}

func TestCleanupStackOrderAndSecondaryFaults(t *testing.T) {
	ctx := RootExecution()
	var order []string
	run := func() {
		var stack CleanupStack
		defer stack.Unwind()
		stack.Push(ctx, func(*Execution) { order = append(order, "outer") })
		stack.Push(ctx, func(*Execution) { order = append(order, "failing"); Raise("close failed") })
		stack.Push(ctx, func(*Execution) { order = append(order, "inner") })
		Raise("primary")
	}
	_, r := capture(t, func() Unit { run(); return Unit{} })
	f, ok := r.(Fault)
	if !ok || f.Message != "primary" || len(f.Secondary) != 1 || !strings.Contains(f.Secondary[0], "close failed") {
		t.Fatalf("fault = %#v", r)
	}
	if strings.Join(order, ",") != "inner,failing,outer" {
		t.Fatalf("order = %v", order)
	}
}

func TestCleanupFaultBecomesPrimaryWithoutPending(t *testing.T) {
	ctx := RootExecution()
	_, r := capture(t, func() Unit {
		var stack CleanupStack
		defer stack.Unwind()
		stack.Push(ctx, func(*Execution) { Raise("only") })
		return Unit{}
	})
	if f, ok := r.(Fault); !ok || !strings.Contains(f.Message, "only") {
		t.Fatalf("recovered %#v", r)
	}
}

func TestCleanupActionRunsOnceAndShielded(t *testing.T) {
	ctx, cancel := cancelledExecution()
	var stack CleanupStack
	runs, sawCancel := 0, false
	action := stack.Push(ctx, func(c *Execution) { runs++; sawCancel = c.Context.Err() != nil })
	cancel()
	action.Run()
	action.Run()
	if runs != 1 || sawCancel {
		t.Fatalf("runs=%d cancelledInside=%v", runs, sawCancel)
	}
}

func TestCleanupPreservesCancellation(t *testing.T) {
	ctx, cancel := cancelledExecution()
	cancel()
	_, r := capture(t, func() Unit {
		var stack CleanupStack
		defer stack.Unwind()
		stack.Push(ctx, func(c *Execution) { CheckCancelled(c) }) // shielded: no unwind
		CheckCancelled(ctx)
		return Unit{}
	})
	if _, ok := r.(cancelled); !ok {
		t.Fatalf("recovered %#v", r)
	}
}

func TestDeferredCleanup(t *testing.T) {
	ctx := RootExecution()
	_, r := capture(t, func() Unit {
		defer Cleanup(ctx, func(*Execution) { Raise("close") })
		Raise("body")
		return Unit{}
	})
	if f, ok := r.(Fault); !ok || f.Message != "body" || len(f.Secondary) != 1 {
		t.Fatalf("recovered %#v", r)
	}
}

func TestRunMainExitStatuses(t *testing.T) {
	if got := RunMain(func(*Execution) int { return 3 }, nil); got != 3 {
		t.Fatalf("exit = %d", got)
	}
	if got := RunMain(func(*Execution) int { return 126 }, nil); got != 70 {
		t.Fatalf("out-of-range exit = %d", got)
	}
	if got := RunMain(func(*Execution) int { return -1 }, nil); got != 70 {
		t.Fatalf("negative exit = %d", got)
	}
	if got := RunMain(func(*Execution) int { Raise("fault"); return 0 }, nil); got != 70 {
		t.Fatalf("fault exit = %d", got)
	}
}

func TestRunMainArgumentsAndHooks(t *testing.T) {
	var gotArgs []string
	var shutdown bool
	hostArguments = func(e *Execution, a []string) { gotArgs = a }
	hostShutdown = func(*Execution) { shutdown = true }
	defer func() { hostArguments, hostShutdown = nil, nil }()
	exit := RunMain(func(ctx *Execution) int {
		if len(ctx.State.Program.Arguments) != 2 {
			t.Error("arguments not stored in ProgramState")
		}
		return 0
	}, []string{"a", "b"})
	if exit != 0 || !shutdown || len(gotArgs) != 2 {
		t.Fatalf("exit=%d shutdown=%v args=%v", exit, shutdown, gotArgs)
	}
}

func TestRunTests(t *testing.T) {
	pass := Test{Name: "m::pass", Run: unitRun(func(*Execution) Unit { return Unit{} })}
	fail := Test{Name: "m::fail", Run: unitRun(func(*Execution) Unit { Raise("nope"); return Unit{} })}
	hang := Test{Name: "m::hang", Run: unitRun(func(c *Execution) Unit { <-c.Context.Done(); return CheckCancelled(c) })}
	if got := RunTests([]Test{pass, fail, pass}, nil); got != 1 {
		t.Fatalf("failed = %d", got)
	}
	if got := RunTests([]Test{pass, fail}, []string{"--filter=pass"}); got != 0 {
		t.Fatalf("filtered failed = %d", got)
	}
	if got := RunTests([]Test{pass}, []string{"--filter=absent"}); got != 1 {
		t.Fatalf("no match = %d", got)
	}
	if got := RunTests([]Test{pass}, []string{"--timeout=bogus"}); got != 2 {
		t.Fatalf("bad args = %d", got)
	}
	if got := RunTests([]Test{hang, pass}, []string{"--timeout=30ms"}); got != 1 {
		t.Fatalf("timeout failed = %d", got)
	}
}

func TestParseTestArgs(t *testing.T) {
	o, err := ParseTestArgs([]string{"--timeout=0", "--filter=x", "other"})
	if err != nil || o.Timeout != 0 || o.Filter != "x" {
		t.Fatalf("%+v %v", o, err)
	}
	if o, _ := ParseTestArgs(nil); o.Timeout != DefaultTestTimeout {
		t.Fatal("default timeout")
	}
}

func TestFaultReportKeepsEachFaultsFramesTogether(t *testing.T) {
	ctx := RootExecution()
	_, r := capture(t, func() Unit {
		var stack CleanupStack
		defer stack.Unwind()
		stack.Push(ctx, func(*Execution) { panic(Fault{Message: "second close", Frames: []string{"a.ms:2 in close"}}) })
		stack.Push(ctx, func(*Execution) { panic(Fault{Message: "first close", Frames: []string{"a.ms:1 in close"}}) })
		return Unit{}
	})
	f, ok := r.(Fault)
	if !ok || f.Message != "first close" || len(f.Frames) == 0 || len(f.Secondary) != 1 {
		t.Fatalf("recovered %#v", r)
	}
	report := f.Error()
	primary, secondary, found := strings.Cut(report, "\ncleanup fault: second close")
	if !found || primary != "first close\n  at a.ms:1 in close" || secondary != "\n  at a.ms:2 in close" {
		t.Fatalf("report = %q", report)
	}
}
