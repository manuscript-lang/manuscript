// Package golower lowers a checked program to idiomatic, fully typed Go. Every
// Manuscript type maps to one Go type, generics are instantiated per concrete
// type, and no value is ever boxed in an interface unless the language itself
// asks for an interface value.
package golower

import (
	"fmt"
	"go/ast"
	"go/token"
	"sort"
	"strconv"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// Options selects the entry point lowered into the generated main function.
type Options struct {
	// Tests lowers test blocks into the generated main; Entry lowers main().
	Tests, Entry bool
}

// Go lowers a checked program to Go source.
func Go(program *checker.Program, entry string, options Options) (string, error) {
	g := &gen{program: program, types: map[string]*typeDecl{}, funcs: map[string]*funcDecl{}, methodByID: map[string]*checker.Method{}}
	for _, m := range program.Methods {
		g.methodByID[m.ID] = m
	}
	file := g.file(entry, options)
	if g.err != nil {
		return "", g.err
	}
	return g.printGo(file)
}

type gen struct {
	program *checker.Program
	module  string
	err     error
	serial  int

	// subst maps the type variables of the instance being lowered to their
	// concrete types; infoCache memoizes the substituted facts.
	subst     map[string]*checker.Type
	infoCache map[*syntax.Expression]*checker.Info

	types     map[string]*typeDecl
	typeOrder []*typeDecl
	funcs     map[string]*funcDecl
	queue     []*funcDecl
	decls     []ast.Decl

	sourceLines map[string]syntax.Position

	names      map[string]bool                // Go identifiers declared at package level
	helpers    map[string]string              // generated per-type helper functions by key
	natives    map[string]bool                // runtime functions the program calls
	methodByID map[string]*checker.Method     // implementations by identity
	aliases    map[*checker.Binding]*checker.Symbol
	captured   map[*checker.Binding]string    // snapshot names of captured variables
	used       map[*checker.Binding]bool      // variables some expression reads
	localEq    int

	// The function being lowered.
	fn *funcState
}

// funcState is the lexical state of the Go function under construction.
type funcState struct {
	decl    *funcDecl
	result  *checker.Type
	pre     []ast.Stmt // statements the current statement needs first
	cleanup bool       // the body registers lexical cleanups
	loops   []*loopState
	// switches counts the Go switches enclosing the statement being lowered.
	switches int
	// mutables names the reassignable variables of the function.
	mutables map[string]bool
}

type loopState struct {
	label    string
	switches int // value of funcState.switches where the loop starts
	used     bool
}

func (g *gen) fail(format string, args ...any) {
	if g.err == nil {
		g.err = fmt.Errorf(format, args...)
	}
}

func (g *gen) temp() string { g.serial++; return "t" + strconv.Itoa(g.serial) }

// sub applies the type variables of the instance being lowered.
func (g *gen) sub(t *checker.Type) *checker.Type {
	if len(g.subst) == 0 || t == nil {
		return t
	}
	return checker.Sub(t, g.subst)
}

// info returns the checked facts of e with the instance's type variables
// substituted in every type they carry.
func (g *gen) info(e *syntax.Expression) *checker.Info {
	info := g.program.Info(e)
	if len(g.subst) == 0 || info == nil {
		return info
	}
	if cached := g.infoCache[e]; cached != nil {
		return cached
	}
	c := *info
	c.Type = g.sub(info.Type)
	c.ErrorSource = g.sub(info.ErrorSource)
	c.PropagatedError = g.sub(info.PropagatedError)
	c.OptionalArgument = g.sub(info.OptionalArgument)
	c.Constructor = g.sub(info.Constructor)
	c.TypeArgs = nil
	for _, arg := range info.TypeArgs {
		c.TypeArgs = append(c.TypeArgs, g.sub(arg))
	}
	if g.infoCache == nil {
		g.infoCache = map[*syntax.Expression]*checker.Info{}
	}
	g.infoCache[e] = &c
	return &c
}

func (g *gen) bindingType(b *checker.Binding) *checker.Type { return g.sub(b.Type) }

// file assembles the Go tree for a whole program.
func (g *gen) file(entry string, options Options) *ast.File {
	imports := []*ast.ImportSpec{
		{Name: ident("rt"), Path: &ast.BasicLit{Kind: token.STRING, Value: `"github.com/manuscript-lang/manuscript/pkg/rt"`}},
		{Path: &ast.BasicLit{Kind: token.STRING, Value: `"os"`}},
	}
	file := &ast.File{Name: ident("main"), Imports: imports, Decls: []ast.Decl{
		&ast.GenDecl{Tok: token.IMPORT, Specs: []ast.Spec{imports[0], imports[1]}},
	}}
	var tests []ast.Expr
	var main *funcDecl
	for _, module := range g.program.Modules {
		g.module = module.File
		for _, d := range module.Declarations {
			switch d.Kind {
			case syntax.KindFn:
				s := g.program.Symbol(module.File, d.Name)
				if s == nil || len(s.Variables) != 0 {
					continue
				}
				f := g.function(s, nil)
				if module.File == entry && d.Name == "main" {
					main = f
				}
			case syntax.KindTest:
				if options.Tests {
					tests = append(tests, g.test(module.File, d))
				}
			}
		}
	}
	g.drain()
	var body []ast.Stmt
	switch {
	case options.Tests:
		body = append(body, define("tests", sliceLiteral(rtName("Test"), tests...)),
			&ast.IfStmt{Cond: binary(rtCall("RunTests", ident("tests"), &ast.SliceExpr{X: selector(ident("os"), "Args"), Low: intLiteral(1)}), token.GTR, intLiteral(0)),
				Body: block(evaluated(call(selector(ident("os"), "Exit"), intLiteral(1))))})
	case options.Entry && main != nil:
		body = append(body, evaluated(call(selector(ident("os"), "Exit"), rtCall("RunMain", ident(main.name), &ast.SliceExpr{X: selector(ident("os"), "Args"), Low: intLiteral(1)}))))
	default:
		body = append(body, discard(selector(ident("os"), "Args")))
	}
	g.decls = append(g.decls, &ast.FuncDecl{Name: ident("main"), Type: functionType(nil, nil), Body: block(body...)})
	file.Decls = append(file.Decls, g.typeDecls()...)
	file.Decls = append(file.Decls, g.decls...)
	return file
}

// test registers a test block as a function and returns its table entry.
func (g *gen) test(module string, d *syntax.Declaration) ast.Expr {
	f := &funcDecl{key: "test:" + module + "::" + d.Name, name: g.unique("test_" + sanitize(d.Name)), module: module, decl: d,
		typ: &checker.Type{Kind: "function", ID: "fn", Name: "fn", Result: unitType}}
	g.queue = append(g.queue, f)
	return composite(nil, keyed("Name", textLiteral(module+"::"+d.Name)), keyed("Run", ident(f.name)))
}

// drain lowers every queued function instance; lowering one can queue more.
func (g *gen) drain() {
	for len(g.queue) > 0 {
		f := g.queue[0]
		g.queue = g.queue[1:]
		g.lowerFunction(f)
	}
}

func sortedKeys[T any](m map[string]T) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return keys
}
