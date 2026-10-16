package lower

import (
	"go/ast"
	"go/token"

	"github.com/manuscript-lang/manuscript/pkg/checker"
)

// jsonScope is the first parameter of every generated JSON encoder.
func jsonScopeType() ast.Expr { return pointerTo(rtName("JsonScope")) }

// jsonEncType is func(*rt.JsonScope, T) (rt.JsonValue, bool).
func (g *gen) jsonEncType(t *checker.Type) *ast.FuncType {
	ft := functionType([]*ast.Field{field("s", jsonScopeType()), field("v", g.goType(t))}, nil)
	ft.Results = &ast.FieldList{List: []*ast.Field{{Type: rtName("JsonValue")}, {Type: ident("bool")}}}
	return ft
}

// jsonEncFunc is the expression of a function of (*rt.JsonScope, T)
// (rt.JsonValue, bool) that encodes a value of type t as JSON.
func (g *gen) jsonEncFunc(t *checker.Type) ast.Expr {
	t = g.sub(t)
	switch t.ID {
	case "Int":
		return rtName("JsonEncInt")
	case "Float":
		return rtName("JsonEncFloat")
	case "Bool":
		return rtName("JsonEncBool")
	case "String":
		return rtName("JsonEncString")
	case "@std/JsonValue":
		return rtName("JsonEncValue")
	}
	switch {
	case t.Kind == "function", t.Kind == "primitive", t.Kind == "contract":
		return generic(rtName("JsonEncNone"), g.goType(t))
	case isStd(t, "List"), isStd(t, "Set"), isStd(t, "Map"), isStd(t, "Optional"), isStd(t, "Result"):
	case isStdType(t) && t.Kind == "native", t.ID == "@std/Url":
		return generic(rtName("JsonEncNative"), g.goType(t))
	}
	key := "json_enc:" + checker.TypeKey(t)
	return g.helperFunc(key, "json_enc_"+g.nameOf(t), func(name string) ast.Decl {
		body := g.jsonEncBody(t)
		if hook := g.explicit(t, "to_json", "@std/JsonEncode"); hook != nil {
			// A JsonEncode implementation replaces the structural encoding.
			fn := g.methodFunction(hook, t)
			body = []ast.Stmt{returned(call(ident(fn.name), call(selector(ident("s"), "Ctx")), ident("v")), ident("true"))}
		}
		return &ast.FuncDecl{Name: ident(name), Type: g.jsonEncType(t), Body: block(body...)}
	})
}

