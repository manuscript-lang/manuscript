package msparse

import (
	"manuscript-co/manuscript/internal/ast"
	"manuscript-co/manuscript/internal/parser"

	"github.com/antlr4-go/antlr/v4"
)

func (v *ParseTreeToAST) VisitLetDecl(ctx *parser.LetDeclContext) interface{} {
	letDecl := &ast.LetDecl{
		BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
	}

	// Handle different let declaration types
	if ctx.LetSingle() != nil {
		if letSingle := ctx.LetSingle().Accept(v); letSingle != nil {
			letDecl.Items = []ast.LetItem{letSingle.(ast.LetItem)}
		}
	} else if ctx.LetBlock() != nil {
		if letBlock := ctx.LetBlock().Accept(v); letBlock != nil {
			letDecl.Items = []ast.LetItem{letBlock.(ast.LetItem)}
		}
	} else if ctx.LetDestructuredObj() != nil {
		if letDestr := ctx.LetDestructuredObj().Accept(v); letDestr != nil {
			letDecl.Items = []ast.LetItem{letDestr.(ast.LetItem)}
		}
	} else if ctx.LetDestructuredArray() != nil {
		if letDestr := ctx.LetDestructuredArray().Accept(v); letDestr != nil {
			letDecl.Items = []ast.LetItem{letDestr.(ast.LetItem)}
		}
	}

	return letDecl
}

func (v *ParseTreeToAST) VisitLetSingle(ctx *parser.LetSingleContext) interface{} {
	letSingle := &ast.LetSingle{
		BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
	}

	// Extract typed ID
	if ctx.TypedID() != nil {
		if typedID := ctx.TypedID().Accept(v); typedID != nil {
			letSingle.ID = typedID.(ast.TypedID)
		}
	}

	// Extract value (expression or try expression)
	if ctx.Expr() != nil {
		if expr := ctx.Expr().Accept(v); expr != nil {
			letSingle.Value = expr.(ast.Expression)
		}
	} else if ctx.TryExpr() != nil {
		if tryExpr := ctx.TryExpr().Accept(v); tryExpr != nil {
			letSingle.Value = tryExpr.(ast.Expression)
			letSingle.IsTry = true
		}
	}

	return letSingle
}

func (v *ParseTreeToAST) VisitLetBlock(ctx *parser.LetBlockContext) interface{} {
	letBlock := &ast.LetBlock{
		BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
	}

	if ctx.LetBlockItemList() != nil {
		if itemList := ctx.LetBlockItemList().Accept(v); itemList != nil {
			letBlock.Items = itemList.([]ast.LetBlockItem)
		}
	}

	return letBlock
}

func (v *ParseTreeToAST) VisitLetBlockItemList(ctx *parser.LetBlockItemListContext) interface{} {
	var items []ast.LetBlockItem
	for _, itemCtx := range ctx.AllLetBlockItem() {
		if item := itemCtx.Accept(v); item != nil {
			items = append(items, item.(ast.LetBlockItem))
		}
	}
	return items
}

// LetBlockItem visitor - was missing
func (v *ParseTreeToAST) VisitLetBlockItem(ctx *parser.LetBlockItemContext) interface{} {
	// The LetBlockItem context is a base type that gets specialized into specific labeled contexts
	// We need to handle it by checking the children and delegating
	for _, child := range ctx.GetChildren() {
		if child != nil {
			if ruleCtx, ok := child.(antlr.RuleContext); ok {
				return ruleCtx.Accept(v)
			}
		}
	}
	return nil
}

// LabelLetBlockItemSingle

func (v *ParseTreeToAST) VisitLabelLetBlockItemSingle(ctx *parser.LabelLetBlockItemSingleContext) interface{} {
	item := &ast.LetBlockItemSingle{
		BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
	}

	if ctx.TypedID() != nil {
		if typedID := ctx.TypedID().Accept(v); typedID != nil {
			item.ID = typedID.(ast.TypedID)
		}
	}

	if ctx.Expr() != nil {
		if expr := ctx.Expr().Accept(v); expr != nil {
			item.Value = expr.(ast.Expression)
		}
	}

	return item
}

// LabelLetBlockItemDestructuredObj

func (v *ParseTreeToAST) VisitLabelLetBlockItemDestructuredObj(ctx *parser.LabelLetBlockItemDestructuredObjContext) interface{} {
	item := &ast.LetBlockItemDestructuredObj{
		BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
	}

	if ctx.TypedIDList() != nil {
		if typedIDList := ctx.TypedIDList().Accept(v); typedIDList != nil {
			item.IDs = typedIDList.([]ast.TypedID)
		}
	}

	if ctx.Expr() != nil {
		if expr := ctx.Expr().Accept(v); expr != nil {
			item.Value = expr.(ast.Expression)
		}
	}

	return item
}

// LabelLetBlockItemDestructuredArray

func (v *ParseTreeToAST) VisitLabelLetBlockItemDestructuredArray(ctx *parser.LabelLetBlockItemDestructuredArrayContext) interface{} {
	item := &ast.LetBlockItemDestructuredArray{
		BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
	}

	if ctx.TypedIDList() != nil {
		if typedIDList := ctx.TypedIDList().Accept(v); typedIDList != nil {
			item.IDs = typedIDList.([]ast.TypedID)
		}
	}

	if ctx.Expr() != nil {
		if expr := ctx.Expr().Accept(v); expr != nil {
			item.Value = expr.(ast.Expression)
		}
	}

	return item
}

// LetDestructuredObj

func (v *ParseTreeToAST) VisitLetDestructuredObj(ctx *parser.LetDestructuredObjContext) interface{} {
	letDestr := &ast.LetDestructuredObj{
		BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
	}

	if ctx.TypedIDList() != nil {
		if typedIDList := ctx.TypedIDList().Accept(v); typedIDList != nil {
			letDestr.IDs = typedIDList.([]ast.TypedID)
		}
	}

	if ctx.Expr() != nil {
		if expr := ctx.Expr().Accept(v); expr != nil {
			letDestr.Value = expr.(ast.Expression)
		}
	}

	return letDestr
}

// LetDestructuredArray

func (v *ParseTreeToAST) VisitLetDestructuredArray(ctx *parser.LetDestructuredArrayContext) interface{} {
	letDestr := &ast.LetDestructuredArray{
		BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
	}

	if ctx.TypedIDList() != nil {
		if typedIDList := ctx.TypedIDList().Accept(v); typedIDList != nil {
			letDestr.IDs = typedIDList.([]ast.TypedID)
		}
	}

	if ctx.Expr() != nil {
		if expr := ctx.Expr().Accept(v); expr != nil {
			letDestr.Value = expr.(ast.Expression)
		}
	}

	return letDestr
}
