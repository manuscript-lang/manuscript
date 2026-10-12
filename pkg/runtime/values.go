// Package msruntime implements the checked operations used by generated Go.
package msruntime

import (
	"fmt"
	"reflect"
	"sort"
	"strconv"
	"strings"
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
}
type Pack struct{ Items []Value }
type Map struct {
	Type    string
	Entries []Entry
}
type Entry struct{ Key, Value Value }
type Set struct {
	Type  string
	Items []Value
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
type Fault struct {
	Message   string
	Secondary []string
	Frames    []string
}

func (f Fault) Error() string {
	message := f.Message
	if len(f.Secondary) > 0 {
		message += "; cleanup faults: " + strings.Join(f.Secondary, "; ")
	}
	if len(f.Frames) > 0 {
		message += "\n  at " + strings.Join(f.Frames, "\n  at ")
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
			if r := recover(); r != nil {
				if p, ok := r.(propagation); ok {
					CheckCancelled(ctx)
					value = Alternative{Type: result, Tag: "error", Fields: []Value{p.Cause}}
				} else {
					panic(r)
				}
			}
		}()
		CheckCancelled(ctx)
		value = body(ctx, args)
		if ctx != nil && ctx.Context.Err() != nil && dispose != nil {
			dispose(ctx, value)
		}
		CheckCancelled(ctx)
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
func Specialize(value Value, args []string, scopes ...TypeScope) Value {
	g, ok := value.(Generic)
	if !ok {
		return value
	}
	sub := map[string]string{}
	typeScopes := map[string]TypeScope{}
	for i, v := range g.Variables {
		sub[v] = args[i]
		if i < len(scopes) {
			typeScopes[v] = scopes[i]
		}
	}
	return g.Build(sub, typeScopes)
}
func Try(value Value) Value {
	v := value.(Alternative)
	if v.Tag == "error" {
		panic(propagation{v.Fields[0]})
	}
	return v.Fields[0]
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
func Field(value Value, name string) Value           { return value.(Record).Fields[name] }
func SetField(value Value, name string, field Value) { value.(Record).Fields[name] = field }
func Tag(value Value) string                         { return value.(Alternative).Tag }
func Payload(value Value, index int) Value           { return value.(Alternative).Fields[index] }
func Positions(value Value, length int) []Value {
	var values []Value
	switch v := value.(type) {
	case *List:
		values = v.Items
	case Pack:
		values = v.Items
	default:
		Panic("runtime invariant: positional binding")
	}
	if len(values) != length {
		Panic("destructuring length mismatch")
	}
	return values
}
func Iterate(value Value) []Value {
	switch v := value.(type) {
	case *List:
		return append([]Value{}, v.Items...)
	case *Set:
		return append([]Value{}, v.Items...)
	case *Map:
		values := make([]Value, len(v.Entries))
		args := typeArguments(v.Type)
		for i, e := range v.Entries {
			values[i] = Record{"@std/MapEntry[" + args[0] + "][" + args[1] + "]", map[string]Value{"key": e.Key, "value": e.Value}}
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
		names := make([]string, 0, len(v.Fields))
		for name := range v.Fields {
			names = append(names, name)
		}
		sort.Strings(names)
		parts := make([]string, len(names))
		for i, name := range names {
			parts[i] = name + ": " + formatValue(v.Fields[name], depth+1)
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
	case Pack:
		return "(" + items(v.Items) + ")"
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
type equalityState struct{ active map[equalityPair]bool }

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

func Equal(a, b Value) bool { return equal(a, b, &equalityState{}) }
func equal(a, b Value, state *equalityState) bool {
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
		if !ok || x.Type != y.Type || len(x.Fields) != len(y.Fields) {
			return false
		}
		for k, v := range x.Fields {
			if !equal(v, y.Fields[k], state) {
				return false
			}
		}
		return true
	case Alternative:
		y, ok := b.(Alternative)
		return ok && x.Type == y.Type && x.Tag == y.Tag && equalItemsState(x.Fields, y.Fields, state)
	case *List:
		y, ok := b.(*List)
		return ok && x.Type == y.Type && equalItemsState(x.Items, y.Items, state)
	case *Set:
		y, ok := b.(*Set)
		if !ok || x.Type != y.Type || len(x.Items) != len(y.Items) {
			return false
		}
		for _, v := range x.Items {
			found := false
			for _, other := range y.Items {
				if equal(v, other, state) {
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
				if equal(e.Key, f.Key, state) && equal(e.Value, f.Value, state) {
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
func indexOf(items []Value, value Value) int {
	for i, v := range items {
		if Equal(v, value) {
			return i
		}
	}
	return -1
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
}

var implementations []Implementation

func Register(implementation Implementation) {
	implementations = append(implementations, implementation)
}
func ViewOf(contract string, receiver Value, scopes ...TypeScope) Value {
	scope := TypeScope{}
	if len(scopes) > 0 {
		scope = scopes[0]
	}
	if v, ok := receiver.(View); ok {
		receiver = v.Receiver
		scope = v.Scope
	}
	return View{Type: contract, Receiver: receiver, Scope: scope}
}
func ContractReceiver(value Value) Value {
	if view, ok := value.(View); ok {
		return view.Receiver
	}
	return Panic("runtime invariant: expected contract view")
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
	typ := ""
	switch v := receiver.(type) {
	case Record:
		typ = v.Type
	case Alternative:
		typ = v.Type
	}
	for _, m := range implementations {
		if m.Name != name || m.Scope != "" && m.Scope != scope.Module {
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
			return m.Build(receiver, sub, typeScopes)
		}
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

func RunTests(tests []Test) int {
	failed := 0
	for _, test := range tests {
		func() {
			defer func() {
				if r := recover(); r != nil {
					failed++
					fmt.Printf("FAIL %s: %v\n", test.Name, r)
				}
			}()
			func() {
				execution := RootExecution()
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
			fmt.Printf("PASS %s\n", test.Name)
		}()
	}
	fmt.Printf("%d tests, %d failed\n", len(tests), failed)
	return failed
}

func NewSourceFunction(labels []string, result, position string, body func(*Execution, []Value) Value) Function {
	return NewFunction(labels, result, func(ctx *Execution, args []Value) (value Value) {
		defer func() {
			if failure := recover(); failure != nil {
				if fault, ok := failure.(Fault); ok {
					fault.Frames = append(append([]string{}, fault.Frames...), position)
					panic(fault)
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
