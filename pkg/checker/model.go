package checker

import (
	"iter"

	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// Checked facts live on the syntax nodes they describe (their Fact field), so
// a tree is self-sufficient once checked. Lookups answer questions about one
// node; iterators walk the program's trees. A tree is annotated by one check at
// a time: callers that check a tree again replace its facts.

// exprFacts annotates an expression: its checked Info plus the variables and
// editor scope attached to that exact node.
type exprFacts struct {
	info       *Info
	parameters []*Binding // lambda parameters
	assigned   *Binding   // variable written when the expression is an assigned value
	scope      *ScopeState
}

type statementFacts struct {
	loop    *Binding
	cleanup *Method
	flow    *Flow
}

type armFacts struct {
	bindings    []*Binding
	hasBindings bool
	contract    *Type
	conflicts   []*Info
}

type declarationFacts struct {
	parameters []*Binding
	self       *Binding
}

func exprFactsOf(e *syntax.Expression) *exprFacts {
	if e == nil {
		return nil
	}
	f, _ := e.Fact.(*exprFacts)
	return f
}

func writableExprFacts(e *syntax.Expression) *exprFacts {
	f := exprFactsOf(e)
	if f == nil {
		f = &exprFacts{}
		e.Fact = f
	}
	return f
}

func statementFactsOf(s *syntax.Statement) *statementFacts {
	f, _ := s.Fact.(*statementFacts)
	return f
}

func writableStatementFacts(s *syntax.Statement) *statementFacts {
	f := statementFactsOf(s)
	if f == nil {
		f = &statementFacts{}
		s.Fact = f
	}
	return f
}

func armFactsOf(a *syntax.Arm) *armFacts {
	f, _ := a.Fact.(*armFacts)
	return f
}

func writableArmFacts(a *syntax.Arm) *armFacts {
	f := armFactsOf(a)
	if f == nil {
		f = &armFacts{}
		a.Fact = f
	}
	return f
}

func declarationFactsOf(d *syntax.Declaration) *declarationFacts {
	f, _ := d.Fact.(*declarationFacts)
	return f
}

func writableDeclarationFacts(d *syntax.Declaration) *declarationFacts {
	f := declarationFactsOf(d)
	if f == nil {
		f = &declarationFacts{}
		d.Fact = f
	}
	return f
}

func infoOf(e *syntax.Expression) *Info {
	if f := exprFactsOf(e); f != nil {
		return f.info
	}
	return nil
}
func setInfo(e *syntax.Expression, info *Info) { writableExprFacts(e).info = info }

func lambdaParametersOf(e *syntax.Expression) []*Binding {
	if f := exprFactsOf(e); f != nil {
		return f.parameters
	}
	return nil
}
func setLambdaParameters(e *syntax.Expression, bindings []*Binding) {
	writableExprFacts(e).parameters = bindings
}
func setAssigned(e *syntax.Expression, b *Binding)    { writableExprFacts(e).assigned = b }
func setScope(e *syntax.Expression, state ScopeState) { writableExprFacts(e).scope = &state }

func parametersOf(d *syntax.Declaration) []*Binding {
	if f := declarationFactsOf(d); f != nil {
		return f.parameters
	}
	return nil
}
func setParameters(d *syntax.Declaration, bindings []*Binding) {
	writableDeclarationFacts(d).parameters = bindings
}
func setSelf(d *syntax.Declaration, b *Binding) { writableDeclarationFacts(d).self = b }

func setLoopBinding(s *syntax.Statement, b *Binding) { writableStatementFacts(s).loop = b }
func setCleanup(s *syntax.Statement, m *Method)      { writableStatementFacts(s).cleanup = m }
func setFlow(s *syntax.Statement, flow Flow)         { writableStatementFacts(s).flow = &flow }
func cleanupOf(s *syntax.Statement) *Method {
	if f := statementFactsOf(s); f != nil {
		return f.cleanup
	}
	return nil
}

func armBindingsOf(a *syntax.Arm) []*Binding {
	if f := armFactsOf(a); f != nil {
		return f.bindings
	}
	return nil
}
func setArmBindings(a *syntax.Arm, bindings []*Binding) {
	f := writableArmFacts(a)
	f.bindings, f.hasBindings = bindings, true
}
func setContractPattern(a *syntax.Arm, t *Type) { writableArmFacts(a).contract = t }
func setNameConflicts(a *syntax.Arm, conflicts []*Info) {
	writableArmFacts(a).conflicts = conflicts
}

// Info returns the checked facts of an expression, or nil for an unchecked one.
func (p *Program) Info(e *syntax.Expression) *Info { return infoOf(e) }

// Expressions visits every checked expression.
func (p *Program) Expressions() iter.Seq2[*syntax.Expression, *Info] {
	return facts(p, func(n *syntax.Nodes, emit func(*syntax.Expression, *Info)) {
		n.Expression = func(e *syntax.Expression) {
			if info := infoOf(e); info != nil {
				emit(e, info)
			}
		}
	})
}

// PatternBinding returns the variable a binding pattern declares.
func (p *Program) PatternBinding(pattern *syntax.Pattern) *Binding {
	b, _ := pattern.Fact.(*Binding)
	return b
}

// PatternBindings visits every binding pattern.
func (p *Program) PatternBindings() iter.Seq2[*syntax.Pattern, *Binding] {
	return facts(p, func(n *syntax.Nodes, emit func(*syntax.Pattern, *Binding)) {
		n.Pattern = func(pattern *syntax.Pattern) {
			if b := p.PatternBinding(pattern); b != nil {
				emit(pattern, b)
			}
		}
	})
}

// LoopBinding returns the variable a for statement declares.
func (p *Program) LoopBinding(s *syntax.Statement) *Binding {
	if f := statementFactsOf(s); f != nil {
		return f.loop
	}
	return nil
}

// LoopBindings visits every for statement variable.
func (p *Program) LoopBindings() iter.Seq2[*syntax.Statement, *Binding] {
	return facts(p, func(n *syntax.Nodes, emit func(*syntax.Statement, *Binding)) {
		n.Statement = func(s *syntax.Statement) {
			if b := p.LoopBinding(s); b != nil {
				emit(s, b)
			}
		}
	})
}

// ArmBindingsFor returns the payload variables a match arm declares.
func (p *Program) ArmBindingsFor(arm *syntax.Arm) []*Binding { return armBindingsOf(arm) }

// ArmBindings visits every match arm that declares variables.
func (p *Program) ArmBindings() iter.Seq2[*syntax.Arm, []*Binding] {
	return facts(p, func(n *syntax.Nodes, emit func(*syntax.Arm, []*Binding)) {
		n.Arm = func(arm *syntax.Arm) {
			if f := armFactsOf(arm); f != nil && f.hasBindings {
				emit(arm, f.bindings)
			}
		}
	})
}

// ContractPattern returns the contract a type pattern arm matches, if any.
func (p *Program) ContractPattern(arm *syntax.Arm) *Type {
	if f := armFactsOf(arm); f != nil {
		return f.contract
	}
	return nil
}

// ParameterBindings returns the parameter variables of a declaration.
func (p *Program) ParameterBindings(d *syntax.Declaration) []*Binding { return parametersOf(d) }

// Parameters visits every declaration that has parameter variables.
func (p *Program) Parameters() iter.Seq2[*syntax.Declaration, []*Binding] {
	return facts(p, func(n *syntax.Nodes, emit func(*syntax.Declaration, []*Binding)) {
		n.Declaration = func(d *syntax.Declaration) {
			if bindings := parametersOf(d); bindings != nil {
				emit(d, bindings)
			}
		}
	})
}

// LambdaBindings returns the parameter variables of a lambda.
func (p *Program) LambdaBindings(e *syntax.Expression) []*Binding { return lambdaParametersOf(e) }

// LambdaParameters visits every lambda that has parameter variables.
func (p *Program) LambdaParameters() iter.Seq2[*syntax.Expression, []*Binding] {
	return facts(p, func(n *syntax.Nodes, emit func(*syntax.Expression, []*Binding)) {
		n.Expression = func(e *syntax.Expression) {
			if bindings := lambdaParametersOf(e); bindings != nil {
				emit(e, bindings)
			}
		}
	})
}

// SelfBinding returns the receiver variable of a method declaration.
func (p *Program) SelfBinding(d *syntax.Declaration) *Binding {
	if f := declarationFactsOf(d); f != nil {
		return f.self
	}
	return nil
}

// SelfBindings visits every method receiver variable.
func (p *Program) SelfBindings() iter.Seq2[*syntax.Declaration, *Binding] {
	return facts(p, func(n *syntax.Nodes, emit func(*syntax.Declaration, *Binding)) {
		n.Declaration = func(d *syntax.Declaration) {
			if b := p.SelfBinding(d); b != nil {
				emit(d, b)
			}
		}
	})
}

// AssignedBinding returns the variable an assignment target writes.
func (p *Program) AssignedBinding(target *syntax.Expression) *Binding {
	if f := exprFactsOf(target); f != nil {
		return f.assigned
	}
	return nil
}

// Cleanup returns the cleanup method a cleanup statement runs.
func (p *Program) Cleanup(s *syntax.Statement) *Method { return cleanupOf(s) }

// FlowOf reports whether control can fall through a statement; ok is false for an unchecked one.
func (p *Program) FlowOf(s *syntax.Statement) (flow Flow, ok bool) {
	if f := statementFactsOf(s); f != nil && f.flow != nil {
		return *f.flow, true
	}
	return Flow{}, false
}

// ScopeAt returns the names visible at a captured editor scope marker.
func (p *Program) ScopeAt(marker *syntax.Expression) (ScopeState, bool) {
	if f := exprFactsOf(marker); f != nil && f.scope != nil {
		return *f.scope, true
	}
	return ScopeState{}, false
}

// ScopeMarkers visits every captured editor scope.
func (p *Program) ScopeMarkers() iter.Seq2[*syntax.Expression, ScopeState] {
	return facts(p, func(n *syntax.Nodes, emit func(*syntax.Expression, ScopeState)) {
		n.Expression = func(e *syntax.Expression) {
			if state, ok := p.ScopeAt(e); ok {
				emit(e, state)
			}
		}
	})
}

// NameConflicts returns the type or case identities that a match arm's payload names shadow.
func (p *Program) NameConflicts(arm *syntax.Arm) []*Info {
	if f := armFactsOf(arm); f != nil {
		return f.conflicts
	}
	return nil
}

// ArmNameConflicts visits every arm whose payload names shadow a type or case.
func (p *Program) ArmNameConflicts() iter.Seq2[*syntax.Arm, []*Info] {
	return facts(p, func(n *syntax.Nodes, emit func(*syntax.Arm, []*Info)) {
		n.Arm = func(arm *syntax.Arm) {
			if conflicts := p.NameConflicts(arm); conflicts != nil {
				emit(arm, conflicts)
			}
		}
	})
}

// TypeReference returns the resolved type of a written type.
func (p *Program) TypeReference(t *syntax.Type) *Type {
	resolved, _ := t.Fact.(*Type)
	return resolved
}

// TypeReferences visits every resolved written type.
func (p *Program) TypeReferences() iter.Seq2[*syntax.Type, *Type] {
	return facts(p, func(n *syntax.Nodes, emit func(*syntax.Type, *Type)) {
		n.Type = func(t *syntax.Type) {
			if resolved := p.TypeReference(t); resolved != nil {
				emit(t, resolved)
			}
		}
	})
}

// visit walks the program's own modules.
func (p *Program) visit(nodes syntax.Nodes) {
	for _, module := range p.Modules {
		nodes.Module(module)
	}
}

// facts builds an iterator over the program's trees. install registers the
// callbacks that call emit for each node carrying the wanted fact; emit stops
// delivering once the consumer stops.
func facts[K, V any](p *Program, install func(n *syntax.Nodes, emit func(K, V))) iter.Seq2[K, V] {
	return func(yield func(K, V) bool) {
		stopped := false
		emit := func(k K, v V) {
			if !stopped && !yield(k, v) {
				stopped = true
			}
		}
		var nodes syntax.Nodes
		install(&nodes, emit)
		p.visit(nodes)
	}
}

// Symbol returns a module-level symbol by module file and name.
func (p *Program) Symbol(file, name string) *Symbol { return p.symbols[file][name] }

// ModuleSymbols returns the module-level symbols of one module by name.
func (p *Program) ModuleSymbols(file string) map[string]*Symbol { return p.symbols[file] }

// AllTypeReferences visits the resolved written types of the program followed
// by those of the standard declarations it can refer to.
func (p *Program) AllTypeReferences() iter.Seq2[*syntax.Type, *Type] {
	return func(yield func(*syntax.Type, *Type) bool) {
		for ref, typ := range p.TypeReferences() {
			if !yield(ref, typ) {
				return
			}
		}
		ensureStandard()
		for ref, typ := range StandardTypeReferences() {
			if !yield(ref, typ) {
				return
			}
		}
	}
}
