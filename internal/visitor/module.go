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

// VisitImportDecl handles Manuscript import declarations.
func (v *ManuscriptAstVisitor) VisitImportDecl(ctx *parser.ImportDeclContext) interface{} {
	if ctx == nil || ctx.ModuleImport() == nil {
		v.addError("Import declaration is missing a module import.", ctx.GetStart())
		return &ast.BadDecl{}
	}
	mod := ctx.ModuleImport()
	importSpecs, ok := v.resolveModuleImport(mod, ctx.GetStart())
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

// VisitExternDecl handles Manuscript extern declarations.
func (v *ManuscriptAstVisitor) VisitExternDecl(ctx *parser.ExternDeclContext) interface{} {
	if ctx == nil || ctx.ModuleImport() == nil {
		v.addError("Extern declaration is missing a module import.", ctx.GetStart())
		return &ast.BadDecl{}
	}
	mod := ctx.ModuleImport()
	importSpecs, ok := v.resolveModuleImport(mod, ctx.GetStart())
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

// VisitExportDecl handles Manuscript export declarations.
func (v *ManuscriptAstVisitor) VisitExportDecl(ctx *parser.ExportDeclContext) interface{} {
	if ctx == nil || ctx.ExportedItem() == nil {
		v.addError("Export declaration is missing an exported item.", ctx.GetStart())
		return &ast.BadDecl{}
	}
	item := ctx.ExportedItem()
	var visitedNode interface{}
	if item.FnDecl() != nil {
		visitedNode = v.Visit(item.FnDecl())
	} else if item.LetDecl() != nil {
		visitedNode = v.Visit(item.LetDecl())
	} else if item.TypeDecl() != nil {
		visitedNode = v.Visit(item.TypeDecl())
	} else if item.InterfaceDecl() != nil {
		visitedNode = v.Visit(item.InterfaceDecl())
	} else {
		v.addError("Exported item is not a recognized declaration.", ctx.GetStart())
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
	// Capitalize identifiers for Go export
	switch d := decl.(type) {
	case *ast.FuncDecl:
		if d.Name != nil {
			d.Name.Name = capitalizeFirstLetter(d.Name.Name)
		}
	case *ast.GenDecl:
		for _, spec := range d.Specs {
			switch s := spec.(type) {
			case *ast.ValueSpec:
				for _, nameIdent := range s.Names {
					nameIdent.Name = capitalizeFirstLetter(nameIdent.Name)
				}
			case *ast.TypeSpec:
				if s.Name != nil {
					s.Name.Name = capitalizeFirstLetter(s.Name.Name)
				}
			}
		}
	}
	return decl
}

// resolveModuleImport processes a moduleImport (for import/extern) and returns Go ImportSpecs.
func (v *ManuscriptAstVisitor) resolveModuleImport(mod parser.IModuleImportContext, errTok antlr.Token) ([]*ast.ImportSpec, bool) {
	if mod == nil {
		v.addError("Module import is nil.", errTok)
		return nil, false
	}
	if destr := mod.DestructuredImport(); destr != nil {
		pathCtx := destr.ImportStr()
		if pathCtx == nil || pathCtx.SingleQuotedString() == nil {
			v.addError("Destructured import/extern is missing a path.", errTok)
			return nil, false
		}
		pathValue := pathCtx.SingleQuotedString().GetText()
		items := destr.ImportItemList()
		if destr.LBRACE() != nil && (items == nil || len(items.AllImportItem()) == 0) {
			// Side-effect import
			specs := []*ast.ImportSpec{{
				Name: ast.NewIdent("_"),
				Path: &ast.BasicLit{Kind: token.STRING, Value: pathValue},
			}}
			return specs, true
		} else if items != nil {
			var specs []*ast.ImportSpec
			for _, item := range items.AllImportItem() {
				var name *ast.Ident
				if item.AS() != nil && item.ID(1) != nil {
					name = ast.NewIdent(item.ID(1).GetText())
				}
				specs = append(specs, &ast.ImportSpec{
					Name: name, // nil if no alias
					Path: &ast.BasicLit{Kind: token.STRING, Value: pathValue},
				})
			}
			return specs, true
		}
	}
	if target := mod.TargetImport(); target != nil {
		pathCtx := target.ImportStr()
		if pathCtx == nil || pathCtx.SingleQuotedString() == nil {
			v.addError("Target import/extern is missing a path.", errTok)
			return nil, false
		}
		pathValue := pathCtx.SingleQuotedString().GetText()
		targetId := target.ID()
		var name *ast.Ident
		if targetId != nil {
			name = ast.NewIdent(targetId.GetText())
		}
		specs := []*ast.ImportSpec{{
			Name: name, // nil if no alias
			Path: &ast.BasicLit{Kind: token.STRING, Value: pathValue},
		}}
		return specs, true
	}
	v.addError("Unknown module import in import/extern statement.", errTok)
	return nil, false
}
