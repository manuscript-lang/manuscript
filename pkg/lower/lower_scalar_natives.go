package lower

import (
	"go/ast"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// scalarNative is a pure standard-library operation over Go scalars with a
// typed runtime implementation. A member's receiver is its first parameter.
type scalarNative struct {
	function string
	params   []string // "" is a boxed Value
	result   string   // "" is a boxed Value
	receiver string   // Manuscript type ID of a Value receiver, when params[0] is ""
}

func floats(function string, count int) scalarNative {
	params := make([]string, count)
	for i := range params {
		params[i] = "float64"
	}
	return scalarNative{function: function, params: params, result: "float64"}
}

var scalarNatives = map[string]scalarNative{
	"math/abs": floats("MathAbs", 1), "math/floor": floats("MathFloor", 1), "math/ceil": floats("MathCeil", 1),
	"math/round": floats("MathRound", 1), "math/sqrt": floats("MathSqrt", 1), "math/exp": floats("MathExp", 1),
	"math/log": floats("MathLog", 1), "math/log2": floats("MathLog2", 1), "math/log10": floats("MathLog10", 1),
	"math/sin": floats("MathSin", 1), "math/cos": floats("MathCos", 1), "math/tan": floats("MathTan", 1),
	"math/asin": floats("MathAsin", 1), "math/acos": floats("MathAcos", 1), "math/atan": floats("MathAtan", 1),
	"math/sinh": floats("MathSinh", 1), "math/cosh": floats("MathCosh", 1), "math/tanh": floats("MathTanh", 1),
	"math/truncate": floats("MathTruncate", 1), "math/pow": floats("MathPow", 2), "math/min": floats("MathMin", 2),
	"math/max": floats("MathMax", 2), "math/hypot": floats("MathHypot", 2), "math/atan2": floats("MathAtan2", 2),
	"math/remainder": floats("MathRemainder", 2),
	"math/abs_int":   {function: "MathAbsInt", params: []string{"int64"}, result: "int64"},

	"math/is_nan":    {function: "MathIsNaN", params: []string{"float64"}, result: "bool"},
	"math/is_finite": {function: "MathIsFinite", params: []string{"float64"}, result: "bool"},

	"string/length":        {function: "StringLengthScalar", params: []string{"string"}, result: "int64"},
	"string/is_empty":      {function: "StringIsEmpty", params: []string{"string"}, result: "bool"},
	"string/compare":       {function: "StringCompare", params: []string{"string", "string"}, result: "int64"},
	"string/concat":        {function: "StringConcat", params: []string{"string", "string"}, result: "string"},
	"string/split":         {function: "StringSplit", params: []string{"string", "string"}},
	"string/replace":       {function: "StringReplaceFirst", params: []string{"string", "string", "string"}, result: "string"},
	"string/replace_first": {function: "StringReplaceFirst", params: []string{"string", "string", "string"}, result: "string"},
	"string/join":          {function: "StringJoin", params: []string{"", "string"}, result: "string", receiver: "@std/List"},

	"string/trim":        {function: "StringTrim", params: []string{"string"}, result: "string"},
	"string/upper":       {function: "StringUpper", params: []string{"string"}, result: "string"},
	"string/lower":       {function: "StringLower", params: []string{"string"}, result: "string"},
	"string/contains":    {function: "StringContains", params: []string{"string", "string"}, result: "bool"},
	"string/starts_with": {function: "StringStartsWith", params: []string{"string", "string"}, result: "bool"},
	"string/ends_with":   {function: "StringEndsWith", params: []string{"string", "string"}, result: "bool"},
}

var scalarTypeNames = map[string]string{"string": "String", "float64": "Float", "int64": "Int", "bool": "Bool"}

// scalarNativeCall returns the table entry when e calls a typed standard
// function or String member with every argument supplied in declaration order,
// and the argument expressions in call order (the receiver first).
func (g *generator) scalarNativeCall(e *syntax.Expression) (scalarNative, []*syntax.Expression, bool) {
	info := g.program.Info(e)
	if info == nil || info.Constructor != nil || e.Left == nil {
		return scalarNative{}, nil, false
	}
	var native string
	var operands []*syntax.Expression
	var params []checker.Param
	callee := g.program.Info(e.Left)
	if callee == nil || callee.Type == nil {
		return scalarNative{}, nil, false
	}
	params = callee.Type.Params
	switch {
	case info.Symbol != nil && info.Symbol.Native != "":
		native = info.Symbol.Native
	case e.Left.Kind == syntax.KindMember && callee.Method != nil && callee.Method.Contract == nil:
		native = callee.Method.Native
		entry, ok := scalarNatives[native]
		receiver := g.program.Info(e.Left.Left)
		want := entry.receiver
		if want == "" && len(entry.params) > 0 {
			want = scalarTypeNames[entry.params[0]]
		}
		if !ok || receiver == nil || receiver.Type == nil || want == "" || receiver.Type.ID != want {
			return scalarNative{}, nil, false
		}
		operands = append(operands, e.Left.Left)
	default:
		return scalarNative{}, nil, false
	}
	entry, ok := scalarNatives[native]
	if !ok || len(info.Arguments) > len(params) || len(operands)+len(info.Arguments) != len(entry.params) {
		return scalarNative{}, nil, false
	}
	// A typed entry may leave out only trailing parameters declared "= none".
	for i := len(info.Arguments); i < len(params); i++ {
		decl := g.declaredParams(info, callee)
		if decl == nil || len(decl) != len(params) || !isNoneDefault(decl[i].Default) {
			return scalarNative{}, nil, false
		}
	}
	for i, argument := range info.Arguments {
		if argument.Name != params[i].Name {
			return scalarNative{}, nil, false
		}
		operands = append(operands, argument.Value)
	}
	return entry, operands, true
}

// scalarNativeValue lowers a typed standard call to a plain runtime call
// without boxing arguments or the result.
func (g *generator) scalarNativeValue(e *syntax.Expression) ast.Expr {
	entry, operands, ok := g.scalarNativeCall(e)
	if !ok {
		return nil
	}
	values := make([]ast.Expr, len(operands))
	for i, operand := range operands {
		var value ast.Expr
		if entry.params[i] == "" {
			value = g.expression(operand)
		} else {
			value = g.scalar(operand, entry.params[i])
		}
		// A later match argument can reassign a local used by an earlier one.
		free := g.exprFree(operand)
		for _, later := range operands[i+1:] {
			free = free && g.exprFree(later)
		}
		if !free {
			value = sequence(value)
		}
		values[i] = value
	}
	return call(runtimeName(entry.function), values...)
}

// declaredParams returns the declaration parameters of the standard function
// or member a call resolves to.
func (g *generator) declaredParams(info *checker.Info, callee *checker.Info) []syntax.Parameter {
	switch {
	case info.Symbol != nil && info.Symbol.Decl != nil:
		return info.Symbol.Decl.Params
	case callee.Method != nil && callee.Method.Decl != nil:
		return callee.Method.Decl.Params
	}
	return nil
}
