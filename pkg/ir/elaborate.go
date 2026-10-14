package ir

import (
	"strconv"
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// Value elaborates one expression using the checked facts the caller supplies
// as info, which may differ from the program's own facts when a boundary
// conversion wraps the value. It returns nil for a form that has no node yet,
// so the caller keeps its existing path for that form.
func Value(program *checker.Program, e *syntax.Expression, info *checker.Info) Expr {
	switch e.Kind {
	case syntax.KindUnary:
		if (e.Text == "-" || e.Text == "+") && e.Right.Kind == syntax.KindNumber && (Primitive(info.Type) == "int64" || Primitive(info.Type) == "float64") {
			text := e.Right.Text
			if e.Text == "-" {
				text = "-" + text
			}
			switch value := number(text, info.Type).(type) {
			case IntLiteral:
				value.Unary = true
				return value
			case FloatLiteral:
				value.Unary = true
				return value
			}
		}
	case syntax.KindNumber:
		return number(e.Text, info.Type)
	case syntax.KindBool:
		return BoolLiteral{Value: e.Text == "true", Type: info.Type}
	case syntax.KindUnit:
		return UnitLiteral{}
	case syntax.KindText:
		parts := make([]TextPart, len(e.Parts))
		for i, p := range e.Parts {
			if p.Value != nil {
				parts[i].Value = Operand(program, p.Value)
			} else {
				parts[i].Text = p.Text
			}
		}
		return Text{Parts: parts, Type: info.Type}
	case syntax.KindList:
		items := make([]Expr, len(e.Elements))
		elements := make([]Edge, len(e.Elements))
		for i, item := range e.Elements {
			elements[i] = Use(program, item, info.Type.Args[0])
			items[i] = OperandAs(program, item, info.Type.Args[0])
		}
		return List{Type: info.Type, Items: items, Elements: elements}
	case syntax.KindMap:
		entries := make([]Entry, 0, len(e.Elements)/2)
		for at := 0; at < len(e.Elements); at += 2 {
			entries = append(entries, Entry{Key: Operand(program, e.Elements[at]), Value: Operand(program, e.Elements[at+1])})
		}
		return Map{Pos: e.Pos, Type: info.Type, Entries: entries}
	}
	return nil
}

// Operand elaborates a child expression. A child that crosses a checked
// boundary conversion, or has no node yet, stays deferred so lowering applies
// the conversion.
func Operand(program *checker.Program, e *syntax.Expression) Expr { return OperandAs(program, e, nil) }

// OperandAs retains the checked element/use expectation without overwriting
// source types; unsupported expression bodies continue through Deferred.
func OperandAs(program *checker.Program, e *syntax.Expression, expected *checker.Type) Expr {
	info := program.Info(e)
	if info == nil {
		return Deferred{Source: e}
	}
	edge := Use(program, e, expected)
	if edge.ErrorSource != nil || edge.Optional != nil || edge.Never {
		return Converted{Use: edge}
	}
	if x := Value(program, e, info); x != nil {
		return x
	}
	return Deferred{Source: e}
}

// number classifies a numeric literal by its written form: a d suffix is a
// decimal, a fraction or exponent a float, anything else an integer.
func number(text string, typ *checker.Type) Expr {
	if strings.HasSuffix(text, "d") {
		return DecimalLiteral{Text: text, Type: typ}
	}
	if strings.ContainsAny(text, ".eE") {
		value, _ := strconv.ParseFloat(text, 64)
		return FloatLiteral{Value: value, Type: typ}
	}
	value, _ := strconv.ParseInt(text, 10, 64)
	return IntLiteral{Value: value, Type: typ}
}
