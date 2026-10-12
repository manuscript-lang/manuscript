package compiler

import (
	"fmt"
	"github.com/manuscript-lang/manuscript/checker"
	"github.com/manuscript-lang/manuscript/syntax"
	"go/format"
	"sort"
	"strconv"
	"strings"
)

type loopLabel struct {
	name string
	used bool
}
type generator struct {
	program     *checker.Program
	serial      int
	cleanups    []string
	loopCleanup []int
	loopLabels  []*loopLabel
	captures    map[*checker.Binding]string
}

func quote(s string) string { return strconv.Quote(s) }
func stringsGo(values []string) string {
	var entries []string
	for _, v := range values {
		entries = append(entries, quote(v))
	}
	return "[]string{" + strings.Join(entries, ",") + "}"
}
func (g *generator) temp() string { g.serial++; return fmt.Sprintf("temporary%d", g.serial) }
func (g *generator) key(t *checker.Type) string {
	return "rt.ResolveType(" + quote(checker.TypeKey(t)) + ", typeArgs)"
}
func (g *generator) binding(b *checker.Binding) string {
	if name := g.captures[b]; name != "" {
		return name
	}
	return b.ID
}
func generate(program *checker.Program, entry string, options Options) (string, error) {
	g := &generator{program: program, captures: map[*checker.Binding]string{}}
	var out strings.Builder
	out.WriteString("package main\nimport (rt \"github.com/manuscript-lang/manuscript/runtime\";\"os\")\n")
	var functions []*checker.Symbol
	for _, module := range program.Modules {
		for _, d := range module.Declarations {
			if d.Kind == "fn" {
				s := program.Symbols[module.File][d.Name]
				functions = append(functions, s)
				out.WriteString("var " + s.ID + " rt.Value\n")
			}
		}
	}
	out.WriteString("func initialize(){\n")
	for _, s := range functions {
		out.WriteString(s.ID + " = ")
		if len(s.Variables) > 0 {
			var vars []string
			for _, v := range s.Variables {
				vars = append(vars, v.ID)
			}
			out.WriteString("rt.Generic{Variables:" + stringsGo(vars) + ", Build:func(typeArgs map[string]string) rt.Function {return ")
			out.WriteString(g.function(s.Decl.Params, s.Decl.Result, s.Decl.Body, program.Parameters[s.Decl], nil, s.Type))
			out.WriteString("}}\n")
		} else {
			out.WriteString("func()rt.Function{typeArgs:=map[string]string{};_ = typeArgs;return ")
			out.WriteString(g.function(s.Decl.Params, s.Decl.Result, s.Decl.Body, program.Parameters[s.Decl], nil, s.Type))
			out.WriteString("}()\n")
		}
	}
	for _, m := range program.Methods {
		var vars []string
		for _, v := range m.Variables {
			vars = append(vars, v.ID)
		}
		out.WriteString("rt.Register(rt.Implementation{Receiver:" + quote(checker.TypeKey(m.Receiver)) + ",Contract:" + quote(checker.TypeKey(m.Contract)) + ",Name:" + quote(m.Decl.Name) + ",Variables:" + stringsGo(vars) + ",Build:func(receiver rt.Value,typeArgs map[string]string) rt.Function{_ = typeArgs;return ")
		out.WriteString(g.function(m.Decl.Params, m.Decl.Result, m.Decl.Body, program.Parameters[m.Decl], program.Self[m.Decl], m.Type))
		out.WriteString("}})\n")
	}
	out.WriteString("}\nfunc main(){initialize();\n")
	if options.Tests {
		out.WriteString("tests:=[]rt.Test{\n")
		for _, module := range program.Modules {
			for _, d := range module.Declarations {
				if d.Kind != "test" {
					continue
				}
				out.WriteString("{Name:" + quote(module.File+"::"+d.Name) + ",Run:func()rt.Function{typeArgs:=map[string]string{};_ = typeArgs;return ")
				out.WriteString(g.function(nil, d.Result, d.Body, nil, nil, &checker.Type{Kind: "function", Result: &checker.Type{ID: "Unit"}}))
				out.WriteString("}()},\n")
			}
		}
		out.WriteString("};if rt.RunTests(tests)>0{os.Exit(1)}\n")
	} else if options.Entry {
		if options.CPUProfile == "" && options.HeapProfile == "" && options.Trace == "" {
			out.WriteString("os.Exit(rt.RunMain(" + program.Symbols[entry]["main"].ID + ",os.Args[1:]))\n")
		} else {
			out.WriteString("os.Exit(rt.Profile(" + quote(options.CPUProfile) + "," + quote(options.HeapProfile) + "," + quote(options.Trace) + ",func()int{return rt.RunMain(" + program.Symbols[entry]["main"].ID + ",os.Args[1:])}))\n")
		}
	} else {
		out.WriteString("_ = os.Args\n")
	}
	out.WriteString("}\n")
	formatted, err := format.Source([]byte(out.String()))
	if err != nil {
		return "", fmt.Errorf("generated invalid Go: %w", err)
	}
	return string(formatted), nil
}
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
	for i, b := range bindings {
		out.WriteString(fmt.Sprintf("%s := args[%d]; _ = %s\n", b.ID, i, b.ID))
	}
	if self != nil {
		out.WriteString(self.ID + " := receiver; _ = " + self.ID + "\n")
	}
	out.WriteString(g.body(body))
	out.WriteString("//line manuscript.generated.go:1\nreturn rt.Unit{}\n})")
	return out.String()
}
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
	if p.Kind == "name" {
		b := g.program.Bindings[p]
		return "var " + b.ID + " rt.Value = " + value + "; _ = " + b.ID + "\n"
	}
	tmp := g.temp()
	out := tmp + " := " + value + "; _ = " + tmp + "\n"
	if p.Kind == "record" {
		for _, f := range p.Fields {
			out += g.pattern(f.Pattern, "rt.Field("+tmp+","+quote(f.Name)+")")
		}
	}
	if p.Kind == "list" {
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
	case "bind":
		return g.pattern(s.Pattern, g.expression(s.Value))
	case "assign":
		return g.programBinding(s.Name, s.Value) + " = " + g.expression(s.Value) + "\n"
	case "return":
		if s.Value == nil {
			return "return rt.Unit{}\n"
		}
		return "return " + g.expression(s.Value) + "\n"
	case "call":
		return "_ = " + g.expression(s.Value) + "\n"
	case "break", "continue":
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
	case "if":
		out := "if rt.Bool(" + g.expression(s.Value) + "){\n" + g.body(s.Body) + "}"
		if len(s.Else) > 0 {
			out += "else{\n" + g.body(s.Else) + "}"
		}
		return out + "\n"
	case "while":
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
	case "for":
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
	case "with":
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
		return "{\n" + b.ID + " := " + g.expression(s.Value) + "; _ = " + b.ID + "\n" + cleanup + " := cleanupStack.PushContract(ctx," + b.ID + "," + contract + ")\n" + body + cleanup + ".Run()\n}\n"
	case "match":
		tmp := g.temp()
		out := tmp + " := " + g.expression(s.Value) + "\nswitch rt.Tag(" + tmp + "){\n"
		for index := range s.Arms {
			a := &s.Arms[index]
			if a.Path.Text == "_" {
				out += "default:\n"
			} else {
				out += "case " + quote(a.Path.Text) + ":\n"
			}
			for i, b := range g.program.ArmBindings[a] {
				if b != nil {
					out += b.ID + " := rt.Payload(" + tmp + "," + strconv.Itoa(i) + "); _ = " + b.ID + "\n"
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
func (g *generator) arguments(args []syntax.Argument) string {
	var values []string
	for _, a := range args {
		values = append(values, "{Name:"+quote(a.Name)+",Value:"+g.expression(a.Value)+"}")
	}
	return "[]rt.Argument{" + strings.Join(values, ",") + "}"
}
func (g *generator) expression(e *syntax.Expression) string {
	info := g.program.Expressions[e]
	switch e.Kind {
	case "number":
		if strings.HasSuffix(e.Text, "d") {
			return "rt.DecimalLiteral(" + quote(e.Text) + ")"
		}
		if strings.ContainsAny(e.Text, ".eE") {
			return "rt.Float(" + quote(e.Text) + ")"
		}
		return "rt.Integer(" + quote(e.Text) + ")"
	case "bool":
		return e.Text
	case "unit":
		return "rt.Unit{}"
	case "text":
		var values []string
		for _, p := range e.Parts {
			if p.Value != nil {
				values = append(values, "rt.Format("+g.expression(p.Value)+")")
			} else {
				values = append(values, quote(p.Text))
			}
		}
		return "rt.Text(" + strings.Join(values, ",") + ")"
	case "name", "apply":
		if info.Binding != nil {
			return g.binding(info.Binding)
		}
		if info.Symbol != nil {
			symbol := info.Symbol
			if symbol.Native != "" {
				return "rt.StandardFunction(" + quote(symbol.Native) + "," + g.key(info.Type.Result) + ")"
			}
			if len(symbol.Variables) > 0 {
				var args []string
				for _, a := range info.TypeArgs {
					args = append(args, g.key(a))
				}
				return "rt.Specialize(" + symbol.ID + ",[]string{" + strings.Join(args, ",") + "})"
			}
			return symbol.ID
		}
		if info.Constructor != nil {
			return "rt.NewAlternative(" + g.key(info.Constructor) + "," + quote(info.Case) + ",nil,nil)"
		}
	case "member":
		if info.Constructor != nil {
			return "rt.NewAlternative(" + g.key(info.Constructor) + "," + quote(info.Case) + ",nil,nil)"
		}
		if info.Method != nil {
			return "rt.Bind(" + g.expression(e.Left) + "," + g.key(info.Method.Contract) + "," + quote(e.Text) + ")"
		}
		if info.Native != "" {
			return "rt.NativeMember(" + g.expression(e.Left) + "," + quote(e.Text) + ")"
		}
		return "rt.Field(" + g.expression(e.Left) + "," + quote(e.Text) + ")"
	case "call":
		args := g.arguments(e.Args)
		if info.Constructor != nil {
			if info.Native == "view" {
				return "rt.ViewOf(" + g.key(info.Type) + "," + g.expression(e.Args[0].Value) + ")"
			}
			if info.Case != "" {
				labels := []string{}
				for _, cs := range checker.Cases(info.Constructor) {
					if cs.Name == info.Case {
						for _, f := range cs.Fields {
							labels = append(labels, f.Name)
						}
					}
				}
				return "rt.NewAlternative(" + g.key(info.Type) + "," + quote(info.Case) + "," + stringsGo(labels) + "," + args + ")"
			}
			return "rt.ConstructWithContext(ctx," + g.key(info.Type) + "," + args + ")"
		}
		if info.Native == "background" {
			return "rt.NewBackground(ctx," + args + ")"
		}
		if info.Native == "parallel" {
			return "rt.ParallelArguments(ctx," + g.key(info.Type) + "," + args + ")"
		}
		if info.Native == "parallel_map" {
			return "rt.ParallelMap(ctx," + g.key(info.Type) + "," + g.key(info.Type.Args[0]) + "," + args + ")"
		}
		var callable string
		if info.Symbol != nil {
			if info.Symbol.Native != "" {
				callable = "rt.StandardFunction(" + quote(info.Symbol.Native) + "," + g.key(info.Type) + ")"
			} else {
				callable = info.Symbol.ID
				if len(info.Symbol.Variables) > 0 {
					var types []string
					for _, a := range info.TypeArgs {
						types = append(types, g.key(a))
					}
					callable = "rt.Specialize(" + callable + ",[]string{" + strings.Join(types, ",") + "})"
				}
			}
		} else {
			callable = g.expression(e.Left)
		}
		return "rt.Invoke(ctx," + callable + "," + args + ")"
	case "list":
		var elements []string
		for _, item := range e.Elements {
			elements = append(elements, g.expression(item))
		}
		if info.Type.Kind == "pack" {
			return "rt.Pack{Items:[]rt.Value{" + strings.Join(elements, ",") + "}}"
		}
		return "rt.List{Type:" + g.key(info.Type) + ",Items:[]rt.Value{" + strings.Join(elements, ",") + "}}"
	case "unary":
		if e.Text == "-" && e.Right.Kind == "number" && e.Right.Text == "9223372036854775808" {
			return "rt.Integer(\"-9223372036854775808\")"
		}
		return "rt.Unary(" + quote(e.Text) + "," + g.expression(e.Right) + ")"
	case "binary":
		if e.Text == "and" || e.Text == "or" {
			op := "&&"
			if e.Text == "or" {
				op = "||"
			}
			return "(rt.Bool(" + g.expression(e.Left) + ")" + op + "rt.Bool(" + g.expression(e.Right) + "))"
		}
		return "rt.Binary(" + quote(e.Text) + "," + g.expression(e.Left) + "," + g.expression(e.Right) + ")"
	case "lambda":
		captures := append([]*checker.Binding{}, info.Captures...)
		sort.Slice(captures, func(i, j int) bool { return captures[i].ID < captures[j].ID })
		var declarations, values []string
		old := map[*checker.Binding]string{}
		for _, b := range captures {
			values = append(values, g.binding(b))
			old[b] = g.captures[b]
			snapshot := g.temp()
			g.captures[b] = snapshot
			declarations = append(declarations, snapshot+" rt.Value")
		}
		fn := g.function(e.Params, e.Result, e.Body, g.program.LambdaParameters[e], nil, info.Type)
		for _, b := range captures {
			if old[b] == "" {
				delete(g.captures, b)
			} else {
				g.captures[b] = old[b]
			}
		}
		return "func(" + strings.Join(declarations, ",") + ") rt.Function{return " + fn + "}(" + strings.Join(values, ",") + ")"
	}
	panic("missing lowering for " + e.Kind)
}
