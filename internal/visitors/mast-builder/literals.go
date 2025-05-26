package mastb

import (
	"manuscript-lang/manuscript/internal/ast"
	"manuscript-lang/manuscript/internal/parser"

	"github.com/antlr4-go/antlr/v4"
)

// String literals and interpolation

func (v *ParseTreeToAST) createTypedNode(ctx antlr.ParserRuleContext) ast.TypedNode {
	return ast.TypedNode{BaseNode: ast.BaseNode{Position: v.getPosition(ctx)}}
}

func (v *ParseTreeToAST) createNamedNode(ctx antlr.ParserRuleContext, name string) ast.NamedNode {
	return ast.NamedNode{
		BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
		Name:     name,
	}
}

func (v *ParseTreeToAST) createStringLiteral(ctx antlr.ParserRuleContext, kind ast.StringKind) *ast.StringLiteral {
	return &ast.StringLiteral{
		TypedNode: v.createTypedNode(ctx),
		Kind:      kind,
	}
}

func (v *ParseTreeToAST) addStringParts(stringLit *ast.StringLiteral, parts []parser.IStringPartContext) {
	for _, partCtx := range parts {
		if part := partCtx.Accept(v); part != nil {
			stringLit.Parts = append(stringLit.Parts, part.(ast.StringPart))
		}
	}
}

func (v *ParseTreeToAST) createStringContent(ctx antlr.ParserRuleContext, content string) *ast.StringContent {
	return &ast.StringContent{
		BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
		Content:  content,
	}
}

func (v *ParseTreeToAST) createNumberLiteral(ctx antlr.ParserRuleContext, value string, kind ast.NumberKind) *ast.NumberLiteral {
	return &ast.NumberLiteral{
		TypedNode: v.createTypedNode(ctx),
		Value:     value,
		Kind:      kind,
	}
}

func (v *ParseTreeToAST) createBooleanLiteral(ctx antlr.ParserRuleContext, value bool) *ast.BooleanLiteral {
	return &ast.BooleanLiteral{
		TypedNode: v.createTypedNode(ctx),
		Value:     value,
	}
}

func (v *ParseTreeToAST) delegateToChild(ctx antlr.ParserRuleContext) interface{} {
	for _, child := range ctx.GetChildren() {
		if ruleCtx, ok := child.(antlr.RuleContext); ok {
			return ruleCtx.Accept(v)
		}
	}
	return nil
}

func (v *ParseTreeToAST) acceptOptional(ctx antlr.ParserRuleContext) interface{} {
	if ctx != nil {
		return ctx.Accept(v)
	}
	return nil
}

func (v *ParseTreeToAST) createStringLiteralWithParts(ctx antlr.ParserRuleContext, kind ast.StringKind, parts []parser.IStringPartContext) *ast.StringLiteral {
	stringLit := v.createStringLiteral(ctx, kind)
	v.addStringParts(stringLit, parts)
	return stringLit
}

func (v *ParseTreeToAST) VisitSingleQuotedString(ctx *parser.SingleQuotedStringContext) interface{} {
	return v.createStringLiteralWithParts(ctx, ast.SingleQuoted, ctx.AllStringPart())
}

func (v *ParseTreeToAST) VisitMultiQuotedString(ctx *parser.MultiQuotedStringContext) interface{} {
	return v.createStringLiteralWithParts(ctx, ast.MultiQuoted, ctx.AllStringPart())
}

func (v *ParseTreeToAST) VisitDoubleQuotedString(ctx *parser.DoubleQuotedStringContext) interface{} {
	return v.createStringLiteralWithParts(ctx, ast.DoubleQuoted, ctx.AllStringPart())
}

func (v *ParseTreeToAST) VisitMultiDoubleQuotedString(ctx *parser.MultiDoubleQuotedStringContext) interface{} {
	return v.createStringLiteralWithParts(ctx, ast.MultiDoubleQuoted, ctx.AllStringPart())
}

func (v *ParseTreeToAST) VisitStringPart(ctx *parser.StringPartContext) interface{} {
	switch {
	case ctx.SINGLE_STR_CONTENT() != nil:
		return v.createStringContent(ctx, ctx.SINGLE_STR_CONTENT().GetText())
	case ctx.MULTI_STR_CONTENT() != nil:
		return v.createStringContent(ctx, ctx.MULTI_STR_CONTENT().GetText())
	case ctx.DOUBLE_STR_CONTENT() != nil:
		return v.createStringContent(ctx, ctx.DOUBLE_STR_CONTENT().GetText())
	case ctx.MULTI_DOUBLE_STR_CONTENT() != nil:
		return v.createStringContent(ctx, ctx.MULTI_DOUBLE_STR_CONTENT().GetText())
	case ctx.Interpolation() != nil:
		return ctx.Interpolation().Accept(v)
	}
	return nil
}

