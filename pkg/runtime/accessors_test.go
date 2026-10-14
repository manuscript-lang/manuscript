package msruntime

import (
	"context"
	"math"
	"os"
	"strings"
	"sync"
	"testing"
)

func TestAccessorReadsStayLiveAndKeepPayloadAliases(t *testing.T) {
	ctx := RootExecution()
	child := NewList("@std/List[Int]", []Value{int64(1)})
	list := NewList("@std/List[@std/List[Int]]", []Value{child})
	if ListLengthRead(ctx, list) != 1 {
		t.Fatal("length")
	}
	first := ListFirstRead(ctx, list).(Alternative)
	if first.Fields[0] != child {
		t.Fatal("first copied element")
	}
	list.Append(child)
	if ListLengthRead(ctx, list) != 2 {
		t.Fatal("length cached")
	}
	child.Append(int64(2))
	if ListLengthRead(ctx, first.Fields[0]) != 2 {
		t.Fatal("payload lost alias")
	}
	empty := NewList("@std/List[@std/Optional[Int]]", nil)
	if ListFirstRead(ctx, empty).(Alternative).Tag != "none" {
		t.Fatal("empty first")
	}
	inner := optional("Int", nil, false)
	empty.Append(inner)
	if got := ListFirstRead(ctx, empty).(Alternative); got.Tag != "some" || got.Fields[0].(Alternative).Tag != "none" {
		t.Fatal("flattened Optional")
	}
	q := &Queue{typ: "@std/Queue[@std/List[Int]]", items: []Value{child}}
	for range 2 {
		if QueuePeekRead(ctx, q).(Alternative).Fields[0] != child || QueueLengthRead(ctx, q) != 1 {
			t.Fatal("peek consumed/copied")
		}
	}
	calls := 0
	priority := &PriorityQueue{typ: "@std/PriorityQueue[Int]", items: []priorityEntry{{int64(8), 0}}, compare: NewFunction(nil, "Never", func(*Execution, []Value) Value { calls++; return Panic("unexpected comparison") })}
	if PriorityQueuePeekRead(ctx, priority).(Alternative).Fields[0] != int64(8) || calls != 0 {
		t.Fatal("peek compared")
	}
}

func TestAccessorClassifiersAndUnitProjections(t *testing.T) {
	ctx := RootExecution()
	for _, some := range []bool{false, true} {
		if OptionalSomeRead(ctx, some) != some || OptionalNoneRead(ctx, some) == some {
			t.Fatal("Optional tag")
		}
	}
	for _, failed := range []bool{false, true} {
		if ResultErrorRead(ctx, failed) != failed || ResultOKRead(ctx, failed) == failed {
			t.Fatal("Result tag")
		}
	}
	for _, v := range []float64{0, math.Copysign(0, -1), math.Inf(1), math.Inf(-1), math.NaN()} {
		if FloatNaNRead(ctx, v) != math.IsNaN(v) || FloatFiniteRead(ctx, v) != (!math.IsNaN(v) && !math.IsInf(v, 0)) {
			t.Fatal("Float classifier")
		}
	}
	text := "aé😀"
	if StringByteLengthRead(ctx, text) != 7 || StringLengthRead(ctx, text) != 3 || StringScalarLengthRead(ctx, text) != 3 {
		t.Fatal("String units")
	}
	span := Duration(-1500000001)
	if DurationNanosecondsRead(ctx, span) != -1500000001 || DurationMicrosecondsRead(ctx, span) != -1500000 || DurationMillisecondsRead(ctx, span) != -1500 || DurationSecondsRead(ctx, span) != -1.500000001 {
		t.Fatal("Duration projection")
	}
	cancelledCtx, cancel := context.WithCancel(ctx.Context)
	cancel()
	stopped := newExecution(ctx, cancelledCtx)
	if IntSecondsRead(stopped, int64(2)) != Duration(2000000000) {
		t.Fatal("Int property acquired cancellation")
	}
	if _, ok := recovered(func() { IntMinutesRead(ctx, int64(math.MaxInt64)) }).(Fault); !ok {
		t.Fatal("Int scaling lost overflow")
	}
	for _, run := range []func(){func() { BytesLengthRead(stopped, Bytes{}) }, func() { OptionalSomeRead(stopped, true) }, func() { FloatFiniteRead(stopped, 0) }, func() { DurationHoursRead(stopped, span) }} {
		if _, ok := recovered(run).(cancelled); !ok {
			t.Fatal("lost admission")
		}
	}
}

