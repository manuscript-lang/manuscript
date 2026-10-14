package ir

import (
	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// Edge is a checked value use. Type is the expression's resolved type;
// Expected belongs to this use, so Never never changes the source type.
// Error widening precedes Optional wrapping. Body/control-flow migration may
// still evaluate Source through Deferred, but must consume these conversions.
type Edge struct {
	Source                                *syntax.Expression
	Type, Expected, ErrorSource, Optional *checker.Type
	Never, ScopedError                    bool
}

// Operation identifies a primitive operation and its ordered operand uses.
// RightEffects requires capture of the left value before evaluating the right.
// Short-circuit operations keep the right edge inside its conditional region.
type Operation struct {
	Identity     string
	Primitive    string
	Left, Right  Edge
	RightEffects bool
}

// Argument is evaluated at its written position before the next argument.
// Slot is the resolved parameter position, independent of evaluation order.
type Argument struct {
	Name  string
	Pos   syntax.Position
	Slot  int
	Value Edge
}

// Parameter records omission permission separately from function identity.
// Defaults run in the callee, after supplied arguments have been captured.
type Parameter struct {
	Name                string
	Type                *checker.Type
	Default             *syntax.Expression
	Omittable, Supplied bool
}

// Call carries checked target identity and argument/default evaluation facts.
// Runtime operation names identify the existing ABI, whose owner remains the
// runtime. Native and Prepared flags are representation eligibility proofs.
type Call struct {
	Symbol                          *checker.Symbol
	Method                          *checker.Method
	TypeArgs                        []*checker.Type
	Receiver                        Edge
	Arguments                       []Argument
	Parameters                      []Parameter
	Ordered, Native, Prepared       bool
	Numeric, Collection, ListSuffix string
	UnwrapAt                        *syntax.Expression
	Record                          *Record
}

// Expression is the common resolved IR fact for an expression. Source is
// provenance and a temporary body/control-flow boundary, never name resolution.
type Expression struct {
	Source           *syntax.Expression
	Pos              syntax.Position
	Type, SourceType *checker.Type
	Primitive        string
	Binding          *checker.Binding
	Boundary         Edge
	NativeForm       string
	Operation        *Operation
	Call             *Call
	Arms             map[*syntax.Arm]Edge
}

// Program owns elaboration and representation proofs. Go emission consumes
// them without reclassifying checker tables. Checked is retained privately for
// elaborating body forms that have not migrated yet.
type Elaborator struct {
	known         map[*syntax.Expression]fold
	nodes         map[*syntax.Expression]Expr
	checked       *checker.Program
	expressions   map[*syntax.Expression]*Expression
	ScalarLocals  map[*checker.Binding]string
	NativeCalls   map[*checker.Symbol]bool
	NativeMethods map[string]*checker.Method
	Folds         *Folder
	Records       map[string]*Record
	RecordOrder   []*Record
	Fields        map[*syntax.Expression]*FieldUse
	Callables     map[*syntax.Declaration]*Callable
	Ranges        map[*syntax.Statement]Range
	bodies        map[*syntax.Statement]*Callable
}

func (p *Elaborator) Expression(e *syntax.Expression) *Expression { return p.expressions[e] }

func Use(program *checker.Program, e *syntax.Expression, expected *checker.Type) Edge {
	info := program.Info(e)
	return Edge{Source: e, Type: info.Type, Expected: expected, Never: info.Type.ID == "Never", ErrorSource: info.ErrorSource, Optional: info.OptionalArgument, ScopedError: info.ScopedError}
}

func (p *Elaborator) Use(e *syntax.Expression, expected *checker.Type) Edge {
	edge := p.expressions[e].Boundary
	edge.Expected = expected
	return edge
}

// Primitive names the native representation of canonical scalar identities.
// Nominal lookalikes and variables always retain the Value boundary.
func Primitive(t *checker.Type) string {
	if t == nil || t.Kind != "primitive" || t.Def != nil || len(t.Args) != 0 {
		return ""
	}
	return map[string]string{"Int": "int64", "Float": "float64", "Bool": "bool", "String": "string"}[t.ID]
}

func ListSuffix(t *checker.Type) string {
	if t == nil || t.ID != "@std/List" || len(t.Args) != 1 {
		return ""
	}
	return map[string]string{"int64": "Int", "float64": "Float", "bool": "Bool", "string": "String"}[Primitive(t.Args[0])]
}

// Elaborate resolves performance nodes once, without rewriting checked source.
func Elaborate(program *checker.Program) *Elaborator {
	p := &Elaborator{checked: program, expressions: map[*syntax.Expression]*Expression{}, Callables: map[*syntax.Declaration]*Callable{}}
	p.resolveRecords()
	p.nodes = map[*syntax.Expression]Expr{}
	p.selectNativeCalls()
	p.selectNativeMethods()
	for e, info := range program.Expressions() {
		sourceType := info.Type
		if info.ErrorSource != nil {
			sourceType = info.ErrorSource
		}
		x := &Expression{Source: e, Pos: e.Pos, Type: info.Type, SourceType: sourceType, Primitive: Primitive(info.Type), Binding: info.Binding, Boundary: Use(program, e, nil)}
		if e.Kind == syntax.KindBinary && p.nativeBinaryOperands(e) {
			expected := program.Info(e.Left).Type
			if expected.ID == "Never" {
				expected = program.Info(e.Right).Type
			}
			if e.Text == "and" || e.Text == "or" {
				expected = boolType
			}
			x.Operation = &Operation{Identity: e.Text, Primitive: Primitive(expected), Left: Use(program, e.Left, expected), Right: Use(program, e.Right, expected), RightEffects: scalarEffects(e.Right)}
		}
		if e.Kind == syntax.KindUnary && (e.Text == "+" || e.Text == "-" || e.Text == "not") && x.Primitive != "" {
			x.Operation = &Operation{Identity: e.Text, Primitive: x.Primitive, Right: Use(program, e.Right, info.Type)}
		}
		if e.Kind == syntax.KindCall {
			x.Call = p.resolveCall(e)
		}
		if e.Kind == syntax.KindMatch {
			x.Arms = map[*syntax.Arm]Edge{}
			for i := range e.Arms {
				a := &e.Arms[i]
				if a.Value != nil {
					x.Arms[a] = Use(program, a.Value, info.Type)
				}
			}
		}
		if info.ErrorSource == nil && x.Primitive != "" {
			switch e.Kind {
			case syntax.KindNumber, syntax.KindBool:
				x.NativeForm = "constant"
			case syntax.KindName, syntax.KindApply:
				x.NativeForm = "binding"
			case syntax.KindBinary, syntax.KindUnary:
				if x.Operation != nil {
					x.NativeForm = "operation"
				}
			case syntax.KindCall:
				if x.Call.Native || x.Call.Numeric != "" || x.Call.UnwrapAt != nil || x.Call.Collection == "CollectionLengthInt" {
					x.NativeForm = "call"
				}
			case syntax.KindMatch:
				x.NativeForm = "match"
			case syntax.KindMember:
				if p.Fields[e] != nil {
					x.NativeForm = "field"
				}
			}
		}
		p.expressions[e] = x
	}
	p.ScalarLocals = p.selectScalarLocals()
	p.Callables = map[*syntax.Declaration]*Callable{}
	p.bodies = map[*syntax.Statement]*Callable{}
	for _, module := range program.Modules {
		for _, d := range module.Declarations {
			if d.Kind == syntax.KindFn {
				s := program.Symbol(module.File, d.Name)
				p.recordBody(s)
			}
		}
	}
	for _, m := range program.Methods {
		if m.Native == "" {
			p.recordBody(methodSymbol(m))
		}
	}
	for e, info := range program.Expressions() {
		if e.Kind == syntax.KindLambda && len(e.Body) > 0 {
			p.bodies[e.Body[0]] = p.callable(e.Params, e.Body, program.LambdaBindings(e), info.Type)
		}
	}

	p.Ranges = map[*syntax.Statement]Range{}
	for statement, b := range program.LoopBindings() {
		if statement.Kind == syntax.KindFor {
			t := program.Info(statement.Value).Type
			p.Ranges[statement] = Range{Value: Use(program, statement.Value, nil), Binding: b, List: t.ID == "@std/List", ListSuffix: ListSuffix(t)}
		}
	}
	p.known = map[*syntax.Expression]fold{}
	p.Folds = p
	return p
}

var boolType = &checker.Type{Name: "Bool", ID: "Bool", Kind: "primitive"}

// BoolUse supplies the expected type for if/while without changing Never.
func (p *Elaborator) BoolUse(e *syntax.Expression) Edge { return p.Use(e, boolType) }

func (p *Elaborator) ShareNativeBody(s *checker.Symbol) bool { return p.Callables[s.Decl].Shared }
func (p *Elaborator) recordBody(s *checker.Symbol) {
	x := p.callable(s.Decl.Params, s.Decl.Body, p.checked.ParameterBindings(s.Decl), s.Type)
	p.Callables[s.Decl] = x
	if len(s.Decl.Body) > 0 {
		p.bodies[s.Decl.Body[0]] = x
	}
}

// Program preserves the published shared-contract name. There is one
// elaborator and one node/fold cache, rather than a parallel API implementation.
type Program = Elaborator

func NewElaborator(program *checker.Program) *Elaborator { return Elaborate(program) }
