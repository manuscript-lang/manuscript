package ir

import (
	"math"
	"strconv"
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// Value elaborates one expression using the checked facts the caller supplies
// as info, which may differ from the program's own facts when a boundary
// conversion wraps the value. It returns nil for a form that has no node yet,
// so the caller keeps its existing path for that form.
func (el *Elaborator) Value(e *syntax.Expression, info *checker.Info) Expr {
	program := el.program
	if value, constant := el.Bool(e); constant {
		return BoolLiteral{Value: value, Type: info.Type}
	}
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
				parts[i].Value = el.Operand(p.Value)
			} else {
				parts[i].Text = p.Text
			}
		}
		return Text{Parts: parts, Type: info.Type}
	case syntax.KindList:
		items := make([]Expr, len(e.Elements))
		for i, item := range e.Elements {
			items[i] = el.Operand(item)
		}
		return List{Type: info.Type, Items: items}
	case syntax.KindName:
		// A name that selects a method or resolves to a symbol stays deferred.
		if info.Method == nil && info.Binding != nil {
			return Local{Binding: info.Binding, Type: info.Type}
		}
	case syntax.KindMember:
		// A constructor member such as Color.red names a type, which has no facts.
		var receiverType *checker.Type
		if receiver := program.Info(e.Left); receiver != nil {
			receiverType = receiver.Type
		}
		return Member{Pos: e.Pos, Receiver: el.Operand(e.Left), ReceiverPos: e.Left.Pos, ReceiverType: receiverType, Name: e.Text, Info: info}
	case syntax.KindCall:
		if info.Constructor != nil && info.Native == "view" {
			receiver := program.Info(e.Args[0].Value)
			if receiver == nil {
				return nil
			}
			return View{Receiver: el.Operand(e.Args[0].Value), ReceiverType: receiver.Type, Type: info.Type}
		}
		syntaxArgs := e.Args
		if info.Arguments != nil {
			syntaxArgs = info.Arguments
		}
		args := make([]Argument, len(syntaxArgs))
		for i, a := range syntaxArgs {
			value := program.Info(a.Value)
			if value == nil {
				return nil
			}
			args[i] = Argument{Pos: a.Pos, Name: a.Name, Value: el.Operand(a.Value), Type: value.Type, Optional: value.OptionalArgument}
		}
		call := Call{Pos: e.Pos, Callee: el.Operand(e.Left), CalleePos: e.Left.Pos, Args: args, Info: info}
		if callee := program.Info(e.Left); callee != nil {
			call.CalleeType = callee.Type
		}
		return call
	case syntax.KindUnary:
		if e.Text == "try" {
			return nil
		}
		if e.Text == "-" && e.Right.Kind == syntax.KindNumber && e.Right.Text == "9223372036854775808" {
			return IntLiteral{Value: math.MinInt64, Type: info.Type}
		}
		return Unary{Pos: e.Pos, Op: e.Text, Operand: el.Operand(e.Right), Type: info.Type}
	case syntax.KindBinary:
		left, right := program.Info(e.Left), program.Info(e.Right)
		if left == nil || right == nil {
			return nil
		}
		return Binary{Pos: e.Pos, Op: e.Text, Left: el.Operand(e.Left), Right: el.Operand(e.Right), LeftType: left.Type, RightType: right.Type, Type: info.Type}
	case syntax.KindMap:
		entries := make([]Entry, 0, len(e.Elements)/2)
		for at := 0; at < len(e.Elements); at += 2 {
			entries = append(entries, Entry{Key: el.Operand(e.Elements[at]), Value: el.Operand(e.Elements[at+1])})
		}
		return Map{Pos: e.Pos, Type: info.Type, Entries: entries}
	}
	return nil
}

// Operand elaborates a child expression. A child that crosses a checked
// boundary conversion, or has no node yet, stays deferred so lowering applies
// the conversion.
func (el *Elaborator) Operand(e *syntax.Expression) Expr {
	info := el.program.Info(e)
	if info == nil || info.ErrorSource != nil {
		return Deferred{Source: e}
	}
	if x := el.Value(e, info); x != nil {
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
