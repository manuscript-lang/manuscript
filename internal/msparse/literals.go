package msparse

import (
	"manuscript-co/manuscript/internal/ast"
	"manuscript-co/manuscript/internal/parser"

	"github.com/antlr4-go/antlr/v4"
)

// String literals and interpolation

func (v *ParseTreeToAST) VisitSingleQuotedString(ctx *parser.SingleQuotedStringContext) interface{} {
	stringLit := &ast.StringLiteral{
		TypedNode: ast.TypedNode{BaseNode: ast.BaseNode{Position: v.getPosition(ctx)}},
		Kind:      ast.SingleQuoted,
	}

	for _, partCtx := range ctx.AllStringPart() {
		if part := partCtx.Accept(v); part != nil {
			stringLit.Parts = append(stringLit.Parts, part.(ast.StringPart))
		}
	}

	return stringLit
}

func (v *ParseTreeToAST) VisitMultiQuotedString(ctx *parser.MultiQuotedStringContext) interface{} {
	stringLit := &ast.StringLiteral{
		TypedNode: ast.TypedNode{BaseNode: ast.BaseNode{Position: v.getPosition(ctx)}},
		Kind:      ast.MultiQuoted,
	}

	for _, partCtx := range ctx.AllStringPart() {
		if part := partCtx.Accept(v); part != nil {
			stringLit.Parts = append(stringLit.Parts, part.(ast.StringPart))
		}
	}

	return stringLit
}

func (v *ParseTreeToAST) VisitDoubleQuotedString(ctx *parser.DoubleQuotedStringContext) interface{} {
	stringLit := &ast.StringLiteral{
		TypedNode: ast.TypedNode{BaseNode: ast.BaseNode{Position: v.getPosition(ctx)}},
		Kind:      ast.DoubleQuoted,
	}

	for _, partCtx := range ctx.AllStringPart() {
		if part := partCtx.Accept(v); part != nil {
			stringLit.Parts = append(stringLit.Parts, part.(ast.StringPart))
		}
	}

	return stringLit
}

func (v *ParseTreeToAST) VisitMultiDoubleQuotedString(ctx *parser.MultiDoubleQuotedStringContext) interface{} {
	stringLit := &ast.StringLiteral{
		TypedNode: ast.TypedNode{BaseNode: ast.BaseNode{Position: v.getPosition(ctx)}},
		Kind:      ast.MultiDoubleQuoted,
	}

	for _, partCtx := range ctx.AllStringPart() {
		if part := partCtx.Accept(v); part != nil {
			stringLit.Parts = append(stringLit.Parts, part.(ast.StringPart))
		}
	}

	return stringLit
}

func (v *ParseTreeToAST) VisitStringPart(ctx *parser.StringPartContext) interface{} {
	if ctx.SINGLE_STR_CONTENT() != nil {
		return &ast.StringContent{
			BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
			Content:  ctx.SINGLE_STR_CONTENT().GetText(),
		}
	} else if ctx.MULTI_STR_CONTENT() != nil {
		return &ast.StringContent{
			BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
			Content:  ctx.MULTI_STR_CONTENT().GetText(),
		}
	} else if ctx.DOUBLE_STR_CONTENT() != nil {
		return &ast.StringContent{
			BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
			Content:  ctx.DOUBLE_STR_CONTENT().GetText(),
		}
	} else if ctx.MULTI_DOUBLE_STR_CONTENT() != nil {
		return &ast.StringContent{
			BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
			Content:  ctx.MULTI_DOUBLE_STR_CONTENT().GetText(),
		}
	} else if ctx.Interpolation() != nil {
		return ctx.Interpolation().Accept(v)
	}
	return nil
}

func (v *ParseTreeToAST) VisitInterpolation(ctx *parser.InterpolationContext) interface{} {
	interpolation := &ast.StringInterpolation{
		BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
	}

	if ctx.Expr() != nil {
		if expr := ctx.Expr().Accept(v); expr != nil {
			interpolation.Expr = expr.(ast.Expression)
		}
	}

	return interpolation
}

// Literal visitors

func (v *ParseTreeToAST) VisitLabelLiteralString(ctx *parser.LabelLiteralStringContext) interface{} {
	return ctx.StringLiteral().Accept(v)
}

func (v *ParseTreeToAST) VisitLabelLiteralNumber(ctx *parser.LabelLiteralNumberContext) interface{} {
	return ctx.NumberLiteral().Accept(v)
}

