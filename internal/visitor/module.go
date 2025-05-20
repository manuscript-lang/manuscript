package visitor

import (
	"go/ast"
	"go/token"
	"manuscript-co/manuscript/internal/parser"
	"unicode"

	"github.com/antlr4-go/antlr/v4"
)

func capitalizeFirstLetter(s string) string {
	if len(s) == 0 {
		return ""
	}
	r := []rune(s)
	r[0] = unicode.ToUpper(r[0])
	return string(r)
}

// resolveModuleImportDecl processes a ModuleDecl (for import/extern) and returns Go ImportSpecs.
func (v *ManuscriptAstVisitor) resolveModuleImportDecl(mod parser.IModuleDeclContext, errTok antlr.Token) ([]*ast.ImportSpec, bool) {
	var specs []*ast.ImportSpec

	switch m := mod.(type) {
	case *parser.DestructuredImportContext:
		pathCtx := m.GetPath()
		if pathCtx == nil || pathCtx.SingleQuotedString() == nil {
			v.addError("Destructured import/extern is missing a path.", errTok)
			return nil, false
		}
		pathValue := pathCtx.SingleQuotedString().GetText()
		items := m.GetItems()
		if m.LBRACE() != nil && len(items) == 0 {
			// Side-effect import
			specs = append(specs, &ast.ImportSpec{
				Name: ast.NewIdent("_"),
				Path: &ast.BasicLit{Kind: token.STRING, Value: pathValue},
			})
		} else {
			for _, item := range items {
				var name *ast.Ident
				if item.GetAlias() != nil {
					name = ast.NewIdent(item.GetAlias().GetText())
				}
				specs = append(specs, &ast.ImportSpec{
					Name: name, // nil if no alias
					Path: &ast.BasicLit{Kind: token.STRING, Value: pathValue},
				})
			}
		}
	case *parser.TargetImportContext:
		pathCtx := m.GetPath()
		if pathCtx == nil || pathCtx.SingleQuotedString() == nil {
			v.addError("Target import/extern is missing a path.", errTok)
			return nil, false
		}
		pathValue := pathCtx.SingleQuotedString().GetText()
		target := m.GetTarget()
		var name *ast.Ident
		if target != nil {
			name = ast.NewIdent(target.GetText())
		}
		specs = append(specs, &ast.ImportSpec{
			Name: name, // nil if no alias
			Path: &ast.BasicLit{Kind: token.STRING, Value: pathValue},
		})
	default:
		v.addError("Unknown module declaration in import/extern statement.", errTok)
		return nil, false
	}
	return specs, true
}

// VisitImportStmt handles Manuscript import statements.
// It translates them to Go import declarations.
func (v *ManuscriptAstVisitor) VisitImportStmt(ctx *parser.ImportStmtContext) interface{} {
	mod := ctx.ModuleDecl()
	if mod == nil {
		v.addError("Import statement is missing a module declaration.", ctx.GetStart())
		return &ast.BadDecl{}
	}
	importSpecs, ok := v.resolveModuleImportDecl(mod, ctx.GetStart())
	if !ok || len(importSpecs) == 0 {
		return &ast.BadDecl{}
	}
	return &ast.GenDecl{
		Tok:   token.IMPORT,
		Specs: toSpecSlice(importSpecs),
	}
}

// VisitImportItem is called when visiting an import item.
// Currently, its information is used directly by VisitImportStmt for logging.
func (v *ManuscriptAstVisitor) VisitImportItem(ctx *parser.ImportItemContext) interface{} {
	// This method could return a struct/map if VisitImportStmt needed to aggregate complex data.
	// For the current AST generation strategy, it's not strictly producing a node.
	return nil
}

// VisitExternStmt handles Manuscript extern statements.
// For Go AST generation, this is currently treated like an import.
func (v *ManuscriptAstVisitor) VisitExternStmt(ctx *parser.ExternStmtContext) interface{} {
	mod := ctx.ModuleDecl()
	if mod == nil {
		v.addError("Extern statement is missing a module declaration.", ctx.GetStart())
		return &ast.BadDecl{}
	}
	importSpecs, ok := v.resolveModuleImportDecl(mod, ctx.GetStart())
	if !ok || len(importSpecs) == 0 {
		return &ast.BadDecl{}
	}
	return &ast.GenDecl{
		Tok:   token.IMPORT,
		Specs: toSpecSlice(importSpecs),
	}
}

// toSpecSlice converts []*ast.ImportSpec to []ast.Spec for GenDecl.
func toSpecSlice(specs []*ast.ImportSpec) []ast.Spec {
	out := make([]ast.Spec, len(specs))
	for i, s := range specs {
		out[i] = s
	}
	return out
}

// VisitExportStmt handles export statements.
// It visits the underlying declaration and modifies its AST
// to ensure relevant identifiers are capitalized for Go export.
// Assumes the visited declaration (fnDecl, letDecl, typeDecl, ifaceDecl)
// returns an ast.Decl node.
func (v *ManuscriptAstVisitor) VisitExportStmt(ctx *parser.ExportStmtContext) interface{} {
	var visitedNode interface{}

	if ctx.FnDecl() != nil {
		visitedNode = v.Visit(ctx.FnDecl())
	} else if ctx.LetDecl() != nil {
		visitedNode = v.Visit(ctx.LetDecl())
	} else if ctx.TypeDecl() != nil {
		visitedNode = v.Visit(ctx.TypeDecl())
	} else if ctx.InterfaceDecl() != nil {
		visitedNode = v.Visit(ctx.InterfaceDecl())
	} else {
		v.addError("Export statement has no recognized declaration (function, let, type, or interface).", ctx.GetStart())
		return &ast.BadDecl{}
	}

	decl, ok := visitedNode.(ast.Decl)
	if !ok {
		if visitedNode == nil {
			v.addError("Exported item is invalid or could not be processed.", ctx.GetStart())
			return &ast.BadDecl{}
		} else {
			v.addError("Internal error: Exported item processing returned an unexpected type.", ctx.GetStart())
		}
		return visitedNode
	}

	// Modify the declaration to make it exported
	switch d := decl.(type) {
	case *ast.FuncDecl:
		if d.Name != nil {
			d.Name.Name = capitalizeFirstLetter(d.Name.Name)
		}
	case *ast.GenDecl:
		for _, spec := range d.Specs {
			switch s := spec.(type) {
			case *ast.ValueSpec: // From letDecl (var/const)
				for _, nameIdent := range s.Names {
					nameIdent.Name = capitalizeFirstLetter(nameIdent.Name)
				}
			case *ast.TypeSpec: // From typeDecl or ifaceDecl
				if s.Name != nil {
					s.Name.Name = capitalizeFirstLetter(s.Name.Name)
				}
			default:
				v.addError("Internal warning: Unhandled specification type in exported generic declaration for: "+ctx.GetText(), ctx.GetStart())
			}
		}
	default:
		v.addError("Internal warning: Exporting an unhandled declaration type for: "+ctx.GetText(), ctx.GetStart())
	}
	return decl
}
