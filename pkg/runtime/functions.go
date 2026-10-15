package msruntime

import (
	"fmt"
	"strings"
	"sync"
	"sync/atomic"
)

type Function struct {
	Labels       []string
	Result       string
	Body         func(*Execution, []Value) Value
	IntCompare   func(*Execution, int64, int64) int64
	FloatCompare func(*Execution, float64, float64) int64
	// BorrowedArguments is an internal proof carried only by compiled bodies
	// that copy parameter Values and never retain/expose their incoming slice.
	BorrowedArguments bool
}

type Generic struct {
	Variables []string
	Build     func(map[string]string, map[string]TypeScope) Function
}

type Argument struct {
	Name  string
	Value Value
}

type propagation struct{ Cause Value }

// controlPanics counts in-flight propagation, source-return and loop-exit
// panics. Layers that only consume those skip recover when none exist, since
// a recover-and-repanic at every frame makes unwinding a deep stack quadratic.
var controlPanics atomic.Int64

func NewFunction(labels []string, result string, body func(*Execution, []Value) Value) Function {
	return newFunction(labels, result, body, nil)
}

func NewAcquisition(labels []string, result string, body func(*Execution, []Value) Value, dispose func(*Execution, Value)) Function {
	return newFunction(labels, result, body, dispose)
}

func newFunction(labels []string, result string, body func(*Execution, []Value) Value, dispose func(*Execution, Value)) Function {
	return Function{Labels: labels, Result: result, Body: func(ctx *Execution, args []Value) (value Value) {
		defer func() {
			if controlPanics.Load() == 0 {
				return
			}
			if r := recover(); r != nil {
				if p, ok := r.(propagation); ok {
					controlPanics.Add(-1)
					CheckCancelled(ctx)
					value = Alternative{Type: result, Tag: "error", Fields: []Value{p.Cause}}
				} else {
					panic(r)
				}
			}
		}()
		CheckCancelled(ctx)
		value = body(ctx, args)
		// One delivery checkpoint decides both disposal and unwinding. A
		// second cancellation check could discard an undisposed acquisition.
		if ctx != nil && isDone(ctx.Context) {
			if dispose != nil {
				dispose(ctx, value)
			}
			panic(cancelled{})
		}
		return value
	}}
}

func Invoke(ctx *Execution, callee Value, args []Argument) Value {
	f, ok := callee.(Function)
	if !ok {
		return Panic("runtime invariant: callee is not specialized")
	}
	ordered := make([]Value, len(f.Labels))
	for _, arg := range args {
		for i, label := range f.Labels {
			if label == arg.Name {
				ordered[i] = arg.Value
			}
		}
	}
	CheckCancelled(ctx)
	return f.Body(ctx, ordered)
}

// PreparedDefaults carries the fully evaluated slots from generated default
// preparation. It is not a source value: propagation may instead return the
// callable's declared Result without entering its native body.
type PreparedDefaults []Value

// WithDefaults preserves the native callable's delivery checkpoint, including
// acquisition disposal. Do not wrap the final call in NewFunction: an extra
// delivery checkpoint could discard a resource after its native owner returned.
// slots lists only the new expression defaults; old Optional.none omissions
// continue directly to the native adapter when these slots are supplied.
func WithDefaults(callee Value, prepare Function, slots []int) Value {
	f := callee.(Function)
	return Function{Labels: f.Labels, Result: f.Result, Body: func(ctx *Execution, args []Value) Value {
		CheckCancelled(ctx)
		missing := false
		for _, index := range slots {
			missing = missing || args[index] == nil
		}
		if !missing {
			return f.Body(ctx, args)
		}
		value := prepare.Body(ctx, args)
		if completed, ok := value.(PreparedDefaults); ok {
			return f.Body(ctx, []Value(completed))
		}
		return value
	}}
}

// Lazy holds a value built on first use; generated code keeps one per call site
// whose type arguments are known statically, so repeated calls skip Specialize.
type Lazy struct {
	once  sync.Once
	value Value
}

func (l *Lazy) Get(build func() Value) Value {
	l.once.Do(func() { l.value = build() })
	return l.value
}

