package checker

import (
	"iter"

	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// The checked program is queried, not indexed. Lookups answer questions about
// one syntax node; iterators visit every fact of a kind. Consumers must not
// depend on how the facts are stored.

// Info returns the checked facts of an expression, or nil for an unchecked one.
func (p *Program) Info(e *syntax.Expression) *Info { return p.expressions[e] }

// Expressions visits every checked expression.
func (p *Program) Expressions() iter.Seq2[*syntax.Expression, *Info] { return mapSeq(p.expressions) }

// PatternBinding returns the variable a binding pattern declares.
func (p *Program) PatternBinding(pattern *syntax.Pattern) *Binding { return p.bindings[pattern] }

// PatternBindings visits every binding pattern.
func (p *Program) PatternBindings() iter.Seq2[*syntax.Pattern, *Binding] { return mapSeq(p.bindings) }

// LoopBinding returns the variable a for statement declares.
func (p *Program) LoopBinding(s *syntax.Statement) *Binding { return p.loopBindings[s] }

// LoopBindings visits every for statement variable.
func (p *Program) LoopBindings() iter.Seq2[*syntax.Statement, *Binding] {
	return mapSeq(p.loopBindings)
}

// ArmBindingsFor returns the payload variables a match arm declares.
func (p *Program) ArmBindingsFor(arm *syntax.Arm) []*Binding { return p.armBindings[arm] }

// ArmBindings visits every match arm that declares variables.
func (p *Program) ArmBindings() iter.Seq2[*syntax.Arm, []*Binding] { return mapSeq(p.armBindings) }

// ContractPattern returns the contract a type pattern arm matches, if any.
func (p *Program) ContractPattern(arm *syntax.Arm) *Type { return p.contractPatterns[arm] }

// ParameterBindings returns the parameter variables of a declaration.
func (p *Program) ParameterBindings(d *syntax.Declaration) []*Binding { return p.parameters[d] }

// Parameters visits every declaration that has parameter variables.
func (p *Program) Parameters() iter.Seq2[*syntax.Declaration, []*Binding] {
	return mapSeq(p.parameters)
}

// LambdaBindings returns the parameter variables of a lambda.
func (p *Program) LambdaBindings(e *syntax.Expression) []*Binding { return p.lambdaParameters[e] }

// LambdaParameters visits every lambda that has parameter variables.
func (p *Program) LambdaParameters() iter.Seq2[*syntax.Expression, []*Binding] {
	return mapSeq(p.lambdaParameters)
}

// SelfBinding returns the receiver variable of a method declaration.
func (p *Program) SelfBinding(d *syntax.Declaration) *Binding { return p.self[d] }

// SelfBindings visits every method receiver variable.
func (p *Program) SelfBindings() iter.Seq2[*syntax.Declaration, *Binding] { return mapSeq(p.self) }

// AssignedBinding returns the variable an assignment target writes.
func (p *Program) AssignedBinding(target *syntax.Expression) *Binding { return p.assignments[target] }

// Cleanup returns the cleanup method a cleanup statement runs.
func (p *Program) Cleanup(s *syntax.Statement) *Method { return p.cleanups[s] }

// FlowOf reports whether control can fall through a statement; ok is false for an unchecked one.
func (p *Program) FlowOf(s *syntax.Statement) (flow Flow, ok bool) {
	flow, ok = p.flow[s]
	return flow, ok
}

// ScopeAt returns the names visible at a captured editor scope marker.
func (p *Program) ScopeAt(marker *syntax.Expression) (ScopeState, bool) {
	state, ok := p.scopes[marker]
	return state, ok
}

// ScopeMarkers visits every captured editor scope.
func (p *Program) ScopeMarkers() iter.Seq2[*syntax.Expression, ScopeState] { return mapSeq(p.scopes) }

// NameConflicts returns the type or case identities that a match arm's payload names shadow.
func (p *Program) NameConflicts(arm *syntax.Arm) []*Info { return p.armNameConflicts[arm] }

// ArmNameConflicts visits every arm whose payload names shadow a type or case.
func (p *Program) ArmNameConflicts() iter.Seq2[*syntax.Arm, []*Info] {
	return mapSeq(p.armNameConflicts)
}

// TypeReference returns the resolved type of a written type.
func (p *Program) TypeReference(t *syntax.Type) *Type { return p.typeReferences[t] }

// TypeReferences visits every resolved written type.
func (p *Program) TypeReferences() iter.Seq2[*syntax.Type, *Type] { return mapSeq(p.typeReferences) }

// Symbol returns a module-level symbol by module file and name.
func (p *Program) Symbol(file, name string) *Symbol { return p.symbols[file][name] }

// ModuleSymbols returns the module-level symbols of one module by name.
func (p *Program) ModuleSymbols(file string) map[string]*Symbol { return p.symbols[file] }

func mapSeq[K comparable, V any](m map[K]V) iter.Seq2[K, V] {
	return func(yield func(K, V) bool) {
		for k, v := range m {
			if !yield(k, v) {
				return
			}
		}
	}
}

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
		for ref, typ := range standardTypeReferences {
			if !yield(ref, typ) {
				return
			}
		}
	}
}
