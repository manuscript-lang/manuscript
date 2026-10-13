package msruntime

import (
	"context"
	"math"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

func recovered(action func()) (failure any) {
	defer func() { failure = recover() }()
	action()
	return nil
}
func TestCheckedNumericOperations(t *testing.T) {
	for name, action := range map[string]func(){"add overflow": func() { Binary("+", int64(math.MaxInt64), int64(1)) }, "sub overflow": func() { Binary("-", int64(math.MinInt64), int64(1)) }, "multiply overflow": func() { Binary("*", int64(math.MaxInt64), int64(2)) }, "minimum division": func() { Binary("/", int64(math.MinInt64), int64(-1)) }, "zero division": func() { Binary("/", int64(3), int64(0)) }, "minimum negation": func() { Unary("-", int64(math.MinInt64)) }, "duration overflow": func() { duration(int64(math.MaxInt64), "minutes") }, "decimal zero divisor": func() { Binary("/", DecimalLiteral("1d"), DecimalLiteral("0d")) }, "decimal overflow": func() { Binary("*", DecimalLiteral("1e6144d"), DecimalLiteral("10d")) }} {
		t.Run(name, func(t *testing.T) {
			if _, ok := recovered(action).(Fault); !ok {
				t.Fatal("expected programming fault")
			}
		})
	}
	if Binary("/", int64(-7), int64(2)) != int64(-3) || Binary("%", int64(-7), int64(3)) != int64(-1) || Binary("%", int64(math.MinInt64), int64(-1)) != int64(0) {
		t.Fatal("integer quotient/remainder semantics")
	}
	if Equal(math.NaN(), math.NaN()) || !Equal(0.0, math.Copysign(0, -1)) {
		t.Fatal("IEEE equality")
	}
	if value := Format(Binary("/", DecimalLiteral("1d"), DecimalLiteral("3d"))); value != "0.3333333333333333333333333333333333" {
		t.Fatal(value)
	}
	for _, value := range []string{"1.00d", "1e6144d", "1e-6176d", "0d", "1234567890123456789012345678901234000d"} {
		if !ValidateDecimalLiteral(value) {
			t.Errorf("rejected exact %s", value)
		}
	}
	for _, value := range []string{"1e6145d", "1e-6177d", "1.2345678901234567890123456789012345d", "1e999999999999999999999999d"} {
		if ValidateDecimalLiteral(value) {
			t.Errorf("accepted inexact %s", value)
		}
	}
	for input, want := range map[string]string{"0.0000001d": "1e-7", "0.000001d": "0.000001", "1e20d": "100000000000000000000", "1e21d": "1e+21", "1.00d": "1"} {
		if got := Format(DecimalLiteral(input)); got != want {
			t.Errorf("%s -> %s, want %s", input, got, want)
		}
	}
	for input, want := range map[float64]string{1e-7: "1e-7", 1e-6: "0.000001", 1e20: "100000000000000000000", 1e21: "1e+21", math.Inf(1): "Infinity"} {
		if got := Format(input); got != want {
			t.Errorf("%v -> %s", input, got)
		}
	}
	if Format(math.Copysign(0, -1)) != "-0" {
		t.Fatal("negative zero formatting")
	}
}
func TestClonedCollectionSnapshots(t *testing.T) {
	ctx := RootExecution()
	original := &Map{Type: "@std/Map[String][Int]"}
	add := func(m *Map, key string, value int64) *Map {
		return Invoke(ctx, NativeMember(m, "with_entry"), []Argument{{"value", value}, {"key", key}}).(*Map)
	}
	a := add(Clone(original).(*Map), "a", 1)
	b := add(Clone(a).(*Map), "b", 2)
	updated := add(Clone(b).(*Map), "a", 3)
	if len(original.Entries) != 0 || a.Entries[0].Value != int64(1) || updated.Entries[0].Key != "a" || updated.Entries[0].Value != int64(3) {
		t.Fatal("update mutated an alias or changed order")
	}
	removed := Invoke(ctx, NativeMember(Clone(updated), "without"), []Argument{{"key", "a"}}).(*Map)
	reinserted := add(removed, "a", 4)
	if reinserted.Entries[1].Key != "a" {
		t.Fatal("reinsertion order")
	}
	if !Equal(updated, add(add(original, "b", 2), "a", 3)) {
		t.Fatal("map equality depends on insertion order")
	}
}

type cleanupResource struct {
	name   string
	events *[]string
	fail   bool
}

func (r cleanupResource) Operation(name string) Function {
	return NewFunction(nil, "Unit", func(ctx *Execution, _ []Value) Value {
		CheckCancelled(ctx)
		*r.events = append(*r.events, r.name)
		if r.fail {
			return Panic(r.name)
		}
		return Unit{}
	})
}
func TestCleanupUnwindsAndPreservesPrimaryFault(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	execution := &Execution{Context: ctx}
	events := []string{}
	failure := recovered(func() {
		stack := NewCleanupStack()
		defer stack.Unwind()
		stack.Push(execution, cleanupResource{"outer", &events, true})
		stack.Push(execution, cleanupResource{"inner", &events, true})
		cancel()
		Panic("primary")
	})
	fault, ok := failure.(Fault)
	if !ok || fault.Message != "primary" || len(fault.Secondary) != 2 {
		t.Fatalf("lost primary/secondary faults: %#v", failure)
	}
	if strings.Join(events, ",") != "inner,outer" {
		t.Fatal(events)
	}
}
func TestCleanupStackReleasesCompletedActions(t *testing.T) {
	events := []string{}
	stack := NewCleanupStack()
	for i := 0; i < 100; i++ {
		action := stack.Push(RootExecution(), cleanupResource{"one", &events, false})
		action.Run()
		action.Run()
	}
	if len(stack.actions) != 0 || len(events) != 100 {
		t.Fatal("retained completed scopes or closed twice")
	}
}

// runTasks exercises the public group lifecycle for existing service regressions.
func runTasks(ctx *Execution, result string, operations []Value, timeout *Duration) Value {
	var args []Argument
	if timeout != nil {
		args = []Argument{{"timeout", *timeout}}
	}
	group := NewTaskGroup(ctx, args).(*TaskGroup)
	defer group.close(Shield(ctx))
	for _, operation := range operations {
		group.start(ctx, "@std/Task["+operation.(Function).Result+"]", operation)
	}
	return group.join(ctx, result)
}
func TestTaskGroupJoinsFaultedSiblings(t *testing.T) {
	started := make(chan struct{})
	cleaned := make(chan struct{})
	first := NewFunction(nil, "Int", func(_ *Execution, _ []Value) Value { <-started; return Panic("work failed") })
	second := NewFunction(nil, "Int", func(ctx *Execution, _ []Value) Value {
		defer close(cleaned)
		close(started)
		<-ctx.Context.Done()
		CheckCancelled(ctx)
		return int64(2)
	})
	outcome := runTasks(RootExecution(), "result", []Value{first, second}, nil).(Alternative)
	if outcome.Tag != "error" || outcome.Fields[0].(Alternative).Tag != "Crashed" {
		t.Fatal(outcome)
	}
	if len(outcome.Fields[0].(Alternative).Fields) != 2 {
		t.Fatal("missing operation identity")
	}
	select {
	case <-cleaned:
	default:
		t.Fatal("returned before sibling cleanup")
	}
}
func TestTaskGroupEmptyZeroTimeoutAndParentCancellation(t *testing.T) {
	zero := Duration(0)
	if runTasks(RootExecution(), "result", nil, &zero).(Alternative).Tag != "ok" {
		t.Fatal("empty group timed out")
	}
	var started atomic.Bool
	task := NewFunction(nil, "Int", func(_ *Execution, _ []Value) Value { started.Store(true); return int64(1) })
	outcome := runTasks(RootExecution(), "result", []Value{task}, &zero).(Alternative)
	if outcome.Tag != "error" || started.Load() {
		t.Fatal("zero timeout started work")
	}
	ctx, cancel := context.WithCancel(context.Background())
	entered := make(chan struct{})
	task = NewFunction(nil, "Int", func(child *Execution, _ []Value) Value {
		close(entered)
		<-child.Context.Done()
		return Panic("cleanup fault after cancellation")
	})
	go func() { <-entered; cancel() }()
	if _, ok := recovered(func() { runTasks(&Execution{Context: ctx}, "result", []Value{task}, nil) }).(cancelled); !ok {
		t.Fatal("parent cancellation became a Result")
	}
}
func startJob(ctx *Execution, b *Scheduler, f Function) Alternative {
	return Invoke(ctx, b.Operation("start"), []Argument{{"operation", f}}).(Alternative)
}
func TestSchedulerAdmissionCancellationAndClose(t *testing.T) {
	ctx := RootExecution()
	b := NewScheduler(ctx, []Argument{{"limit", int64(1)}}).(*Scheduler)
	started := make(chan struct{})
	cleaned := make(chan struct{})
	f := NewFunction(nil, "@std/Result[Unit][String]", func(child *Execution, _ []Value) Value {
		defer close(cleaned)
		close(started)
		<-child.Context.Done()
		CheckCancelled(child)
		return nil
	})
	first := startJob(ctx, b, f)
	id := first.Fields[0].(OperationId)
	<-started
	full := startJob(ctx, b, f)
	if full.Fields[0].(Alternative).Tag != "Full" {
		t.Fatal(full)
	}
	Invoke(ctx, b.Operation("cancel"), []Argument{{"id", id}})
	b.close(ctx)
	select {
	case <-cleaned:
	default:
		t.Fatal("close did not join")
	}
	if Invoke(ctx, b.Operation("status"), []Argument{{"id", id}}).(Alternative).Tag != "Cancelled" {
		t.Fatal("cancelled job status")
	}
	if startJob(ctx, b, f).Fields[0].(Alternative).Tag != "Closed" {
		t.Fatal("admitted after close")
	}
	b.close(ctx)
}
func TestSchedulerReporterHistoryAndOwnLifetime(t *testing.T) {
	parent, cancel := context.WithCancel(context.Background())
	defer cancel()
	ctx := &Execution{Context: parent}
	reports := make(chan Value, 2)
	reporter := NewFunction([]string{"failure"}, "Unit", func(_ *Execution, args []Value) Value { reports <- args[0]; return Unit{} })
	b := NewScheduler(ctx, []Argument{{"limit", int64(2)}, {"reporter", reporter}, {"history_limit", int64(1)}, {"drain", Duration(time.Second)}}).(*Scheduler)
	failure := NewFunction(nil, "@std/Result[Unit][String]", func(_ *Execution, _ []Value) Value {
		return Alternative{"@std/Result[Unit][String]", "error", []Value{"expected failure"}}
	})
	id1 := startJob(ctx, b, failure).Fields[0].(OperationId)
	b.jobs.Wait()
	<-reports
	success := NewFunction(nil, "@std/Result[Unit][String]", func(_ *Execution, _ []Value) Value {
		return Alternative{"@std/Result[Unit][String]", "ok", []Value{Unit{}}}
	})
	id2 := startJob(ctx, b, success).Fields[0].(OperationId)
	b.jobs.Wait()
	if Invoke(ctx, b.Operation("status"), []Argument{{"id", id1}}).(Alternative).Tag != "Unknown" || Invoke(ctx, b.Operation("status"), []Argument{{"id", id2}}).(Alternative).Tag != "Succeeded" {
		t.Fatal("history retention")
	}
	b.close(ctx)
}
func TestSchedulerCannotJoinItselfOrNestedDescendant(t *testing.T) {
	ctx := RootExecution()
	reports := make(chan Value, 1)
	reporter := NewFunction([]string{"failure"}, "Unit", func(_ *Execution, args []Value) Value { reports <- args[0]; return Unit{} })
	b := NewScheduler(ctx, []Argument{{"limit", int64(1)}, {"reporter", reporter}, {"drain", Duration(time.Second)}}).(*Scheduler)
	operation := NewFunction(nil, "@std/Result[Unit][String]", func(child *Execution, _ []Value) Value {
		nested := NewFunction(nil, "Unit", func(grandchild *Execution, _ []Value) Value { b.close(grandchild); return Unit{} })
		result := runTasks(child, "result", []Value{nested}, nil).(Alternative)
		if result.Tag != "error" {
			return Panic("self close was accepted")
		}
		return Alternative{"@std/Result[Unit][String]", "error", []Value{"descendant close rejected"}}
	})
	startJob(ctx, b, operation)
	b.jobs.Wait()
	b.close(ctx)
	select {
	case <-reports:
	default:
		t.Fatal("nested close did not finish with report")
	}
}
func TestSchedulerSubmittingContextDoesNotReparent(t *testing.T) {
	parent := RootExecution()
	b := NewScheduler(parent, []Argument{{"limit", int64(1)}, {"drain", Duration(time.Second)}}).(*Scheduler)
	submit, cancel := context.WithCancel(context.Background())
	started := make(chan struct{})
	release := make(chan struct{})
	f := NewFunction(nil, "@std/Result[Unit][String]", func(ctx *Execution, _ []Value) Value {
		close(started)
		<-release
		CheckCancelled(ctx)
		return Alternative{"@std/Result[Unit][String]", "ok", []Value{Unit{}}}
	})
	id := startJob(&Execution{Context: submit}, b, f).Fields[0].(OperationId)
	<-started
	cancel()
	close(release)
	b.jobs.Wait()
	if Invoke(parent, b.Operation("status"), []Argument{{"id", id}}).(Alternative).Tag != "Succeeded" {
		t.Fatal("submission reparented accepted work")
	}
	b.close(parent)
}
func TestSchedulerConcurrentClose(t *testing.T) {
	ctx := RootExecution()
	b := NewScheduler(ctx, []Argument{{"limit", int64(1)}}).(*Scheduler)
	var callers sync.WaitGroup
	for i := 0; i < 10; i++ {
		callers.Add(1)
		go func() { defer callers.Done(); b.close(ctx) }()
	}
	callers.Wait()
	if !b.closed {
		t.Fatal("close not committed")
	}
}

func TestJoinedOperationCannotDetachNestedScheduler(t *testing.T) {
	started := make(chan struct{})
	finished := make(chan struct{})
	task := NewFunction(nil, "Int", func(ctx *Execution, _ []Value) Value {
		b := NewScheduler(ctx, []Argument{{"limit", int64(1)}}).(*Scheduler)
		job := NewFunction(nil, "@std/Result[Unit][String]", func(child *Execution, _ []Value) Value {
			defer close(finished)
			close(started)
			<-child.Context.Done()
			CheckCancelled(child)
			return nil
		})
		startJob(ctx, b, job)
		<-started
		return int64(1)
	})
	outcome := runTasks(RootExecution(), "result", []Value{task}, nil).(Alternative)
	if outcome.Tag != "ok" {
		t.Fatal(outcome)
	}
	select {
	case <-finished:
	default:
		t.Fatal("nested service work escaped its joined lifetime")
	}
}
func TestSchedulerReporterFailureAndOverflow(t *testing.T) {
	ctx := RootExecution()
	blocked := make(chan struct{})
	release := make(chan struct{})
	var calls atomic.Int64
	reporter := NewFunction([]string{"failure"}, "Unit", func(_ *Execution, _ []Value) Value {
		calls.Add(1)
		close(blocked)
		<-release
		return Panic("reporter failed")
	})
	b := NewScheduler(ctx, []Argument{{"limit", int64(1)}, {"reporter", reporter}}).(*Scheduler)
	operation := NewFunction(nil, "@std/Result[Unit][String]", func(_ *Execution, _ []Value) Value {
		return Alternative{"@std/Result[Unit][String]", "error", []Value{"domain error"}}
	})
	startJob(ctx, b, operation)
	b.jobs.Wait()
	<-blocked
	second := startJob(ctx, b, operation)
	if second.Tag != "ok" {
		t.Fatal("reporter throttled admission")
	}
	b.jobs.Wait()
	close(release)
	b.close(ctx)
	FlushDiagnostics()
	if calls.Load() != 1 {
		t.Fatal("overflow or reporter fault invoked reporter recursively")
	}
}

func TestAcquisitionDisposesUndeliveredResources(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	events := []string{}
	resource := cleanupResource{"disposed", &events, false}
	acquire := NewAcquisition(nil, "result", func(_ *Execution, _ []Value) Value { cancel(); return resource }, func(execution *Execution, value Value) { Invoke(Shield(execution), Bind(value, "", "close"), nil) })
	if _, ok := recovered(func() { Invoke(&Execution{Context: ctx}, acquire, nil) }).(cancelled); !ok {
		t.Fatal("delivered after cancellation")
	}
	if len(events) != 1 {
		t.Fatal("undelivered resource was not disposed exactly once")
	}
}

func TestDecimalZeroDoesNotAllocateWrittenExponent(t *testing.T) {
	for _, literal := range []string{"0e2147483647d", "0e999999999999999999999999999999d", "-0.00e-99999999999999999999999d"} {
		if !ValidateDecimalLiteral(literal) || Format(DecimalLiteral(literal)) != "0" {
			t.Fatal(literal)
		}
	}
	if ValidateDecimalLiteral("0e+d") {
		t.Fatal("invalid zero exponent accepted")
	}
}
