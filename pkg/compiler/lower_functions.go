package compiler

import (
	"fmt"
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func recordDefaults(d *syntax.Declaration) bool {
	if d == nil || d.Kind != syntax.KindRecord {
		return false
	}
	for _, f := range d.Fields {
		if f.Default != nil {
			return true
		}
	}
	return false
}

func (g *generator) declaredFunction(s *checker.Symbol) string {
	d := s.Decl
	if d.Kind == syntax.KindFn {
		return g.function(d.Name, d.Params, d.Result, d.Body, g.program.Parameters[d], nil, s.Type)
	}
	var args []string
	for i, field := range d.Fields {
		args = append(args, "rt.Argument{Name:"+quote(field.Name)+",Value:"+g.program.Parameters[d][i].ID+"}")
	}
	t := checker.ConstructorSignature(s.Type)
	return g.function(d.Name, d.Fields, &syntax.Type{Pos: d.Pos}, nil, g.program.Parameters[d], nil, t,
		"return rt.ConstructWithContext(ctx,"+g.key(s.Type)+",[]rt.Argument{"+strings.Join(args, ",")+"})\n")
}

func (g *generator) function(name string, params []syntax.Parameter, result *syntax.Type, body []*syntax.Statement, bindings []*checker.Binding, self *checker.Binding, t *checker.Type, tail ...string) string {
	oldCleanups, oldLoops, oldLabels, oldDepth := g.cleanups, g.loopCleanup, g.loopLabels, g.expressionDepth
	g.expressionDepth = 0
	g.cleanups = nil
	g.loopCleanup = nil
	g.loopLabels = nil
	defer func() {
		g.cleanups = oldCleanups
		g.loopCleanup = oldLoops
		g.loopLabels = oldLabels
		g.expressionDepth = oldDepth
	}()
	var out strings.Builder
	labels := []string{}
	for _, p := range t.Params {
		labels = append(labels, p.Name)
	}
	out.WriteString("rt.NewSourceFunction(" + stringsGo(labels) + "," + g.key(t.Result) + "," + quote(result.Pos.String()) + ",func(ctx *rt.Execution,args []rt.Value)rt.Value{\nsourcePosition:=" + quote(result.Pos.String()) + ";defer rt.TraceSource(ctx,&sourcePosition," + quote(name) + ")\ncleanupStack:=rt.NewCleanupStack();defer cleanupStack.Unwind()\n")
	if self != nil {
		out.WriteString(self.ID + " := receiver; _ = " + self.ID + "\n")
	}
	for i, b := range bindings {
		out.WriteString(fmt.Sprintf("%s := args[%d]; _ = %s\n", b.ID, i, b.ID))
		// Checked source values are concrete (including Unit and Optional.none);
		// Invoke leaves nil only for an omitted argument.
		if params[i].Default == nil && t.Defaults[t.Params[i].Name] && b.Type.ID == "@std/Optional" {
			out.WriteString("if " + b.ID + " == nil { " + b.ID + " = rt.NewAlternative(" + g.key(b.Type) + ",\"none\",nil,nil) }\n")
		}
		if params[i].Default != nil {
			pos := params[i].Default.Pos
			filename := strings.NewReplacer("\n", "_", "\r", "_").Replace(pos.File)
			fmt.Fprintf(&out, "//line %s:%d\n", filename, pos.Line)
			out.WriteString("if " + b.ID + " == nil { " + b.ID + " = " + g.expression(params[i].Default) + " }\n")
		}
	}
	out.WriteString(g.body(body))
	for _, code := range tail {
		out.WriteString(code)
	}
	out.WriteString("//line manuscript.generated.go:1\nreturn rt.Unit{}\n})")
	return out.String()
}
