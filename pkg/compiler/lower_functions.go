package compiler

import (
	"fmt"
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func (g *generator) function(params []syntax.Parameter, result *syntax.Type, body []*syntax.Statement, bindings []*checker.Binding, self *checker.Binding, t *checker.Type) string {
	oldCleanups, oldLoops, oldLabels := g.cleanups, g.loopCleanup, g.loopLabels
	g.cleanups = nil
	g.loopCleanup = nil
	g.loopLabels = nil
	defer func() { g.cleanups = oldCleanups; g.loopCleanup = oldLoops; g.loopLabels = oldLabels }()
	var out strings.Builder
	labels := []string{}
	for _, p := range params {
		labels = append(labels, p.Name)
	}
	out.WriteString("rt.NewSourceFunction(" + stringsGo(labels) + "," + g.key(t.Result) + "," + quote(result.Pos.String()) + ",func(ctx *rt.Execution,args []rt.Value)rt.Value{\ncleanupStack:=rt.NewCleanupStack();defer cleanupStack.Unwind()\n")
	if self != nil {
		out.WriteString(self.ID + " := receiver; _ = " + self.ID + "\n")
	}
	for i, b := range bindings {
		out.WriteString(fmt.Sprintf("%s := args[%d]; _ = %s\n", b.ID, i, b.ID))
		// Checked source values are concrete (including Unit and Optional.none);
		// Invoke leaves nil only for an omitted argument.
		if params[i].Default == nil && t.Defaults[params[i].Name] && b.Type.ID == "@std/Optional" {
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
	out.WriteString("//line manuscript.generated.go:1\nreturn rt.Unit{}\n})")
	return out.String()
}
