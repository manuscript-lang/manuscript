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

	var item ast.LetItem
	switch {
	case ctx.LetSingle() != nil:
		if result := ctx.LetSingle().Accept(v); result != nil {
			item = result.(ast.LetItem)
		}
	case ctx.LetBlock() != nil:
		if result := ctx.LetBlock().Accept(v); result != nil {
			item = result.(ast.LetItem)
		}
	case ctx.LetDestructuredObj() != nil:
		if result := ctx.LetDestructuredObj().Accept(v); result != nil {
			item = result.(ast.LetItem)
		}
	case ctx.LetDestructuredArray() != nil:
		if result := ctx.LetDestructuredArray().Accept(v); result != nil {
			item = result.(ast.LetItem)
		}
	}

	if item != nil {
		letDecl.Items = []ast.LetItem{item}
	}

	return letDecl
}

func (v *ParseTreeToAST) VisitLetSingle(ctx *parser.LetSingleContext) interface{} {
	letSingle := &ast.LetSingle{
		BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
	}

	if ctx.TypedID() != nil {
		if result := ctx.TypedID().Accept(v); result != nil {
			letSingle.ID = result.(ast.TypedID)
		}
	}

	if ctx.TryExpr() != nil {
		if result := ctx.TryExpr().Accept(v); result != nil {
			letSingle.Value = result.(ast.Expression)
			letSingle.IsTry = true
		}
	} else if ctx.Expr() != nil {
		if result := ctx.Expr().Accept(v); result != nil {
			letSingle.Value = result.(ast.Expression)
		}
	}

	return letSingle
}

func (v *ParseTreeToAST) VisitLetBlock(ctx *parser.LetBlockContext) interface{} {
	letBlock := &ast.LetBlock{
		BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
	}

	if ctx.LetBlockItemList() != nil {
		if result := ctx.LetBlockItemList().Accept(v); result != nil {
			letBlock.Items = result.([]ast.LetBlockItem)
		}
	}

	return letBlock
}

func (v *ParseTreeToAST) VisitLetBlockItemList(ctx *parser.LetBlockItemListContext) interface{} {
	var items []ast.LetBlockItem
	for _, itemCtx := range ctx.AllLetBlockItem() {
		if result := itemCtx.Accept(v); result != nil {
			items = append(items, result.(ast.LetBlockItem))
		}
	}
	return items
}

func (v *ParseTreeToAST) VisitLetBlockItem(ctx *parser.LetBlockItemContext) interface{} {
	for _, child := range ctx.GetChildren() {
		if ruleCtx, ok := child.(antlr.RuleContext); ok {
			return ruleCtx.Accept(v)
		}
	}
	return nil
}

func (v *ParseTreeToAST) VisitLabelLetBlockItemSingle(ctx *parser.LabelLetBlockItemSingleContext) interface{} {
	item := &ast.LetBlockItemSingle{
		BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
	}

	if ctx.TypedID() != nil {
		if result := ctx.TypedID().Accept(v); result != nil {
			item.ID = result.(ast.TypedID)
		}
	}

	if ctx.Expr() != nil {
		if result := ctx.Expr().Accept(v); result != nil {
			item.Value = result.(ast.Expression)
		}
	}

	return item
}

func (v *ParseTreeToAST) VisitLabelLetBlockItemDestructuredObj(ctx *parser.LabelLetBlockItemDestructuredObjContext) interface{} {
	item := &ast.LetBlockItemDestructuredObj{
		BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
	}

	if ctx.TypedIDList() != nil {
		if result := ctx.TypedIDList().Accept(v); result != nil {
			item.IDs = result.([]ast.TypedID)
		}
	}

	if ctx.Expr() != nil {
		if result := ctx.Expr().Accept(v); result != nil {
			item.Value = result.(ast.Expression)
		}
	}

	return item
}

func (v *ParseTreeToAST) VisitLabelLetBlockItemDestructuredArray(ctx *parser.LabelLetBlockItemDestructuredArrayContext) interface{} {
	item := &ast.LetBlockItemDestructuredArray{
		BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
	}

	if ctx.TypedIDList() != nil {
		if result := ctx.TypedIDList().Accept(v); result != nil {
			item.IDs = result.([]ast.TypedID)
		}
	}

	if ctx.Expr() != nil {
		if result := ctx.Expr().Accept(v); result != nil {
			item.Value = result.(ast.Expression)
		}
	}

	return item
}

func (v *ParseTreeToAST) VisitLetDestructuredObj(ctx *parser.LetDestructuredObjContext) interface{} {
	item := &ast.LetDestructuredObj{
		BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
	}

	if ctx.TypedIDList() != nil {
		if result := ctx.TypedIDList().Accept(v); result != nil {
			item.IDs = result.([]ast.TypedID)
		}
	}

	if ctx.Expr() != nil {
		if result := ctx.Expr().Accept(v); result != nil {
			item.Value = result.(ast.Expression)
		}
	}

	return item
}

func (v *ParseTreeToAST) VisitLetDestructuredArray(ctx *parser.LetDestructuredArrayContext) interface{} {
	item := &ast.LetDestructuredArray{
		BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
	}

	if ctx.TypedIDList() != nil {
		if result := ctx.TypedIDList().Accept(v); result != nil {
			item.IDs = result.([]ast.TypedID)
		}
	}

	if ctx.Expr() != nil {
		if result := ctx.Expr().Accept(v); result != nil {
			item.Value = result.(ast.Expression)
		}
	}

	return item
}
