package ir

import (
	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// Callable is the declaration/body representation proof shared by typed
// entries, boxed adapters and comparator emission.
type Callable struct {
	Parameters []Parameter
	Bindings   []*checker.Binding
	Result     *checker.Type
	Shared     bool
	Comparator string
}

// Range records the authoritative captured List header representation.
// Backing reads stay live within that header; mutation must not reload its size.
type Range struct {
	Value      Edge
	Binding    *checker.Binding
	List       bool
	ListSuffix string
}

func (p *Program) callable(params []syntax.Parameter, body []*syntax.Statement, bindings []*checker.Binding, t *checker.Type) *Callable {
	x := &Callable{Bindings: bindings, Result: t.Result, Shared: p.nativeBodyCompatible(params, body, bindings, t), Comparator: comparatorKind(t, params)}
	for i, param := range t.Params {
		v := Parameter{Name: param.Name, Type: param.Type, Omittable: t.Defaults[param.Name]}
		if i < len(params) {
			v.Default = params[i].Default
			v.Omittable = v.Omittable || v.Default != nil
		}
		x.Parameters = append(x.Parameters, v)
	}
	return x
}

func (p *Program) Body(body []*syntax.Statement) *Callable {
	if len(body) == 0 {
		return &Callable{}
	}
	if x := p.bodies[body[0]]; x != nil {
		return x
	}
	return &Callable{}
}
