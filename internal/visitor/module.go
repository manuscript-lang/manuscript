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

// DRY helper for import/extern
func (v *ManuscriptAstVisitor) handleImportLikeDecl(mod parser.IModuleImportContext, errTok antlr.Token) interface{} {
	if mod == nil {
		v.addError("Module import is nil.", errTok)
		return &ast.BadDecl{}
	}
	importSpecs, ok := v.resolveModuleImport(mod, errTok)
	if !ok || len(importSpecs) == 0 {
		return &ast.BadDecl{}
	}
	return &ast.GenDecl{
		Tok:   token.IMPORT,
		Specs: toSpecSlice(importSpecs),
	}
}

func (v *ManuscriptAstVisitor) VisitImportDecl(ctx *parser.ImportDeclContext) interface{} {
	if ctx == nil || ctx.ModuleImport() == nil {
		v.addError("Import declaration is missing a module import.", ctx.GetStart())
		return &ast.BadDecl{}
	}
	return v.handleImportLikeDecl(ctx.ModuleImport(), ctx.GetStart())
}

func (v *ManuscriptAstVisitor) VisitExternDecl(ctx *parser.ExternDeclContext) interface{} {
	if ctx == nil || ctx.ModuleImport() == nil {
		v.addError("Extern declaration is missing a module import.", ctx.GetStart())
		return &ast.BadDecl{}
	}
	return v.handleImportLikeDecl(ctx.ModuleImport(), ctx.GetStart())
}

// VisitExportDecl handles Manuscript export declarations using the visitor pattern.
func (v *ManuscriptAstVisitor) VisitExportDecl(ctx *parser.ExportDeclContext) interface{} {
	if ctx == nil || ctx.ExportedItem() == nil {
		v.addError("Export declaration is missing an exported item.", ctx.GetStart())
		return &ast.BadDecl{}
	}
	item := ctx.ExportedItem()
	var visitedNode interface{}
	switch t := item.(type) {
	case *parser.ExportedFnContext:
		if fn := t.FnDecl(); fn != nil {
			if fnCtx, ok := fn.(*parser.FnDeclContext); ok {
				visitedNode = v.VisitFnDecl(fnCtx)
			}
		}
	case *parser.ExportedLetContext:
		if let := t.LetDecl(); let != nil {
			if letCtx, ok := let.(*parser.LetDeclContext); ok {
				visitedNode = v.Visit(letCtx)
			}
		}
	case *parser.ExportedTypeContext:
		if typ := t.TypeDecl(); typ != nil {
			if typCtx, ok := typ.(*parser.TypeDeclContext); ok {
				visitedNode = v.VisitTypeDecl(typCtx)
			}
		}
	case *parser.ExportedInterfaceContext:
		if iface := t.InterfaceDecl(); iface != nil {
			if ifaceCtx, ok := iface.(*parser.InterfaceDeclContext); ok {
				visitedNode = v.VisitInterfaceDecl(ifaceCtx)
			}
		}
	default:
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
	// Destructured import: {a, b as c} from 'path'
	if destr, ok := mod.(*parser.ModuleImportDestructuredContext); ok {
		destructured := destr.DestructuredImport()
		if destructured == nil {
			v.addError("Destructured import/extern is missing destructuredImport.", errTok)
			return nil, false
		}
		pathCtx := destructured.ImportStr()
		if pathCtx == nil || pathCtx.SingleQuotedString() == nil {
			v.addError("Destructured import/extern is missing a path.", errTok)
			return nil, false
		}
		pathValue := pathCtx.SingleQuotedString().GetText()
		items := destructured.ImportItemList()
		if destructured.LBRACE() != nil && (items == nil || len(items.AllImportItem()) == 0) {
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
				ids := item.AllID()
				if item.AS() != nil && len(ids) > 1 {
					name = ast.NewIdent(ids[1].GetText())
				}
				specs = append(specs, &ast.ImportSpec{
					Name: name, // nil if no alias
					Path: &ast.BasicLit{Kind: token.STRING, Value: pathValue},
				})
			}
			return specs, true
		}
	}
	// Target import: foo from 'path'
	if target, ok := mod.(*parser.ModuleImportTargetContext); ok {
		targetImport := target.TargetImport()
		if targetImport == nil {
			v.addError("Target import/extern is missing targetImport.", errTok)
			return nil, false
		}
		pathCtx := targetImport.ImportStr()
		if pathCtx == nil || pathCtx.SingleQuotedString() == nil {
			v.addError("Target import/extern is missing a path.", errTok)
			return nil, false
		}
		pathValue := pathCtx.SingleQuotedString().GetText()
		targetId := targetImport.ID()
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