func (v *ParseTreeToAST) VisitLabelLiteralBool(ctx *parser.LabelLiteralBoolContext) interface{} {
	return ctx.BooleanLiteral().Accept(v)
}

func (v *ParseTreeToAST) VisitLabelLiteralNull(ctx *parser.LabelLiteralNullContext) interface{} {
	return &ast.NullLiteral{
		TypedNode: ast.TypedNode{BaseNode: ast.BaseNode{Position: v.getPosition(ctx)}},
	}
}

func (v *ParseTreeToAST) VisitLabelLiteralVoid(ctx *parser.LabelLiteralVoidContext) interface{} {
	return &ast.VoidLiteral{
		TypedNode: ast.TypedNode{BaseNode: ast.BaseNode{Position: v.getPosition(ctx)}},
	}
}

func (v *ParseTreeToAST) VisitStringLiteral(ctx *parser.StringLiteralContext) interface{} {
	if ctx.SingleQuotedString() != nil {
		return ctx.SingleQuotedString().Accept(v)
	} else if ctx.MultiQuotedString() != nil {
		return ctx.MultiQuotedString().Accept(v)
	} else if ctx.DoubleQuotedString() != nil {
		return ctx.DoubleQuotedString().Accept(v)
	} else if ctx.MultiDoubleQuotedString() != nil {
		return ctx.MultiDoubleQuotedString().Accept(v)
	}
	return nil
}

// Number literals

func (v *ParseTreeToAST) VisitLabelNumberLiteralInt(ctx *parser.LabelNumberLiteralIntContext) interface{} {
	return &ast.NumberLiteral{
		TypedNode: ast.TypedNode{BaseNode: ast.BaseNode{Position: v.getPosition(ctx)}},
		Value:     ctx.INTEGER().GetText(),
		Kind:      ast.Integer,
	}
}

func (v *ParseTreeToAST) VisitLabelNumberLiteralFloat(ctx *parser.LabelNumberLiteralFloatContext) interface{} {
	return &ast.NumberLiteral{
		TypedNode: ast.TypedNode{BaseNode: ast.BaseNode{Position: v.getPosition(ctx)}},
		Value:     ctx.FLOAT().GetText(),
		Kind:      ast.Float,
	}
}

func (v *ParseTreeToAST) VisitLabelNumberLiteralHex(ctx *parser.LabelNumberLiteralHexContext) interface{} {
	return &ast.NumberLiteral{
		TypedNode: ast.TypedNode{BaseNode: ast.BaseNode{Position: v.getPosition(ctx)}},
		Value:     ctx.HEX_LITERAL().GetText(),
		Kind:      ast.Hex,
	}
}

func (v *ParseTreeToAST) VisitLabelNumberLiteralBin(ctx *parser.LabelNumberLiteralBinContext) interface{} {
	return &ast.NumberLiteral{
		TypedNode: ast.TypedNode{BaseNode: ast.BaseNode{Position: v.getPosition(ctx)}},
		Value:     ctx.BINARY_LITERAL().GetText(),
		Kind:      ast.Binary,
	}
}

func (v *ParseTreeToAST) VisitLabelNumberLiteralOct(ctx *parser.LabelNumberLiteralOctContext) interface{} {
	return &ast.NumberLiteral{
		TypedNode: ast.TypedNode{BaseNode: ast.BaseNode{Position: v.getPosition(ctx)}},
		Value:     ctx.OCTAL_LITERAL().GetText(),
		Kind:      ast.Octal,
	}
}

// Boolean literals

func (v *ParseTreeToAST) VisitLabelBoolLiteralTrue(ctx *parser.LabelBoolLiteralTrueContext) interface{} {
	return &ast.BooleanLiteral{
		TypedNode: ast.TypedNode{BaseNode: ast.BaseNode{Position: v.getPosition(ctx)}},
		Value:     true,
	}
}

func (v *ParseTreeToAST) VisitLabelBoolLiteralFalse(ctx *parser.LabelBoolLiteralFalseContext) interface{} {
	return &ast.BooleanLiteral{
		TypedNode: ast.TypedNode{BaseNode: ast.BaseNode{Position: v.getPosition(ctx)}},
		Value:     false,
	}
}

// Collection literals

func (v *ParseTreeToAST) VisitArrayLiteral(ctx *parser.ArrayLiteralContext) interface{} {
	arrayLit := &ast.ArrayLiteral{
		TypedNode: ast.TypedNode{BaseNode: ast.BaseNode{Position: v.getPosition(ctx)}},
	}

	if ctx.ExprList() != nil {
		if exprList := ctx.ExprList().Accept(v); exprList != nil {
			arrayLit.Elements = exprList.([]ast.Expression)
		}
	}

	return arrayLit
}

