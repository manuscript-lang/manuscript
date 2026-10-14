package ir

import (
	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func (p *Program) selectScalarLocals() map[*checker.Binding]string {
	captured := map[*checker.Binding]bool{}
	for _, info := range p.checked.Expressions() {
		for _, b := range info.Captures {
			captured[b] = true
		}
	}
	locals := map[*checker.Binding]string{}
	allowed := map[*syntax.Expression]bool{}
	uses := map[*checker.Binding][]*syntax.Expression{}
	for e, info := range p.checked.Expressions() {
		if info.Binding != nil {
			uses[info.Binding] = append(uses[info.Binding], e)
		}
		if e.Kind == syntax.KindBinary && p.nativeBinaryOperands(e) {
			allowed[e.Left], allowed[e.Right] = true, true
		}
		if e.Kind == syntax.KindUnary && (e.Text == "-" || e.Text == "not") {
			allowed[e.Right] = true
		}
	}
	visitor := syntax.Visitor{Statement: func(s *syntax.Statement) {
		if s.Kind == syntax.KindIf || s.Kind == syntax.KindWhile || s.Kind == syntax.KindReturn {
			allowed[s.Value] = true
		}
		if s.Kind != syntax.KindBind || s.Pattern.Kind != syntax.KindName || !p.scalarProducer(s.Value) {
			return
		}
		b := p.checked.PatternBinding(s.Pattern)
		if b == nil || b.Mutable || captured[b] {
			return
		}
		valid := true
		for _, use := range uses[b] {
			valid = valid && allowed[use]
		}
		if typ := primitiveEqualityType(b.Type); valid && typ != "" {
			locals[b] = typ
		}
	}}
	// Build permitted statement uses before selecting immutable producers.
	for _, module := range p.checked.Modules {
		for _, d := range module.Declarations {
			syntax.Visitor{Statement: func(s *syntax.Statement) {
				if s.Kind == syntax.KindIf || s.Kind == syntax.KindWhile || s.Kind == syntax.KindReturn {
					allowed[s.Value] = true
				}
			}}.Walk(d)
		}
	}
	for _, module := range p.checked.Modules {
		for _, d := range module.Declarations {
			visitor.Walk(d)
		}
	}
	for statement, b := range p.checked.LoopBindings() {
		if statement.Kind != syntax.KindFor || captured[b] || primitiveListSuffix(p.checked.Info(statement.Value).Type) == "" {
			continue
		}
		valid := true
		for _, use := range uses[b] {
			valid = valid && allowed[use]
		}
		if typ := primitiveEqualityType(b.Type); valid && typ != "" {
			locals[b] = typ
		}
	}
	for e := range p.checked.Expressions() {
		if e.Kind != syntax.KindMatch || p.typedListAtSuffix(e.Left) == "" {
			continue
		}
		for i := range e.Arms {
			for _, b := range p.checked.ArmBindingsFor(&e.Arms[i]) {
				if b == nil || captured[b] {
					continue
				}
				valid := true
				for _, use := range uses[b] {
					valid = valid && allowed[use]
				}
				if typ := primitiveEqualityType(b.Type); valid && typ != "" {
					locals[b] = typ
				}
			}
		}
	}
	for e := range p.checked.Expressions() {
		b := p.checked.AssignedBinding(e)
		if b == nil {
			continue
		}
		if b.Mutable && !captured[b] && p.scalarProducer(e) {
			if typ := primitiveEqualityType(b.Type); typ != "" {
				locals[b] = typ
			}
		}
	}
	// A boxed source result/payload can reuse its box at the next boxed call.
	// Only known native producers remove both sides of that boundary.
	for e := range p.checked.Expressions() {
		b := p.checked.AssignedBinding(e)
		if b == nil {
			continue
		}
		if e.Kind == syntax.KindCall && !p.scalarProducer(e) {
			delete(locals, b)
		}
		if e.Kind == syntax.KindUnary && (e.Text == "try" || e.Text == "+") {
			delete(locals, b)
		}
	}
	return locals
}

func (p *Program) scalarProducer(e *syntax.Expression) bool {
	if e == nil {
		return false
	}
	switch e.Kind {
	case syntax.KindBinary:
		return p.nativeBinaryOperands(e)
	case syntax.KindUnary:
		return e.Text == "-" || e.Text == "not"
	case syntax.KindCall:
		return p.numericCallName(e) != "" || p.typedCollectionScalar(e) || p.nativeCallAvailable(e) && p.shareNativeBody(p.checked.Info(e).Symbol) || p.nativeMethodAvailable(e) && p.shareNativeBody(methodSymbol(p.checked.Info(e.Left).Method))
	}
	return false
}

func scalarEffects(e *syntax.Expression) bool {
	if e == nil {
		return false
	}
	switch e.Kind {
	case syntax.KindNumber, syntax.KindBool, syntax.KindName, syntax.KindApply:
		return false
	case syntax.KindCall, syntax.KindMatch, syntax.KindLambda:
		return true
	case syntax.KindUnary:
		return e.Text == "try" || scalarEffects(e.Right)
	case syntax.KindBinary:
		return scalarEffects(e.Left) || scalarEffects(e.Right)
	case syntax.KindMember:
		return scalarEffects(e.Left) || scalarEffects(e.Right)
	}
	// Interpolation and indexed/literal receivers can contain arbitrary calls.
	return true
}

func (p *Program) nativeBinaryOperands(e *syntax.Expression) bool {
	a, b := p.checked.Info(e.Left), p.checked.Info(e.Right)
	if e.Text == "and" || e.Text == "or" {
		return true
	}
	if a == nil || b == nil || primitiveEqualityType(a.Type) == "" || a.Type.ID != b.Type.ID || primitiveEqualityType(a.Type) != primitiveEqualityType(b.Type) {
		return false
	}
	switch e.Text {
	case "==", "!=":
		return true
	case "and", "or":
		return a.Type.ID == "Bool"
	case "+", "-", "*", "/", "<", "<=", ">", ">=":
		return a.Type.ID == "Int" || a.Type.ID == "Float"
	case "%":
		return a.Type.ID == "Int"
	}
	return false
}

func (p *Program) selectNativeCalls() {
	p.NativeCalls = map[*checker.Symbol]bool{}
	for _, m := range p.checked.Modules {
		for _, d := range m.Declarations {
			if d.Kind != syntax.KindFn {
				continue
			}
			s := p.checked.Symbol(m.File, d.Name)
			p.NativeCalls[s] = s.Native == "" && len(s.Variables) == 0 && !hasTypeVariable(s.Type)
		}
	}
}

func (p *Program) nativeCallAvailable(e *syntax.Expression) bool {
	info := p.checked.Info(e)
	if info == nil || !p.NativeCalls[info.Symbol] {
		return false
	}
	args := e.Args
	if info.Arguments != nil {
		args = info.Arguments
	}
	if len(args) > len(info.Symbol.Type.Params) {
		return false
	}
	present := map[string]bool{}
	for _, a := range args {
		present[a.Name] = true
	}
	for i, p := range info.Symbol.Type.Params {
		if !present[p.Name] && !nativeDefault(info.Symbol, i) {
			return false
		}
	}
	return true
}

// The boxed adapter can share the typed body only when its inputs stay native
// and its output is newly computed. Otherwise lower a boxed adapter from the
// same checked body, preserving the original box for identity/capture/storage.

func (p *Program) shareNativeBody(s *checker.Symbol) bool {
	return p.nativeBodyCompatible(s.Decl.Params, s.Decl.Body, p.checked.ParameterBindings(s.Decl), s.Type)
}

func (p *Program) nativeBodyCompatible(params []syntax.Parameter, body []*syntax.Statement, bindings []*checker.Binding, t *checker.Type) bool {
	parameters := map[*checker.Binding]bool{}
	for i, b := range bindings {
		parameters[b] = true
		if params[i].Default != nil || t.Defaults[t.Params[i].Name] {
			return false
		}
	}
	allowed := map[*syntax.Expression]bool{}
	var uses []*syntax.Expression
	valid := true
	syntax.Visitor{Statement: func(stmt *syntax.Statement) {
		if primitiveEqualityType(t.Result) != "" && stmt.Kind == syntax.KindReturn && !p.freshScalar(stmt.Value) {
			valid = false
		}
	}, Expression: func(e *syntax.Expression) {
		info := p.checked.Info(e)
		if info == nil {
			return
		}
		if parameters[info.Binding] {
			uses = append(uses, e)
		}
		if e.Kind == syntax.KindLambda {
			for _, b := range info.Captures {
				if parameters[b] {
					valid = false
				}
			}
		}
		if e.Kind == syntax.KindBinary && p.nativeBinaryOperands(e) {
			allowed[e.Left], allowed[e.Right] = true, true
		}
		if e.Kind == syntax.KindUnary && (e.Text == "-" || e.Text == "not") {
			allowed[e.Right] = true
		}
	}}.Callable(params, body)
	for _, e := range uses {
		if primitiveEqualityType(p.checked.Info(e).Type) != "" && !allowed[e] {
			valid = false
		}
	}
	return valid
}

func (p *Program) freshScalar(e *syntax.Expression) bool {
	if e == nil {
		return false
	}
	switch e.Kind {
	case syntax.KindNumber, syntax.KindBool:
		return true
	case syntax.KindBinary:
		return p.nativeBinaryOperands(e)
	case syntax.KindUnary:
		return e.Text == "-" || e.Text == "not"
	case syntax.KindName:
		return p.ScalarLocals[p.checked.Info(e).Binding] != ""
	case syntax.KindCall:
		return p.numericCallName(e) != "" || p.typedCollectionScalar(e)
	}
	return false
}

func comparatorKind(t *checker.Type, params []syntax.Parameter) string {
	if t == nil || hasTypeVariable(t) || primitiveEqualityType(t.Result) != "int64" || len(t.Params) != 2 {
		return ""
	}
	for i, p := range t.Params {
		if params[i].Default != nil || t.Defaults[p.Name] {
			return ""
		}
	}
	a, b := primitiveEqualityType(t.Params[0].Type), primitiveEqualityType(t.Params[1].Type)
	if a != b {
		return ""
	}
	if a == "int64" {
		return "Int"
	}
	if a == "float64" {
		return "Float"
	}
	return ""
}

func (p *Program) selectNativeMethods() {
	p.NativeMethods = map[string]*checker.Method{}
	for _, m := range p.checked.Methods {
		if m.Native == "" && len(m.Variables) == 0 && !hasTypeVariable(m.Receiver) && !hasTypeVariable(m.Type) {
			p.NativeMethods[m.ID] = m
		}
	}
}

func (p *Program) nativeMethodAvailable(e *syntax.Expression) bool {
	if e.Kind != syntax.KindCall || e.Left.Kind != syntax.KindMember {
		return false
	}
	info := p.checked.Info(e.Left)
	if info == nil || info.Method == nil || p.NativeMethods[info.Method.ID] == nil {
		return false
	}
	receiver := p.checked.Info(e.Left.Left).Type
	if receiver.Kind == "contract" || hasTypeVariable(receiver) {
		return false
	}
	args := e.Args
	if converted := p.checked.Info(e).Arguments; converted != nil {
		args = converted
	}
	// Omitted inherited interface defaults retain their existing preparation.
	return len(args) == len(info.Method.Type.Params)
}

func primitiveListSuffix(t *checker.Type) string { return ListSuffix(t) }

func (p *Program) typedListAtSuffix(e *syntax.Expression) string {
	if e == nil || e.Kind != syntax.KindCall || e.Left.Kind != syntax.KindMember {
		return ""
	}
	info := p.checked.Info(e.Left)
	if info == nil || info.Method == nil || info.Method.Contract != nil || info.Method.Native != "collections/at" {
		return ""
	}
	args := e.Args
	if converted := p.checked.Info(e).Arguments; converted != nil {
		args = converted
	}
	if len(args) != 1 {
		return ""
	}
	return primitiveListSuffix(p.checked.Info(e.Left.Left).Type)
}

func (p *Program) typedUnwrapAt(e *syntax.Expression) bool {
	if e.Kind != syntax.KindCall || e.Left.Kind != syntax.KindMember {
		return false
	}
	info := p.checked.Info(e.Left)
	if info == nil || info.Method == nil || info.Method.Contract != nil || info.Method.Native != "optional/unwrap" {
		return false
	}
	args := e.Args
	if converted := p.checked.Info(e).Arguments; converted != nil {
		args = converted
	}
	return len(args) == 0 && p.typedListAtSuffix(e.Left.Left) != ""
}

func (p *Program) typedCollectionScalar(e *syntax.Expression) bool {
	if p.typedUnwrapAt(e) {
		return true
	}
	if e.Kind != syntax.KindCall || e.Left.Kind != syntax.KindMember {
		return false
	}
	info := p.checked.Info(e.Left)
	if info == nil || info.Method == nil || info.Method.Contract != nil || info.Method.Native != "length" {
		return false
	}
	t := p.checked.Info(e.Left.Left).Type
	return len(e.Args) == 0 && (t.ID == "@std/List" || t.ID == "@std/Map" || t.ID == "@std/Set")
}

func (p *Program) numericCallName(e *syntax.Expression) string {
	if e.Kind != syntax.KindCall {
		return ""
	}
	info := p.checked.Info(e)
	if info == nil {
		return ""
	}
	args := e.Args
	if info.Arguments != nil {
		args = info.Arguments
	}
	if info.Symbol != nil && len(args) == 1 && args[0].Name == "value" && primitiveEqualityType(p.checked.Info(args[0].Value).Type) == "float64" {
		return map[string]string{"math/sqrt": "NativeFloatSqrt", "math/abs": "NativeFloatAbs", "math/floor": "NativeFloatFloor", "math/ceil": "NativeFloatCeil"}[info.Symbol.Native]
	}
	if e.Left.Kind == syntax.KindMember && len(args) == 0 {
		callee := p.checked.Info(e.Left)
		if callee != nil && callee.Method != nil && callee.Method.Contract == nil && callee.Method.Native == "to_float" && primitiveEqualityType(p.checked.Info(e.Left.Left).Type) == "int64" {
			return "NativeIntToFloat"
		}
	}
	return ""
}

func hasTypeVariable(t *checker.Type) bool {
	if t == nil {
		return false
	}
	if t.Kind == "variable" {
		return true
	}
	for _, arg := range t.Args {
		if hasTypeVariable(arg) {
			return true
		}
	}
	if t.Kind == "function" {
		for _, param := range t.Params {
			if hasTypeVariable(param.Type) {
				return true
			}
		}
		return hasTypeVariable(t.Result)
	}
	return false
}

func primitiveEqualityType(t *checker.Type) string { return Primitive(t) }

func methodSymbol(m *checker.Method) *checker.Symbol {
	return &checker.Symbol{ID: m.ID, Module: m.Module, Decl: m.Decl, Type: m.Type}
}

func nativeDefault(s *checker.Symbol, index int) bool {
	return s.Decl.Params[index].Default != nil || s.Type.Defaults[s.Type.Params[index].Name]
}
