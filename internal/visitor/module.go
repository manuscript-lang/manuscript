package visitor

import (
	"fmt"
	"go/ast"
	"go/token"
	"manuscript-co/manuscript/internal/parser"
)

func (v *ManuscriptAstVisitor) VisitModuleImportTarget(ctx *parser.ModuleImportTargetContext) interface{} {
	target := ctx.TargetImport()
	if target == nil {
		v.addError("Malformed import: missing target", ctx.GetStart())
		return nil
	}
	var alias string
	if id := target.ID(); id != nil {
		alias = id.GetText()
	}
	var importLt *ast.BasicLit
	if a := v.stringPartsToBasicLit(target.SingleQuotedString().AllStringPart()); a != nil {
		lt, ok := a.(*ast.BasicLit)
		if ok {
			importLt = lt
		} else {
			v.addError("Malformed import: missing import path", ctx.GetStart())
			return nil
		}
	}
	importSpec := &ast.ImportSpec{Path: importLt}
	if alias != "" {
		importSpec.Name = ast.NewIdent(alias)
	}
	v.goImports = append(v.goImports, importSpec)
	return []ast.Decl{}
}

func (v *ManuscriptAstVisitor) VisitModuleImportDestructured(ctx *parser.ModuleImportDestructuredContext) interface{} {
	destr := ctx.DestructuredImport()
	if destr == nil {
		v.addError("Malformed destructured import: missing destructured import", ctx.GetStart())
		return nil
	}
	var importLt *ast.BasicLit
	if a := v.stringPartsToBasicLit(destr.SingleQuotedString().AllStringPart()); a != nil {
		lt, ok := a.(*ast.BasicLit)
		if ok {
			importLt = lt
		} else {
			v.addError("Malformed destructured import: missing import path", ctx.GetStart())
			return nil
		}
	}
	// Find if this importPath already has an alias
	alias := fmt.Sprintf("__import%s", v.nextTempVarCounter())
	v.goImports = append(v.goImports, &ast.ImportSpec{
		Path: importLt,
		Name: ast.NewIdent(alias),
	})
	decls := []ast.Decl{}
	if destr.ImportItemList() != nil {
		for _, item := range destr.ImportItemList().AllImportItem() {
			var orig, as string
			if item.ID(0) != nil {
				orig = item.ID(0).GetText()
			}
			if item.ID(1) != nil {
				as = item.ID(1).GetText()
			} else {
				as = orig
			}
			decls = append(decls, &ast.GenDecl{
				Tok: token.VAR,
				Specs: []ast.Spec{
					&ast.ValueSpec{
						Names: []*ast.Ident{ast.NewIdent(as)},
						Values: []ast.Expr{&ast.SelectorExpr{
							X:   ast.NewIdent(alias),
							Sel: ast.NewIdent(orig),
						}},
					},
				},
			})
		}
	}
	return decls
}
