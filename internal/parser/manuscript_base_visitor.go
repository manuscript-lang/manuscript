// Code generated from Manuscript.g4 by ANTLR 4.13.1. DO NOT EDIT.

package parser // Manuscript

import "github.com/antlr4-go/antlr/v4"

type BaseManuscriptVisitor struct {
	*antlr.BaseParseTreeVisitor
}

func (v *BaseManuscriptVisitor) VisitProgram(ctx *ProgramContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitProgramItem(ctx *ProgramItemContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitImportStmt(ctx *ImportStmtContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitImportItem(ctx *ImportItemContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitExternStmt(ctx *ExternStmtContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitExternItem(ctx *ExternItemContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitExportStmt(ctx *ExportStmtContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLetDecl(ctx *LetDeclContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLetAssignment(ctx *LetAssignmentContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLetPattern(ctx *LetPatternContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitArrayPattn(ctx *ArrayPattnContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitObjectPattn(ctx *ObjectPattnContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitFnDecl(ctx *FnDeclContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitParameters(ctx *ParametersContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitParam(ctx *ParamContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitTypeDecl(ctx *TypeDeclContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitFieldDecl(ctx *FieldDeclContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitIfaceDecl(ctx *IfaceDeclContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitMethodDecl(ctx *MethodDeclContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitMethodBlockDecl(ctx *MethodBlockDeclContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitMethodImpl(ctx *MethodImplContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitTypeAnnotation(ctx *TypeAnnotationContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitBaseTypeAnnotation(ctx *BaseTypeAnnotationContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitFunctionType(ctx *FunctionTypeContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitStmt(ctx *StmtContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitExprStmt(ctx *ExprStmtContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitReturnStmt(ctx *ReturnStmtContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitYieldStmt(ctx *YieldStmtContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitIfStmt(ctx *IfStmtContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitForStmt(ctx *ForStmtContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitForInitPattn(ctx *ForInitPattnContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLoopPattern(ctx *LoopPatternContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitWhileStmt(ctx *WhileStmtContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitCodeBlock(ctx *CodeBlockContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitExpr(ctx *ExprContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitAssignmentExpr(ctx *AssignmentExprContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLogicalOrExpr(ctx *LogicalOrExprContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLogicalAndExpr(ctx *LogicalAndExprContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitEqualityExpr(ctx *EqualityExprContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitComparisonExpr(ctx *ComparisonExprContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitAdditiveExpr(ctx *AdditiveExprContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitMultiplicativeExpr(ctx *MultiplicativeExprContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitUnaryExpr(ctx *UnaryExprContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitAwaitExpr(ctx *AwaitExprContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitPostfixExpr(ctx *PostfixExprContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitPrimaryExpr(ctx *PrimaryExprContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitFnExpr(ctx *FnExprContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLambdaExpr(ctx *LambdaExprContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitTryBlockExpr(ctx *TryBlockExprContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitMatchExpr(ctx *MatchExprContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitCaseClause(ctx *CaseClauseContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitSingleQuotedString(ctx *SingleQuotedStringContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitMultiQuotedString(ctx *MultiQuotedStringContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitStringPart(ctx *StringPartContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitInterpolation(ctx *InterpolationContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLiteral(ctx *LiteralContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitStringLiteral(ctx *StringLiteralContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitNumberLiteral(ctx *NumberLiteralContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitBooleanLiteral(ctx *BooleanLiteralContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitArrayLiteral(ctx *ArrayLiteralContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitObjectLiteral(ctx *ObjectLiteralContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitObjectField(ctx *ObjectFieldContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitMapLiteral(ctx *MapLiteralContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitMapField(ctx *MapFieldContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitSetLiteral(ctx *SetLiteralContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitTupleLiteral(ctx *TupleLiteralContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitImportStr(ctx *ImportStrContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitTupleType(ctx *TupleTypeContext) interface{} {
	return v.VisitChildren(ctx)
}
