//go:build ignore

// Oracle: prints the canonical AST dump (see crates/ms-syntax/src/dump.rs) of
// the Go parser, for strict parses and editor recovery.
package main

import (
	"fmt"
	"os"
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/parser"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

type d struct{ b strings.Builder }

func quote(s string) string {
	x := &d{}
	x.q(s)
	return x.b.String()
}
func (x *d) w(s string) { x.b.WriteString(s) }
func (x *d) q(s string) {
	x.w("\"")
	for i := 0; i < len(s); i++ {
		c := s[i]
		if c >= 0x20 && c < 0x7f && c != '"' && c != '\\' {
			x.b.WriteByte(c)
		} else {
			fmt.Fprintf(&x.b, "\\x%02x", c)
		}
	}
	x.w("\"")
}
func (x *d) p(p syntax.Position) { fmt.Fprintf(&x.b, "%d:%d:%d", p.Line, p.Column, p.Offset) }
func (x *d) typ(t *syntax.Type) {
	if t == nil {
		x.w("nil")
		return
	}
	x.w("(type ")
	x.p(t.Pos)
	x.w(" ")
	x.q(t.Name)
	x.w(" ")
	x.types(t.Args)
	x.w(" ")
	x.params(t.Params)
	x.w(" ")
	x.typ(t.Result)
	x.w(")")
}
func (x *d) types(ts []*syntax.Type) {
	x.w("[")
	for _, t := range ts {
		x.typ(t)
		x.w(" ")
	}
	x.w("]")
}
func (x *d) params(ps []syntax.Parameter) {
	x.w("[")
	for _, pm := range ps {
		x.w("(param ")
		x.p(pm.Pos)
		x.w(" ")
		x.q(pm.Name)
		x.w(" ")
		x.typ(pm.Type)
		x.w(" ")
		x.expr(pm.Default)
		x.w(") ")
	}
	x.w("]")
}
func (x *d) expr(e *syntax.Expression) {
	if e == nil {
		x.w("nil")
		return
	}
	x.w("(expr ")
	x.p(e.Pos)
	x.w(" " + e.Kind + " ")
	x.q(e.Text)
	x.w(" ")
	x.expr(e.Left)
	x.w(" ")
	x.expr(e.Right)
	x.w(" [")
	for _, a := range e.Args {
		x.w("(arg ")
		x.p(a.Pos)
		x.w(" ")
		x.q(a.Name)
		x.w(" ")
		x.expr(a.Value)
		x.w(") ")
	}
	x.w("] ")
	x.types(e.Types)
	x.w(" [")
	for _, el := range e.Elements {
		x.expr(el)
		x.w(" ")
	}
	x.w("] [")
	for _, part := range e.Parts {
		x.w("(part ")
		x.q(part.Text)
		x.w(" ")
		x.expr(part.Value)
		x.w(") ")
	}
	x.w("] ")
	x.params(e.Params)
	x.w(" ")
	x.typ(e.Result)
	x.w(" ")
	x.body(e.Body)
	x.w(" [")
	for _, a := range e.Arms {
		x.w("(arm ")
		x.p(a.Pos)
		x.w(" ")
		x.expr(a.Path)
		x.w(" [")
		for i, n := range a.Names {
			x.w("(")
			x.q(n)
			x.w(" ")
			x.p(a.NamePositions[i])
			x.w(") ")
		}
		x.w("] ")
		x.body(a.Body)
		x.w(" ")
		x.expr(a.Value)
		x.w(") ")
	}
	x.w("])")
}
func (x *d) pattern(p *syntax.Pattern) {
	if p == nil {
		x.w("nil")
		return
	}
	x.w("(pattern ")
	x.p(p.Pos)
	x.w(" " + p.Kind + " ")
	x.q(p.Name)
	x.w(" [")
	for _, e := range p.Elements {
		x.pattern(e)
		x.w(" ")
	}
	x.w("] [")
	for _, f := range p.Fields {
		x.w("(pf ")
		x.p(f.Pos)
		x.w(" ")
		x.q(f.Name)
		x.w(" ")
		x.pattern(f.Pattern)
		x.w(") ")
	}
	x.w("])")
}
func (x *d) body(b []*syntax.Statement) {
	x.w("[")
	for _, s := range b {
		x.stmt(s)
		x.w(" ")
	}
	x.w("]")
}
func (x *d) stmt(s *syntax.Statement) {
	x.w("(stmt ")
	x.p(s.Pos)
	x.w(" " + s.Kind + " ")
	x.q(s.Name)
	x.w(" ")
	x.q(s.Compound)
	fmt.Fprintf(&x.b, " %v ", s.Mutable)
	x.p(s.Group)
	x.w(" ")
	x.pattern(s.Pattern)
	x.w(" ")
	x.typ(s.Type)
	x.w(" ")
	x.expr(s.Target)
	x.w(" ")
	x.expr(s.Value)
	x.w(" ")
	x.body(s.Body)
	x.w(" ")
	x.body(s.Else)
	x.w(")")
}
func (x *d) decl(dd *syntax.Declaration) {
	x.w("(decl ")
	x.p(dd.Pos)
	x.w(" " + dd.Kind + " ")
	x.q(dd.Name)
	fmt.Fprintf(&x.b, " %v %v ", dd.Export, dd.Constant)
	x.p(dd.Group)
	fmt.Fprintf(&x.b, " %v ", dd.Synthetic)
	x.w("[")
	for _, tp := range dd.TypeParams {
		x.w("(tp ")
		x.p(tp.Pos)
		x.w(" ")
		x.q(tp.Name)
		x.w(" ")
		x.types(tp.Bounds)
		x.w(" ")
		x.typ(tp.Default)
		x.w(") ")
	}
	x.w("] ")
	x.params(dd.Fields)
	x.w(" [")
	for _, c := range dd.Cases {
		x.w("(case ")
		x.p(c.Pos)
		x.w(" ")
		x.q(c.Name)
		x.w(" ")
		x.params(c.Fields)
		x.w(") ")
	}
	x.w("] [")
	for _, m := range dd.Methods {
		x.decl(m)
		x.w(" ")
	}
	x.w("] ")
	x.params(dd.Params)
	x.w(" ")
	x.typ(dd.Result)
	x.w(" ")
	x.typ(dd.Contract)
	x.w(" ")
	x.typ(dd.Receiver)
	x.w(" ")
	x.body(dd.Body)
	x.w(")")
}
func module(m *syntax.Module) string {
	x := &d{}
	for _, i := range m.Imports {
		x.w("import ")
		x.p(i.Pos)
		x.w(" ")
		x.p(i.NamePos)
		x.w(" ")
		x.q(i.Name)
		x.w(" ")
		x.q(i.Path)
		x.w("\n")
	}
	for _, dd := range m.Declarations {
		x.decl(dd)
		x.w("\n")
	}
	x.w("omitted [")
	for _, o := range m.Omitted {
		x.q(o)
		x.w(" ")
	}
	x.w("]\nrecovered [")
	for _, r := range m.Recovered {
		fmt.Fprintf(&x.b, "%d-%d ", r.Start, r.End)
	}
	x.w("]\n")
	return x.b.String()
}

func main() {
	mode := os.Args[1]
	for _, path := range os.Args[2:] {
		data, _ := os.ReadFile(path)
		fmt.Println("file", path)
		if mode == "strict" {
			m, err := parser.Parse("f.ms", string(data))
			if err != nil {
				e := err.(syntax.Diagnostic)
				fmt.Printf("error %s %d:%d:%d %s\n", e.Phase, e.Position.Line, e.Position.Column, e.Position.Offset, quote(e.Message))
				continue
			}
			fmt.Print("ok\n" + module(m))
			continue
		}
		m, diags := parser.ParsePartial("f.ms", string(data))
		for _, e := range diags {
			end := "-"
			if e.End != nil {
				end = fmt.Sprintf("%d:%d:%d", e.End.Line, e.End.Column, e.End.Offset)
			}
			fix := "-"
			if e.Fix != nil {
				fix = fmt.Sprintf("%d:%d:%d>%d:%d:%d=%s", e.Fix.Position.Line, e.Fix.Position.Column, e.Fix.Position.Offset, e.Fix.End.Line, e.Fix.End.Column, e.Fix.End.Offset, quote(e.Fix.Replacement))
			}
			fmt.Printf("diag %s %d:%d:%d end=%s fix=%s %s\n", e.Phase, e.Position.Line, e.Position.Column, e.Position.Offset, end, fix, quote(e.Message))
		}
		fmt.Print(module(m))
	}
}
