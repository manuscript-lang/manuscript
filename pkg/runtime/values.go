// Package msruntime implements the checked operations used by generated Go.
package msruntime

import (
	"context"
	"fmt"
	"os"
	"reflect"
	goruntime "runtime"
	"sort"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/manuscript-lang/manuscript/internal/nativeabi"
)

type Value = any
type Unit struct{}
type Function struct {
	Labels []string
	Result string
	Body   func(*Execution, []Value) Value
}
type Generic struct {
	Variables []string
	Build     func(map[string]string, map[string]TypeScope) Function
}

// TypeScope carries lexical implementation selection through specialization.
// Arguments retain their own scopes so a generic implementation can forward
// its receiver's type parameters without changing their contract evidence.
type TypeScope struct {
	Module string
	Args   []TypeScope
}
type Argument struct {
	Name  string
	Value Value
}
type Record struct {
	Type   string
	Fields map[string]Value
}
type Alternative struct {
	Type, Tag string
	Fields    []Value
}
type List struct {
	Type  string
	Items []Value
	// shared marks Items as visible to a running for-loop; in-place writes must clone first.
	shared bool
}

// ownItems gives the list a private backing array before an in-place write.
func (l *List) ownItems() {
	if l.shared {
		l.Items = append([]Value(nil), l.Items...)
		l.shared = false
	}
}

// snapshot retains membership without copying the backing array. All updates
// to existing elements detach through ownItems; appends lie beyond this length.
// The private header prevents callback traversal from observing alias growth.
func (l *List) snapshot() *List {
	l.shared = true
	return &List{Type: l.Type, Items: l.Items[:len(l.Items):len(l.Items)], shared: true}
}

type Map struct {
	Type    string
	Entries []Entry
	keys    keyIndex
	// shared marks Entries as visible to a running for-loop; in-place writes must clone first.
	shared bool
}
type Entry struct{ Key, Value Value }
type Set struct {
	Type  string
	Items []Value
	keys  keyIndex
	// shared marks Items as visible to a running for-loop; in-place writes must clone first.
	shared bool
}
type Bytes struct{ Items []byte }
type Duration int64
type Instant struct {
	Domain *clockDomain
	Tick   int64
}

//lint:ignore U1000 A nonzero size keeps distinct clock-domain pointers distinguishable.
type clockDomain struct{ identity byte }
type View struct {
	Type     string
	Receiver Value
	Scope    TypeScope
}
type propagation struct{ Cause Value }

// controlPanics counts in-flight propagation, source-return and loop-exit
// panics. Layers that only consume those skip recover when none exist, since
// a recover-and-repanic at every frame makes unwinding a deep stack quadratic.
var controlPanics atomic.Int64

type Fault struct {
	Message   string
	Secondary []string
	Frames    []string
	Truncated bool
}

func (f Fault) Error() string {
	message := f.Message
	if len(f.Secondary) > 0 {
		message += "; cleanup faults: " + strings.Join(f.Secondary, "; ")
	}
	if len(f.Frames) > 0 {
		message += "\n  at " + strings.Join(f.Frames, "\n  at ")
	}
	if f.Truncated {
		message += "\n  ... outer frames omitted"
	}
	return message
}