func Specialize(value Value, args []string, scopes ...TypeScope) Value {
	g, ok := value.(Generic)
	if !ok {
		return value
	}
	var key string
	cache := genericCache(g)
	if cache != nil {
		var b strings.Builder
		for i, arg := range args {
			b.WriteString(arg)
			b.WriteByte(0)
			if i < len(scopes) {
				writeScopeKey(&b, scopes[i])
			}
			b.WriteByte(1)
		}
		key = b.String()
		if cached, ok := cache.Load(key); ok {
			return cached.(Function)
		}
	}
	sub := map[string]string{}
	typeScopes := map[string]TypeScope{}
	for i, v := range g.Variables {
		sub[v] = args[i]
		if i < len(scopes) {
			typeScopes[v] = scopes[i]
		}
	}
	built := g.Build(sub, typeScopes)
	if cache != nil {
		cache.Store(key, built)
	}
	return built
}

// genericCaches holds one instantiation cache per Generic, keyed by the address
// of its Variables backing array, which every copy of the value shares.
var genericCaches sync.Map

func genericCache(g Generic) *sync.Map {
	if len(g.Variables) == 0 {
		return nil
	}
	key := &g.Variables[0]
	if cache, ok := genericCaches.Load(key); ok {
		return cache.(*sync.Map)
	}
	cache, _ := genericCaches.LoadOrStore(key, new(sync.Map))
	return cache.(*sync.Map)
}

func writeScopeKey(b *strings.Builder, scope TypeScope) {
	b.WriteString(scope.Module)
	b.WriteByte('(')
	for _, arg := range scope.Args {
		writeScopeKey(b, arg)
		b.WriteByte(',')
	}
	b.WriteByte(')')
}

func Try(value Value, scopes ...TypeScope) Value {
	v := value.(Alternative)
	if v.Tag == "error" {
		cause := v.Fields[0]
		if len(scopes) > 0 {
			cause = ViewOf("@std/Error", cause, scopes[0])
		}
		controlPanics.Add(1)
		panic(propagation{cause})
	}
	return v.Fields[0]
}

// ErrorResult changes a Result's static error boundary while retaining the
// original payload. Only scoped implementation evidence requires a view.
func ErrorResult(value Value, result string, scopes ...TypeScope) Value {
	v := value.(Alternative)
	v.Type = result
	if v.Tag == "error" && len(scopes) > 0 {
		v.Fields = []Value{ViewOf("@std/Error", v.Fields[0], scopes[0])}
	}
	return v
}

type sourceReturn struct{ value Value }

func Return(value Value) Value {
	controlPanics.Add(1)
	panic(sourceReturn{value})
}

// MaxCallDepth bounds nested source calls per execution so runaway recursion
// is a fault instead of Go's unrecoverable stack overflow.
const MaxCallDepth = 200000

// Keep admission and depth release inline on these hot paths. Limit faults and
// source-return consumption are shared; guard tests enforce boundary parity.
func sourceDepthFault(calls *callState) {
	calls.depth--
	Panic(fmt.Sprintf("call depth limit exceeded (%d nested calls)", MaxCallDepth))
}

// consumeSourceReturn owns source-return accounting for boxed and typed bodies.
// The typed boundary still checks its payload and delivery cancellation itself.
func consumeSourceReturn(failure any) (Value, bool) {
	returned, ok := failure.(sourceReturn)
	if ok {
		controlPanics.Add(-1)
	}
	return returned.value, ok
}

func NewSourceFunction(labels []string, result, position string, body func(*Execution, []Value) Value) Function {
	return NewFunction(labels, result, func(ctx *Execution, args []Value) (value Value) {
		if ctx != nil && ctx.calls != nil {
			calls := ctx.calls
			if calls.depth++; calls.depth > MaxCallDepth {
				sourceDepthFault(calls)
			}
			defer func() { calls.depth-- }()
		}
		defer func() {
			if controlPanics.Load() == 0 {
				return
			}
			if failure := recover(); failure != nil {
				if returned, ok := consumeSourceReturn(failure); ok {
					value = returned
					return
				}
				panic(failure)
			}
		}()
		if sourceProfiling.Load() {
			return profileSource(ctx, position, args, body)
		}
		return body(ctx, args)
	})
}

// NewCompiledSourceFunction has the same guarded Body ABI as NewSourceFunction.
// Its raw body must copy incoming Values and never retain or expose args itself.
// Capturing an individual copied Value, including a mutable reference, is valid.
func NewCompiledSourceFunction(labels []string, result, position string, body func(*Execution, []Value) Value) Function {
	function := NewSourceFunction(labels, result, position, body)
	function.BorrowedArguments = true
	return function
}