// jsonEncBody mirrors formatBody: one arm per kind of type.
func (g *gen) jsonEncBody(t *checker.Type) []ast.Stmt {
	s, v := ident("s"), ident("v")
	newMap := func(name string) ast.Stmt {
		return define(name, call(generic(rtName("NewMap"), ident("string"), rtName("JsonValue"))))
	}
	field := func(m string, name string, ft *checker.Type, value ast.Expr) ast.Stmt {
		if isStd(ft, "Optional") {
			return evaluated(call(generic(rtName("JsonOptField"), g.goType(ft.Args[0])), s, ident(m), textLiteral(name), value, g.jsonEncFunc(ft.Args[0])))
		}
		return evaluated(call(generic(rtName("JsonField"), g.goType(ft)), s, ident(m), textLiteral(name), value, g.jsonEncFunc(ft)))
	}
	switch {
	case isStd(t, "Optional"):
		return []ast.Stmt{returned(call(generic(rtName("JsonEncOption"), g.goType(t.Args[0])), s, v, g.jsonEncFunc(t.Args[0])))}
	case isStd(t, "Result"):
		failed := []ast.Stmt{newMap("p"), field("p", "cause", t.Args[1], selector(v, "Err")), returned(rtCall("JsonTagged", s, textLiteral("error"), ident("p")))}
		return []ast.Stmt{
			&ast.IfStmt{Cond: selector(v, "Failed"), Body: block(failed...)},
			newMap("p"), field("p", "value", t.Args[0], selector(v, "Val")),
			returned(rtCall("JsonTagged", s, textLiteral("ok"), ident("p")))}
	case isStd(t, "List"):
		return []ast.Stmt{returned(call(generic(rtName("JsonEncList"), g.goType(t.Args[0])), s, v, g.jsonEncFunc(t.Args[0])))}
	case isStd(t, "Set"):
		return []ast.Stmt{returned(call(generic(rtName("JsonEncSet"), g.goType(t.Args[0])), s, v, g.jsonEncFunc(t.Args[0])))}
	case isStd(t, "Map"):
		return []ast.Stmt{returned(call(generic(rtName("JsonEncMap"), g.goType(t.Args[0]), g.goType(t.Args[1])), s, v, g.jsonKeyEnc(t.Args[0]), g.jsonEncFunc(t.Args[1])))}
	case t.Kind == "record":
		var body []ast.Stmt
		body = append(body, g.cycleGuard(t)...)
		body = append(body, newMap("m"))
		for _, f := range checker.Fields(t) {
			body = append(body, field("m", f.Name, f.Type, selector(v, fieldName(f.Name))))
		}
		return append(body, returned(rtCall("JsonObject", s, ident("m"))))
	case t.Kind == "alternative":
		var clauses []ast.Stmt
		for _, c := range checker.Cases(t) {
			var body []ast.Stmt
			if len(c.Fields) == 0 {
				body = []ast.Stmt{returned(rtCall("JsonCase", textLiteral(c.Name)))}
			} else {
				body = append(body, newMap("p"))
				for _, f := range c.Fields {
					body = append(body, field("p", f.Name, f.Type, selector(ident("x"), fieldName(f.Name))))
				}
				body = append(body, returned(rtCall("JsonTagged", s, textLiteral(c.Name), ident("p"))))
			}
			clauses = append(clauses, &ast.CaseClause{List: []ast.Expr{g.caseType(t, c.Name)}, Body: body})
		}
		sw := &ast.TypeSwitchStmt{Assign: &ast.AssignStmt{Lhs: []ast.Expr{ident("x")}, Tok: token.DEFINE, Rhs: []ast.Expr{&ast.TypeAssertExpr{X: v}}}, Body: block(clauses...)}
		trimSwitch(sw, "x")
		return append(g.cycleGuard(t), sw, returned(ident("nil"), ident("false")))
	}
	g.fail("no JSON form for %s", t)
	return []ast.Stmt{returned(ident("nil"), ident("false"))}
}

// cycleGuard stops a type that can reach itself from recursing forever.
func (g *gen) cycleGuard(t *checker.Type) []ast.Stmt {
	if !g.reference(t) || !g.mayCycle(t, map[string]bool{}, t) {
		return nil
	}
	return []ast.Stmt{
		&ast.IfStmt{Cond: not(call(selector(ident("s"), "Enter"), ident("v"))), Body: block(returned(ident("nil"), ident("false")))},
		&ast.DeferStmt{Call: call(selector(ident("s"), "Leave"), ident("v"))},
	}
}

// jsonCodecArgs supplies the generated encoder that json.stringify takes
// after the execution.
func (g *gen) jsonCodecArgs(native string, typeArgs []*checker.Type) []ast.Expr {
	switch {
	case native == "Json_Stringify" && len(typeArgs) == 1:
		return []ast.Expr{g.jsonEncFunc(typeArgs[0])}
	case native == "Json_Parse" && len(typeArgs) == 1:
		return []ast.Expr{g.jsonDecFunc(typeArgs[0])}
	}
	return nil
}

// jsonCodecFields are the leading parameters of the JSON natives that carry a
// generated codec, for the runtime signature check.
func (g *gen) jsonCodecFields(native string, vars []*checker.Type) []*ast.Field {
	if len(vars) != 1 {
		return nil
	}
	switch native {
	case "Json_Stringify":
		ft := functionType([]*ast.Field{{Type: jsonScopeType()}, {Type: ident(vars[0].Name)}}, nil)
		ft.Results = &ast.FieldList{List: []*ast.Field{{Type: ident("JsonValue")}, {Type: ident("bool")}}}
		return []*ast.Field{field("enc", ft)}
	case "Json_Parse":
		ft := functionType([]*ast.Field{{Type: pointerTo(ident("JsonReader"))}, {Type: ident("JsonValue")}}, nil)
		ft.Results = &ast.FieldList{List: []*ast.Field{{Type: ident(vars[0].Name)}, {Type: ident("bool")}}}
		return []*ast.Field{field("dec", ft)}
	}
	return nil
}

// jsonDecType is func(*rt.JsonReader, rt.JsonValue) (T, bool).
func (g *gen) jsonDecType(t *checker.Type) *ast.FuncType {
	ft := functionType([]*ast.Field{field("r", pointerTo(rtName("JsonReader"))), field("j", rtName("JsonValue"))}, nil)
	ft.Results = &ast.FieldList{List: []*ast.Field{{Type: g.goType(t)}, {Type: ident("bool")}}}
	return ft
}

