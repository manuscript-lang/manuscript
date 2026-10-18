package checker

import (
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func (c *checker) implementation(d *syntax.Declaration) {
	old := c.scope
	c.scope = newScope(nil)
	// Implementations inherit names and bounds from the nominal receiver declaration.
	var vars []*Type
	if symbol := c.names[d.Receiver.Name]; symbol != nil && symbol.Decl != nil && symbol.Kind == syntax.KindType {
		// Copy resolved bounds: their names belong to the receiver's module and
		// need not be imported by a module extending that receiver.
		sub := map[string]*Type{}
		for _, parameter := range symbol.Variables {
			v := &Type{Name: parameter.Name, ID: c.unique("typevar"), Kind: "variable"}
			vars = append(vars, v)
			c.scope.types[v.Name] = v
			sub[parameter.ID] = v
		}
		for i, parameter := range symbol.Variables {
			for _, bound := range parameter.Bounds {
				vars[i].Bounds = append(vars[i].Bounds, Sub(bound, sub))
			}
		}
	}
	receiver := c.resolve(d.Receiver, false)
	if receiver.Def == nil || receiver.Def.Symbol == nil || receiver.Def.Symbol.Native != "" && !c.standardDeclarations || (receiver.Kind != syntax.KindRecord && receiver.Kind != "alternative") {
		if receiver.ID != "<invalid>" {
			c.error(d.Pos, "type", "implementation receiver must be nominal source data; implement interfaces for a type or alternative you declare, such as 'impl Show for Point:', not for built-in or function types")
		}
		// An impl whose receiver is not valid nominal data must not become
		// evidence for later conversions; report the receiver's own faults only.
		c.wellFormed(receiver, d.Pos, map[*Type]bool{})
		c.scope = old
		return
	}
	occurs := map[string]bool{}
	var visit func(*Type)
	visit = func(t *Type) {
		occurs[t.ID] = true
		for _, a := range t.Args {
			visit(a)
		}
		for _, param := range t.Params {
			visit(param.Type)
		}
		if t.Result != nil {
			visit(t.Result)
		}
	}
	visit(receiver)
	active := vars[:0]
	specialized := map[string]*Type{}
	for i, v := range vars {
		if occurs[v.ID] {
			active = append(active, v)
		} else {
			delete(c.scope.types, v.Name)
			if i < len(receiver.Args) {
				specialized[v.ID] = receiver.Args[i]
			}
		}
	}
	vars = active
	for _, v := range vars {
		for i, bound := range v.Bounds {
			v.Bounds[i] = Sub(bound, specialized)
		}
	}
	contract := c.resolve(d.Contract, false)
	if contract.Kind != "contract" && contract.ID != "<invalid>" {
		c.error(d.Pos, "type", "implementation target must be an interface; write 'impl <Interface> for <Type>:' where the interface is declared with 'interface'")
	}
	// An interface argument that is a receiver parameter carries the interface's
	// declared bounds into this implementation, without changing the data type.
	if contract.Def != nil && len(contract.Args) == len(contract.Def.Variables) {
		sub := substitution(contract)
		for i, parameter := range contract.Def.Variables {
			argument := contract.Args[i]
			for _, v := range vars {
				if argument.ID == v.ID {
					for _, bound := range parameter.Bounds {
						v.Bounds = append(v.Bounds, Sub(bound, sub))
					}
				}
			}
		}
	}
	// Resolution copies variable types, so refresh applications after adding bounds.
	receiver = c.resolve(d.Receiver, false)
	contract = c.resolve(d.Contract, false)
	for _, m := range c.Methods {
		if c.methodVisible(m) && overlap(receiver, contract, m.Receiver, m.Contract, append(append([]*Type{}, vars...), m.Variables...)) {
			c.error(d.Pos, "type", "duplicate or overlapping implementation; "+contract.String()+" is already implemented for "+receiver.String()+" (or an overlapping type), so remove one impl")
			break
		}
	}
	seen := map[string]bool{}
	ops := []Operation{}
	if contract.Def != nil {
		for _, op := range contract.Def.Operations {
			op.Type = Sub(op.Type, substitution(contract))
			ops = append(ops, op)
		}
	}
	for _, method := range d.Methods {
		if seen[method.Name] {
			c.error(method.Pos, "type", "duplicate implementation operation "+method.Name+"; define each operation once per impl")
		}
		seen[method.Name] = true
		t := c.signature(method.Params, method.Result)
		found := false
		for _, op := range ops {
			if op.Name == method.Name {
				found = true
				if len(op.Type.Defaults) > 0 {
					if t.Defaults == nil {
						t.Defaults = map[string]bool{}
					}
					for name, allowed := range op.Type.Defaults {
						t.Defaults[name] = allowed
					}
				}
				if !Same(t, op.Type) {
					c.error(method.Pos, "type", "implementation operation signature does not match contract; "+method.Name+" must be declared as fn "+method.Name+signatureText(op.Type))
				}
			}
		}
		if !found {
			c.error(method.Pos, "type", "extra operation "+method.Name+"; "+contract.String()+" declares: "+list(operationNames(ops), 12)+" (remove it or add it to the interface)")
		}
		local := receiver.Def != nil && receiver.Def.Symbol != nil && receiver.Def.Symbol.Module != c.module.File
		c.Methods = append(c.Methods, &Method{ID: c.unique("method"), Module: c.module.File, Local: local, Receiver: receiver, Contract: contract, Variables: vars, Decl: method, Type: t})
	}
	for _, op := range ops {
		if !seen[op.Name] {
			if std(contract, "TestHooks") {
				// This standard lifecycle contract has no-op defaults; retain ordinary
				// checked methods so interface calls and generic bounds use normal dispatch.
				method := &syntax.Declaration{Kind: syntax.KindFn, Name: op.Name, Pos: d.Pos, Result: &syntax.Type{Name: "Unit", Pos: d.Pos}}
				c.Methods = append(c.Methods, &Method{ID: c.unique("method"), Module: c.module.File, Local: receiver.Def.Symbol.Module != c.module.File, Receiver: receiver, Contract: contract, Variables: vars, Decl: method, Type: op.Type})
			} else {
				c.error(d.Pos, "type", "missing implementation operation "+op.Name+"; add fn "+op.Name+signatureText(op.Type)+" to this impl")
			}
		}
	}
	c.wellFormed(receiver, d.Pos, map[*Type]bool{})
	c.wellFormed(contract, d.Pos, map[*Type]bool{})
	c.scope = old
}
func overlap(a, b, x, y *Type, vars []*Type) bool {
	variable := variableSet(vars)
	sub := map[string]*Type{}
	var match func(*Type, *Type) bool
	deref := func(t *Type) *Type {
		seen := map[string]bool{}
		for sub[t.ID] != nil && !seen[t.ID] {
			seen[t.ID] = true
			t = sub[t.ID]
		}
		return t
	}
	var occurs func(string, *Type) bool
	occurs = func(id string, t *Type) bool {
		t = deref(t)
		if t.ID == id {
			return true
		}
		for _, arg := range t.Args {
			if occurs(id, arg) {
				return true
			}
		}
		for _, param := range t.Params {
			if occurs(id, param.Type) {
				return true
			}
		}
		return t.Result != nil && occurs(id, t.Result)
	}
	match = func(a, b *Type) bool {
		a = deref(a)
		b = deref(b)
		if a.ID == b.ID && variable[a.ID] {
			return true
		}
		if variable[a.ID] {
			if occurs(a.ID, b) {
				return false
			}
			sub[a.ID] = b
			return true
		}
		if variable[b.ID] {
			if occurs(b.ID, a) {
				return false
			}
			sub[b.ID] = a
			return true
		}
		if a.ID != b.ID || len(a.Args) != len(b.Args) {
			return false
		}
		for i := range a.Args {
			if !match(a.Args[i], b.Args[i]) {
				return false
			}
		}
		if a.Kind == "function" {
			if len(a.Params) != len(b.Params) {
				return false
			}
			for i, param := range a.Params {
				if param.Name != b.Params[i].Name || !match(param.Type, b.Params[i].Type) {
					return false
				}
			}
			return match(a.Result, b.Result)
		}
		return true
	}
	return match(a, x) && match(b, y)
}
func (c *checker) implements(receiver, contract *Type) bool {
	if receiver == nil || contract == nil {
		return false
	}
	if std(contract, "Closeable") && (std(receiver, "TaskGroup") || std(receiver, "Scheduler") || std(receiver, "SynchronizedGuard")) {
		return true
	}
	if receiver.ID == contract.ID {
		return Same(receiver, contract)
	}
	if std(contract, "Equal") || std(contract, "Hashable") {
		return c.property(receiver, contract.Name, nil)
	}
	if receiver.Kind == "variable" {
		for _, bound := range receiver.Bounds {
			if Same(bound, contract) {
				return true
			}
		}
		return false
	}
	for _, m := range c.Methods {
		if !c.methodVisible(m) {
			continue
		}
		sub := map[string]*Type{}
		if unify(m.Receiver, receiver, variableSet(m.Variables), sub) && Same(Sub(m.Contract, sub), contract) && c.boundsSatisfied(m.Variables, sub) {
			return true
		}
	}
	return std(contract, "Comparable") && builtinComparable(receiver)
}

// builtinComparable reports the standard types whose native compare operation
// satisfies Comparable without an impl.
func builtinComparable(t *Type) bool {
	switch t.ID {
	case "Int", "Float", "String", "@std/Decimal", "@std/BigInt", "@std/Duration", "@std/Instant", "@std/Timestamp":
		return true
	}
	return false
}
func (c *checker) boundsSatisfied(vars []*Type, sub map[string]*Type) bool {
	for _, v := range vars {
		a := sub[v.ID]
		if a == nil {
			return false
		}
		for _, b := range v.Bounds {
			if !c.satisfies(a, Sub(b, sub)) {
				return false
			}
		}
	}
	return true
}
func (c *checker) satisfies(t, bound *Type) bool {
	if std(bound, "Equal") || std(bound, "Hashable") {
		return c.property(t, bound.Name, nil)
	}
	return c.implements(t, bound)
}

type propertyState struct {
	active    map[string]bool
	completed map[string]bool
}

func (c *checker) property(t *Type, property string, state *propertyState) (result bool) {
	if t == nil {
		return false
	}
	if t.ID == "<invalid>" {
		return true
	}
	if state == nil {
		state = &propertyState{active: map[string]bool{}, completed: map[string]bool{}}
	}
	key := typeKey(t) + property
	if result, ok := state.completed[key]; ok {
		return result
	}
	if state.active[key] {
		// Equality handles cycles; structural hashing requires an acyclic shape.
		return property != "Hashable"
	}
	if len(state.active) > 200 {
		return false
	}
	state.active[key] = true
	defer func() {
		delete(state.active, key)
		state.completed[key] = result
	}()
	if t.Kind == "variable" {
		for _, b := range t.Bounds {
			if std(b, property) || std(b, "Hashable") && property == "Equal" {
				return true
			}
		}
		return false
	}
	// Explicit implementations take precedence over structural data semantics.
	for _, m := range c.Methods {
		if !c.methodVisible(m) || !std(m.Contract, property) {
			continue
		}
		sub := map[string]*Type{}
		if unify(m.Receiver, t, variableSet(m.Variables), sub) && c.boundsSatisfied(m.Variables, sub) {
			return property != "Hashable" || c.property(t, "Equal", nil)
		}
	}
	if property == "Hashable" {
		for _, m := range c.Methods {
			if !c.methodVisible(m) || !std(m.Contract, "Equal") {
				continue
			}
			sub := map[string]*Type{}
			if unify(m.Receiver, t, variableSet(m.Variables), sub) && c.boundsSatisfied(m.Variables, sub) {
				return false
			}
		}
	}
	if t.Kind == "function" {
		return false
	}
	if t.Kind == "contract" {
		return false
	}
	if t.Kind == "primitive" {
		return t.ID != "Float" || property != "Hashable"
	}
	if std(t, "Decimal") || std(t, "Bytes") || std(t, "Duration") || std(t, "Instant") {
		return true
	}
	if std(t, "Task") || std(t, "TaskGroup") || std(t, "OperationId") || std(t, "Scheduler") || std(t, "Queue") || std(t, "BlockingQueue") || std(t, "PriorityQueue") || std(t, "Synchronized") || std(t, "SynchronizedGuard") {
		return false
	}
	if std(t, "List") || std(t, "Map") || std(t, "Set") {
		if property == "Hashable" {
			return false
		}
		for _, a := range t.Args {
			if !c.property(a, property, state) {
				return false
			}
		}
		return true
	}
	if std(t, "BigInt") || std(t, "Regex") || std(t, "Timestamp") {
		return property == "Equal" && !std(t, "Regex")
	}
	if t.Kind == syntax.KindNative {
		return false
	}
	if t.Def != nil {
		for _, f := range Fields(t) {
			if !c.property(f.Type, property, state) {
				return false
			}
		}
		for _, cs := range Cases(t) {
			for _, f := range cs.Fields {
				if !c.property(f.Type, property, state) {
					return false
				}
			}
		}
		return true
	}
	return false
}
func (c *checker) methods(receiver *Type, name string) []*Method {
	if m := nativeMethod(receiver, name); m != nil && nativeReceiverAvailable(c, receiver, name) {
		return []*Method{m}
	}
	if receiver.Kind == "contract" && receiver.Def != nil {
		for _, op := range receiver.Def.Operations {
			if op.Name == name {
				return []*Method{{Contract: receiver, Receiver: receiver, Type: Sub(op.Type, substitution(receiver)), Native: "contract", Decl: op.Decl, Variables: standardOperationVariables[receiver.ID+"/"+name]}}
			}
		}
	}
	if receiver.Kind == "variable" {
		var methods []*Method
		for _, b := range receiver.Bounds {
			if b.Kind == "contract" {
				methods = append(methods, c.methods(b, name)...)
			}
		}
		return methods
	}
	var methods []*Method
	for _, m := range c.Methods {
		if !c.methodVisible(m) || m.Decl == nil || m.Decl.Name != name {
			continue
		}
		sub := map[string]*Type{}
		if unify(m.Receiver, receiver, variableSet(m.Variables), sub) && c.boundsSatisfied(m.Variables, sub) {
			r := *m
			r.Type = Sub(m.Type, sub)
			r.Contract = Sub(m.Contract, sub)
			r.Receiver = receiver
			r.Variables = nil // Implementation variables are fixed by the receiver.
			methods = append(methods, &r)
		}
	}
	if len(methods) == 0 && (name == "equals" || name == "hash") {
		property := "Equal"
		if name == "hash" {
			property = "Hashable"
		}
		if c.property(receiver, property, nil) {
			contract := standard(property)
			operation := contract.Def.Operations[0]
			return []*Method{{Receiver: receiver, Contract: contract, Type: operation.Type, Native: name, Decl: standardMethodDeclaration(contract, name)}}
		}
	}
	return methods
}

func (c *checker) methodVisible(m *Method) bool {
	return m.VisibleIn(c.currentModule())
}

func (c *checker) currentModule() string {
	if c.module != nil {
		return c.module.File
	}
	return ""
}

func nativeMethod(t *Type, name string) *Method {
	if name == "clone" && (t.Kind == syntax.KindRecord || t.Kind == "alternative" || std(t, "List") || std(t, "Map") || std(t, "Set") || std(t, "Bytes")) {
		receiver := t
		if t.Kind == syntax.KindRecord || t.Kind == "alternative" {
			receiver = standardSymbols["CloneOperations"].Type
		}
		return &Method{Receiver: t, Type: function(nil, t), Native: name, Decl: standardMethodDeclaration(receiver, name)}
	}
	if name == "to_string" {
		receiver := standardSymbols["ValueOperations"].Type
		return &Method{Receiver: t, Type: receiver.Def.Operations[0].Type, Native: name, Decl: standardMethodDeclaration(receiver, name)}
	}
	receiver := t
	if intrinsic := intrinsicOperations[t.ID]; intrinsic != nil {
		receiver = intrinsic
	}
	if receiver.Kind == syntax.KindNative || receiver != t || standardReceiverBindings[receiver.ID+"/"+name] != "" || receiver.Kind == "alternative" && receiver.Def.Symbol.Native != "" {
		for _, operation := range receiver.Def.Operations {
			if operation.Name == name {
				native := name
				if identity := standardReceiverBindings[receiver.ID+"/"+name]; identity != "" {
					native = identity
				}
				return &Method{Receiver: t, Type: Sub(operation.Type, substitution(t)), Native: native, Decl: operation.Decl, Variables: standardOperationVariables[receiver.ID+"/"+name]}
			}
		}
	}
	return nil
}

func (c *checker) closeable(t *Type) bool {
	if std(t, "TaskGroup") || std(t, "Scheduler") || std(t, "SynchronizedGuard") {
		return true
	}
	if t.Kind == "contract" || t.Kind == "variable" {
		for _, m := range c.methods(t, "close") {
			if len(m.Type.Params) == 0 && m.Type.Result.ID == "Unit" {
				return true
			}
		}
		return false
	}
	return c.implements(t, standard("Closeable"))
}

// wellFormed checks every bound reachable from t. seen is keyed by pointer: a
// structural key costs the whole subtree at each level, which made deeply
// nested inferred types cubic.
func (c *checker) wellFormed(t *Type, pos syntax.Position, seen map[*Type]bool) {
	if t == nil || seen[t] {
		return
	}
	seen[t] = true
	c.boundsHold(t, pos)
	for _, a := range t.Args {
		c.wellFormed(a, pos, seen)
	}
	for _, p := range t.Params {
		c.wellFormed(p.Type, pos, seen)
	}
	c.wellFormed(t.Result, pos, seen)
}

// boundsHold checks t's own type arguments against its definition's bounds,
// without descending into those arguments.
func (c *checker) boundsHold(t *Type, pos syntax.Position) {
	if t.Def == nil || len(t.Args) != len(t.Def.Variables) {
		return
	}
	sub := substitution(t)
	for _, v := range t.Def.Variables {
		for _, b := range v.Bounds {
			if !c.satisfies(sub[v.ID], Sub(b, sub)) {
				c.error(pos, "type", c.unsatisfiedMessage(sub[v.ID], Sub(b, sub), "use a type that implements it"))
			}
		}
	}
}
func (c *checker) declarationChecks(module *syntax.Module) {
	for _, d := range module.Declarations {
		if d.Kind == syntax.KindTest || d.Kind == syntax.KindImpl {
			continue
		}
		s := c.names[d.Name]
		if s.Decl != d {
			continue
		}
		old := c.scope
		c.scope = c.variableScope(s.Variables)
		check := func(t *Type) {
			c.wellFormed(t, d.Pos, map[*Type]bool{})
			if s.Export {
				c.public(t, d.Pos, map[string]bool{})
			}
		}
		if s.Kind == syntax.KindFn {
			check(s.Type)
		} else {
			for _, f := range s.Type.Def.Fields {
				check(f.Type)
			}
			for _, cs := range s.Type.Def.Cases {
				for _, f := range cs.Fields {
					check(f.Type)
				}
			}
			for _, op := range s.Type.Def.Operations {
				check(op.Type)
			}
		}
		for _, v := range s.Variables {
			for _, b := range v.Bounds {
				check(b)
			}
		}
		c.scope = old
	}
}
func (c *checker) public(t *Type, pos syntax.Position, seen map[string]bool) {
	if t == nil || seen[typeKey(t)] {
		return
	}
	seen[typeKey(t)] = true
	if t.Def != nil && t.Def.Symbol != nil && t.Def.Symbol.Module == c.module.File && !t.Def.Symbol.Export {
		c.error(pos, "type", "public signature exposes private type "+t.Name+"; add 'export' to its declaration or keep the function private")
	}
	for _, a := range t.Args {
		c.public(a, pos, seen)
	}
	for _, p := range t.Params {
		c.public(p.Type, pos, seen)
	}
	c.public(t.Result, pos, seen)
}

// unsatisfiedMessage explains a failed bound with a fix the writer can apply.
// An impl is suggested only for data the module may declare an impl for;
// built-in and collection types cannot take one, so they are told what to
// use instead.
func (c *checker) unsatisfiedMessage(t, bound *Type, alternative string) string {
	prefix := t.String() + " does not satisfy " + bound.String() + "; "
	switch {
	case std(bound, "Hashable") && t.ID == "Float":
		return t.String() + " does not satisfy Hashable; Float has no Hashable implementation, so wrap it in a record with an Int or String key, or use Decimal"
	case std(bound, "Hashable") && (std(t, "List") || std(t, "Map") || std(t, "Set")):
		return prefix + "collections have no Hashable implementation, so use a record key or join the elements into a String"
	case t.Kind == syntax.KindRecord || t.Kind == "alternative":
		if t.Def != nil && t.Def.Symbol != nil && (t.Def.Symbol.Native == "" || c.standardDeclarations) {
			return prefix + "add 'impl " + bound.String() + " for " + t.String() + ":' or " + alternative
		}
	}
	return prefix + alternative
}

// withNotCloseableMessage explains a failed with binding. Built-in and
// wrapper types cannot receive an implementation, so suggesting one would send
// the user to a second error; they need to unwrap the value first.
func (c *checker) withNotCloseableMessage(t *Type) string {
	name := t.String()
	if std(t, "Result") || std(t, "Optional") {
		return "with needs a Closeable value, but this expression is " + name + "; unwrap it first with 'try' (inside a function that returns a compatible Result) or 'if let'"
	}
	if t.Def == nil || t.Def.Symbol == nil || t.Def.Symbol.Native != "" || (t.Kind != syntax.KindRecord && t.Kind != "alternative") {
		return "with needs a Closeable value, but this expression is " + name + ", which cannot implement Closeable; bind a source type that has 'impl Closeable' or declares close() Unit"
	}
	return "with requires an explicit Closeable implementation or a contract declaring close() Unit; " + name + " has none, so add 'impl Closeable for " + name + ":' with fn close() Unit"
}

func operationNames(ops []Operation) []string {
	names := make([]string, len(ops))
	for i, op := range ops {
		names[i] = op.Name
	}
	return names
}
