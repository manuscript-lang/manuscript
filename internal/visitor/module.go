package visitor

import (
	"go/ast"
	"go/token"
	"log"
	"manuscript-co/manuscript/internal/parser"
	"unicode"
)

func capitalizeFirstLetter(s string) string {
	if len(s) == 0 {
		return ""
	}
	r := []rune(s)
	r[0] = unicode.ToUpper(r[0])
	return string(r)
}

// VisitImportStmt handles Manuscript import statements.
// It translates them to Go import declarations.
func (v *ManuscriptAstVisitor) VisitImportStmt(ctx *parser.ImportStmtContext) interface{} {
	pathToken := ctx.GetPath()
	if pathToken == nil {
		v.addError("Import statement is missing a path.", ctx.GetStart())
		return &ast.BadDecl{}
	}
	pathValue := pathToken.GetText() // e.g., "\"module/path\""

	var importName *ast.Ident // Go package alias

	if targetNode := ctx.GetTarget(); targetNode != nil { // Form 2: IMPORT target FROM path
		importName = ast.NewIdent(targetNode.GetText())
	} else { // Form 1: IMPORT { items } FROM path
		allItems := ctx.AllImportItem()
		if ctx.LBRACE() != nil && len(allItems) == 0 { // IMPORT {} FROM path
			importName = ast.NewIdent("_") // Import for side-effects
		} else if len(allItems) == 1 {
			// If one item & aliased, use that alias for the package.
			itemCtx := allItems[0].(*parser.ImportItemContext)
			if itemCtx.GetAlias() != nil {
				importName = ast.NewIdent(itemCtx.GetAlias().GetText())
			}
		}
		// Otherwise (multiple items, single unaliased item), importName remains nil (default Go package name).

		// Log details of all items for Manuscript's symbol table/resolver phase
		for _, itemAntlrNode := range allItems {
			itemCtx := itemAntlrNode.(*parser.ImportItemContext)
			itemNameStr := itemCtx.GetName().GetText()
			if itemCtx.GetAlias() != nil {
				aliasStr := itemCtx.GetAlias().GetText()
				log.Printf("DEBUG: Manuscript import item: '%s' as '%s' from %s", itemNameStr, aliasStr, pathValue)
			} else {
				log.Printf("DEBUG: Manuscript import item: '%s' from %s", itemNameStr, pathValue)
			}
		}
	}

	importSpec := &ast.ImportSpec{
		Name: importName, // Can be nil or ast.NewIdent("_")
		Path: &ast.BasicLit{Kind: token.STRING, Value: pathValue},
	}

	return &ast.GenDecl{
		Tok:   token.IMPORT,
		Specs: []ast.Spec{importSpec},
	}
}

// VisitImportItem is called when visiting an import item.
// Currently, its information is used directly by VisitImportStmt for logging.
func (v *ManuscriptAstVisitor) VisitImportItem(ctx *parser.ImportItemContext) interface{} {
	name := ctx.GetName().GetText()
	alias := ""
	if ctx.GetAlias() != nil {
		alias = ctx.GetAlias().GetText()
	}
	log.Printf("TRACE: Visiting ImportItem: %s (alias: %s)", name, alias)
	// This method could return a struct/map if VisitImportStmt needed to aggregate complex data.
	// For the current AST generation strategy, it's not strictly producing a node.
	return nil
}

// VisitExternStmt handles Manuscript extern statements.
// For Go AST generation, this is currently treated like an import.
func (v *ManuscriptAstVisitor) VisitExternStmt(ctx *parser.ExternStmtContext) interface{} {
	pathToken := ctx.GetPath()
	if pathToken == nil {
		v.addError("Extern statement is missing a path.", ctx.GetStart())
		return &ast.BadDecl{}
	}
	pathValue := pathToken.GetText()

	var importName *ast.Ident // Go package alias

	if targetNode := ctx.GetTarget(); targetNode != nil { // Form 2: EXTERN target FROM path
		importName = ast.NewIdent(targetNode.GetText())
	} else { // Form 1: EXTERN { items } FROM path
		allItems := ctx.AllExternItem()
		if ctx.LBRACE() != nil && len(allItems) == 0 { // EXTERN {} FROM path
			importName = ast.NewIdent("_") // Import for side-effects
		} else if len(allItems) == 1 {
			itemCtx := allItems[0].(*parser.ExternItemContext)
			if itemCtx.GetAlias() != nil {
				importName = ast.NewIdent(itemCtx.GetAlias().GetText())
			}
		}
		// Log details of all items
		for _, itemAntlrNode := range allItems {
			itemCtx := itemAntlrNode.(*parser.ExternItemContext)
			itemNameStr := itemCtx.GetName().GetText()
			if itemCtx.GetAlias() != nil {
				aliasStr := itemCtx.GetAlias().GetText()
				log.Printf("DEBUG: Manuscript extern item: '%s' as '%s' from %s", itemNameStr, aliasStr, pathValue)
			} else {
				log.Printf("DEBUG: Manuscript extern item: '%s' from %s", itemNameStr, pathValue)
			}
		}
	}

	importSpec := &ast.ImportSpec{
		Name: importName,
		Path: &ast.BasicLit{Kind: token.STRING, Value: pathValue},
	}

	return &ast.GenDecl{
		Tok:   token.IMPORT, // Still generates a Go import declaration
		Specs: []ast.Spec{importSpec},
	}
}

// VisitExternItem is called when visiting an extern item.
func (v *ManuscriptAstVisitor) VisitExternItem(ctx *parser.ExternItemContext) interface{} {
	name := ctx.GetName().GetText()
	alias := ""
	if ctx.GetAlias() != nil {
		alias = ctx.GetAlias().GetText()
	}
	log.Printf("TRACE: Visiting ExternItem: %s (alias: %s)", name, alias)
	return nil
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
	} else if ctx.IfaceDecl() != nil {
		visitedNode = v.Visit(ctx.IfaceDecl())
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
			log.Printf("DEBUG: Exporting function: %s -> %s", d.Name.Name, capitalizeFirstLetter(d.Name.Name))
			d.Name.Name = capitalizeFirstLetter(d.Name.Name)
		}
	case *ast.GenDecl:
		for _, spec := range d.Specs {
			switch s := spec.(type) {
			case *ast.ValueSpec: // From letDecl (var/const)
				for _, nameIdent := range s.Names {
					log.Printf("DEBUG: Exporting variable: %s -> %s", nameIdent.Name, capitalizeFirstLetter(nameIdent.Name))
					nameIdent.Name = capitalizeFirstLetter(nameIdent.Name)
				}
			case *ast.TypeSpec: // From typeDecl or ifaceDecl
				if s.Name != nil {
					log.Printf("DEBUG: Exporting type/interface: %s -> %s", s.Name.Name, capitalizeFirstLetter(s.Name.Name))
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
