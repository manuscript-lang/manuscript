// Package golower lowers a checked program to idiomatic, fully typed Go. Every
// Manuscript type maps to one Go type, generics are instantiated per concrete
// type, and no value is ever boxed in an interface unless the language itself
// asks for an interface value.
package golower

import (
	"fmt"
	"go/ast"
	"go/token"
	"hash/fnv"
	"runtime"
	"sort"
	"strconv"
	"sync"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// Options selects the entry point lowered into the generated main function.
type Options struct {
	// Tests lowers test blocks into the generated main; Entry lowers main().
	Tests, Entry                   bool
	CPUProfile, HeapProfile, Trace string
	// DebugLiterals trades repeated literal construction cost for faster
	// native compilation, as Debug builds do.
	DebugLiterals bool
}

// Go lowers a checked program to Go source.
func Go(program *checker.Program, entry string, options Options) (string, error) {
	g := newGen(program)
	file := g.file(entry, options)
	if g.err != nil {
		return "", g.err
	}
	return g.printGo(file)
}

func newGen(program *checker.Program) *gen {
	sh := &shared{program: program, types: map[string]*typeDecl{}, funcs: map[string]*funcDecl{}, helpers: map[string]*helper{},
		names: map[string]string{}, methodByID: map[string]*checker.Method{}, sourceLines: map[string]syntax.Position{}}
	if program != nil {
		for _, m := range program.Methods {
			sh.methodByID[m.ID] = m
			if m.Local && m.Contract != nil && m.Contract.ID == "@std/Equal" {
				sh.localEq = true
			}
		}
	}
	sh.dup = duplicateNames(program)
	sh.recursive = recursiveDeclarations(program)
	return &gen{shared: sh, stack: []*node{{}}}
}

// duplicateNames finds the source names several declarations share, which
// their generated names must tell apart by identity.
func duplicateNames(program *checker.Program) map[string]bool {
	count := map[string]int{}
	if program != nil {
		for _, module := range program.Modules {
			for _, d := range module.Declarations {
				switch d.Kind {
				case syntax.KindFn, syntax.KindType, syntax.KindTest, syntax.KindInterface:
					count[sanitize(d.Name)]++
					if d.Kind == syntax.KindTest {
						count["test_"+sanitize(d.Name)]++
					}
				}
			}
		}
		for _, m := range program.Methods {
			if m.Decl != nil && m.Receiver != nil {
				count[sanitize(m.Receiver.Name)+"_"+sanitize(m.Decl.Name)]++
			}
		}
	}
	dup := map[string]bool{}
	for name, n := range count {
		dup[name] = n > 1
	}
	return dup
}

// shared is the registry every unit of work interns into: the program's
// instances, types, and helpers, each created once under mu. A unit never
// reads another unit's results while it runs.
type shared struct {
	program    *checker.Program
	err        error
	inRuntime  bool                         // generating the runtime package itself: type variables stay variables
	localEq    bool                         // some module declares an extension Equal implementation
	dup        map[string]bool              // source names more than one declaration uses
	recursive  map[*syntax.Declaration]bool // functions on a call cycle
	methodByID map[string]*checker.Method

	mu      sync.Mutex
	types   map[string]*typeDecl
	funcs   map[string]*funcDecl
	helpers map[string]*helper
	names   map[string]string // Go identifiers declared at package level, by owning key
	natives map[string]bool   // runtime functions the program calls
	checks  map[string]int

	// sourceLines maps located-statement labels to positions; merging numbers them.
	sourceLines map[string]syntax.Position
}

// node is an item of generated output and the items it needs. Merging walks
// nodes in the order units first touched them, which makes the output the same
// on every run however the units were scheduled.
type node struct {
	decl []ast.Decl
	deps []*node
	seen map[*node]bool
	done bool
	fn   *funcDecl // set when the node is a function awaiting lowering
	typ  bool      // type declarations print in their own section

	labels []labelRef // located-statement labels, numbered when merged
}

func (n *node) add(d *node) {
	if d == n || n.seen[d] {
		return
	}
	if n.seen == nil {
		n.seen = map[*node]bool{}
	}
	n.seen[d] = true
	n.deps = append(n.deps, d)
}

// helper is a generated per-type function such as equal_T or format_T.
type helper struct {
	node
	name string
}

// gen is one unit of work: the state of lowering a single function instance.
type gen struct {
	*shared
	module string

	// subst maps the type variables of the instance being lowered to their
	// concrete types; infoCache memoizes the substituted facts.
	subst     map[string]*checker.Type
	infoCache map[*syntax.Expression]*checker.Info
	serial    int

	locals     map[*checker.Binding]string // Go names of this unit's variables
	localNames map[string]bool
	aliases    map[*checker.Binding]*checker.Symbol
	captured   map[*checker.Binding]string // snapshot names of captured variables
	used       map[*checker.Binding]bool   // variables some expression reads

	// stack holds the nodes being built, innermost last; items the unit
	// touches become dependencies of the innermost.
	stack []*node

	// The function being lowered.
	fn *funcState
}

type labelRef struct {
	id  *ast.Ident
	pos syntax.Position
}

// fork starts a unit of work over the same registry.
func (g *gen) fork() *gen { return &gen{shared: g.shared, stack: []*node{{}}} }

// touch records that the node being built needs n.
func (g *gen) touch(n *node) { g.stack[len(g.stack)-1].add(n) }

// building runs build with n as the node that collects touched items.
func (g *gen) building(n *node, build func()) {
	g.stack = append(g.stack, n)
	build()
	g.stack = g.stack[:len(g.stack)-1]
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
	// withs names the actions of the open `with` scopes.
	withs []string
}

type loopState struct {
	label    string
	switches int // value of funcState.switches where the loop starts
	withs    int // number of open cleanups where the loop starts
	used     bool
}

func (g *gen) fail(format string, args ...any) {
	g.mu.Lock()
	defer g.mu.Unlock()
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
	types, out := g.assemble()
	var body []ast.Stmt
	switch {
	case options.Tests:
		body = append(body, define("tests", sliceLiteral(rtName("Test"), tests...)),
			&ast.IfStmt{Cond: binary(rtCall("RunTests", ident("tests"), &ast.SliceExpr{X: selector(ident("os"), "Args"), Low: intLiteral(1)}), token.GTR, intLiteral(0)),
				Body: block(evaluated(call(selector(ident("os"), "Exit"), intLiteral(1))))})
	case options.Entry && main != nil:
		run := ast.Expr(rtCall("RunMain", ident(main.name), &ast.SliceExpr{X: selector(ident("os"), "Args"), Low: intLiteral(1)}))
		if options.CPUProfile != "" || options.HeapProfile != "" || options.Trace != "" {
			run = rtCall("Profile", textLiteral(options.CPUProfile), textLiteral(options.HeapProfile), textLiteral(options.Trace), closure(nil, ident("int"), returned(run)))
		}
		body = append(body, evaluated(call(selector(ident("os"), "Exit"), run)))
	default:
		body = append(body, discard(selector(ident("os"), "Args")))
	}
	out = append(out, &ast.FuncDecl{Name: ident("main"), Type: functionType(nil, nil), Body: block(body...)})
	file.Decls = append(file.Decls, types...)
	file.Decls = append(file.Decls, out...)
	return file
}

// test registers a test block as a function and returns its table entry.
func (g *gen) test(module string, d *syntax.Declaration) ast.Expr {
	key := "test:" + module + "::" + d.Name
	name := "test_" + sanitize(d.Name)
	if g.dup[name] {
		name += "_" + shortHash(key)
	}
	f := &funcDecl{key: key, name: g.claim(name, key), module: module, decl: d,
		typ: &checker.Type{Kind: "function", ID: "fn", Name: "fn", Result: unitType}}
	f.fn = f
	g.touch(&f.node)
	return composite(nil, keyed("Name", textLiteral(module+"::"+d.Name)), keyed("Run", ident(f.name)))
}

// assemble lowers every function instance reachable from the roots, a wave at
// a time. The functions of a wave are independent units and lower in parallel;
// their results merge in the order they were first requested, so the output
// does not depend on scheduling.
func (g *gen) assemble() (types, out []ast.Decl) {
	var next, order []*funcDecl
	var emit func(n *node)
	emit = func(n *node) {
		if n.done {
			return
		}
		n.done = true
		for _, d := range n.deps {
			emit(d)
		}
		g.numberLabels(n)
		switch {
		case n.fn != nil:
			next = append(next, n.fn)
		case n.typ:
			types = append(types, n.decl...)
		default:
			out = append(out, n.decl...)
		}
	}
	root := g.stack[0]
	g.stack = g.stack[:1]
	emit(root)
	for len(next) > 0 {
		wave := next
		next = nil
		g.lowerWave(wave)
		for _, f := range wave {
			order = append(order, f)
			out = append(out, f.out)
			g.numberLabels(&f.node)
			for _, d := range f.deps {
				emit(d)
			}
		}
	}
	return types, append(out, g.registration(order))
}

// registration names every lowered function for fault traces.
func (g *gen) registration(order []*funcDecl) ast.Decl {
	var body []ast.Stmt
	for _, f := range order {
		if f.out == nil {
			continue
		}
		body = append(body, evaluated(rtCall("RegisterSource", ident(f.name), textLiteral(f.sourceName()))))
	}
	return &ast.FuncDecl{Name: ident("init"), Type: functionType(nil, nil), Body: block(body...)}
}

// numberLabels gives the node's located-statement labels their global names.
func (g *gen) numberLabels(n *node) {
	for _, l := range n.labels {
		name := "manuscriptSourceLine" + strconv.Itoa(len(g.sourceLines))
		l.id.Name = name
		g.sourceLines[name] = l.pos
	}
	n.labels = nil
}

// lowerWave lowers independent function instances concurrently.
func (g *gen) lowerWave(wave []*funcDecl) {
	workers := runtime.GOMAXPROCS(0)
	if g.inRuntime || workers < 2 || len(wave) < 2 {
		workers = 1
	}
	var wg sync.WaitGroup
	jobs := make(chan *funcDecl)
	for i := 0; i < workers; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for f := range jobs {
				g.fork().lowerFunction(f)
			}
		}()
	}
	for _, f := range wave {
		jobs <- f
	}
	close(jobs)
	wg.Wait()
}

// claim reserves a package-level Go identifier for key. Names derive from the
// source, with a hash of the identity wherever source names repeat, so no two
// keys meet in one name and no name depends on scheduling.
func (g *gen) claim(name, key string) string {
	if reserved[name] || goKeywords[name] {
		name += "_"
	}
	g.mu.Lock()
	owner, taken := g.names[name]
	if !taken {
		g.names[name] = key
	}
	g.mu.Unlock()
	if taken && owner != key {
		g.fail("generated name %s is claimed by both %s and %s", name, owner, key)
	}
	return name
}

func shortHash(key string) string {
	h := fnv.New32a()
	h.Write([]byte(key))
	return strconv.FormatUint(uint64(h.Sum32()), 36)
}

func sortedKeys[T any](m map[string]T) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return keys
}