// jsonDecFunc is the expression of a function of (*rt.JsonReader,
// rt.JsonValue) (T, bool) that reads a JSON value as type t.
func (g *gen) jsonDecFunc(t *checker.Type) ast.Expr {
	t = g.sub(t)
	switch t.ID {
	case "Int":
		return rtName("JsonDecInt")
	case "Float":
		return rtName("JsonDecFloat")
	case "Bool":
		return rtName("JsonDecBool")
	case "String":
		return rtName("JsonDecString")
	case "@std/JsonValue":
		return rtName("JsonDecValue")
	}
	switch {
	case t.Kind == "function", t.Kind == "primitive", t.Kind == "contract":
		return generic(rtName("JsonDecNone"), g.goType(t))
	case isStd(t, "List"), isStd(t, "Set"), isStd(t, "Map"), isStd(t, "Optional"), isStd(t, "Result"):
	case isStdType(t) && t.Kind == "native", t.ID == "@std/Url":
		return generic(rtName("JsonDecNative"), g.goType(t))
	}
	key := "json_dec:" + checker.TypeKey(t)
	return g.helperFunc(key, "json_dec_"+g.nameOf(t), func(name string) ast.Decl {
		return &ast.FuncDecl{Name: ident(name), Type: g.jsonDecType(t), Body: block(g.jsonDecBody(t)...)}
	})
}

func (g *gen) jsonDecBody(t *checker.Type) []ast.Stmt {
	r, j := ident("r"), ident("j")
	switch {
	case isStd(t, "Optional"):
		return []ast.Stmt{returned(call(generic(rtName("JsonDecOption"), g.goType(t.Args[0])), r, j, g.jsonDecFunc(t.Args[0])))}
	case isStd(t, "List"):
		return []ast.Stmt{returned(call(generic(rtName("JsonDecList"), g.goType(t.Args[0])), r, j, g.jsonDecFunc(t.Args[0])))}
	case isStd(t, "Set"):
		return []ast.Stmt{returned(call(generic(rtName("JsonDecSet"), g.goType(t.Args[0])), r, j, g.keysFor(t.Args[0]), g.jsonDecFunc(t.Args[0])))}
	case isStd(t, "Map"):
		return []ast.Stmt{returned(call(generic(rtName("JsonDecMap"), g.goType(t.Args[0]), g.goType(t.Args[1])), r, j, g.keysFor(t.Args[0]), g.jsonKeyDec(t.Args[0]), g.jsonDecFunc(t.Args[1])))}
	case isStd(t, "Result"):
		return g.jsonDecResult(t)
	case t.Kind == "record":
		return g.jsonDecRecord(t)
	case t.Kind == "alternative":
		return g.jsonDecAlternative(t)
	}
	g.fail("no JSON reader for %s", t)
	return []ast.Stmt{returned(ident("nil"), ident("false"))}
}

// jsonFail returns the zero value and false.
func jsonFail() ast.Stmt { return returned(ident("zero"), ident("false")) }

func (g *gen) zeroDecl(t *checker.Type) ast.Stmt { return varDecl("zero", g.goType(t), nil) }

// jsonDecFields reads the fields of an object o into variables f0, f1, ...,
// filling absent ones with fill(i) and counting the members used in
// "matched". An Optional field without a default is none.
func (g *gen) jsonDecFields(fields []checker.Param, fill func(i int, f checker.Param) []ast.Stmt) []ast.Stmt {
	out := []ast.Stmt{define("matched", intLiteral(0))}
	for i, f := range fields {
		v, found, ok := "f"+itoa(i), "found"+itoa(i), "ok"+itoa(i)
		out = append(out,
			&ast.AssignStmt{Lhs: []ast.Expr{ident(v), ident(found), ident(ok)}, Tok: token.DEFINE,
				Rhs: []ast.Expr{call(generic(rtName("JsonDecField"), g.goType(f.Type)), ident("r"), ident("o"), textLiteral(f.Name), g.jsonDecFunc(f.Type))}},
			&ast.IfStmt{Cond: not(ident(ok)), Body: block(jsonFail())},
			&ast.IfStmt{Cond: ident(found),
				Body: block(&ast.IncDecStmt{X: ident("matched"), Tok: token.INC}),
				Else: block(fill(i, f)...)},
		)
	}
	out = append(out, &ast.IfStmt{Cond: binary(call(selector(ident("o"), "Len")), token.NEQ, ident("matched")), Body: block(jsonFail())})
	return out
}

