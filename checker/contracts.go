package checker

import (
	"github.com/manuscript-lang/manuscript/syntax"
)

func (c *checker) implementation(d *syntax.Declaration) {
	old := c.scope
	c.scope = newScope(nil)
	// Implementations inherit names and bounds from the nominal receiver declaration.
	var vars []*Type
	if symbol := c.names[d.Receiver.Name]; symbol != nil && symbol.Decl != nil && symbol.Kind == "type" {
		vars = c.typeVariables(symbol.Decl.TypeParams)
	}
	receiver := c.resolve(d.Receiver, false)
	if receiver.Def == nil || receiver.Kind == "contract" || receiver.Def.Symbol.Module != c.module.File {
		c.error(d.Pos, "type", "implementation receiver must be nominal data defined in this module")
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
	if contract.Kind != "contract" {
		c.error(d.Pos, "type", "implementation target must be an interface")
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
		if overlap(receiver, contract, m.Receiver, m.Contract, append(append([]*Type{}, vars...), m.Variables...)) {
			c.error(d.Pos, "type", "duplicate or overlapping implementation")
			break
		}
	}
	seen := map[string]bool{}
	ops := []Param{}
	if contract.Def != nil {
		for _, op := range contract.Def.Operations {
			ops = append(ops, Param{op.Name, Sub(op.Type, substitution(contract))})
		}
	}
	for _, method := range d.Methods {
		if seen[method.Name] {
			c.error(method.Pos, "type", "duplicate implementation operation")
		}
		seen[method.Name] = true
		t := c.signature(method.Params, method.Result)
		found := false
		for _, op := range ops {
			if op.Name == method.Name {
				found = true
				if !Same(t, op.Type) {
					c.error(method.Pos, "type", "implementation operation signature does not match contract")
				}
			}
		}
		if !found {
			c.error(method.Pos, "type", "extra operation "+method.Name)
		}
		c.Methods = append(c.Methods, &Method{ID: c.unique("method"), Receiver: receiver, Contract: contract, Variables: vars, Decl: method, Type: t})
	}
	for _, op := range ops {
		if !seen[op.Name] {
			c.error(d.Pos, "type", "missing implementation operation "+op.Name)
		}
	}
	c.wellFormed(receiver, d.Pos, map[string]bool{})
	c.wellFormed(contract, d.Pos, map[string]bool{})
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
	if std(contract, "Closeable") && (std(receiver, "Background") || std(receiver, "Pool") || std(receiver, "Lease") || std(receiver, "SynchronizedGuard")) {
		return true
	}
	if receiver.ID == contract.ID {
		return Same(receiver, contract)
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
		sub := map[string]*Type{}
		if unify(m.Receiver, receiver, variableSet(m.Variables), sub) && Same(Sub(m.Contract, sub), contract) && c.boundsSatisfied(m.Variables, sub) {
			return true
		}
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
	if bound.ID == "Equal" || bound.ID == "Hashable" {
		return c.property(t, bound.ID, nil)
	}
	return c.implements(t, bound)
}
func (c *checker) property(t *Type, property string, seen map[string]bool) bool {
	if t == nil {
		return false
	}
	if t.ID == "<invalid>" {
		return true
	}
	if seen == nil {
		seen = map[string]bool{}
	}
	key := typeKey(t) + property
	if seen[key] {
		return true
	}
	if len(seen) > 200 {
		return false
	}
	seen[key] = true
	if t.Kind == "variable" {
		for _, b := range t.Bounds {
			if b.ID == property || b.ID == "Hashable" && property == "Equal" {
				return true
			}
		}
		return false
	}
	if t.Kind == "function" {
		return false
	}
	if t.Kind == "contract" || t.Kind == "pack" {
		return false
	}
	if t.Kind == "primitive" {
		return t.ID != "Float" || property != "Hashable"
	}
	if std(t, "Decimal") || std(t, "Bytes") || std(t, "Duration") || std(t, "Instant") {
		return true
	}
	if std(t, "OperationId") || std(t, "Background") || std(t, "Queue") || std(t, "Synchronized") || std(t, "SynchronizedGuard") || std(t, "Pool") || std(t, "Lease") {
		return false
	}
	if std(t, "List") || std(t, "Map") || std(t, "Set") {
		if property == "Hashable" {
			return false
		}
		for _, a := range t.Args {
			if !c.property(a, property, seen) {
				return false
			}
		}
		return true
	}
	if std(t, "BigInt") || std(t, "Regex") || std(t, "Timestamp") {
		return property == "Equal" && !std(t, "Regex")
	}
	if t.Kind == "native" {
		return false
	}
	if t.Def != nil {
		for _, f := range Fields(t) {
			if !c.property(f.Type, property, seen) {
				return false
			}
		}
		for _, cs := range Cases(t) {
			for _, f := range cs.Fields {
				if !c.property(f.Type, property, seen) {
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
				return []*Method{{Contract: receiver, Receiver: receiver, Type: Sub(op.Type, substitution(receiver)), Native: "contract", Decl: standardMethodDeclaration(receiver, name), Variables: standardOperationVariables[receiver.ID+"/"+name]}}
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
		if m.Decl == nil || m.Decl.Name != name {
			continue
		}
		sub := map[string]*Type{}
		if unify(m.Receiver, receiver, variableSet(m.Variables), sub) && c.boundsSatisfied(m.Variables, sub) {
			r := *m
			r.Type = Sub(m.Type, sub)
			r.Contract = Sub(m.Contract, sub)
			r.Receiver = receiver
			methods = append(methods, &r)
		}
	}
	return methods
}

func nativeMethod(t *Type, name string) *Method {
	receiver := t
	if intrinsic := intrinsicOperations[t.ID]; intrinsic != nil {
		receiver = intrinsic
	}
	if receiver.Kind == "native" || receiver != t {
		for _, operation := range receiver.Def.Operations {
			if operation.Name == name {
				native := name
				return &Method{Receiver: t, Type: Sub(operation.Type, substitution(t)), Native: native, Decl: standardMethodDeclaration(receiver, name), Variables: standardOperationVariables[receiver.ID+"/"+name]}
			}
		}
	}
	return nil
}

func (c *checker) closeable(t *Type) bool {
	if std(t, "Background") || std(t, "Pool") || std(t, "Lease") || std(t, "SynchronizedGuard") {
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
func (c *checker) wellFormed(t *Type, pos syntax.Position, seen map[string]bool) {
	if t == nil {
		return
	}
	key := typeKey(t)
	if seen[key] {
		return
	}
	seen[key] = true
	if t.Def != nil && len(t.Args) == len(t.Def.Variables) {
		sub := substitution(t)
		for _, v := range t.Def.Variables {
			for _, b := range v.Bounds {
				if !c.satisfies(sub[v.ID], Sub(b, sub)) {
					c.error(pos, "type", sub[v.ID].String()+" does not satisfy "+b.String())
				}
			}
		}
	}
	if (std(t, "Pool") || std(t, "Lease")) && len(t.Args) == 1 {
		element := t.Args[0]
		if (element.Kind != "contract" && element.Kind != "variable") || !c.closeable(element) {
			c.error(pos, "type", "pool elements must be operation contracts declaring close() -> Unit")
		}
	}

	for _, a := range t.Args {
		c.wellFormed(a, pos, seen)
	}
	for _, p := range t.Params {
		c.wellFormed(p.Type, pos, seen)
	}
	c.wellFormed(t.Result, pos, seen)
}
func (c *checker) declarationChecks(module *syntax.Module) {
	for _, d := range module.Declarations {
		if d.Kind == "test" || d.Kind == "impl" {
			continue
		}
		s := c.names[d.Name]
		if s.Decl != d {
			continue
		}
		old := c.scope
		c.scope = c.variableScope(s.Variables)
		check := func(t *Type) {
			c.wellFormed(t, d.Pos, map[string]bool{})
			if s.Export {
				c.public(t, d.Pos, map[string]bool{})
			}
		}
		if s.Kind == "fn" {
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
			c.layout(s.Type, d.Pos, map[string]*Type{}, false)
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
		c.error(pos, "type", "public signature exposes private type "+t.Name)
	}
	for _, a := range t.Args {
		c.public(a, pos, seen)
	}
	for _, p := range t.Params {
		c.public(p.Type, pos, seen)
	}
	c.public(t.Result, pos, seen)
}
func (c *checker) layout(t *Type, pos syntax.Position, active map[string]*Type, indirect bool) {
	if t == nil || t.Kind == "function" || t.Kind == "contract" || t.Kind == "variable" {
		return
	}
	if previous := active[t.ID]; previous != nil {
		if !Same(previous, t) {
			c.error(pos, "type", "recursive generic applications must preserve their parameters")
		}
		if !indirect {
			c.error(pos, "type", "unguarded inline recursive layout")
		}
		return
	}
	if t.Def == nil {
		return
	}
	active[t.ID] = t
	defer delete(active, t.ID)
	if std(t, "List") || std(t, "Set") || std(t, "Map") {
		for _, a := range t.Args {
			c.layout(a, pos, active, true)
		}
		return
	}
	for _, f := range Fields(t) {
		c.layout(f.Type, pos, active, indirect)
	}
	for _, cs := range Cases(t) {
		for _, f := range cs.Fields {
			c.layout(f.Type, pos, active, indirect)
		}
	}
}