func TestDynamicAccessorRetainsKindAndImplementationEvidence(t *testing.T) {
	ctx := RootExecution()
	typ, contract := "accessor-test/Box[Int]", "accessor-test/Read[Int]"
	receiver := Record{Type: typ, Fields: map[string]Value{"value": int64(4)}}
	for _, module := range []string{"accessor-left", "accessor-right"} {
		owner := module
		Register(Implementation{Receiver: "accessor-test/Box[T]", Contract: "accessor-test/Read[T]", Name: "value", Scope: owner, Variables: []string{"T"}, Accessor: true,
			Read: func(_ *Execution, v Value, args map[string]string, scopes map[string]TypeScope) Value {
				if args["T"] != "Int" || scopes["T"].Module != owner+"-arg" {
					t.Fatal("lost generic evidence", args, scopes)
				}
				return owner
			}})
	}
	for range 2 {
		for _, module := range []string{"accessor-left", "accessor-right"} {
			scope := TypeScope{Module: module, Args: []TypeScope{{Module: module + "-arg"}}}
			view := ViewOf(contract, receiver, scope)
			if ReadAccessor(ctx, view, "", "value", TypeScope{Module: "wrong"}) != module {
				t.Fatal("read ignored View evidence or cached a value")
			}
		}
	}
	// Callable and accessor registries may have equal names under distinct
	// contracts, but lookup cannot interchange their implementation kinds.
	methodContract := "accessor-test/Method[Int]"
	Register(Implementation{Receiver: typ, Contract: methodContract, Name: "value", Build: func(Value, map[string]string, map[string]TypeScope) Function {
		return NewFunction(nil, "Int", func(*Execution, []Value) Value { return int64(99) })
	}})
	if Invoke(ctx, Bind(receiver, methodContract, "value"), nil) != int64(99) {
		t.Fatal("method kind changed")
	}
	if _, ok := recovered(func() { ReadAccessor(ctx, receiver, methodContract, "value", TypeScope{}) }).(Fault); !ok {
		t.Fatal("method satisfied accessor")
	}
}

func TestAccessorGuardValidationAndContendedDelivery(t *testing.T) {
	root := RootExecution()
	cell := synchronizedInt()
	guard := lockCell(root, cell)
	if SynchronizedGuardValueRead(root, guard) != int64(0) {
		t.Fatal("value")
	}
	Invoke(root, guard.Operation("set"), []Argument{{"value", int64(7)}})
	if SynchronizedGuardValueRead(root, guard) != int64(7) {
		t.Fatal("cached guard payload")
	}
	guard.close()
	next := lockCell(root, cell)
	defer next.close()
	if fault, ok := recovered(func() { SynchronizedGuardValueRead(root, guard) }).(Fault); !ok || fault.Message != closedGuardMessage {
		t.Fatal("stale guard read")
	}
	// The old function wrapper checked delivery after the cell mutex. Coordinate
	// admission with a context that signals its first Err query, then cancel while
	// the read is blocked on the mutex and release it without timing assumptions.
	raw, cancel := context.WithCancel(root.Context)
	queried := make(chan struct{})
	probe := &accessorAdmissionContext{Context: raw, queried: queried}
	ctx := newExecution(root, probe)
	cell.mu.Lock()
	done := make(chan any, 1)
	go func() { done <- recovered(func() { SynchronizedGuardValueRead(ctx, next) }) }()
	<-queried
	cancel()
	cell.mu.Unlock()
	if _, ok := (<-done).(cancelled); !ok {
		t.Fatal("contended read delivered after cancellation")
	}
}

type accessorAdmissionContext struct {
	context.Context
	once    sync.Once
	queried chan struct{}
}

func (c *accessorAdmissionContext) Err() error {
	err := c.Context.Err()
	c.once.Do(func() { close(c.queried) })
	return err
}

