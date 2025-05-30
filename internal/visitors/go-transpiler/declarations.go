package transpiler

import (
	"fmt"
	"go/ast"
	"go/token"
	"strings"

	mast "manuscript-lang/manuscript/internal/ast"
)

// VisitImportDecl transpiles import declarations
func (t *GoTranspiler) VisitImportDecl(node *mast.ImportDecl) ast.Node {
	if node == nil || node.Import == nil {
		t.addError("invalid import declaration", nil)
		return nil
	}

	// Visit the import node
	result := t.Visit(node.Import)

	return result
}

// VisitExportDecl transpiles export declarations
func (t *GoTranspiler) VisitExportDecl(node *mast.ExportDecl) ast.Node {
	if node == nil || node.Item == nil {
		t.addError("invalid export declaration", node)
		return nil
	}

	// Visit the exported item
	result := t.Visit(node.Item)
	if result == nil {
		return nil
	}

	// Make the exported item public by capitalizing the name
	switch decl := result.(type) {
	case *ast.FuncDecl:
		if decl.Name != nil {
			decl.Name.Name = t.capitalizeForExport(decl.Name.Name)
		}
		return decl
	case *ast.GenDecl:
		// Handle type and variable declarations
		for _, spec := range decl.Specs {
			switch s := spec.(type) {
			case *ast.TypeSpec:
				if s.Name != nil {
					s.Name.Name = t.capitalizeForExport(s.Name.Name)
				}
			case *ast.ValueSpec:
				for _, name := range s.Names {
					if name != nil {
						name.Name = t.capitalizeForExport(name.Name)
					}
				}
			}
		}
		return decl
	default:
		return result
	}
}

// VisitExternDecl transpiles extern declarations (similar to imports)
func (t *GoTranspiler) VisitExternDecl(node *mast.ExternDecl) ast.Node {
	if node == nil || node.Import == nil {
		t.addError("invalid extern declaration", node)
		return nil
	}

	// Visit the module import
	t.Visit(node.Import)

	// Extern declarations are typically handled as imports in Go
	return nil
}

// VisitLetDecl transpiles let declarations to Go variable declarations or assignment statements
func (t *GoTranspiler) VisitLetDecl(node *mast.LetDecl) ast.Node {
	if node == nil {
		t.addError("received nil let declaration", nil)
		return nil
	}

	// Process all items in the let declaration
	var statements []ast.Stmt

	for _, item := range node.Items {
		result := t.Visit(item)

		// Handle different result types
		switch v := result.(type) {
		case *DestructuringBlockStmt:
			// Standalone destructuring - unwrap to the underlying BlockStmt
			statements = append(statements, v.BlockStmt)
		case *ast.BlockStmt:
			// Flatten block statements (including let blocks)
			statements = append(statements, v.List...)
		case ast.Stmt:
			statements = append(statements, v)
		case nil:
			// Skip nil results
			continue
		default:
			t.addError(fmt.Sprintf("unexpected result type from let item: %T", result), item)
		}
	}

	// Register mapping only for the primary node
	var result ast.Node
	if len(statements) > 1 {
		result = &ast.BlockStmt{List: statements}
	} else if len(statements) == 1 {
		result = statements[0]
	} else {
		return nil
	}

	// Register mapping for the primary result only
	t.registerNodeMapping(result, node)
	return result
}

// VisitTypeDecl transpiles type declarations
func (t *GoTranspiler) VisitTypeDecl(node *mast.TypeDecl) ast.Node {
	if node == nil || node.Name == "" {
		t.addError("invalid type declaration", node)
		return nil
	}

	// Visit the type body
	typeExpr := t.Visit(node.Body)
	if typeExpr == nil {
		t.addError("failed to transpile type body", node)
		return nil
	}

	// Convert to Go type
	var goType ast.Expr
	if expr, ok := typeExpr.(ast.Expr); ok {
		goType = expr
	} else {
		t.addError("type body did not produce valid Go type expression", node)
		return nil
	}

	typeSpec := &ast.TypeSpec{
		Name: &ast.Ident{
			Name:    t.generateVarName(node.Name),
			NamePos: t.pos(node),
		},
		Type: goType,
	}

	genDecl := &ast.GenDecl{
		TokPos: t.pos(node),
		Tok:    token.TYPE,
		Specs:  []ast.Spec{typeSpec},
	}

	t.registerNodeMapping(genDecl, node)
	return genDecl
}

// VisitInterfaceDecl transpiles interface declarations
func (t *GoTranspiler) VisitInterfaceDecl(node *mast.InterfaceDecl) ast.Node {
	if node == nil || node.Name == "" {
		t.addError("invalid interface declaration", node)
		return nil
	}

	var methods []*ast.Field

	// Process interface methods
	for i := range node.Methods {
		method := &node.Methods[i]
		field := t.Visit(method)
		if astField, ok := field.(*ast.Field); ok {
			methods = append(methods, astField)
		}
	}

	interfaceType := &ast.InterfaceType{
		Methods: &ast.FieldList{List: methods},
	}

	typeSpec := &ast.TypeSpec{
		Name: &ast.Ident{Name: t.generateVarName(node.Name)},
		Type: interfaceType,
	}

	return &ast.GenDecl{
		Tok:   token.TYPE,
		Specs: []ast.Spec{typeSpec},
	}
}

// capitalizeForExport capitalizes the first letter for Go exports
func (t *GoTranspiler) capitalizeForExport(name string) string {
	if name == "" {
		return name
	}

	if len(name) == 1 {
		return strings.ToUpper(name)
	}

	return strings.ToUpper(name[:1]) + name[1:]
}