func (g *gen) fieldVars(n int) []ast.Expr {
	var out []ast.Expr
	for i := 0; i < n; i++ {
		out = append(out, ident("f"+itoa(i)))
	}
	return out
}

func (g *gen) jsonDecRecord(t *checker.Type) []ast.Stmt {
	fields := checker.Fields(t)
	c := g.recordCallee(t)
	objectOf := []ast.Stmt{
		&ast.AssignStmt{Lhs: []ast.Expr{ident("o"), ident("ok")}, Tok: token.DEFINE, Rhs: []ast.Expr{rtCall("JsonObjectOf", ident("j"))}},
		&ast.IfStmt{Cond: not(ident("ok")), Body: block(jsonFail())},
	}
	saved := g.fn
	savedModule, savedSubst, savedCaptured := g.module, g.subst, g.captured
	g.fn = &funcState{}
	defer func() { g.fn, g.module, g.subst, g.captured = saved, savedModule, savedSubst, savedCaptured }()
	slots := make([]ast.Expr, len(fields))
	for i := range slots {
		slots[i] = ident("f" + itoa(i))
	}
	body := append([]ast.Stmt{g.zeroDecl(t), define("ctx", call(selector(ident("r"), "Ctx")))}, objectOf...)
	body = append(body, discard(ident("ctx")))
	body = append(body, g.jsonDecFields(fields, func(i int, f checker.Param) []ast.Stmt {
		hasDefault := c.defaults[f.Name]
		if !hasDefault && !isStd(f.Type, "Optional") {
			return []ast.Stmt{jsonFail()}
		}
		if !hasDefault {
			return []ast.Stmt{assign(ident("f"+itoa(i)), token.ASSIGN, composite(g.goType(f.Type)))}
		}
		g.fn.pre = nil
		value := g.defaultArgument(i, f, c, append([]ast.Expr(nil), slots...))
		stmts := append(g.fn.pre, assign(ident("f"+itoa(i)), token.ASSIGN, value))
		g.fn.pre = nil
		return stmts
	})...)
	body = append(body, returned(g.construct(t, slots), ident("true")))
	return body
}

func (g *gen) jsonDecAlternative(t *checker.Type) []ast.Stmt {
	body := []ast.Stmt{g.zeroDecl(t),
		&ast.AssignStmt{Lhs: []ast.Expr{ident("name"), ident("payload"), ident("ok")}, Tok: token.DEFINE, Rhs: []ast.Expr{rtCall("JsonTag", ident("j"))}},
		&ast.IfStmt{Cond: not(ident("ok")), Body: block(jsonFail())},
	}
	var clauses []ast.Stmt
	for _, c := range checker.Cases(t) {
		var arm []ast.Stmt
		if len(c.Fields) == 0 {
			arm = []ast.Stmt{
				&ast.IfStmt{Cond: binary(ident("payload"), token.NEQ, ident("nil")), Body: block(jsonFail())},
				returned(g.caseValue(t, c.Name, nil), ident("true")),
			}
		} else {
			arm = append(arm,
				&ast.IfStmt{Cond: binary(ident("payload"), token.EQL, ident("nil")), Body: block(jsonFail())},
				define("o", ident("payload")))
			arm = append(arm, g.jsonDecFields(c.Fields, func(_ int, f checker.Param) []ast.Stmt {
				if !isStd(f.Type, "Optional") {
					return []ast.Stmt{jsonFail()}
				}
				return []ast.Stmt{assign(ident("f"+itoa(indexOf(c.Fields, f.Name))), token.ASSIGN, composite(g.goType(f.Type)))}
			})...)
			arm = append(arm, returned(g.caseValue(t, c.Name, g.fieldVars(len(c.Fields))), ident("true")))
		}
		clauses = append(clauses, &ast.CaseClause{List: []ast.Expr{textLiteral(c.Name)}, Body: arm})
	}
	body = append(body, &ast.SwitchStmt{Tag: ident("name"), Body: block(clauses...)}, jsonFail())
	return body
}

func indexOf(fields []checker.Param, name string) int {
	for i, f := range fields {
		if f.Name == name {
			return i
		}
	}
	return 0
}

