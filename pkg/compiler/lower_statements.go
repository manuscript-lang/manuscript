package compiler

import (
	"fmt"
	"strconv"
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func (g *generator) body(body []*syntax.Statement) string {
	var out strings.Builder
	for _, s := range body {
		filename := strings.NewReplacer("\n", "_", "\r", "_").Replace(s.Pos.File)
		fmt.Fprintf(&out, "//line %s:%d\n", filename, s.Pos.Line)
		out.WriteString(g.statement(s))
	}
	return out.String()
}
func (g *generator) pattern(p *syntax.Pattern, value string) string {
	if p.Kind == syntax.KindName {
		b := g.program.Bindings[p]
		return "var " + b.ID + " rt.Value = " + value + "; _ = " + b.ID + "\n"
	}
	tmp := g.temp()
	out := tmp + " := " + value + "; _ = " + tmp + "\n"
	if p.Kind == syntax.KindRecord {
		for _, f := range p.Fields {
			out += g.pattern(f.Pattern, "rt.Field("+tmp+","+quote(f.Name)+")")
		}
	}
	if p.Kind == syntax.KindList {
		positions := g.temp()
		out += positions + " := rt.Positions(" + tmp + "," + strconv.Itoa(len(p.Elements)) + "); _ = " + positions + "\n"
		for i, child := range p.Elements {
			out += g.pattern(child, fmt.Sprintf("%s[%d]", positions, i))
		}
	}
	return out
}
func (g *generator) statement(s *syntax.Statement) string {
	switch s.Kind {
	case syntax.KindBind:
		return g.pattern(s.Pattern, g.expression(s.Value))
	case syntax.KindAssign:
		if s.Target != nil {
			return "rt.SetField(" + g.expression(s.Target.Left) + "," + quote(s.Target.Text) + "," + g.expression(s.Value) + ")\n"
		}
		return g.programBinding(s.Name, s.Value) + " = " + g.expression(s.Value) + "\n"
	case syntax.KindReturn:
		if s.Value == nil {
			return "return rt.Unit{}\n"
		}
		return "return " + g.expression(s.Value) + "\n"
	case syntax.KindCall:
		return "_ = " + g.expression(s.Value) + "\n"
	case syntax.KindBreak, syntax.KindContinue:
		out := ""
		start := 0
		if len(g.loopCleanup) > 0 {
			start = g.loopCleanup[len(g.loopCleanup)-1]
		}
		for i := len(g.cleanups) - 1; i >= start; i-- {
			out += g.cleanups[i] + ".Run()\n"
		}
		label := g.loopLabels[len(g.loopLabels)-1]
		label.used = true
		return out + s.Kind + " " + label.name + "\n"
	case syntax.KindIf:
		out := "if rt.Bool(" + g.expression(s.Value) + "){\n" + g.body(s.Body) + "}"
		if len(s.Else) > 0 {
			out += "else{\n" + g.body(s.Else) + "}"
		}
		return out + "\n"
	case syntax.KindWhile:
		g.loopCleanup = append(g.loopCleanup, len(g.cleanups))
		label := &loopLabel{name: g.temp()}
		g.loopLabels = append(g.loopLabels, label)
		body := g.body(s.Body)
		g.loopCleanup = g.loopCleanup[:len(g.loopCleanup)-1]
		g.loopLabels = g.loopLabels[:len(g.loopLabels)-1]
		prefix := ""
		if label.used {
			prefix = label.name + ":\n"
		}
		return prefix + "for rt.Bool(" + g.expression(s.Value) + "){\nrt.CheckCancelled(ctx)\n" + body + "}\n"
	case syntax.KindFor:
		b := g.program.LoopBindings[s]
		g.loopCleanup = append(g.loopCleanup, len(g.cleanups))
		label := &loopLabel{name: g.temp()}
		g.loopLabels = append(g.loopLabels, label)
		body := g.body(s.Body)
		g.loopCleanup = g.loopCleanup[:len(g.loopCleanup)-1]
		g.loopLabels = g.loopLabels[:len(g.loopLabels)-1]
		prefix := ""
		if label.used {
			prefix = label.name + ":\n"
		}
		return prefix + "for _," + b.ID + " := range rt.Iterate(" + g.expression(s.Value) + "){\n_ = " + b.ID + "\nrt.CheckCancelled(ctx)\n" + body + "}\n"
	case syntax.KindWith:
		b := g.program.LoopBindings[s]
		cleanup := g.temp()
		g.cleanups = append(g.cleanups, cleanup)
		body := g.body(s.Body)
		g.cleanups = g.cleanups[:len(g.cleanups)-1]
		contract := ""
		if method := g.program.Cleanups[s]; method != nil && method.Contract != nil {
			contract = g.key(method.Contract)
		} else {
			contract = quote("")
		}
		return "{\n" + b.ID + " := " + g.expression(s.Value) + "; _ = " + b.ID + "\n" + cleanup + " := cleanupStack.PushContract(ctx," + b.ID + "," + contract + "," + g.typeScope(b.Type) + ")\n" + body + cleanup + ".Run()\n}\n"
	case syntax.KindMatch:
		tmp := g.temp()
		contractMatch := g.program.Expressions[s.Value].Type.Kind == "contract"
		out := tmp + " := " + g.expression(s.Value) + "\n"
		if contractMatch {
			out += tmp + " = rt.ContractReceiver(" + tmp + ")\nswitch rt.ConcreteType(" + tmp + "){\n"
		} else {
			out += "switch rt.Tag(" + tmp + "){\n"
		}
		for index := range s.Arms {
			a := &s.Arms[index]
			if a.Path.Text == "_" {
				out += "default:\n"
			} else if contractMatch {
				out += "case " + g.key(g.program.ContractPatterns[a]) + ":\n"
			} else {
				out += "case " + quote(a.Path.Text) + ":\n"
			}
			for i, b := range g.program.ArmBindings[a] {
				if b != nil {
					value := "rt.Payload(" + tmp + "," + strconv.Itoa(i) + ")"
					if contractMatch {
						value = tmp
					}
					out += b.ID + " := " + value + "; _ = " + b.ID + "\n"
				}
			}
			out += g.body(a.Body)
		}
		return out + "}\n"
	}
	return ""
}

// Assignment binding identities are recorded by the checker, including shadows.
func (g *generator) programBinding(name string, e *syntax.Expression) string {
	return g.program.Assignments[e].ID
}