func (v *ParseTreeToAST) VisitObjectLiteral(ctx *parser.ObjectLiteralContext) interface{} {
	objectLit := &ast.ObjectLiteral{
		TypedNode: ast.TypedNode{BaseNode: ast.BaseNode{Position: v.getPosition(ctx)}},
	}

	if ctx.ObjectFieldList() != nil {
		if fieldList := ctx.ObjectFieldList().Accept(v); fieldList != nil {
			objectLit.Fields = fieldList.([]ast.ObjectField)
		}
	}

	return objectLit
}

func (v *ParseTreeToAST) VisitObjectFieldList(ctx *parser.ObjectFieldListContext) interface{} {
	var fields []ast.ObjectField
	for _, fieldCtx := range ctx.AllObjectField() {
		if field := fieldCtx.Accept(v); field != nil {
			fields = append(fields, field.(ast.ObjectField))
		}
	}
	return fields
}

func (v *ParseTreeToAST) VisitObjectField(ctx *parser.ObjectFieldContext) interface{} {
	field := ast.ObjectField{
		BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
	}

	if ctx.ObjectFieldName() != nil {
		if name := ctx.ObjectFieldName().Accept(v); name != nil {
			field.Name = name.(ast.ObjectFieldName)
		}
	}

	if ctx.Expr() != nil {
		if expr := ctx.Expr().Accept(v); expr != nil {
			field.Value = expr.(ast.Expression)
		}
	}

	return field
}

func (v *ParseTreeToAST) VisitLabelObjectFieldNameID(ctx *parser.LabelObjectFieldNameIDContext) interface{} {
	return &ast.ObjectFieldID{
		NamedNode: ast.NamedNode{
			BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
			Name:     ctx.ID().GetText(),
		},
	}
}

func (v *ParseTreeToAST) VisitLabelObjectFieldNameStr(ctx *parser.LabelObjectFieldNameStrContext) interface{} {
	fieldName := &ast.ObjectFieldString{
		BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
	}

	if ctx.StringLiteral() != nil {
		if strLit := ctx.StringLiteral().Accept(v); strLit != nil {
			fieldName.Literal = strLit.(*ast.StringLiteral)
		}
	}

	return fieldName
}