// SourceDirect wraps a method body with everything a bound method gets from
// NewSourceFunction and newFunction: the call-depth limit, source returns,
// profiling, propagation of a nested try into an error Result, and the
// post-body cancellation checkpoint. Limit faults and return consumption are shared.
func SourceDirect(position, result string, body func(*Execution, Value, []Value) Value) func(*Execution, Value, []Value) Value {
	source := func(ctx *Execution, receiver Value, args []Value) (value Value) {
		if ctx != nil && ctx.calls != nil {
			calls := ctx.calls
			if calls.depth++; calls.depth > MaxCallDepth {
				sourceDepthFault(calls)
			}
			defer func() { calls.depth-- }()
		}
		defer func() {
			if controlPanics.Load() == 0 {
				return
			}
			if failure := recover(); failure != nil {
				if returned, ok := consumeSourceReturn(failure); ok {
					value = returned
					return
				}
				panic(failure)
			}
		}()
		if sourceProfiling.Load() {
			return profileSource(ctx, position, args, func(ctx *Execution, args []Value) Value { return body(ctx, receiver, args) })
		}
		return body(ctx, receiver, args)
	}
	return func(ctx *Execution, receiver Value, args []Value) (value Value) {
		defer func() {
			if controlPanics.Load() == 0 {
				return
			}
			if r := recover(); r != nil {
				if p, ok := r.(propagation); ok {
					controlPanics.Add(-1)
					CheckCancelled(ctx)
					value = Alternative{Type: result, Tag: "error", Fields: []Value{p.Cause}}
				} else {
					panic(r)
				}
			}
		}()
		value = source(ctx, receiver, args)
		if ctx != nil && ctx.Context.Err() != nil {
			panic(cancelled{})
		}
		return value
	}
}

// BoundDirect binds a receiver to a direct method body.
func BoundDirect(receiver Value, labels []string, result string, direct func(*Execution, Value, []Value) Value) Function {
	return NewFunction(labels, result, func(ctx *Execution, args []Value) Value { return direct(ctx, receiver, args) })
}

// loopExit crosses generated expression closures, never a source callable.
type loopExit struct{ stop bool }

func ExitLoop(stop bool) {
	controlPanics.Add(1)
	panic(loopExit{stop})
}

func LoopBody(body func() Value) (exit int) {
	defer func() {
		if controlPanics.Load() == 0 {
			return
		}
		if failure := recover(); failure != nil {
			if loop, ok := failure.(loopExit); ok {
				controlPanics.Add(-1)
				if loop.stop {
					exit = 1
				} else {
					exit = 2
				}
			} else {
				panic(failure)
			}
		}
	}()
	body()
	return 0
}

// Seq returns value after evaluating it in place, which orders the operand
// before the calls that follow it in a Go expression.
func Seq[T any](value T) T { return value }

// SourceAccessorRead is the executable-read boundary for source implementation
// thunks. Its receiver and evidence are already evaluated; it never constructs a
// callable value. Direct source reads retain their own sampled entry behavior.
func SourceAccessorRead(ctx *Execution, receiver Value, result, position string, typeArgs map[string]string, typeScopes map[string]TypeScope, body func(*Execution, Value, map[string]string, map[string]TypeScope) Value) (value Value) {
	defer func() {
		if controlPanics.Load() == 0 {
			return
		}
		if failure := recover(); failure != nil {
			if p, ok := failure.(propagation); ok {
				controlPanics.Add(-1)
				CheckCancelled(ctx)
				value = Alternative{Type: result, Tag: "error", Fields: []Value{p.Cause}}
			} else {
				panic(failure)
			}
		}
	}()
	value = sourceAccessorBody(ctx, receiver, position, typeArgs, typeScopes, body)
	CheckCancelled(ctx)
	return value
}
func sourceAccessorBody(ctx *Execution, receiver Value, position string, typeArgs map[string]string, typeScopes map[string]TypeScope, body func(*Execution, Value, map[string]string, map[string]TypeScope) Value) (value Value) {
	if ctx != nil && ctx.calls != nil {
		calls := ctx.calls
		if calls.depth++; calls.depth > MaxCallDepth {
			sourceDepthFault(calls)
		}
		defer func() { calls.depth-- }()
	}
	defer func() {
		if controlPanics.Load() == 0 {
			return
		}
		if failure := recover(); failure != nil {
			if returned, ok := consumeSourceReturn(failure); ok {
				value = returned
				return
			}
			panic(failure)
		}
	}()
	if sourceProfiling.Load() {
		return profileSource(ctx, position, nil, func(ctx *Execution, _ []Value) Value { return body(ctx, receiver, typeArgs, typeScopes) })
	}
	return body(ctx, receiver, typeArgs, typeScopes)
}