// jsonDecResult reads {"ok":{"value":v}} and {"error":{"cause":e}}.
func (g *gen) jsonDecResult(t *checker.Type) []ast.Stmt {
	ok, bad := t.Args[0], t.Args[1]
	body := []ast.Stmt{g.zeroDecl(t),
		&ast.AssignStmt{Lhs: []ast.Expr{ident("name"), ident("payload"), ident("ok")}, Tok: token.DEFINE, Rhs: []ast.Expr{rtCall("JsonTag", ident("j"))}},
		&ast.IfStmt{Cond: binary(not(ident("ok")), token.LOR, binary(ident("payload"), token.EQL, ident("nil"))), Body: block(jsonFail())},
		define("o", ident("payload")),
	}
	arm := func(label string, ft *checker.Type, build func(v ast.Expr) ast.Expr) *ast.CaseClause {
		fields := []checker.Param{{Name: label, Type: ft}}
		stmts := g.jsonDecFields(fields, func(int, checker.Param) []ast.Stmt { return []ast.Stmt{jsonFail()} })
		stmts = append(stmts, returned(build(ident("f0")), ident("true")))
		return &ast.CaseClause{List: []ast.Expr{textLiteral(map[string]string{"value": "ok", "cause": "error"}[label])}, Body: stmts}
	}
	body = append(body, &ast.SwitchStmt{Tag: ident("name"), Body: block(
		arm("value", ok, func(v ast.Expr) ast.Expr {
			return call(generic(rtName("Ok"), g.goType(ok), g.goType(bad)), v)
		}),
		arm("cause", bad, func(v ast.Expr) ast.Expr {
			return call(generic(rtName("Fail"), g.goType(ok), g.goType(bad)), v)
		}),
	)}, jsonFail())
	return body
}

// jsonKeyEnc names a Map key as an object member: scalars by their text, a
// case without payload by its name.
func (g *gen) jsonKeyEnc(k *checker.Type) ast.Expr {
	k = g.sub(k)
	if k.Kind != "alternative" || isStdType(k) {
		return generic(rtName("JsonKey"), g.goType(k))
	}
	return g.helperFunc("json_key_enc:"+checker.TypeKey(k), "json_key_enc_"+g.nameOf(k), func(name string) ast.Decl {
		var clauses []ast.Stmt
		for _, c := range checker.Cases(k) {
			if len(c.Fields) == 0 {
				clauses = append(clauses, &ast.CaseClause{List: []ast.Expr{g.caseType(k, c.Name)}, Body: []ast.Stmt{returned(textLiteral(c.Name), ident("true"))}})
			}
		}
		sw := &ast.TypeSwitchStmt{Assign: &ast.ExprStmt{X: &ast.TypeAssertExpr{X: ident("k")}}, Body: block(clauses...)}
		ft := functionType([]*ast.Field{field("k", g.goType(k))}, nil)
		ft.Results = &ast.FieldList{List: []*ast.Field{{Type: ident("string")}, {Type: ident("bool")}}}
		return &ast.FuncDecl{Name: ident(name), Type: ft, Body: block(sw, returned(textLiteral(""), ident("false")))}
	})
}

// jsonKeyDec reads an object member name as a Map key.
func (g *gen) jsonKeyDec(k *checker.Type) ast.Expr {
	k = g.sub(k)
	if k.Kind != "alternative" || isStdType(k) {
		return generic(rtName("JsonParseKey"), g.goType(k))
	}
	return g.helperFunc("json_key_dec:"+checker.TypeKey(k), "json_key_dec_"+g.nameOf(k), func(name string) ast.Decl {
		var clauses []ast.Stmt
		for _, c := range checker.Cases(k) {
			if len(c.Fields) == 0 {
				clauses = append(clauses, &ast.CaseClause{List: []ast.Expr{textLiteral(c.Name)}, Body: []ast.Stmt{returned(g.caseValue(k, c.Name, nil), ident("true"))}})
			}
		}
		ft := functionType([]*ast.Field{field("r", pointerTo(rtName("JsonReader"))), field("text", ident("string"))}, nil)
		ft.Results = &ast.FieldList{List: []*ast.Field{{Type: g.goType(k)}, {Type: ident("bool")}}}
		return &ast.FuncDecl{Name: ident(name), Type: ft, Body: block(g.zeroDecl(k), discard(ident("r")), &ast.SwitchStmt{Tag: ident("text"), Body: block(clauses...)}, jsonFail())}
	})
}