func Panic(message string) Value { panic(Fault{Message: message}) }
func Bool(v Value) bool {
	if b, ok := v.(bool); ok {
		return b
	}
	Panic("runtime invariant: expected Bool")
	return false
}
func NewFunction(labels []string, result string, body func(*Execution, []Value) Value) Function {
	return newFunction(labels, result, body, nil)
}
func NewAcquisition(labels []string, result string, body func(*Execution, []Value) Value, dispose func(*Execution, Value)) Function {
	return newFunction(labels, result, body, dispose)
}
func newFunction(labels []string, result string, body func(*Execution, []Value) Value, dispose func(*Execution, Value)) Function {
	return Function{labels, result, func(ctx *Execution, args []Value) (value Value) {
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
		if ctx != nil && ctx.Context.Err() != nil {
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
	return Function{f.Labels, f.Result, func(ctx *Execution, args []Value) Value {
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
func NewRecord(typ string, args []Argument) Value {
	fields := map[string]Value{}
	for _, arg := range args {
		fields[arg.Name] = arg.Value
	}
	return Record{typ, fields}
}
func NewAlternative(typ, tag string, labels []string, args []Argument) Value {
	values := make([]Value, len(labels))
	for _, a := range args {
		for i, label := range labels {
			if a.Name == label {
				values[i] = a.Value
			}
		}
	}
	return Alternative{typ, tag, values}
}
func Field(value Value, name string) Value           { return readField(value.(Record).Fields, name) }
func SetField(value Value, name string, field Value) { writeField(value.(Record).Fields, name, field) }
func Tag(value Value) string                         { return value.(Alternative).Tag }
func Payload(value Value, index int) Value           { return value.(Alternative).Fields[index] }
func Positions(value Value, length int) []Value {
	var values []Value
	switch v := value.(type) {
	case *List:
		values = v.Items
	default:
		Panic("runtime invariant: positional binding")
	}
	if len(values) != length {
		Panic(fmt.Sprintf("destructuring length mismatch; the pattern binds %d names but the list has %d elements", length, len(values)))
	}
	return values
}
func Iterate(value Value) []Value {
	switch v := value.(type) {
	case *List:
		// Loops see the elements as of loop start. Appends land beyond the captured
		// length; in-place writes call ownItems and leave this slice untouched.
		v.shared = true
		return v.Items[:len(v.Items):len(v.Items)]
	case *Set:
		v.shared = true
		return v.Items[:len(v.Items):len(v.Items)]
	case *Map:
		values := make([]Value, len(v.Entries))
		args := typeArguments(v.Type)
		entryType := "@std/MapEntry[" + args[0] + "][" + args[1] + "]"
		for i, e := range v.Entries {
			values[i] = Record{entryType, map[string]Value{"key": e.Key, "value": e.Value}}
		}
		return values
	}
	Panic("runtime invariant: iterable")
	return nil
}
func Text(values ...Value) Value {
	var text strings.Builder
	for _, v := range values {
		text.WriteString(Format(v))
	}
	return text.String()
}
func Format(value Value) string {
	return formatValue(value, 0)
}

// Opaque resources are deliberately not inspected or invoked while formatting.
// The depth limit also makes cyclic values supplied by native adapters printable.
func formatValue(value Value, depth int) string {
	if depth >= 64 {
		return "..."
	}
	items := func(values []Value) string {
		parts := make([]string, len(values))
		for i, value := range values {
			parts[i] = formatValue(value, depth+1)
		}
		return strings.Join(parts, ", ")
	}
	switch v := value.(type) {
	case string:
		return v
	case int64:
		return strconv.FormatInt(v, 10)
	case float64:
		return formatFloat(v)
	case bool:
		return strconv.FormatBool(v)
	case Unit:
		return "unit"
	case Decimal:
		return v.String()
	case Record:
		fields := fieldsSnapshot(v.Fields)
		names := make([]string, 0, len(fields))
		for name := range fields {
			names = append(names, name)
		}
		sort.Strings(names)
		parts := make([]string, len(names))
		for i, name := range names {
			parts[i] = name + ": " + formatValue(fields[name], depth+1)
		}
		return displayType(v.Type) + "(" + strings.Join(parts, ", ") + ")"
	case Alternative:
		text := displayType(v.Type) + "." + v.Tag
		if len(v.Fields) > 0 {
			text += "(" + items(v.Fields) + ")"
		}
		return text
	case *List:
		return "[" + items(v.Items) + "]"
	case *Map:
		parts := make([]string, len(v.Entries))
		for i, entry := range v.Entries {
			parts[i] = formatValue(entry.Key, depth+1) + ": " + formatValue(entry.Value, depth+1)
		}
		return "Map(" + strings.Join(parts, ", ") + ")"
	case *Set:
		return "Set(" + items(v.Items) + ")"
	case Bytes:
		parts := make([]string, len(v.Items))
		for i, b := range v.Items {
			parts[i] = strconv.Itoa(int(b))
		}
		return "Bytes(" + strings.Join(parts, ", ") + ")"
	case View:
		return formatValue(v.Receiver, depth+1)
	case Function, Generic:
		return "[function]"
	case Duration:
		return strconv.FormatInt(int64(v), 10) + "ns"
	case Instant:
		return "Instant(" + strconv.FormatInt(v.Tick, 10) + ")"
	case OperationId:
		return "OperationId(" + strconv.FormatUint(v.number, 10) + ")"
	case libraryBigInt:
		return v.n.String()
	case libraryTimestamp:
		return v.t.UTC().Format("2006-01-02T15:04:05.999999999Z07:00")
	case libraryRegex:
		return v.pattern.String()
	}
	return "[object]"
}

func displayType(key string) string {
	name, _ := splitType(key)
	if at := strings.LastIndexAny(name, "/#"); at >= 0 {
		name = name[at+1:]
	}
	return name
}

type equalityIdentity struct {
	pointer  any
	typ, tag string
}
type equalityPair struct{ left, right equalityIdentity }
type equalityState struct {
	active map[equalityPair]bool
	ctx    *Execution
	scope  TypeScope
}

func equalityID(value Value) (equalityIdentity, bool) {
	switch v := value.(type) {
	case Record:
		return equalityIdentity{reflect.ValueOf(v.Fields).UnsafePointer(), v.Type, "record"}, true
	case *List:
		return equalityIdentity{v, v.Type, "list"}, true
	case *Map:
		return equalityIdentity{v, v.Type, "map"}, true
	case *Set:
		return equalityIdentity{v, v.Type, "set"}, true
	case Alternative:
		return equalityIdentity{reflect.ValueOf(v.Fields).UnsafePointer(), v.Type, v.Tag}, true
	}
	return equalityIdentity{}, false
}

// primitiveEqual compares Int, Float, String, and Bool operands directly. These
// types cannot carry a user Equal implementation, so it needs no scope, cycle
// bookkeeping, or state allocation.
func primitiveEqual(a, b Value) (result, ok bool) {
	switch x := a.(type) {
	case int64:
		if y, same := b.(int64); same {
			return x == y, true
		}
	case string:
		if y, same := b.(string); same {
			return x == y, true
		}
	case bool:
		if y, same := b.(bool); same {
			return x == y, true
		}
	case float64:
		if y, same := b.(float64); same {
			return x == y, true
		}
	}
	return false, false
}

func Equal(a, b Value) bool                   { return equal(a, b, &equalityState{}) }
func EqualIn(ctx *Execution, a, b Value) bool { return EqualSelected(ctx, a, b, ctx.EqualityScope) }
func EqualSelected(ctx *Execution, a, b Value, scope TypeScope) bool {
	if result, ok := primitiveEqual(a, b); ok {
		return result
	}
	return equal(a, b, &equalityState{ctx: ctx, scope: scope})
}
func Equality(ctx *Execution, operator string, a, b Value, scope TypeScope) Value {
	result := EqualSelected(ctx, a, b, scope)
	if operator == "!=" {
		result = !result
	}
	return result
}
func equal(a, b Value, state *equalityState) bool {
	if result, ok := primitiveEqual(a, b); ok {
		return result
	}
	if view, ok := a.(View); ok {
		a = view.Receiver
		stateCopy := *state
		stateCopy.scope = view.Scope
		state = &stateCopy
	}
	if view, ok := b.(View); ok {
		b = view.Receiver
	}
	if state.ctx != nil {
		if method, ok := implementationFunction(a, "@std/Equal", "equals", state.scope); ok {
			return Invoke(state.ctx, method, []Argument{{"other", ViewOf("@std/Equal", b, state.scope)}}).(bool)
		}
	}
	if left, ok := equalityID(a); ok {
		if right, ok := equalityID(b); ok {
			pair := equalityPair{left, right}
			if state.active[pair] {
				return true
			}
			if state.active == nil {
				state.active = map[equalityPair]bool{}
			}
			state.active[pair] = true
			defer delete(state.active, pair)
		}
	}
	switch x := a.(type) {
	case libraryBigInt:
		y, ok := b.(libraryBigInt)
		return ok && x.n.Cmp(y.n) == 0
	case libraryTimestamp:
		y, ok := b.(libraryTimestamp)
		return ok && x.t.Equal(y.t)
	case int64:
		y, ok := b.(int64)
		return ok && x == y
	case float64:
		y, ok := b.(float64)
		return ok && x == y
	case string:
		y, ok := b.(string)
		return ok && x == y
	case bool:
		y, ok := b.(bool)
		return ok && x == y
	case Unit:
		_, ok := b.(Unit)
		return ok
	case Decimal:
		y, ok := b.(Decimal)
		return ok && x.Value.Cmp(y.Value) == 0
	case Duration:
		y, ok := b.(Duration)
		return ok && x == y
	case Instant:
		y, ok := b.(Instant)
		if !ok {
			return false
		}
		sameClock(x, y)
		return x.Tick == y.Tick
	case Bytes:
		y, ok := b.(Bytes)
		if !ok || len(x.Items) != len(y.Items) {
			return false
		}
		for i, v := range x.Items {
			if v != y.Items[i] {
				return false
			}
		}
		return true
	case Record:
		y, ok := b.(Record)
		if !ok || x.Type != y.Type {
			return false
		}
		xf, yf := fieldsSnapshot(x.Fields), fieldsSnapshot(y.Fields)
		if len(xf) != len(yf) {
			return false
		}
		for k, v := range xf {
			if !equal(v, yf[k], state) {
				return false
			}
		}
		return true
	case Alternative:
		y, ok := b.(Alternative)
		return ok && x.Type == y.Type && x.Tag == y.Tag && equalItemsState(x.Fields, y.Fields, state)
	case *List:
		y, ok := b.(*List)
		return ok && x.Type == y.Type && equalItemsState(x.Items, y.Items, equalityChild(state, 0))
	case *Set:
		y, ok := b.(*Set)
		if !ok || x.Type != y.Type || len(x.Items) != len(y.Items) {
			return false
		}
		for _, v := range x.Items {
			found := false
			for _, other := range y.Items {
				if equal(v, other, equalityChild(state, 0)) {
					found = true
					break
				}
			}
			if !found {
				return false
			}
		}
		return true
	case *Map:
		y, ok := b.(*Map)
		if !ok || x.Type != y.Type || len(x.Entries) != len(y.Entries) {
			return false
		}
		for _, e := range x.Entries {
			found := false
			for _, f := range y.Entries {
				if equal(e.Key, f.Key, equalityChild(state, 0)) && equal(e.Value, f.Value, equalityChild(state, 1)) {
					found = true
					break
				}
			}
			if !found {
				return false
			}
		}
		return true
	}
	return false
}
func equalItemsState(a, b []Value, state *equalityState) bool {
	if len(a) != len(b) {
		return false
	}
	for i, v := range a {
		if !equal(v, b[i], state) {
			return false
		}
	}
	return true
}
func sameClock(a, b Instant) {
	if a.Domain != b.Domain {
		Panic("instants belong to different clock domains")
	}
}
func ResolveType(pattern string, sub map[string]string) string {
	if at := strings.IndexByte(pattern, ':'); at >= 0 && (!strings.Contains(pattern[:at], "[")) {
		return pattern[:at+1] + ResolveType(pattern[at+1:], sub)
	}
	name, args := splitType(pattern)
	if v := sub[name]; v != "" && len(args) == 0 {
		return v
	}
	var out strings.Builder
	out.WriteString(name)
	for _, arg := range args {
		out.WriteString("[")
		out.WriteString(ResolveType(arg, sub))
		out.WriteString("]")
	}
	return out.String()
}
func splitType(key string) (name string, args []string) {
	index := strings.IndexByte(key, '[')
	if index < 0 {
		return key, nil
	}
	name = key[:index]
	for index < len(key) {
		start := index + 1
		depth := 1
		index++
		for index < len(key) && depth > 0 {
			if key[index] == '[' {
				depth++
			}
			if key[index] == ']' {
				depth--
			}
			index++
		}
		args = append(args, key[start:index-1])
	}
	return
}
func typeArguments(key string) []string { _, a := splitType(key); return a }
func matchType(pattern, actual string, vars map[string]bool, sub map[string]string) bool {
	if at := strings.IndexByte(pattern, ':'); at >= 0 && !strings.Contains(pattern[:at], "[") {
		label := pattern[:at+1]
		return strings.HasPrefix(actual, label) && matchType(pattern[at+1:], actual[len(label):], vars, sub)
	}
	pn, pa := splitType(pattern)
	an, aa := splitType(actual)
	if vars[pn] && len(pa) == 0 {
		if previous := sub[pn]; previous != "" {
			return previous == actual
		}
		sub[pn] = actual
		return true
	}
	if pn != an || len(pa) != len(aa) {
		return false
	}
	for i, p := range pa {
		if !matchType(p, aa[i], vars, sub) {
			return false
		}
	}
	return true
}

type Implementation struct {
	Receiver, Contract, Name string
	// Scope is empty for implementations in the receiver's defining module.
	Scope     string
	Variables []string
	Build     func(Value, map[string]string, map[string]TypeScope) Function
	// Direct runs a nongeneric method for any receiver of the implemented type
	// without first binding it; Build derives from it when present.
	Direct func(*Execution, Value, []Value) Value
}

var implementations []Implementation

// implementationsByName indexes implementations by method name so a lookup
// visits only candidates instead of the whole registry.
var implementationsByName = map[string][]int{}

func Register(implementation Implementation) {
	implementationCache.Clear()
	implementationGeneration.Add(1)
	implementationsByName[implementation.Name] = append(implementationsByName[implementation.Name], len(implementations))
	implementations = append(implementations, implementation)
}
func ViewOf(contract string, receiver Value, scopes ...TypeScope) Value {
	scope := TypeScope{}
	if len(scopes) > 0 {
		scope = scopes[0]
	}
	if v, ok := receiver.(View); ok {
		if v.Type == contract {
			return receiver
		}
		receiver = v.Receiver
		scope = v.Scope
	}
	return View{Type: contract, Receiver: receiver, Scope: scope}
}
func ContractReceiver(value Value) Value {
	if view, ok := value.(View); ok {
		return view.Receiver
	}
	return value
}
func ConcreteType(value Value) string {
	switch value := value.(type) {
	case Record:
		return value.Type
	case Alternative:
		return value.Type
	default:
		// Native receivers remain available to the generic wildcard handler.
		return ""
	}
}
func Bind(receiver Value, contract, name string, scopes ...TypeScope) Value {
	if name == "toString" {
		return NativeMember(receiver, name)
	}
	scope := TypeScope{}
	if len(scopes) > 0 {
		scope = scopes[0]
	}
	if view, ok := receiver.(View); ok {
		if contract == "" {
			contract = view.Type
		}
		receiver = view.Receiver
		scope = view.Scope
	}
	if native, ok := receiver.(Native); ok {
		return native.Operation(name)
	}
	if method, ok := implementationFunction(receiver, contract, name, scope); ok {
		return method
	}

	return NativeMember(receiver, name)
}

func implementationScopes(pattern string, scope TypeScope, vars map[string]bool, result map[string]TypeScope) {
	name, args := splitType(pattern)
	if vars[name] && len(args) == 0 {
		result[name] = scope
		return
	}
	for i, arg := range args {
		child := TypeScope{Module: scope.Module}
		if i < len(scope.Args) {
			child = scope.Args[i]
		}
		implementationScopes(arg, child, vars, result)
	}
}

type Test struct {
	Name string
	Run  Function
}

// DefaultTestTimeout bounds each test run by the generated test executable
// so one deadlocked test cannot hang the whole run silently.
const DefaultTestTimeout = 60 * time.Second

// testCancelGrace is how long a timed-out test gets to unwind after
// cancellation before the runner abandons it and moves on.
const testCancelGrace = 2 * time.Second

// TestOptions selects and bounds the tests a run executes. A zero Timeout
// disables the per-test limit; a non-empty Filter keeps tests whose full
// name (module::name) contains it.
type TestOptions struct {
	Timeout time.Duration
	Filter  string
}

// ParseTestArgs reads --timeout=<duration> and --filter=<text> from the test
// executable's arguments; other arguments are ignored.
func ParseTestArgs(args []string) (TestOptions, error) {
	options := TestOptions{Timeout: DefaultTestTimeout}
	for _, arg := range args {
		switch {
		case strings.HasPrefix(arg, "--timeout="):
			timeout, err := time.ParseDuration(strings.TrimPrefix(arg, "--timeout="))
			if err != nil || timeout < 0 {
				return options, fmt.Errorf("invalid --timeout %q; use a duration such as 30s or 2m, or 0 to disable", strings.TrimPrefix(arg, "--timeout="))
			}
			options.Timeout = timeout
		case strings.HasPrefix(arg, "--filter="):
			options.Filter = strings.TrimPrefix(arg, "--filter=")
		}
	}
	return options, nil
}

// RunTestsArgs runs tests with the options encoded in the executable's arguments.
func RunTestsArgs(tests []Test, args []string) int {
	reporter, err := openTestReporter()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 2
	}
	defer reporter.close()
	options, err := ParseTestArgs(args)
	if err != nil {
		reporter.emit(nativeabi.TestEvent{Event: "error", Reason: "argument_error", Failure: err.Error()})
		fmt.Fprintln(os.Stderr, err)
		return 2
	}
	return runTestsWith(tests, options, reporter)
}

func RunTests(tests []Test) int { return RunTestsWith(tests, TestOptions{}) }

func RunTestsWith(tests []Test, options TestOptions) int {
	return runTestsWith(tests, options, nil)
}

func runTestsWith(tests []Test, options TestOptions, reporter *testReporter) int {
	total := len(tests)
	if options.Filter != "" {
		var selected []Test
		for _, test := range tests {
			if strings.Contains(test.Name, options.Filter) {
				selected = append(selected, test)
			}
		}
		tests = selected
	}
	if reporter != nil {
		names := make([]string, len(tests))
		for i, test := range tests {
			names[i] = test.Name
		}
		reporter.emit(nativeabi.TestEvent{Event: "plan", Format: 1, Available: total, Names: names})
	}
	if options.Filter != "" {
		if len(tests) == 0 {
			reporter.emit(nativeabi.TestEvent{Event: "done", Reason: "no_match"})
			fmt.Printf("no tests match filter %q (%d tests available); the filter matches any part of a test's module::name\n", options.Filter, total)
			return 1
		}
	}
	failed := 0
	for i, test := range tests {
		reporter.emit(nativeabi.TestEvent{Event: "run", Index: i})
		fmt.Printf("RUN %s\n", test.Name)
		if failure := runTest(test, options.Timeout); failure != nil {
			failed++
			if reporter != nil {
				reporter.emit(nativeabi.TestEvent{Event: "failed", Index: i, Failure: fmt.Sprint(failure)})
			}
			fmt.Printf("FAIL %s: %v\n", test.Name, failure)
			continue
		}
		reporter.emit(nativeabi.TestEvent{Event: "passed", Index: i})
		fmt.Printf("PASS %s\n", test.Name)
	}
	if len(tests) == 0 {
		fmt.Println("no test blocks found: add test blocks to test.ms or *_test.ms files in the project, or pass a .ms file")
	}
	fmt.Printf("%d tests, %d failed\n", len(tests), failed)
	reason := ""
	if len(tests) == 0 {
		reason = "no_tests"
	}
	reporter.emit(nativeabi.TestEvent{Event: "done", Reason: reason})
	return failed
}

// runTest executes one test on its own root execution and returns its failure.
// When the timeout elapses the execution is cancelled; a test that still does
// not stop is abandoned after a goroutine dump so later tests can run.
func runTest(test Test, timeout time.Duration) any {
	execution := RootExecution()
	cancelled, cancel := context.WithCancel(execution.Context)
	defer cancel()
	execution.Context = cancelled
	done := make(chan any, 1)
	go func() {
		var failure any
		defer func() { done <- failure }()
		defer func() {
			if r := recover(); r != nil {
				failure = r
			}
		}()
		if err := execution.Host.initialize(); err != nil {
			Panic(err.Error())
		}
		defer Cleanup(execution, hostValue(execution, "stdin"))
		defer Cleanup(execution, hostValue(execution, "stdout"))
		defer Cleanup(execution, hostValue(execution, "stderr"))
		defer Cleanup(execution, hostValue(execution, "network"))
		defer FinishExecution(execution)
		Invoke(execution, test.Run, nil)
	}()
	if timeout <= 0 {
		return <-done
	}
	timer := time.NewTimer(timeout)
	defer timer.Stop()
	select {
	case failure := <-done:
		return failure
	case <-timer.C:
	}
	cancel()
	select {
	case <-done:
		return fmt.Sprintf("timed out after %s; the test was cancelled (use --timeout to change the limit, 0 disables it)", timeout)
	case <-time.After(testCancelGrace):
	}
	stacks := make([]byte, 1<<20)
	stacks = stacks[:goruntime.Stack(stacks, true)]
	fmt.Fprintf(os.Stderr, "goroutines after timeout in %s:\n%s\n", test.Name, stacks)
	return fmt.Sprintf("timed out after %s and did not stop when cancelled; goroutine dump is on stderr", timeout)
}

type sourceReturn struct{ value Value }

func Return(value Value) Value {
	controlPanics.Add(1)
	panic(sourceReturn{value})
}

// MaxCallDepth bounds nested source calls per execution so runaway recursion
// is a fault instead of Go's unrecoverable stack overflow.
const MaxCallDepth = 200000

// maxFaultFrames bounds the trace kept on a fault; deeper frames are counted.
const maxFaultFrames = 32

// SourceCall is the single source boundary used by native entries and boxed
// adapters. The body is unguarded and owns its source trace and cleanup defers.
// T must use the same dynamic representation as its checked Value boundary.
func SourceCall[T any](ctx *Execution, result string, body func(*Execution) T) (value T) {
	CheckCancelled(ctx)
	if ctx != nil && ctx.calls != nil {
		calls := ctx.calls
		if calls.depth.Add(1) > MaxCallDepth {
			calls.depth.Add(-1)
			Panic(fmt.Sprintf("call depth limit exceeded (%d nested calls)", MaxCallDepth))
		}
		defer func() {
			if calls.depth.Add(-1) == 0 {
				calls.traceFull.Store(false)
			}
		}()
	}
	completed := false
	defer func() {
		if controlPanics.Load() != 0 {
			if failure := recover(); failure != nil {
				switch failure := failure.(type) {
				case sourceReturn:
					controlPanics.Add(-1)
					// A boxed runtime callback may return nil. Preserve that Value
					// without accepting nil as a typed scalar representation.
					if failure.value == nil {
						var zero T
						if any(zero) == nil {
							value, completed = zero, true
							break
						}
					}
					value = any(failure.value).(T)
					completed = true
				case propagation:
					controlPanics.Add(-1)
					CheckCancelled(ctx)
					value = any(Alternative{Type: result, Tag: "error", Fields: []Value{failure.Cause}}).(T)
					return
				default:
					panic(failure)
				}
			}
		}
		if completed && ctx != nil && ctx.Context.Err() != nil {
			panic(cancelled{})
		}
	}()
	value = body(ctx)
	completed = true
	return value
}

// Keep the adapter in this package. Inlining it into generated importers loses
// the shared generic guard's no-escape fact and allocates a body thunk per call.
//
//go:noinline
func NewSourceFunction(labels []string, result, position string, body func(*Execution, []Value) Value) Function {
	return Function{labels, result, func(ctx *Execution, args []Value) Value {
		if SourceCallNeedsProfile(ctx) {
			return ProfileSourceCall(ctx, result, position, func(ctx *Execution) Value { return body(ctx, args) })
		}
		return SourceCall(ctx, result, func(ctx *Execution) Value { return body(ctx, args) })
	}}
}

type implementationKey struct {
	typ, contract, name, module, args string
}

// resolvedImplementation is the receiver-independent outcome of a lookup.
type resolvedImplementation struct {
	impl       *Implementation
	sub        map[string]string
	typeScopes map[string]TypeScope
}

// implementationGeneration invalidates call-site caches when Register runs.
var implementationGeneration atomic.Uint64

// SourceDirect and BoundDirect select the same guarded entry. Neither adapter
// adds another source guard around it.
//
//go:noinline
func SourceDirect(position, result string, body func(*Execution, Value, []Value) Value) func(*Execution, Value, []Value) Value {
	return func(ctx *Execution, receiver Value, args []Value) Value {
		if SourceCallNeedsProfile(ctx) {
			return ProfileSourceCall(ctx, result, position, func(ctx *Execution) Value { return body(ctx, receiver, args) })
		}
		return SourceCall(ctx, result, func(ctx *Execution) Value { return body(ctx, receiver, args) })
	}
}

func BoundDirect(receiver Value, labels []string, result string, direct func(*Execution, Value, []Value) Value) Function {
	return Function{labels, result, func(ctx *Execution, args []Value) Value { return direct(ctx, receiver, args) }}
}

// MethodSite caches the direct body last resolved for one call site.
type MethodSite struct {
	entry atomic.Pointer[methodEntry]
}

type methodEntry struct {
	generation uint64
	typ        string
	direct     func(*Execution, Value, []Value) Value
}

// CallMethod calls a user method whose receiver has a concrete record or
// alternative type. Arguments are already in declaration order.
func CallMethod(ctx *Execution, site *MethodSite, receiver Value, contract, name string, scope TypeScope, args []Value) Value {
	typ := ConcreteType(receiver)
	if e := site.entry.Load(); e != nil && e.typ == typ && e.generation == implementationGeneration.Load() {
		CheckCancelled(ctx)
		return e.direct(ctx, receiver, args)
	}
	return callMethodSlow(ctx, site, receiver, contract, name, scope, args)
}

func callMethodSlow(ctx *Execution, site *MethodSite, receiver Value, contract, name string, scope TypeScope, args []Value) Value {
	generation := implementationGeneration.Load()
	typ := ConcreteType(receiver)
	if typ != "" && name != "toString" {
		key := implementationKey{typ: typ, contract: contract, name: name, module: scope.Module}
		if len(scope.Args) == 0 {
			var resolved *resolvedImplementation
			if cached, ok := implementationCache.Load(key); ok {
				resolved = cached.(*resolvedImplementation)
			} else {
				resolved = resolveImplementation(typ, contract, name, scope)
				implementationCache.Store(key, resolved)
			}
			if resolved != nil && resolved.impl.Direct != nil {
				site.entry.Store(&methodEntry{generation: generation, typ: typ, direct: resolved.impl.Direct})
				CheckCancelled(ctx)
				return resolved.impl.Direct(ctx, receiver, args)
			}
		}
	}
	f, ok := Bind(receiver, contract, name, scope).(Function)
	if !ok {
		return Panic("runtime invariant: callee is not specialized")
	}
	CheckCancelled(ctx)
	return f.Body(ctx, args)
}

// implementationCache memoizes lookups; Register discards it.
var implementationCache sync.Map

func implementationFunction(receiver Value, contract, name string, scope TypeScope) (Function, bool) {
	key := implementationKey{typ: ConcreteType(receiver), contract: contract, name: name, module: scope.Module}
	if len(scope.Args) > 0 {
		var b strings.Builder
		writeScopeKey(&b, scope)
		key.args = b.String()
	}
	if cached, ok := implementationCache.Load(key); ok {
		resolved := cached.(*resolvedImplementation)
		if resolved == nil {
			return Function{}, false
		}
		return resolved.impl.Build(receiver, resolved.sub, resolved.typeScopes), true
	}
	resolved := resolveImplementation(key.typ, contract, name, scope)
	implementationCache.Store(key, resolved)
	if resolved == nil {
		return Function{}, false
	}
	return resolved.impl.Build(receiver, resolved.sub, resolved.typeScopes), true
}

func resolveImplementation(typ, contract, name string, scope TypeScope) *resolvedImplementation {
	for _, at := range implementationsByName[name] {
		m := &implementations[at]
		if m.Scope != "" && m.Scope != scope.Module {
			continue
		}
		vars := map[string]bool{}
		for _, v := range m.Variables {
			vars[v] = true
		}
		sub := map[string]string{}
		if matchType(m.Receiver, typ, vars, sub) && (contract == "" || ResolveType(m.Contract, sub) == contract) {
			typeScopes := map[string]TypeScope{}
			implementationScopes(m.Receiver, scope, vars, typeScopes)
			return &resolvedImplementation{m, sub, typeScopes}
		}
	}
	return nil
}

func indexOfIn(ctx *Execution, items []Value, value Value) int {
	for i, v := range items {
		if EqualIn(ctx, v, value) {
			return i
		}
	}
	return -1
}

func equalityChild(state *equalityState, index int) *equalityState {
	if index >= len(state.scope.Args) {
		return state
	}
	child := *state
	child.scope = state.scope.Args[index]
	return &child
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

// SourceAt records an operation's site after its operands have been evaluated.
func SourceAt[T any](position *string, site string, value T) T {
	*position = site
	return value
}

// TraceSource runs once per source function, after its cleanup has completed.
func TraceSource(ctx *Execution, position *string, name string) {
	if ctx != nil && ctx.calls != nil && ctx.calls.traceFull.Load() {
		return
	}
	if failure := recover(); failure != nil {
		if fault, ok := failure.(Fault); ok {
			fault.Frames = append(append([]string{}, fault.Frames...), *position+" in "+name)
			if len(fault.Frames) >= maxFaultFrames && ctx != nil && ctx.calls != nil {
				// Re-raising at every frame makes unwinding a deep stack
				// quadratic, so outer frames are no longer recorded.
				fault.Truncated = true
				ctx.calls.traceFull.Store(true)
			}
			panic(fault)
		}
		panic(failure)
	}
}
