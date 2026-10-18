package lower

import (
	"go/ast"
	"go/token"

	"github.com/manuscript-lang/manuscript/pkg/checker"
)

// Map keys and Set elements match by Manuscript equality. Types whose Go
// representation already compares as Manuscript does (scalars, strings,
// durations, handles) use Go map lookup directly and need no rt.Keys. Records,
// alternatives, Optional, Result, Bytes, BigInt, and Decimal match structurally
// through a projection to a comparable value; a type with explicit Hashable and
// Equal implementations supplies them instead.

// keysFor is an expression of type *rt.Keys[T], or nil for Go equality.
func (g *gen) keysFor(t *checker.Type) ast.Expr {
	t = g.sub(t)
	if h := g.explicit(t, "hash", "@std/Hashable"); h != nil {
		hash := g.methodFunction(h, t)
		in := []*ast.Field{field("a", g.goType(t))}
		hashFn := closure(in, ident("int"), returned(call(ident(hash.name), ident("ctx"), ident("a"))))
		return rtCall("CustomKeys", hashFn, g.equalClosure(t))
	}
	if g.identityKeys(t) {
		return ident("nil")
	}
	switch t.ID {
	case "@std/Bytes":
		return rtCall("BytesKeys")
	case "@std/BigInt":
		return rtCall("BigIntKeys")
	case "@std/Decimal":
		return rtCall("DecimalKeys")
	}
	return rtCall("StructuralKeys", g.projection(t))
}

// equalClosure adapts the generated equality to the rt.Keys shape by binding
// the constructing execution.
func (g *gen) equalClosure(t *checker.Type) ast.Expr {
	params := []*ast.Field{field("a", g.goType(t)), field("b", g.goType(t))}
	return closure(params, ident("bool"), returned(call(g.equalFunc(t), ident("ctx"), ident("a"), ident("b"))))
}

// explicit finds a visible explicit implementation of an Equal or Hashable
// operation for t.
func (g *gen) explicit(t *checker.Type, name, contract string) *checker.Method {
	for _, m := range g.resolve(t, name) {
		if m.Contract != nil && m.Contract.ID == contract && m.Native == "" {
			return m
		}
	}
	return nil
}

// identityKeys reports whether Go equality on t's representation is its
// Manuscript equality for map lookup.
func (g *gen) identityKeys(t *checker.Type) bool {
	switch {
	case scalarGo(t) != "" || t.ID == "Unit":
		return true
	case t.Kind == "contract" || t.Kind == "function":
		return true
	case isStdType(t) && t.Kind == "native":
		switch t.ID {
		case "@std/Bytes", "@std/BigInt", "@std/Decimal", "@std/IpAddress", "@std/Cidr":
			return false
		}
		return true
	}
	return false
}

// derivedHash is the hash of a value whose type has no explicit Hashable
// implementation: equal values hash alike because both derive from the same
// comparable projection that map keys match by.
func (g *gen) derivedHash(t *checker.Type, v ast.Expr) ast.Expr {
	return rtCall("HashKey", g.projected(t, v))
}

// projection is a function of (T) any returning the comparable form of a key.
func (g *gen) projection(t *checker.Type) ast.Expr {
	t = g.sub(t)
	key := "key:" + checker.TypeKey(t)
	if g.localEq {
		key += "@" + g.module + "@" + g.scope
	}
	return g.helperFunc(key, "key_"+g.nameOf(t), func(name string) ast.Decl {
		params := []*ast.Field{field("v", g.goType(t))}
		return &ast.FuncDecl{Name: ident(name), Type: functionType(params, ident("any")), Body: block(g.projectionBody(t)...)}
	})
}

// projected is the comparable form of a value of type t inside a projection.
func (g *gen) projected(t *checker.Type, v ast.Expr) ast.Expr {
	t = g.sub(t)
	if g.explicit(t, "hash", "@std/Hashable") != nil {
		g.fail("%s has an explicit Hashable implementation and cannot be part of a structural key", t)
	}
	if g.identityKeys(t) {
		return v
	}
	switch t.ID {
	case "@std/Bytes":
		return rtCall("KeyBytes", v)
	case "@std/BigInt":
		return rtCall("KeyBigInt", v)
	case "@std/Decimal":
		return rtCall("KeyDecimal", v)
	case "@std/IpAddress", "@std/Cidr":
		return rtCall("FormatNative", v)
	}
	return call(g.projection(t), v)
}

func array(elements ...ast.Expr) ast.Expr {
	return composite(&ast.ArrayType{Len: intLiteral(len(elements)), Elt: ident("any")}, elements...)
}

func (g *gen) projectionBody(t *checker.Type) []ast.Stmt {
	v := ident("v")
	switch {
	case isStd(t, "Optional"):
		inner := g.projected(t.Args[0], selector(v, "Val"))
		return []ast.Stmt{
			&ast.IfStmt{Cond: not(selector(v, "Some")), Body: block(returned(array(ident("false"), ident("nil"))))},
			returned(array(ident("true"), inner)),
		}
	case isStd(t, "Result"):
		return []ast.Stmt{
			&ast.IfStmt{Cond: selector(v, "Failed"), Body: block(returned(array(ident("true"), g.projected(t.Args[1], selector(v, "Err")))))},
			returned(array(ident("false"), g.projected(t.Args[0], selector(v, "Val")))),
		}
	case t.Kind == "record":
		var parts []ast.Expr
		for _, f := range checker.Fields(t) {
			parts = append(parts, g.projected(f.Type, selector(v, fieldName(f.Name))))
		}
		return []ast.Stmt{returned(array(parts...))}
	case t.Kind == "alternative":
		var clauses []ast.Stmt
		for _, c := range checker.Cases(t) {
			parts := []ast.Expr{textLiteral(c.Name)}
			for _, f := range c.Fields {
				parts = append(parts, g.projected(f.Type, selector(ident("x"), fieldName(f.Name))))
			}
			clauses = append(clauses, &ast.CaseClause{List: []ast.Expr{g.caseType(t, c.Name)}, Body: []ast.Stmt{returned(array(parts...))}})
		}
		sw := &ast.TypeSwitchStmt{Assign: &ast.AssignStmt{Lhs: []ast.Expr{ident("x")}, Tok: token.DEFINE, Rhs: []ast.Expr{&ast.TypeAssertExpr{X: v}}}, Body: block(clauses...)}
		trimSwitch(sw, "x")
		return []ast.Stmt{sw, returned(ident("nil"))}
	}
	g.fail("%s cannot be a map key or set element", t)
	return []ast.Stmt{returned(ident("nil"))}
}
