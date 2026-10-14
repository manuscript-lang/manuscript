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
		for i, item := range e.Elements {
			items[i] = Operand(program, item)
		}
		return List{Type: info.Type, Items: items}
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
func Operand(program *checker.Program, e *syntax.Expression) Expr {
	info := program.Info(e)
	if info == nil || info.ErrorSource != nil {
		return Deferred{Source: e}
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
