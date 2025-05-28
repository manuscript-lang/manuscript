package transpiler

import (
	"fmt"
	"go/ast"
	"go/token"
	mast "manuscript-lang/manuscript/internal/ast"
)

// Additional missing visitor methods to complete the interface

// VisitDestructuredImport transpiles destructured imports
func (t *GoTranspiler) VisitDestructuredImport(node *mast.DestructuredImport) ast.Node {
	if node == nil || node.Module == "" {
		t.addError("invalid destructured import", nil)
		return nil
	}

	// Generate a unique temporary import alias
	tempAlias := fmt.Sprintf("__import%d", t.tempVarCount+1)
	t.tempVarCount++

	// Create import spec and add to imports slice
	importSpec := &ast.ImportSpec{
		Path: &ast.BasicLit{
			Kind:  token.STRING,
			Value: `"` + node.Module + `"`,
		},
		Name: &ast.Ident{Name: tempAlias},
	}
	t.Imports = append(t.Imports, importSpec)

	// Generate individual variable declarations for each imported item
	var decls []ast.Decl
	for _, item := range node.Items {
		// Determine the variable name (use alias if provided, otherwise use original name)
		varName := item.Name
		if item.Alias != "" {
			varName = item.Alias
		}

		// Create individual GenDecl for each variable
		genDecl := &ast.GenDecl{
			Tok: token.VAR,
			Specs: []ast.Spec{
				&ast.ValueSpec{
					Names: []*ast.Ident{{Name: t.generateVarName(varName)}},
					Values: []ast.Expr{
						&ast.SelectorExpr{
							X:   &ast.Ident{Name: tempAlias},
							Sel: &ast.Ident{Name: t.generateVarName(item.Name)},
						},
					},
				},
			},
		}
		decls = append(decls, genDecl)
	}

	// Return multiple declarations using the new MultipleDeclarations type
	if len(decls) == 1 {
		return decls[0]
	} else if len(decls) > 1 {
		return &MultipleDeclarations{Decls: decls}
	}

	return nil
}

// VisitTargetImport transpiles target imports (import name from 'module')
func (t *GoTranspiler) VisitTargetImport(node *mast.TargetImport) ast.Node {
	if node == nil || node.Module == "" {
		t.addError("invalid target import", nil)
		return nil
	}

	// Create import spec and add to imports slice
	importSpec := &ast.ImportSpec{
		Path: &ast.BasicLit{
			Kind:  token.STRING,
			Value: `"` + node.Module + `"`,
		},
		Name: &ast.Ident{Name: node.Name},
	}
	t.Imports = append(t.Imports, importSpec)

	return nil
}

// VisitImportItem transpiles import items
func (t *GoTranspiler) VisitImportItem(node *mast.ImportItem) ast.Node {
	if node == nil {
		return nil
	}

	// ImportItems are typically handled as part of DestructuredImport
	ident := &ast.Ident{Name: t.generateVarName(node.Name)}

	t.registerNodeMapping(ident, node)
	return ident
}

// VisitModuleImport transpiles module imports
func (t *GoTranspiler) VisitModuleImport(node *mast.ModuleImport) ast.Node {
	if node == nil {
		t.addError("invalid module import", nil)
		return nil
	}

	// ModuleImport is an interface, dispatch to specific implementations
	switch importNode := (*node).(type) {
	case *mast.DestructuredImport:
		return t.VisitDestructuredImport(importNode)
	case *mast.TargetImport:
		return t.VisitTargetImport(importNode)
	default:
		t.addError("unknown module import type", nil)
		return nil
	}
}
