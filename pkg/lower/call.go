package lower

import (
	"go/ast"
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// callExpr lowers a call of a function, method, constructor, or function value.
func (g *gen) callExpr(e *syntax.Expression, info *checker.Info) ast.Expr {
	switch {
	case info.Constructor != nil && info.Native == "view":
		return g.viewCall(e, info)
	case info.Constructor != nil && info.Case != "":
		return g.caseCall(e, info)
	case info.Constructor != nil:
		return g.recordCall(e, info)
	case info.Symbol != nil:
		return g.symbolCall(e, info)
	case info.Method != nil && callsMember(e.Left):
		return g.methodCall(e, info)
	}
	return g.dynamicCall(e, info)
}

// callee describes the parameters of the callable being invoked: their types
// in declaration order, the source declarations that carry their defaults, and
// the bindings those defaults may read.
type callee struct {
	params   []checker.Param
	decls    []syntax.Parameter
	bindings []*checker.Binding
	defaults map[string]bool
	module   string
	// siteDefaults means omitted arguments are evaluated by the caller, as
	// for native operations and record fields. Otherwise the callee fills
	// them in and receives rt.Arg for each defaulted parameter.
	siteDefaults bool
	// subst fixes the type variables of a generic record while its field
	// defaults are lowered at the construction site.
	subst map[string]*checker.Type
}

// arguments lowers the supplied arguments in written order, fills omitted
// parameters from their defaults, and returns the values in declaration order.
func (g *gen) arguments(args []syntax.Argument, c callee) []ast.Expr {
	index := map[string]int{}
	for i, p := range c.params {
		index[p.Name] = i
	}
	items := make([]*syntax.Expression, len(args))
	types := make([]*checker.Type, len(args))
	for i, a := range args {
		items[i] = a.Value
		types[i] = g.sub(c.params[index[a.Name]].Type)
	}
	values := g.operandsAs(items, types)
	slots := make([]ast.Expr, len(c.params))
	order := make([]int, len(args))
	for i, a := range args {
		slots[index[a.Name]] = values[i]
		order[i] = index[a.Name]
	}
	// Go evaluates the call's operands left to right in declaration order.
	// When the written order differs, capture the operands that run code so
	// source order wins.
	if !ascending(order) {
		running := 0
		for _, v := range values {
			if effectsOf(v).calls {
				running++
			}
		}
		if running > 1 {
			for _, at := range order {
				if effectsOf(slots[at]).calls {
					slots[at] = g.spill(slots[at])
				}
			}
		}
	}
	for i, p := range c.params {
		callerFills := c.siteDefaults || !c.defaults[p.Name]
		if slots[i] != nil {
			if !callerFills {
				slots[i] = rtCall("Given", slots[i])
			}
			continue
		}
		if !callerFills {
			slots[i] = composite(generic(rtName("Arg"), g.goType(p.Type)))
			continue
		}
		slots[i] = g.defaultArgument(i, p, c, slots)
	}
	return slots
}

func ascending(order []int) bool {
	for i := 1; i < len(order); i++ {
		if order[i] < order[i-1] {
			return false
		}
	}
	return true
}

// defaultArgument evaluates the default of an omitted parameter. The default
// is written in the callee's scope and may read earlier parameters, so each of
// those is bound to the value this call supplied.
func (g *gen) defaultArgument(i int, p checker.Param, c callee, slots []ast.Expr) ast.Expr {
	if i >= len(c.decls) || c.decls[i].Default == nil {
		if !c.defaults[p.Name] {
			g.fail("missing argument %s", p.Name)
			return ident("nil")
		}
		// An omittable Optional parameter without an expression defaults to none.
		return composite(g.goType(p.Type))
	}
	// Declarations of standard native records default omittable Optional
	// fields to none and carry no checked expression.
	if d := c.decls[i].Default; g.program.Info(d) == nil && d.Kind == syntax.KindName && d.Text == "none" {
		return composite(g.goType(p.Type))
	}
	savedModule, savedSubst := g.module, g.subst
	g.module = c.module
	if len(c.subst) > 0 {
		g.subst = map[string]*checker.Type{}
		for k, v := range savedSubst {
			g.subst[k] = v
		}
		for k, v := range c.subst {
			g.subst[k] = v
		}
	}
	defer func() { g.module, g.subst = savedModule, savedSubst }()
	savedCaptured := g.captured
	g.captured = map[*checker.Binding]string{}
	for k, v := range savedCaptured {
		g.captured[k] = v
	}
	defer func() { g.captured = savedCaptured }()
	for j := 0; j < i && j < len(c.bindings); j++ {
		slots[j] = g.spill(slots[j])
		if id, ok := slots[j].(*ast.Ident); ok {
			g.captured[c.bindings[j]] = id.Name
		} else if trivial(slots[j]) {
			name := g.temp()
			g.fn.pre = append(g.fn.pre, define(name, slots[j]))
			slots[j] = ident(name)
			g.captured[c.bindings[j]] = name
		}
	}
	return g.valueAs(c.decls[i].Default, p.Type)
}

func (g *gen) calleeOf(s *checker.Symbol, t *checker.Type) callee {
	c := callee{params: t.Params, defaults: t.Defaults, module: s.Module, siteDefaults: s.Native != ""}
	if d := s.Decl; d != nil {
		c.decls = d.Params
		c.bindings = g.program.ParameterBindings(d)
	}
	return c
}

// symbolCall calls a named function, instantiating it when generic.
func (g *gen) symbolCall(e *syntax.Expression, info *checker.Info) ast.Expr {
	s := info.Symbol
	signature := g.info(e.Left).Type
	args := g.arguments(info.Arguments, g.calleeOf(s, signature))
	if s.Native != "" {
		return g.nativeCall(s, info.TypeArgs, args)
	}
	f := g.function(s, info.TypeArgs)
	return call(ident(f.name), append([]ast.Expr{ident("ctx")}, args...)...)
}

// recordCall constructs a record. Omitted fields take their defaults.
func (g *gen) recordCall(e *syntax.Expression, info *checker.Info) ast.Expr {
	t := g.sub(info.Constructor)
	if isStd(t, "Set") && len(info.Arguments) == 0 {
		return g.construct(t, nil)
	}
	args := g.arguments(info.Arguments, g.recordCallee(t))
	return g.construct(t, args)
}

// recordCallee describes a record's constructor: its fields, their defaults
// and the scope those defaults are written in.
func (g *gen) recordCallee(t *checker.Type) callee {
	signature := checker.ConstructorSignature(t)
	c := callee{params: signature.Params, defaults: signature.Defaults, siteDefaults: true}
	if t.Def != nil && t.Def.Symbol != nil && t.Def.Symbol.Decl != nil {
		d := t.Def.Symbol.Decl
		c.decls, c.module = d.Fields, t.Def.Symbol.Module
		c.bindings = g.program.ParameterBindings(d)
		if vars := t.Def.Variables; len(vars) > 0 && len(vars) == len(t.Args) {
			c.subst = map[string]*checker.Type{}
			for i, v := range vars {
				c.subst[v.ID] = t.Args[i]
			}
		}
	}
	return c
}

// construct builds a record from field values in declaration order.
func (g *gen) construct(t *checker.Type, values []ast.Expr) ast.Expr {
	if isStdType(t) {
		return g.stdRecord(t, values)
	}
	d := g.declare(t)
	var elements []ast.Expr
	for i, f := range checker.Fields(t) {
		elements = append(elements, keyed(fieldName(f.Name), values[i]))
	}
	return address(composite(ident(d.name), elements...))
}

func (g *gen) stdRecord(t *checker.Type, values []ast.Expr) ast.Expr {
	name := strings.TrimPrefix(t.ID, "@std/")
	if name == "Bytes" {
		name = "BytesFromValues"
	}
	var typeArgs []ast.Expr
	for _, a := range t.Args {
		typeArgs = append(typeArgs, g.goType(a))
	}
	if t.Kind == "record" {
		var elements []ast.Expr
		for i, f := range checker.Fields(t) {
			elements = append(elements, keyed(fieldName(f.Name), values[i]))
		}
		return address(composite(generic(rtName(name), typeArgs...), elements...))
	}
	// A Hashable type argument tells the collection how its keys match.
	var keys []ast.Expr
	if t.Def != nil {
		for i, v := range t.Def.Variables {
			for _, b := range v.Bounds {
				if isStd(b, "Hashable") && i < len(t.Args) {
					keys = append(keys, g.keysFor(t.Args[i]))
				}
			}
		}
	}
	if name == "Set" && len(values) == 1 {
		name = "SetFromList"
		if len(keys) == 0 {
			keys = append(keys, ident("nil"))
		}
	} else if len(keys) > 0 && (name == "Map" || name == "Set") {
		name += "With"
	}
	return call(generic(rtName("New"+name), typeArgs...), append(keys, values...)...)
}

// caseCall constructs a sum-type case from its payload.
func (g *gen) caseCall(e *syntax.Expression, info *checker.Info) ast.Expr {
	t := g.sub(info.Constructor)
	var params []checker.Param
	for _, c := range checker.Cases(t) {
		if c.Name == info.Case {
			params = c.Fields
		}
	}
	args := g.arguments(info.Arguments, callee{params: params})
	return g.caseValue(t, info.Case, args)
}

// dynamicCall calls a function value.
func (g *gen) dynamicCall(e *syntax.Expression, info *checker.Info) ast.Expr {
	calleeInfo := g.info(e.Left)
	signature := calleeInfo.Type
	target := g.expr(e.Left)
	c := callee{params: signature.Params, defaults: signature.Defaults}
	if !trivial(target) && effectsOf(target).calls {
		name := g.temp()
		g.fn.pre = append(g.fn.pre, define(name, target))
		target = ident(name)
	}
	mark := len(g.fn.pre)
	args := g.arguments(info.Arguments, c)
	// An argument that runs code may reassign a mutable callee variable.
	if id, ok := target.(*ast.Ident); ok && g.fn.mutables[id.Name] && len(g.fn.pre) > mark {
		name := g.temp()
		g.fn.pre = append(g.fn.pre[:mark:mark], append([]ast.Stmt{define(name, target)}, g.fn.pre[mark:]...)...)
		target = ident(name)
	}
	return call(target, append([]ast.Expr{ident("ctx")}, args...)...)
}

// nativeName is the runtime function implementing a native by convention:
// module functions are Module_Function and receiver operations Type_Operation.
// implName is the runtime function of a native contract implementation; one
// exists per receiver type because Go has no overloading.
func implName(m *checker.Method, receiver *checker.Type) string {
	return nativeName(m.Native) + "_" + sanitize(receiver.Name)
}

func nativeName(key string) string {
	var parts []string
	for _, part := range strings.Split(key, "/") {
		parts = append(parts, camel(part))
	}
	return strings.Join(parts, "_")
}

func camel(snake string) string {
	var b strings.Builder
	upper := true
	for _, r := range snake {
		if r == '_' {
			upper = true
			continue
		}
		if upper && r >= 'a' && r <= 'z' {
			r -= 'a' - 'A'
		}
		upper = false
		b.WriteRune(r)
	}
	return b.String()
}

// exportName is the exported Go name of a record field or interface
// operation. camel is not injective (x_ and x, or a_b and aB, both give X and
// AB), so names outside the canonical snake form keep their full spelling
// behind a prefix whose underscore no canonical result has.
func exportName(name string) string {
	if canonicalSnake(name) && name != "receiver" && name != "describe" {
		// receiver and describe are methods every interface view carries.
		return camel(name)
	}
	return "Z_" + name
}

// canonicalSnake reports whether camel is injective for name: lowercase ASCII
// words joined by single underscores, each starting with a letter.
func canonicalSnake(name string) bool {
	word := 0
	for _, r := range name {
		switch {
		case r >= 'a' && r <= 'z':
			word++
		case r >= '0' && r <= '9' && word > 0:
			word++
		case r == '_' && word > 0:
			word = 0
		default:
			return false
		}
	}
	return word > 0
}

// cloneValue lowers the built-in clone of a record or alternative. A record
// copies its outer storage; nested references stay shared. An alternative is
// immutable, so its clone is itself.
func (g *gen) cloneValue(t *checker.Type, receiver ast.Expr) ast.Expr {
	t = g.sub(t)
	if t.Kind != "record" {
		return receiver
	}
	goT := g.goType(t)
	fn := g.helperFunc("clone:"+checker.TypeKey(t), "clone_"+g.nameOf(t), func(name string) ast.Decl {
		body := []ast.Stmt{
			define("c", &ast.StarExpr{X: ident("v")}),
			returned(address(ident("c"))),
		}
		return &ast.FuncDecl{Name: ident(name), Type: functionType([]*ast.Field{field("v", goT)}, goT), Body: block(body...)}
	})
	return call(fn, receiver)
}

// nativeCall calls a runtime function for a standard module function.
func (g *gen) nativeCall(s *checker.Symbol, typeArgs []*checker.Type, args []ast.Expr) ast.Expr {
	var targs []ast.Expr
	for _, a := range typeArgs {
		targs = append(targs, g.goType(a))
	}
	g.noteNative(nativeName(s.Native))
	bind := map[string]*checker.Type{}
	for i, v := range s.Variables {
		if i < len(typeArgs) {
			bind[v.ID] = typeArgs[i]
		}
	}
	leading := append([]ast.Expr{ident("ctx")}, g.capabilityArgs(checker.BoundCapabilities(s.Variables), bind)...)
	leading = append(leading, g.jsonCodecArgs(nativeName(s.Native), typeArgs)...)
	return call(generic(rtName(nativeName(s.Native)), targs...), append(leading, args...)...)
}

// capabilityArgs supplies the Equal capabilities a native operation takes
// after the execution: the generated equality of each constrained type.
// Hashable supplies the *rt.Keys that tell a collection how keys match.
func (g *gen) capabilityArgs(caps []checker.Capability, bind map[string]*checker.Type) []ast.Expr {
	var out []ast.Expr
	for _, c := range caps {
		t := bind[c.Variable.ID]
		if t == nil {
			g.fail("%s capability for %s is not determined", c.Property, c.Variable.Name)
			continue
		}
		switch c.Property {
		case "Hashable":
			out = append(out, g.keysFor(t))
		case "Comparable":
			out = append(out, g.compareFunc(t))
		default:
			out = append(out, g.equalFunc(t))
		}
	}
	return out
}

// nativeFunctionValue is a standard function used as a value.
func (g *gen) nativeFunctionValue(s *checker.Symbol, typeArgs []*checker.Type, info *checker.Info) ast.Expr {
	var targs []ast.Expr
	for _, a := range typeArgs {
		targs = append(targs, g.goType(a))
	}
	if len(checker.BoundCapabilities(s.Variables)) > 0 {
		for _, c := range checker.BoundCapabilities(s.Variables) {
			if c.Property == "Equal" || c.Property == "Hashable" || c.Property == "Comparable" {
				g.fail("%s needs an equality or ordering capability and cannot be used as a function value", s.Name)
			}
		}
	}
	if len(g.jsonCodecArgs(nativeName(s.Native), typeArgs)) > 0 {
		g.fail("%s needs the generated codec of its type and cannot be used as a function value", s.Name)
	}
	g.noteNative(nativeName(s.Native))
	return generic(rtName(nativeName(s.Native)), targs...)
}

// noteNative records a runtime function the program uses, for the
// completeness check between standard declarations and the runtime.
func (g *gen) noteNative(name string) {
	g.mu.Lock()
	defer g.mu.Unlock()
	if g.natives == nil {
		g.natives = map[string]bool{}
	}
	g.natives[name] = true
}

// methodCall calls a method: a source implementation resolved statically, a
// native receiver operation, or an operation on a contract value.
func (g *gen) methodCall(e *syntax.Expression, info *checker.Info) ast.Expr {
	member := e.Left
	if member.Kind == syntax.KindApply {
		member = member.Left
	}
	calleeInfo := g.info(e.Left)
	if calleeInfo != nil && calleeInfo.Method != nil {
		info = &checker.Info{Method: calleeInfo.Method, Type: info.Type, Arguments: info.Arguments, TypeArgs: info.TypeArgs, Native: info.Native}
	}
	receiverType := g.info(member.Left).Type
	m := g.resolveMethod(info.Method, receiverType, member.Text)
	signature := g.sub(calleeInfo.Type)
	c := callee{params: signature.Params, defaults: signature.Defaults, module: g.module, siteDefaults: m.Native != "" && (m.Native != "contract" || isStdType(g.sub(receiverType)))}
	if m.Decl != nil {
		c.decls = m.Decl.Params
		c.bindings = g.program.ParameterBindings(m.Decl)
	}
	// The receiver is evaluated before the arguments.
	receiver := g.spillIfCalls(g.expr(member.Left))
	mark := len(g.fn.pre)
	args := g.arguments(info.Arguments, c)
	// An argument that runs code may reassign a mutable receiver variable.
	if id, ok := receiver.(*ast.Ident); ok && g.fn.mutables[id.Name] && len(g.fn.pre) > mark {
		name := g.temp()
		snapshot := define(name, receiver)
		g.fn.pre = append(g.fn.pre[:mark:mark], append([]ast.Stmt{snapshot}, g.fn.pre[mark:]...)...)
		receiver = ident(name)
	}
	return g.invokeMethod(m, receiverType, receiver, member.Text, args, calleeInfo)
}

// spillIfCalls captures a receiver that runs code so arguments cannot run first.
func (g *gen) spillIfCalls(e ast.Expr) ast.Expr {
	if effects := effectsOf(e); effects.calls || effects.reads {
		return g.spill(e)
	}
	return e
}

// resolveMethod re-resolves the operation after type variables are replaced:
// a bound variable's contract operation becomes the concrete implementation.
func (g *gen) resolveMethod(m *checker.Method, receiver *checker.Type, name string) *checker.Method {
	receiver = g.sub(receiver)
	if m.Native == "contract" && receiver.Kind == "contract" {
		return m
	}
	if len(g.subst) == 0 && m.Native != "contract" {
		return m
	}
	// A bound variable's operation resolves against the implementations
	// visible where the instance is used; any other operation was chosen
	// lexically by the checker and keeps its module's view.
	candidates := g.program.ResolveMethods(g.module, receiver, name)
	if m.Native == "contract" {
		candidates = g.resolve(receiver, name)
	}
	for _, candidate := range candidates {
		if m.Contract == nil || candidate.Contract == nil || candidate.Contract.ID == g.sub(m.Contract).ID {
			return candidate
		}
	}
	return m
}

// invokeMethod emits the call for a resolved method.
func (g *gen) invokeMethod(m *checker.Method, receiverType *checker.Type, receiver ast.Expr, name string, args []ast.Expr, calleeInfo *checker.Info) ast.Expr {
	receiverType = g.sub(receiverType)
	switch {
	case m.Decl != nil && m.Decl.Name == "to_string" && len(args) == 0:
		return g.format(receiverType, receiver)
	case m.Native == "contract":
		return call(selector(receiver, exportName(name)), append([]ast.Expr{ident("ctx")}, args...)...)
	case m.Native == "hash" && m.Contract != nil && m.Contract.ID == "@std/Hashable":
		return g.derivedHash(receiverType, receiver)
	case m.Native != "" && m.Contract == nil:
		return g.nativeMethodCall(m, receiverType, receiver, name, args, calleeInfo)
	case m.Native != "":
		g.noteNative(implName(m, g.sub(receiverType)))
		return call(rtName(implName(m, g.sub(receiverType))), append([]ast.Expr{ident("ctx"), receiver}, args...)...)
	}
	f := g.methodFunction(m, receiverType)
	return call(ident(f.name), append([]ast.Expr{ident("ctx"), receiver}, args...)...)
}

// nativeMethodCall calls the runtime function for a native receiver
// operation, named Type_Operation and instantiated at the receiver's and the
// operation's type arguments.
func (g *gen) nativeMethodCall(m *checker.Method, receiverType *checker.Type, receiver ast.Expr, name string, args []ast.Expr, calleeInfo *checker.Info) ast.Expr {
	if m.Decl.Name == "clone" && (receiverType.Kind == "record" || receiverType.Kind == "alternative") {
		return g.cloneValue(receiverType, receiver)
	}
	if m.Decl.Name == "length" && len(args) == 0 {
		// A List or Bytes length is Go's len on the backing slice.
		if isStd(receiverType, "List") {
			return call(ident("len"), selector(receiver, "Items"))
		}
		if isStd(receiverType, "Bytes") {
			return call(ident("len"), selector(receiver, "Data"))
		}
	}
	fn := g.nativeMethodName(m, receiverType)
	g.noteNative(fn)
	targs, bind := g.nativeTypeArguments(m, receiverType, calleeInfo)
	leading := []ast.Expr{ident("ctx")}
	if op, ok := checker.NativeOperationFor(receiverType, m.Decl.Name); ok {
		leading = append(leading, g.capabilityArgs(checker.OperationCapabilities(receiverType, op.Requirements, op.Variables), bind)...)
	}
	if calleeInfo != nil && calleeInfo.Type != nil {
		args = g.unviewArgs(args, calleeInfo.Type, receiverType)
	}
	return call(generic(rtName(fn), targs...), append(append(leading, receiver), args...)...)
}

// unviewArgs unwraps the Comparable argument of a native compare to the
// receiver's own type, which is what the native operation takes.
func (g *gen) unviewArgs(args []ast.Expr, callee, receiverType *checker.Type) []ast.Expr {
	out := append([]ast.Expr(nil), args...)
	for i := range out {
		if i >= len(callee.Params) {
			break
		}
		if p := g.sub(callee.Params[i].Type); p.ID == "@std/Comparable" && p.ID != receiverType.ID {
			out[i] = call(generic(rtName("Unview"), g.goType(receiverType)), out[i])
		}
	}
	return out
}

func (g *gen) nativeMethodName(m *checker.Method, receiverType *checker.Type) string {
	base := receiverType.Name
	if receiverType.Kind == "primitive" {
		base = receiverType.ID
	}
	return base + "_" + camel(m.Decl.Name)
}

// nativeTypeArguments are the receiver's type arguments followed by the
// operation's own, which the checker leaves implicit: they are recovered by
// unifying the generic operation signature with the specialized callee type.
func (g *gen) nativeTypeArguments(m *checker.Method, receiverType *checker.Type, calleeInfo *checker.Info) ([]ast.Expr, map[string]*checker.Type) {
	var targs []ast.Expr
	bind := map[string]*checker.Type{}
	for i, a := range receiverType.Args {
		targs = append(targs, g.goType(a))
		if receiverType.Def != nil && i < len(receiverType.Def.Variables) {
			bind[receiverType.Def.Variables[i].ID] = a
		}
	}
	if len(m.Variables) > 0 && calleeInfo != nil {
		sub, ok := checker.Unify(m.Type, g.sub(calleeInfo.Type), m.Variables)
		if !ok {
			g.fail("cannot infer the type arguments of %s", m.Native)
		}
		for _, v := range m.Variables {
			if t := sub[v.ID]; t != nil {
				bind[v.ID] = t
				targs = append(targs, g.goType(t))
			} else {
				g.fail("type argument %s of %s is not determined", v.Name, m.Native)
			}
		}
	}
	return targs, bind
}

// callsMember reports whether callee names a member, possibly with explicit
// type arguments, rather than being the result of another call.
func callsMember(callee *syntax.Expression) bool {
	if callee.Kind == syntax.KindApply {
		callee = callee.Left
	}
	return callee.Kind == syntax.KindMember
}
