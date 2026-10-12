package compiler

import (
	"fmt"
	"go/format"
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// lowerGo consumes checked identities and optimization facts. It never parses
// source or resolves a type or binding by its spelling.
func lowerGo(optimized optimizedProgram, entry string, options Options) (string, error) {
	program := optimized.program
	g := &generator{program: program, booleans: optimized.booleans, captures: map[*checker.Binding]string{}}
	var out strings.Builder
	out.WriteString("package main\nimport (rt \"github.com/manuscript-lang/manuscript/pkg/runtime\";\"os\")\n")
	var functions []*checker.Symbol
	for _, module := range program.Modules {
		for _, d := range module.Declarations {
			if d.Kind == syntax.KindFn || recordDefaults(d) {
				s := program.Symbols[module.File][d.Name]
				functions = append(functions, s)
				out.WriteString("var " + s.ID + " rt.Value\n")
			}
		}
	}
	out.WriteString("func initialize(){\n")
	for _, s := range functions {
		g.module = s.Module
		out.WriteString(s.ID + " = ")
		if len(s.Variables) > 0 {
			var vars []string
			for _, v := range s.Variables {
				vars = append(vars, v.ID)
			}
			out.WriteString("rt.Generic{Variables:" + stringsGo(vars) + ", Build:func(typeArgs map[string]string,typeScopes map[string]rt.TypeScope) rt.Function {return ")
			out.WriteString(g.declaredFunction(s))
			out.WriteString("}}\n")
		} else {
			out.WriteString("func()rt.Function{typeArgs:=map[string]string{};_ = typeArgs;return ")
			out.WriteString(g.declaredFunction(s))
			out.WriteString("}()\n")
		}
	}
	for _, m := range program.Methods {
		g.module = m.Module
		var vars []string
		for _, v := range m.Variables {
			vars = append(vars, v.ID)
		}
		scope := ""
		if m.Local {
			scope = m.Module
		}
		out.WriteString("rt.Register(rt.Implementation{Receiver:" + quote(checker.TypeKey(m.Receiver)) + ",Contract:" + quote(checker.TypeKey(m.Contract)) + ",Name:" + quote(m.Decl.Name) + ",Scope:" + quote(scope) + ",Variables:" + stringsGo(vars) + ",Build:func(receiver rt.Value,typeArgs map[string]string,typeScopes map[string]rt.TypeScope) rt.Function{_ = typeArgs;return ")
		if m.Native != "" {
			out.WriteString("rt.StandardImplementation(" + quote(m.Native) + ",receiver)")
		} else {
			out.WriteString(g.function(m.Decl.Params, m.Decl.Result, m.Decl.Body, program.Parameters[m.Decl], program.Self[m.Decl], m.Type))
		}
		out.WriteString("}})\n")
	}
	out.WriteString("}\nfunc main(){initialize();\n")
	if options.Tests {
		out.WriteString("tests:=[]rt.Test{\n")
		for _, module := range program.Modules {
			g.module = module.File
			for _, d := range module.Declarations {
				if d.Kind != syntax.KindTest {
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
