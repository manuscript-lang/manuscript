package lower

import (
	"go/ast"
	"strconv"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// A generic source function whose body only moves values of its type
// variables (binds, assigns, returns, branches, literals) has one Go function
// per concrete instantiation, so a scalar type argument stays an unboxed Go
// scalar through the call. The body is the checked generic body lowered with
// the type variables substituted; nothing in it selects an implementation by
// type, which is what makes substitution sound. Other generic functions keep
// the dynamic rt.Generic path.
type instance struct {
	symbol *checker.Symbol
	direct *directFunction
	subst  map[string]*checker.Type
}

// sub applies the type variables of the generic instance being lowered.
func (g *generator) sub(t *checker.Type) *checker.Type {
	if len(g.subst) == 0 || t == nil {
		return t
	}
	return checker.Sub(t, g.subst)
}

// info returns the checked facts of e, with the current instance's type
// variables substituted in every type they carry.
func (g *generator) info(e *syntax.Expression) *checker.Info {
	info := g.program.Info(e)
	if len(g.subst) == 0 || info == nil {
		return info
	}
	if cached := g.infoCache[e]; cached != nil {
		return cached
	}
	c := *info
	c.Type = g.sub(info.Type)
	c.ErrorSource = g.sub(info.ErrorSource)
	c.PropagatedError = g.sub(info.PropagatedError)
	c.OptionalArgument = g.sub(info.OptionalArgument)
	c.TypeArgs = nil
	for _, arg := range info.TypeArgs {
		c.TypeArgs = append(c.TypeArgs, g.sub(arg))
	}
	if g.infoCache == nil {
		g.infoCache = map[*syntax.Expression]*checker.Info{}
	}
	g.infoCache[e] = &c
	return &c
}

// instanceFor returns the direct function of s instantiated at args, planning
// it on first use, or nil when s or the arguments do not qualify.
func (g *generator) instanceFor(s *checker.Symbol, args []*checker.Type) *directFunction {
	if !g.directOn || len(args) != len(s.Variables) || !g.instantiable(s) {
		return nil
	}
	key := s.ID
	for _, arg := range args {
		if hasTypeVariable(arg) {
			return nil
		}
		key += "\x00" + checker.TypeKey(arg)
	}
	if in := g.instances[key]; in != nil {
		return in.direct
	}
	subst := map[string]*checker.Type{}
	for i, v := range s.Variables {
		subst[v.ID] = args[i]
	}
	in := &instance{symbol: s, subst: subst}
	g.subst = subst
	signature := g.sub(s.Type)
	direct := &directFunction{name: "call_" + s.ID + "_i" + strconv.Itoa(len(g.instanceOrder)+1), result: primitiveEqualityType(signature.Result), shape: alternativeShape(signature.Result)}
	for _, b := range g.program.ParameterBindings(s.Decl) {
		direct.params = append(direct.params, g.scalarBinding(b))
		direct.defaulted = append(direct.defaulted, false)
	}
	g.subst = nil
	in.direct = direct
	if g.instances == nil {
		g.instances = map[string]*instance{}
	}
	g.instances[key] = in
	g.instanceQueue = append(g.instanceQueue, in)
	g.instanceOrder = append(g.instanceOrder, in)
	return direct
}

// lowerInstances emits every planned instance and its source-name registration.
// Lowering one cannot plan another: instance bodies make no calls.
func (g *generator) lowerInstances() (decls []ast.Decl, registrations []ast.Stmt) {
	for len(g.instanceQueue) > 0 {
		in := g.instanceQueue[0]
		g.instanceQueue = g.instanceQueue[1:]
		s, d := in.symbol, in.symbol.Decl
		oldModule, oldTyped, oldInfo := g.module, g.typed, g.infoCache
		g.module, g.subst, g.infoCache = s.Module, in.subst, nil
		g.typed = map[*checker.Binding]string{}
		literal := g.directFunctionLiteral(in.direct, d.Name, d.Params, d.Result, d.Body, g.program.ParameterBindings(d), nil, g.sub(s.Type)).(*ast.FuncLit)
		g.module, g.subst, g.infoCache, g.typed = oldModule, nil, oldInfo, oldTyped
		decls = append(decls, &ast.FuncDecl{Name: ident(in.direct.name), Type: literal.Type, Body: literal.Body})
		registrations = append(registrations, evaluated(runtimeCall("RegisterSource", ident(in.direct.name), textLiteral(d.Name))))
	}
	return decls, registrations
}

// instantiable reports whether s is a generic function the instance path can
// lower soundly. The result is cached per symbol.
func (g *generator) instantiable(s *checker.Symbol) bool {
	if ok, seen := g.instanceChecked[s]; seen {
		return ok
	}
	if g.instanceChecked == nil {
		g.instanceChecked = map[*checker.Symbol]bool{}
	}
	ok := g.checkInstantiable(s)
	g.instanceChecked[s] = ok
	return ok
}

func (g *generator) checkInstantiable(s *checker.Symbol) bool {
	d := s.Decl
	if s.Native != "" || d == nil || d.Kind != syntax.KindFn || len(s.Variables) == 0 || s.Type == nil {
		return false
	}
	bindings := g.program.ParameterBindings(d)
	if len(bindings) != len(d.Params) || len(s.Type.Params) != len(d.Params) || len(s.Type.Defaults) != 0 {
		return false
	}
	variables := map[string]bool{}
	for _, v := range s.Variables {
		variables[v.ID] = true
	}
	// A type is moved opaquely when it names no variable or is a bare one.
	opaque := func(t *checker.Type) bool {
		return t == nil || !hasTypeVariable(t) || (t.Kind == "variable" && variables[t.ID])
	}
	for i, p := range d.Params {
		if p.Default != nil || !opaque(bindings[i].Type) {
			return false
		}
	}
	if !opaque(s.Type.Result) {
		return false
	}
	ok := true
	reject := func() { ok = false }
	syntax.Nodes{
		Pattern: func(p *syntax.Pattern) {
			if p.Kind != syntax.KindName {
				reject()
			}
		},
		Arm: func(*syntax.Arm) { reject() },
		Statement: func(st *syntax.Statement) {
			switch st.Kind {
			case syntax.KindBind, syntax.KindAssign, syntax.KindReturn, syntax.KindIf:
			default:
				reject()
			}
		},
		Expression: func(e *syntax.Expression) {
			switch e.Kind {
			case syntax.KindName, syntax.KindNumber, syntax.KindBool, syntax.KindText, syntax.KindUnit:
			case syntax.KindUnary, syntax.KindBinary:
				// An operator on a type variable would select its implementation by type.
				for _, operand := range []*syntax.Expression{e.Left, e.Right} {
					if operand != nil && (g.program.Info(operand) == nil || hasTypeVariable(g.program.Info(operand).Type)) {
						reject()
					}
				}
			default:
				reject()
				return
			}
			info := g.program.Info(e)
			if info == nil || info.Symbol != nil || info.Method != nil || info.Constructor != nil || len(info.TypeArgs) != 0 ||
				info.ErrorSource != nil || info.PropagatedError != nil || info.OptionalArgument != nil || len(info.Captures) != 0 ||
				info.Case != "" || info.Native != "" || !opaque(info.Type) || (info.Binding != nil && !opaque(info.Binding.Type)) {
				reject()
			}
		},
	}.Module(&syntax.Module{Declarations: []*syntax.Declaration{d}})
	return ok
}