// ObjectFieldName visitor - was missing
func (v *ParseTreeToAST) VisitObjectFieldName(ctx *parser.ObjectFieldNameContext) interface{} {
	// The ObjectFieldName context is a base type that gets specialized into specific labeled contexts
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

// Map literals

func (v *ParseTreeToAST) VisitLabelMapLiteralEmpty(ctx *parser.LabelMapLiteralEmptyContext) interface{} {
	return &ast.MapLiteral{
		TypedNode: ast.TypedNode{BaseNode: ast.BaseNode{Position: v.getPosition(ctx)}},
		IsEmpty:   true,
	}
}

func (v *ParseTreeToAST) VisitLabelMapLiteralNonEmpty(ctx *parser.LabelMapLiteralNonEmptyContext) interface{} {
	mapLit := &ast.MapLiteral{
		TypedNode: ast.TypedNode{BaseNode: ast.BaseNode{Position: v.getPosition(ctx)}},
		IsEmpty:   false,
	}

	if ctx.MapFieldList() != nil {
		if fieldList := ctx.MapFieldList().Accept(v); fieldList != nil {
			mapLit.Fields = fieldList.([]ast.MapField)
		}
	}

	return mapLit
}

func (v *ParseTreeToAST) VisitMapFieldList(ctx *parser.MapFieldListContext) interface{} {
	var fields []ast.MapField
	for _, fieldCtx := range ctx.AllMapField() {
		if field := fieldCtx.Accept(v); field != nil {
			fields = append(fields, field.(ast.MapField))
		}
	}
	return fields
}

func (v *ParseTreeToAST) VisitMapField(ctx *parser.MapFieldContext) interface{} {
	field := ast.MapField{
		BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
	}

	exprs := ctx.AllExpr()
	if len(exprs) >= 2 {
		if key := exprs[0].Accept(v); key != nil {
			field.Key = key.(ast.Expression)
		}
		if value := exprs[1].Accept(v); value != nil {
			field.Value = value.(ast.Expression)
		}
	}

	return field
}

func (v *ParseTreeToAST) VisitSetLiteral(ctx *parser.SetLiteralContext) interface{} {
	setLit := &ast.SetLiteral{
		TypedNode: ast.TypedNode{BaseNode: ast.BaseNode{Position: v.getPosition(ctx)}},
	}

	for _, exprCtx := range ctx.AllExpr() {
		if expr := exprCtx.Accept(v); expr != nil {
			setLit.Elements = append(setLit.Elements, expr.(ast.Expression))
		}
	}

	return setLit
}

// MapLiteral visitor - was missing
func (v *ParseTreeToAST) VisitMapLiteral(ctx *parser.MapLiteralContext) interface{} {
	// The MapLiteral context is a base type that gets specialized into specific labeled contexts
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

// Tagged block strings

func (v *ParseTreeToAST) VisitTaggedBlockString(ctx *parser.TaggedBlockStringContext) interface{} {
	taggedBlock := &ast.TaggedBlockString{
		NamedNode: ast.NamedNode{
			BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
			Name:     ctx.ID().GetText(),
		},
	}

	if ctx.MultiQuotedString() != nil {
		if content := ctx.MultiQuotedString().Accept(v); content != nil {
			taggedBlock.Content = content.(*ast.StringLiteral)
		}
	} else if ctx.MultiDoubleQuotedString() != nil {
		if content := ctx.MultiDoubleQuotedString().Accept(v); content != nil {
			taggedBlock.Content = content.(*ast.StringLiteral)
		}
	}

	return taggedBlock
}

// Struct initialization

func (v *ParseTreeToAST) VisitStructInitExpr(ctx *parser.StructInitExprContext) interface{} {
	structInit := &ast.StructInitExpr{
		NamedNode: ast.NamedNode{
			BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
			Name:     ctx.ID().GetText(),
		},
	}

	if ctx.StructFieldList() != nil {
		if fieldList := ctx.StructFieldList().Accept(v); fieldList != nil {
			structInit.Fields = fieldList.([]ast.StructField)
		}
	}

	return structInit
}

func (v *ParseTreeToAST) VisitStructFieldList(ctx *parser.StructFieldListContext) interface{} {
	var fields []ast.StructField
	fieldNames := make(map[string]bool)

	for _, fieldCtx := range ctx.AllStructField() {
		if field := fieldCtx.Accept(v); field != nil {
			structField := field.(ast.StructField)

			// Check for duplicate field names
			if fieldNames[structField.Name] {
				// Note: In a real implementation, we might want to collect errors
				// For now, we'll skip duplicate fields
				continue
			}
			fieldNames[structField.Name] = true

			fields = append(fields, structField)
		}
	}
	return fields
}

func (v *ParseTreeToAST) VisitStructField(ctx *parser.StructFieldContext) interface{} {
	field := ast.StructField{
		NamedNode: ast.NamedNode{
			BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
			Name:     ctx.ID().GetText(),
		},
	}

	if ctx.Expr() != nil {
		if expr := ctx.Expr().Accept(v); expr != nil {
			field.Value = expr.(ast.Expression)
		}
	}

	return field
}

// Type annotations
// Helper visitors for rules that don't directly map to AST

func (v *ParseTreeToAST) VisitStmt_sep(ctx *parser.Stmt_sepContext) interface{} {
	// Statement separators don't need AST representation
	return nil
}

func (v *ParseTreeToAST) VisitLetBlockItemSep(ctx *parser.LetBlockItemSepContext) interface{} {
	// Item separators don't need AST representation
	return nil
}

func (v *ParseTreeToAST) VisitFieldList(ctx *parser.FieldListContext) interface{} {
	var fields []ast.FieldDecl
	for _, fieldCtx := range ctx.AllFieldDecl() {
		if field := fieldCtx.Accept(v); field != nil {
			fields = append(fields, field.(ast.FieldDecl))
		}
	}
	return fields
}

// NumberLiteral visitor - was missing
func (v *ParseTreeToAST) VisitNumberLiteral(ctx *parser.NumberLiteralContext) interface{} {
	// The NumberLiteral context is a base type that gets specialized into specific labeled contexts
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

// BooleanLiteral visitor - was missing
func (v *ParseTreeToAST) VisitBooleanLiteral(ctx *parser.BooleanLiteralContext) interface{} {
	// The BooleanLiteral context is a base type that gets specialized into specific labeled contexts
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

// Literal visitor - was missing
func (v *ParseTreeToAST) VisitLiteral(ctx *parser.LiteralContext) interface{} {
	// The Literal context is a base type that gets specialized into specific labeled contexts
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
