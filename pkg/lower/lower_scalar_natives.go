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
	params   []string
	result   string
}

func floats(function string, count int) scalarNative {
	params := make([]string, count)
	for i := range params {
		params[i] = "float64"
	}
	return scalarNative{function, params, "float64"}
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
	"math/abs_int":   {"MathAbsInt", []string{"int64"}, "int64"},

	"math/is_nan":    {"MathIsNaN", []string{"float64"}, "bool"},
	"math/is_finite": {"MathIsFinite", []string{"float64"}, "bool"},

	"string/length":      {"StringLengthScalar", []string{"string"}, "int64"},
	"string/is_empty":    {"StringIsEmpty", []string{"string"}, "bool"},
	"string/compare":     {"StringCompare", []string{"string", "string"}, "int64"},
	"string/concat":      {"StringConcat", []string{"string", "string"}, "string"},
	"string/trim":        {"StringTrim", []string{"string"}, "string"},
	"string/upper":       {"StringUpper", []string{"string"}, "string"},
	"string/lower":       {"StringLower", []string{"string"}, "string"},
	"string/contains":    {"StringContains", []string{"string", "string"}, "bool"},
	"string/starts_with": {"StringStartsWith", []string{"string", "string"}, "bool"},
	"string/ends_with":   {"StringEndsWith", []string{"string", "string"}, "bool"},
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
		if !ok || receiver == nil || receiver.Type == nil || len(entry.params) == 0 || receiver.Type.ID != scalarTypeNames[entry.params[0]] {
			return scalarNative{}, nil, false
		}
		operands = append(operands, e.Left.Left)
	default:
		return scalarNative{}, nil, false
	}
	entry, ok := scalarNatives[native]
	if !ok || len(info.Arguments) != len(params) || len(operands)+len(params) != len(entry.params) {
		return scalarNative{}, nil, false
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
		value := g.scalar(operand, entry.params[i])
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
