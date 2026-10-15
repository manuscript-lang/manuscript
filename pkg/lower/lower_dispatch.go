package lower

import (
	"go/ast"
	"go/token"
	"strconv"

	"github.com/manuscript-lang/manuscript/pkg/checker"
)

// A call through a user interface type resolves its implementation by the
// receiver's runtime type. When every implementation of the method that the
// program declares is a direct method on a generated struct, the call goes
// through a small generated function that type-switches on those structs and
// calls the direct method, instead of the runtime's cache lookup. Receivers
// of any other type, including ones registered at run time, keep the ordinary
// rt.CallInterface route.
type dispatcher struct {
	name     string
	contract *checker.Type
	method   string
	params   int
	impls    []dispatchTarget
}

type dispatchTarget struct {
	st     *structType
	method *checker.Method
	direct *directFunction
}

// interfaceDispatcher returns the dispatcher for a method of a user interface,
// or nil when a module-scoped implementation could be selected instead.
func (g *generator) interfaceDispatcher(contract *checker.Type, method string, params int) *dispatcher {
	if contract == nil || len(contract.Args) != 0 || len(g.directMethods) == 0 {
		return nil
	}
	key := checker.TypeKey(contract) + "\x00" + method
	if d, ok := g.dispatchers[key]; ok {
		return d
	}
	d := g.planDispatcher(contract, method, params)
	if g.dispatchers == nil {
		g.dispatchers = map[string]*dispatcher{}
	}
	g.dispatchers[key] = d
	if d != nil {
		d.name = "dispatch" + strconv.Itoa(len(g.dispatchOrder)+1)
		g.dispatchOrder = append(g.dispatchOrder, d)
	}
	return d
}

func (g *generator) planDispatcher(contract *checker.Type, method string, params int) *dispatcher {
	d := &dispatcher{contract: contract, method: method, params: params}
	want := checker.TypeKey(contract)
	for _, m := range g.program.Methods {
		if m.Contract == nil || m.Decl == nil || m.Decl.Name != method || checker.TypeKey(m.Contract) != want {
			continue
		}
		if m.Local {
			// A module-scoped implementation may be the one selected for a
			// receiver of the same type, so the runtime must choose.
			return nil
		}
		direct := g.directMethods[m.ID]
		if direct == nil || len(m.Variables) != 0 || m.Native != "" || len(direct.params) != params {
			continue
		}
		st := g.structFor(m.Receiver)
		if st == nil {
			continue
		}
		d.impls = append(d.impls, dispatchTarget{st: st, method: m, direct: direct})
	}
	if len(d.impls) == 0 {
		return nil
	}
	return d
}

// dispatcherDeclarations emits every requested dispatcher.
func (g *generator) dispatcherDeclarations() []ast.Decl {
	var decls []ast.Decl
	for _, d := range g.dispatchOrder {
		params := []*ast.Field{
			field("ctx", &ast.StarExpr{X: runtimeName("Execution")}),
			field("site", &ast.StarExpr{X: runtimeName("MethodSite")}),
			field("receiver", runtimeName("Value")),
			field("scope", runtimeName("TypeScope")),
		}
		var boxed []ast.Expr
		for i := 0; i < d.params; i++ {
			name := "a" + strconv.Itoa(i)
			params = append(params, field(name, runtimeName("Value")))
			boxed = append(boxed, ident(name))
		}
		var clauses []ast.Stmt
		for _, impl := range d.impls {
			forwarded := []ast.Expr{ident("ctx"), ident("r")}
			for i := 0; i < d.params; i++ {
				var arg ast.Expr = ident("a" + strconv.Itoa(i))
				if typ := impl.direct.params[i]; typ != "" {
					arg = unbox(arg, typ)
				}
				forwarded = append(forwarded, arg)
			}
			var forward ast.Expr = call(ident(impl.direct.name), forwarded...)
			if impl.direct.shape != nil {
				forward = call(selector(forward, "Box"), g.key(impl.method.Type.Result))
			}
			clauses = append(clauses, &ast.CaseClause{
				List: []ast.Expr{&ast.StarExpr{X: ident(impl.st.name)}},
				Body: []ast.Stmt{
					evaluated(runtimeCall("Enter", ident("ctx"))),
					define("value", forward),
					evaluated(runtimeCall("Exit", ident("ctx"))),
					returned(ident("value")),
				},
			})
		}
		target := &ast.TypeSwitchStmt{
			Assign: define("r", &ast.TypeAssertExpr{X: ident("target")}),
			Body:   block(clauses...),
		}
		body := block(
			define("target", ident("receiver")),
			&ast.IfStmt{
				Init: &ast.AssignStmt{Lhs: []ast.Expr{ident("view"), ident("ok")}, Tok: token.DEFINE, Rhs: []ast.Expr{&ast.TypeAssertExpr{X: ident("receiver"), Type: runtimeName("View")}}},
				Cond: ident("ok"),
				Body: block(assign(ident("target"), token.ASSIGN, selector(ident("view"), "Receiver"))),
			},
			target,
			returned(runtimeCall("CallInterface", ident("ctx"), ident("site"), ident("receiver"), g.key(d.contract), textLiteral(d.method), ident("scope"), sliceLiteral(runtimeName("Value"), boxed...))),
		)
		decls = append(decls, &ast.FuncDecl{Name: ident(d.name), Type: functionType(params, runtimeName("Value")), Body: body})
	}
	return decls
}
