package compiler

import (
	"go/ast"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// Scalar storage is a lowering fact about a checked binding, never its source
// name. Select only mutable accumulators with scalar operator assignments:
// immutable and ABI-only copies can reuse an existing box. Captures and callable
// parameters retain the Value ABI; selected locals have no boxed mirror.
func scalarLocals(program *checker.Program) map[*checker.Binding]string {
	captured := map[*checker.Binding]bool{}
	for _, info := range program.Expressions {
		for _, binding := range info.Captures {
			captured[binding] = true
		}
	}
	operatorAssigned := map[*checker.Binding]bool{}
	for value, binding := range program.Assignments {
		// try copies an already boxed payload; unary + is also an identity.
		// Neither establishes arithmetic work that benefits from native storage.
		unaryOperation := value.Kind == syntax.KindUnary && (value.Text == "-" || value.Text == "not")
		if value.Kind == syntax.KindBinary || unaryOperation {
			operatorAssigned[binding] = true
		}
	}
	locals := map[*checker.Binding]string{}
	for _, binding := range program.Bindings {
		if captured[binding] || !binding.Mutable || !operatorAssigned[binding] {
			continue
		}
		switch binding.Type.ID {
		case "Int":
			locals[binding] = "int64"
		case "Float":
			locals[binding] = "float64"
		case "Bool":
			locals[binding] = "bool"
		}
	}
	// A call already returns a boxed Value. Keeping an accumulator boxed avoids
	// extracting that result only to allocate a new box at the next call. This
	// conservative boundary rule is measured separately from arithmetic loops.
	for value, binding := range program.Assignments {
		if value.Kind == syntax.KindCall {
			delete(locals, binding)
		}
	}
	visitor := syntax.Visitor{Statement: func(statement *syntax.Statement) {
		if statement.Kind == syntax.KindBind && statement.Pattern.Kind == syntax.KindName && statement.Value.Kind == syntax.KindCall {
			delete(locals, program.Bindings[statement.Pattern])
		}
	}}
	for _, module := range program.Modules {
		for _, declaration := range module.Declarations {
			visitor.Walk(declaration)
		}
	}
	return locals
}

func (g *generator) localValue(binding *checker.Binding, value ast.Expr) ast.Expr {
	switch g.scalarLocals[binding] {
	case "int64":
		return runtimeCall("IntValue", value)
	case "float64":
		return runtimeCall("FloatValue", value)
	case "bool":
		return runtimeCall("Bool", value)
	}
	return value
}