func (v *ParseTreeToAST) VisitInterpolation(ctx *parser.InterpolationContext) interface{} {
	interpolation := &ast.StringInterpolation{
		BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
	}

	if expr := v.acceptOptional(ctx.Expr()); expr != nil {
		interpolation.Expr = expr.(ast.Expression)
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
	return &ast.NullLiteral{TypedNode: v.createTypedNode(ctx)}
}

func (v *ParseTreeToAST) VisitLabelLiteralVoid(ctx *parser.LabelLiteralVoidContext) interface{} {
	return &ast.VoidLiteral{TypedNode: v.createTypedNode(ctx)}
}

func (v *ParseTreeToAST) VisitStringLiteral(ctx *parser.StringLiteralContext) interface{} {
	switch {
	case ctx.SingleQuotedString() != nil:
		return ctx.SingleQuotedString().Accept(v)
	case ctx.MultiQuotedString() != nil:
		return ctx.MultiQuotedString().Accept(v)
	case ctx.DoubleQuotedString() != nil:
		return ctx.DoubleQuotedString().Accept(v)
	case ctx.MultiDoubleQuotedString() != nil:
		return ctx.MultiDoubleQuotedString().Accept(v)
	}
	return nil
}

// Number literals

func (v *ParseTreeToAST) VisitLabelNumberLiteralInt(ctx *parser.LabelNumberLiteralIntContext) interface{} {
	return v.createNumberLiteral(ctx, ctx.INTEGER().GetText(), ast.Integer)
}

func (v *ParseTreeToAST) VisitLabelNumberLiteralFloat(ctx *parser.LabelNumberLiteralFloatContext) interface{} {
	return v.createNumberLiteral(ctx, ctx.FLOAT().GetText(), ast.Float)
}

func (v *ParseTreeToAST) VisitLabelNumberLiteralHex(ctx *parser.LabelNumberLiteralHexContext) interface{} {
	return v.createNumberLiteral(ctx, ctx.HEX_LITERAL().GetText(), ast.Hex)
}

func (v *ParseTreeToAST) VisitLabelNumberLiteralBin(ctx *parser.LabelNumberLiteralBinContext) interface{} {
	return v.createNumberLiteral(ctx, ctx.BINARY_LITERAL().GetText(), ast.Binary)
}

func (v *ParseTreeToAST) VisitLabelNumberLiteralOct(ctx *parser.LabelNumberLiteralOctContext) interface{} {
	return v.createNumberLiteral(ctx, ctx.OCTAL_LITERAL().GetText(), ast.Octal)
}

// Boolean literals

func (v *ParseTreeToAST) VisitLabelBoolLiteralTrue(ctx *parser.LabelBoolLiteralTrueContext) interface{} {
	return v.createBooleanLiteral(ctx, true)
}

func (v *ParseTreeToAST) VisitLabelBoolLiteralFalse(ctx *parser.LabelBoolLiteralFalseContext) interface{} {
	return v.createBooleanLiteral(ctx, false)
}

// Collection literals

func (v *ParseTreeToAST) VisitArrayLiteral(ctx *parser.ArrayLiteralContext) interface{} {
	arrayLit := &ast.ArrayLiteral{TypedNode: v.createTypedNode(ctx)}

	if exprList := v.acceptOptional(ctx.ExprList()); exprList != nil {
		arrayLit.Elements = exprList.([]ast.Expression)
	}

	return arrayLit
}

func (v *ParseTreeToAST) VisitObjectLiteral(ctx *parser.ObjectLiteralContext) interface{} {
	objectLit := &ast.ObjectLiteral{TypedNode: v.createTypedNode(ctx)}

	if fieldList := v.acceptOptional(ctx.ObjectFieldList()); fieldList != nil {
		objectLit.Fields = fieldList.([]ast.ObjectField)
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

	if name := v.acceptOptional(ctx.ObjectFieldName()); name != nil {
		field.Name = name.(ast.ObjectFieldName)
	}

	if expr := v.acceptOptional(ctx.Expr()); expr != nil {
		field.Value = expr.(ast.Expression)
	}

	return field
}

func (v *ParseTreeToAST) VisitLabelObjectFieldNameID(ctx *parser.LabelObjectFieldNameIDContext) interface{} {
	return &ast.ObjectFieldID{
		NamedNode: v.createNamedNode(ctx, ctx.ID().GetText()),
	}
}

func (v *ParseTreeToAST) VisitLabelObjectFieldNameStr(ctx *parser.LabelObjectFieldNameStrContext) interface{} {
	fieldName := &ast.ObjectFieldString{
		BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
	}

	if strLit := v.acceptOptional(ctx.StringLiteral()); strLit != nil {
		fieldName.Literal = strLit.(*ast.StringLiteral)
	}

	return fieldName
}

func (v *ParseTreeToAST) VisitObjectFieldName(ctx *parser.ObjectFieldNameContext) interface{} {
	return v.delegateToChild(ctx)
}

// Map literals

func (v *ParseTreeToAST) VisitLabelMapLiteralEmpty(ctx *parser.LabelMapLiteralEmptyContext) interface{} {
	return &ast.MapLiteral{
		TypedNode: v.createTypedNode(ctx),
		IsEmpty:   true,
	}
}

func (v *ParseTreeToAST) VisitLabelMapLiteralNonEmpty(ctx *parser.LabelMapLiteralNonEmptyContext) interface{} {
	mapLit := &ast.MapLiteral{
		TypedNode: v.createTypedNode(ctx),
		IsEmpty:   false,
	}

	if fieldList := v.acceptOptional(ctx.MapFieldList()); fieldList != nil {
		mapLit.Fields = fieldList.([]ast.MapField)
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
	setLit := &ast.SetLiteral{TypedNode: v.createTypedNode(ctx)}

	for _, exprCtx := range ctx.AllExpr() {
		if expr := exprCtx.Accept(v); expr != nil {
			setLit.Elements = append(setLit.Elements, expr.(ast.Expression))
		}
	}

	return setLit
}

func (v *ParseTreeToAST) VisitMapLiteral(ctx *parser.MapLiteralContext) interface{} {
	return v.delegateToChild(ctx)
}

// Tagged block strings

func (v *ParseTreeToAST) VisitTaggedBlockString(ctx *parser.TaggedBlockStringContext) interface{} {
	taggedBlock := &ast.TaggedBlockString{
		NamedNode: v.createNamedNode(ctx, ctx.ID().GetText()),
	}

	switch {
	case ctx.MultiQuotedString() != nil:
		if content := ctx.MultiQuotedString().Accept(v); content != nil {
			taggedBlock.Content = content.(*ast.StringLiteral)
		}
	case ctx.MultiDoubleQuotedString() != nil:
		if content := ctx.MultiDoubleQuotedString().Accept(v); content != nil {
			taggedBlock.Content = content.(*ast.StringLiteral)
		}
	}

	return taggedBlock
}

// Struct initialization

func (v *ParseTreeToAST) VisitStructInitExpr(ctx *parser.StructInitExprContext) interface{} {
	structInit := &ast.StructInitExpr{
		NamedNode: v.createNamedNode(ctx, ctx.ID().GetText()),
	}

	if fieldList := v.acceptOptional(ctx.StructFieldList()); fieldList != nil {
		structInit.Fields = fieldList.([]ast.StructField)
	}

	return structInit
}

func (v *ParseTreeToAST) VisitStructFieldList(ctx *parser.StructFieldListContext) interface{} {
	var fields []ast.StructField
	fieldNames := make(map[string]bool)

	for _, fieldCtx := range ctx.AllStructField() {
		if field := fieldCtx.Accept(v); field != nil {
			structField := field.(ast.StructField)

			if fieldNames[structField.Name] {
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
		NamedNode: v.createNamedNode(ctx, ctx.ID().GetText()),
	}

	if expr := v.acceptOptional(ctx.Expr()); expr != nil {
		field.Value = expr.(ast.Expression)
	}

	return field
}

// Typed object literal

func (v *ParseTreeToAST) VisitTypedObjectLiteral(ctx *parser.TypedObjectLiteralContext) interface{} {
	typedObjLit := &ast.TypedObjectLiteral{
		NamedNode: v.createNamedNode(ctx, ctx.ID().GetText()),
	}

	if fieldList := v.acceptOptional(ctx.ObjectFieldList()); fieldList != nil {
		typedObjLit.Fields = fieldList.([]ast.ObjectField)
	}

	return typedObjLit
}

// Type annotations
// Helper visitors for rules that don't directly map to AST

func (v *ParseTreeToAST) VisitStmt_sep(ctx *parser.Stmt_sepContext) interface{} {
	return nil
}

func (v *ParseTreeToAST) VisitLetBlockItemSep(ctx *parser.LetBlockItemSepContext) interface{} {
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

func (v *ParseTreeToAST) VisitNumberLiteral(ctx *parser.NumberLiteralContext) interface{} {
	return v.delegateToChild(ctx)
}

func (v *ParseTreeToAST) VisitBooleanLiteral(ctx *parser.BooleanLiteralContext) interface{} {
	return v.delegateToChild(ctx)
}

func (v *ParseTreeToAST) VisitLiteral(ctx *parser.LiteralContext) interface{} {
	return v.delegateToChild(ctx)
}