func TestMigratedNativeReadsCannotBindFunctions(t *testing.T) {
	values := []struct {
		receiver Value
		names    []string
	}{
		{NewList("@std/List[Int]", nil), []string{"length", "is_empty", "first", "last"}},
		{Bytes{}, []string{"length", "is_empty"}},
		{optional("Int", nil, false), []string{"is_some", "is_none"}},
		{float64(0), []string{"is_nan", "is_finite"}},
	}
	for _, v := range values {
		for _, name := range v.names {
			if fault, ok := recovered(func() { NativeMember(v.receiver, name) }).(Fault); !ok || !strings.Contains(fault.Message, "accessor") {
				t.Fatal("bound getter Function", name)
			}
		}
	}
	// Error.message remains a method value and does not execute on binding.
	errorValue := Alternative{Type: "@std/IoError", Tag: "Failed", Fields: []Value{"verbatim"}}
	bound := NativeImplementations[0].Build(errorValue)
	if Invoke(RootExecution(), bound, nil) != "verbatim" {
		t.Fatal("Error.message behavior changed")
	}
}

func TestAccessorMetadataTracksReplacementAndLoggerThreshold(t *testing.T) {
	ctx := RootExecution()
	headers := &libraryHeaders{}
	head := Record{Type: "@std/HttpResponseMetadata", Fields: map[string]Value{"status": int64(200), "headers": headers}}
	response := Record{Type: "@std/ClientResponse", Fields: map[string]Value{"head": head, "body": Bytes{}}}
	alias := ClientResponseMetadataRead(ctx, response).(Record)
	alias.Fields["status"] = int64(201)
	if ClientResponseMetadataRead(ctx, response).(Record).Fields["status"] != int64(201) {
		t.Fatal("metadata copied")
	}
	replacement := Record{Type: head.Type, Fields: map[string]Value{"status": int64(404), "headers": &libraryHeaders{}}}
	response.Fields["head"] = replacement
	if ClientResponseMetadataRead(ctx, response).(Record).Fields["status"] != int64(404) || alias.Fields["status"] != int64(201) {
		t.Fatal("metadata snapshot/replaced earlier alias")
	}
	logger := &libraryLogger{threshold: 1}
	first := LoggerLevelRead(ctx, logger).(Alternative)
	logger.mu.Lock()
	logger.threshold = 4
	logger.mu.Unlock()
	if LoggerLevelRead(ctx, logger).(Alternative).Tag == first.Tag {
		t.Fatal("logger threshold cached")
	}
	paths := ViewOf("@std/PathOperations", libraryPaths{windows: true})
	if PathOperationsSeparatorRead(ctx, paths) != "\\" || PathOperationsDelimiterRead(ctx, paths) != ";" {
		t.Fatal("path accessor")
	}
}

func TestSourceAccessorBoundaryRetainsReturnPropagationAndDelivery(t *testing.T) {
	root := RootExecution()
	result := "@std/Result[Int][String]"
	body := func(*Execution, Value, map[string]string, map[string]TypeScope) Value { return Return(int64(9)) }
	if SourceAccessorRead(root, nil, "Int", "accessor.ms:1:1", nil, nil, body) != int64(9) || Depth(root) != 0 {
		t.Fatal("source return/depth")
	}
	failed := func(*Execution, Value, map[string]string, map[string]TypeScope) Value {
		return Try(Alternative{Type: result, Tag: "error", Fields: []Value{"cause"}})
	}
	if got := SourceAccessorRead(root, nil, result, "accessor.ms:1:1", nil, nil, failed).(Alternative); got.Type != result || got.Tag != "error" || got.Fields[0] != "cause" {
		t.Fatal("propagation")
	}
	raw, cancel := context.WithCancel(root.Context)
	ctx := newExecution(root, raw)
	cancelBody := func(*Execution, Value, map[string]string, map[string]TypeScope) Value {
		cancel()
		return Return(int64(9))
	}
	if _, ok := recovered(func() { SourceAccessorRead(ctx, nil, "Int", "accessor.ms:1:1", nil, nil, cancelBody) }).(cancelled); !ok || Depth(ctx) != 0 {
		t.Fatal("delivery cancellation/depth")
	}
}

func TestAccessorDirectoryPathsRetainPostCloseAvailability(t *testing.T) {
	ctx := RootExecution()
	path := t.TempDir()
	file, err := os.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	file.Close()
	directory := &libraryDirectory{file: file, closed: true}
	temporary := &libraryTemporary{path: path, closed: true}
	if DirectoryPathRead(ctx, directory) != path || TemporaryDirectoryPathRead(ctx, temporary) != path {
		t.Fatal("closed directory paths")
	}
}
