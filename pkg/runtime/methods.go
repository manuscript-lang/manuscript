package msruntime

import (
	"strings"
	"sync"
	"sync/atomic"
)

// TypeScope carries lexical implementation selection through specialization.
// Arguments retain their own scopes so a generic implementation can forward
// its receiver's type parameters without changing their contract evidence.
type TypeScope struct {
	Module string
	Args   []TypeScope
}

type View struct {
	Type     string
	Receiver Value
	Scope    TypeScope
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
	case Struct:
		return value.StructType()
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
