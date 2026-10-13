package lower

import (
	"go/ast"
	"go/token"
	"strconv"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// Options selects the entry point lowered into the generated main function.
type Options struct {
	// Tests lowers test blocks into the generated main; Entry lowers main().
	Tests, Entry                   bool
	CPUProfile, HeapProfile, Trace string
	// DebugLiterals trades repeated literal construction cost for faster native
	// compilation, as Debug builds do.
	DebugLiterals bool
}

// Go lowers a checked program to Go source. It consumes checked identities and
// optimization facts and never parses source or resolves a type or binding by
// its spelling.
func Go(program *checker.Program, entry string, options Options) (string, error) {
	optimized := optimize(program)
	g := &generator{program: optimized.program, booleans: optimized.booleans, captures: map[*checker.Binding]string{}, debugLiterals: options.DebugLiterals}
	file := g.file(entry, options)
	if g.loweringError != nil {
		return "", g.loweringError
	}
	return g.printGo(file)
}

// file assembles the Go tree; executable source is serialized only by printGo.
func (g *generator) file(entry string, options Options) *ast.File {
	program := g.program
	imports := []*ast.ImportSpec{
		{Name: ident("rt"), Path: &ast.BasicLit{Kind: token.STRING, Value: `"github.com/manuscript-lang/manuscript/pkg/runtime"`}},
		{Path: &ast.BasicLit{Kind: token.STRING, Value: `"os"`}},
	}
	file := &ast.File{Name: ident("main"), Imports: imports, Decls: []ast.Decl{
		&ast.GenDecl{Tok: token.IMPORT, Specs: []ast.Spec{imports[0], imports[1]}},
	}}
	var functions []*checker.Symbol
	for _, module := range program.Modules {
		for _, d := range module.Declarations {
			if d.Kind == syntax.KindFn || recordDefaults(d) {
				s := program.Symbol(module.File, d.Name)
				functions = append(functions, s)
				file.Decls = append(file.Decls, variable(s.ID, runtimeName("Value"), nil))
			}
		}
	}
	var initialize []ast.Stmt
	for _, s := range functions {
		g.module = s.Module
		var value ast.Expr
		if len(s.Variables) > 0 {
			var vars []string
			for _, v := range s.Variables {
				vars = append(vars, v.ID)
			}
			value = composite(runtimeName("Generic"), keyed("Variables", stringSlice(vars)), keyed("Build", closure(buildParameters(false), runtimeName("Function"), returned(g.declaredFunction(s)))))
		} else {
			value = concreteFunction(g.declaredFunction(s))
		}
		initialize = append(initialize, assign(ident(s.ID), token.ASSIGN, value))
	}
	var natives []ast.Expr
	flushNatives := func() {
		if len(natives) > 0 {
			initialize = append(initialize, evaluated(runtimeCall("RegisterStandard", sliceLiteral(runtimeName("StandardRegistration"), natives...))))
			natives = nil
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
		fields := []ast.Expr{keyed("Receiver", textLiteral(checker.TypeKey(m.Receiver))), keyed("Contract", textLiteral(checker.TypeKey(m.Contract))), keyed("Name", textLiteral(m.Decl.Name)), keyed("Scope", textLiteral(scope)), keyed("Variables", stringSlice(vars))}
		// Consecutive standard implementations register as one data table,
		// which compiles much faster than a closure for each.
		if m.Native != "" {
			fields = append(fields, keyed("Native", textLiteral(m.Native)))
			natives = append(natives, composite(nil, fields...))
			continue
		}
		flushNatives()
		labels, resultKey, position, body := g.functionParts(m.Receiver.Name+"."+m.Decl.Name, m.Decl.Params, m.Decl.Result, m.Decl.Body, program.ParameterBindings(m.Decl), program.SelfBinding(m.Decl), m.Type)
		if len(m.Variables) == 0 && !mentionsTypeBindings(body) {
			// A nongeneric method body needs only its receiver, so call sites
			// can run it without building a bound Function for each call.
			name := "direct" + strconv.Itoa(len(initialize)+1)
			direct := closure([]*ast.Field{field("ctx", &ast.StarExpr{X: runtimeName("Execution")}), field("receiver", runtimeName("Value")), field("args", sliceOf(runtimeName("Value")))}, runtimeName("Value"), body...)
			initialize = append(initialize, define(name, runtimeCall("SourceDirect", textLiteral(position), resultKey, direct)))
			fields = append(fields, keyed("Direct", ident(name)), keyed("Build", closure(buildParameters(true), runtimeName("Function"), discard(ident("typeArgs")), returned(runtimeCall("BoundDirect", ident("receiver"), stringSlice(labels), resultKey, ident(name))))))
		} else {
			fn := runtimeCall("NewSourceFunction", stringSlice(labels), resultKey, textLiteral(position), closure([]*ast.Field{field("ctx", &ast.StarExpr{X: runtimeName("Execution")}), field("args", sliceOf(runtimeName("Value")))}, runtimeName("Value"), body...))
			fields = append(fields, keyed("Build", closure(buildParameters(true), runtimeName("Function"), discard(ident("typeArgs")), returned(fn))))
		}
		initialize = append(initialize, evaluated(runtimeCall("Register", composite(runtimeName("Implementation"), fields...))))
	}
	flushNatives()
	file.Decls = append(file.Decls, &ast.FuncDecl{Name: ident("initialize"), Type: functionType(nil, nil), Body: block(initialize...)})
	main := []ast.Stmt{evaluated(call(ident("initialize")))}
	if options.Tests {
		var tests []ast.Expr
		for _, module := range program.Modules {
			g.module = module.File
			for _, d := range module.Declarations {
				if d.Kind != syntax.KindTest {
					continue
				}
				fn := g.function("test "+d.Name, nil, d.Result, d.Body, nil, nil, &checker.Type{Kind: "function", Result: &checker.Type{ID: "Unit"}})
				tests = append(tests, composite(nil, keyed("Name", textLiteral(module.File+"::"+d.Name)), keyed("Run", concreteFunction(fn))))
			}
		}
		main = append(main, define("tests", sliceLiteral(runtimeName("Test"), tests...)), &ast.IfStmt{Cond: &ast.BinaryExpr{X: runtimeCall("RunTestsArgs", ident("tests"), &ast.SliceExpr{X: selector(ident("os"), "Args"), Low: intLiteral(1)}), Op: token.GTR, Y: intLiteral(0)}, Body: block(evaluated(call(selector(ident("os"), "Exit"), intLiteral(1))))})
	} else if options.Entry {
		run := runtimeCall("RunMain", ident(program.Symbol(entry, "main").ID), &ast.SliceExpr{X: selector(ident("os"), "Args"), Low: intLiteral(1)})
		if options.CPUProfile != "" || options.HeapProfile != "" || options.Trace != "" {
			run = runtimeCall("Profile", textLiteral(options.CPUProfile), textLiteral(options.HeapProfile), textLiteral(options.Trace), closure(nil, ident("int"), returned(run)))
		}
		main = append(main, evaluated(call(selector(ident("os"), "Exit"), run)))
	} else {
		main = append(main, discard(selector(ident("os"), "Args")))
	}
	file.Decls = append(file.Decls, &ast.FuncDecl{Name: ident("main"), Type: functionType(nil, nil), Body: block(main...)})
	for _, name := range g.hoisted {
		file.Decls = append(file.Decls, variable(name, runtimeName("Lazy"), nil))
	}
	for _, name := range g.sites {
		file.Decls = append(file.Decls, variable(name, runtimeName("MethodSite"), nil))
	}
	file.Decls = append(file.Decls, g.literalData...)
	return file
}

// mentionsTypeBindings reports whether lowered statements read the type
// arguments or scopes that only a bound method build provides.
func mentionsTypeBindings(body []ast.Stmt) bool {
	found := false
	for _, stmt := range body {
		ast.Inspect(stmt, func(n ast.Node) bool {
			if id, ok := n.(*ast.Ident); ok && (id.Name == "typeArgs" || id.Name == "typeScopes") {
				found = true
			}
			return !found
		})
	}
	return found
}
