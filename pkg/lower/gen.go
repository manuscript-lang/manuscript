// Package lower lowers a checked program to idiomatic, fully typed Go. Every
// Manuscript type maps to one Go type, generics are instantiated per concrete
// type, and no value is ever boxed in an interface unless the language itself
// asks for an interface value.
package lower

import (
	"fmt"
	"go/ast"
	"go/token"
	"hash/fnv"
	"runtime"
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
	// Locals, when set, is told which Go local each source binding became in
	// which function, so a debugger can map Go variables back to source.
	Locals func(function, goName string, binding *checker.Binding)
	// PreserveBindings keeps source locals and statement boundaries for Debug.
	PreserveBindings bool
	// DebugLiterals trades repeated literal construction cost for faster
	// native compilation, as Debug builds do.
	DebugLiterals bool
}

// Go lowers a checked program to Go source.
func Go(program *checker.Program, entry string, options Options) (string, error) {
	g := newGen(program)
	g.options = options
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
			if m.Local && m.Contract != nil {
				sh.localImpl = true
			}
		}
	}
	sh.dup = duplicateNames(program)
	sh.declared = declaredNames(program)
	sh.recursive = recursiveDeclarations(program)
	g := &gen{shared: sh, stack: []*node{{}}}
	// Without local implementations concrete Int evidence cannot vary by
	// callable/module. Resolve once instead of scanning methods per constructor.
	if program != nil && !sh.localImpl {
		sh.closedIntMap = g.explicit(intType, "hash", "@std/Hashable") == nil &&
			g.explicit(intType, "equals", "@std/Equal") == nil
	}
	sh.resultBounds = g.resultIntSummaries()
	sh.capturedBindings = g.captureInventory()
	return g
}

// duplicateNames finds the source names several declarations share, which
// their generated names must tell apart by identity.
func duplicateNames(program *checker.Program) map[string]bool {
	count := map[string]int{}
	if program != nil {
		for _, module := range program.Modules {
			for _, d := range module.Declarations {
				switch d.Kind {
				case syntax.KindFn, syntax.KindType, syntax.KindRecord, "alternative", syntax.KindTest, syntax.KindInterface:
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

// declaredNames finds every Go name a source declaration takes, which a
// derived name (an instantiation or a case struct) must not equal.
func declaredNames(program *checker.Program) map[string]bool {
	declared := map[string]bool{}
	if program == nil {
		return declared
	}
	for _, module := range program.Modules {
		for _, d := range module.Declarations {
			switch d.Kind {
			case syntax.KindFn, syntax.KindType, syntax.KindRecord, "alternative", syntax.KindInterface:
				declared[sanitize(d.Name)] = true
			case syntax.KindTest:
				declared["test_"+sanitize(d.Name)] = true
			}
		}
	}
	for _, m := range program.Methods {
		if m.Decl != nil && m.Receiver != nil {
			declared[sanitize(m.Receiver.Name)+"_"+sanitize(m.Decl.Name)] = true
		}
	}
	return declared
}

// derived claims a name built from other names, such as Box_Int for Box[Int]
// or Shape_Circle for a case. A source declaration may already spell that name,
// so the identity is appended then; no name depends on scheduling.
func (g *gen) derived(name, key string) string {
	if g.declared[name] {
		name += "_" + shortHash(key)
	}
	return g.claim(name, key)
}

func (g *gen) derivedOrClaim(name, key string, isDerived bool) string {
	if isDerived {
		return g.derived(name, key)
	}
	return g.claim(name, key)
}

// shared is the registry every unit of work interns into: the program's
// instances, types, and helpers, each created once under mu. A unit never
// reads another unit's results while it runs.
type shared struct {
	options          Options
	program          *checker.Program
	err              error
	inRuntime        bool // generating the runtime package itself: type variables stay variables
	localImpl        bool // some module declares an extension implementation
	localEq          bool // some module declares an extension Equal implementation
	resultBounds     map[*syntax.Declaration]resultIntSummary
	capturedBindings map[*checker.Binding]bool
	closedIntMap     bool                         // program-wide evidence permits closed Int storage
	dup              map[string]bool              // source names more than one declaration uses
	declared         map[string]bool              // Go names the source declarations themselves take
	recursive        map[*syntax.Declaration]bool // functions on a call cycle
	methodByID       map[string]*checker.Method

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
	// scope lists (comma-separated) the modules whose implementations a generic instance also
	// sees: the module that instantiated it. Empty for non-generic code.
	scope string

	// subst maps the type variables of the instance being lowered to their
	// concrete types; infoCache memoizes the substituted facts.
	subst     map[string]*checker.Type
	infoCache map[*syntax.Expression]*checker.Info
	serial    int

	locals     map[*checker.Binding]string // Go names of this unit's variables
	localNames map[string]bool
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
	lambda  bool       // a lambda nested in decl, not decl itself
	loops   []*loopState
	// switches counts the Go switches enclosing the statement being lowered.
	switches int
	// mutables names the reassignable variables of the function.
	mutables map[string]bool
	// withs names the actions of the open `with` scopes.
	withs []string
	// stepped marks `i + 1` and `i - 1` expressions that a loop guard proves
	// cannot overflow.
	stepped map[*syntax.Expression]bool
	// safeInt contains function-local proofs of nonoverflowing Int +/-/* nodes.
	safeInt          map[*syntax.Expression]bool
	listLengths      map[*syntax.Expression]int64
	counterChunks    map[*syntax.Statement]*counterChunk
	recordUpdates    map[*syntax.Expression]*localRecordCall
	localCollections *localCollectionProof
	// literalStarts is conservative, body-local eligibility for counter polling.
	literalStarts map[*checker.Binding]bool
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

// file assembles the Go tree for a whole program.
func (g *gen) file(entry string, options Options) *ast.File {
	imports := []*ast.ImportSpec{
		{Name: ident("rt"), Path: &ast.BasicLit{Kind: token.STRING, Value: `"github.com/manuscript-lang/manuscript/pkg/runtime"`}},
		{Path: &ast.BasicLit{Kind: token.STRING, Value: `"os"`}},
	}
	file := &ast.File{Name: ident("main"), Imports: imports, Decls: []ast.Decl{
		&ast.GenDecl{Tok: token.IMPORT, Specs: []ast.Spec{imports[0], imports[1]}},
	}}
	var tests []ast.Expr
	var main *funcDecl
	fixtures, setup := g.fixtures(options)
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
					tests = append(tests, g.test(module.File, d, fixtures[module.File]))
				}
			}
		}
	}
	types, out := g.assemble()
	var body []ast.Stmt
	switch {
	case options.Tests:
		run := ast.Expr(rtCall("RunTests", ident("tests"), &ast.SliceExpr{X: selector(ident("os"), "Args"), Low: intLiteral(1)}))
		if options.CPUProfile != "" || options.HeapProfile != "" || options.Trace != "" {
			run = rtCall("Profile", textLiteral(options.CPUProfile), textLiteral(options.HeapProfile), textLiteral(options.Trace), closure(nil, ident("int"), returned(run)))
		}
		body = append(body, setup...)
		body = append(body, define("tests", sliceLiteral(rtName("Test"), tests...)),
			&ast.IfStmt{Cond: binary(run, token.GTR, intLiteral(0)),
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

// fixture is the Go state of one file's make_fixture: the variable that
// holds the instance and the runtime fixture that creates it.
type fixture struct{ holder, runtime string }

// fixtures declares the test fixtures of the modules that define make_fixture,
// in module order. The runner creates each instance on first use; the file's
// tests read it from the holder.
func (g *gen) fixtures(options Options) (map[string]*fixture, []ast.Stmt) {
	found := map[string]*fixture{}
	var setup []ast.Stmt
	if !options.Tests {
		return found, nil
	}
	for _, module := range g.program.Modules {
		checked := g.program.TestFixtures[module.File]
		if checked == nil {
			continue
		}
		g.module = module.File
		n := itoa(len(found))
		f := &fixture{holder: "fixtureValue" + n, runtime: "fixture" + n}
		found[module.File] = f
		factory := g.function(checked.Factory, nil)
		create := closure([]*ast.Field{field("ctx", pointerTo(rtName("Execution")))}, rtName("TestHooks"),
			assign(ident(f.holder), token.ASSIGN, call(ident(factory.name), ident("ctx"))),
			returned(g.viewOf(ident(f.holder), checked.Type, checked.Hooks)))
		setup = append(setup, varDecl(f.holder, g.goType(checked.Type), nil),
			define(f.runtime, address(composite(rtName("TestFixture"), keyed("File", textLiteral(module.File)), keyed("Create", create)))))
	}
	return found, setup
}

// test registers a test block as a function and returns its table entry. A
// test in a file with a fixture receives the shared instance as `fixture`.
func (g *gen) test(module string, d *syntax.Declaration, fixture *fixture) ast.Expr {
	key := "test:" + module + "::" + d.Name
	name := "test_" + sanitize(d.Name)
	if g.dup[name] {
		name += "_" + shortHash(key)
	}
	f := &funcDecl{key: key, name: g.claim(name, key), module: module, decl: d,
		typ: &checker.Type{Kind: "function", ID: "fn", Name: "fn", Result: checker.TestOutcome()}}
	f.fn = f
	g.touch(&f.node)
	var run ast.Expr = ident(f.name)
	entry := []ast.Expr{keyed("Name", textLiteral(module+"::"+d.Name))}
	if fixture != nil {
		run = closure([]*ast.Field{field("ctx", pointerTo(rtName("Execution")))}, g.goType(checker.TestOutcome()),
			returned(call(ident(f.name), ident("ctx"), ident(fixture.holder))))
		entry = append(entry, keyed("Run", run), keyed("Fixture", ident(fixture.runtime)))
		return composite(nil, entry...)
	}
	return composite(nil, append(entry, keyed("Run", run))...)
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
	workers := min(runtime.GOMAXPROCS(0), len(wave))
	if g.inRuntime || workers < 2 {
		for _, f := range wave {
			g.fork().lowerFunction(f)
		}
		return
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
	if reserved[name] || goKeywords[name] || predeclared[name] {
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
