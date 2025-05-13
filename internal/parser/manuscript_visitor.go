// Code generated from Manuscript.g4 by ANTLR 4.13.1. DO NOT EDIT.

package parser // Manuscript

import "github.com/antlr4-go/antlr/v4"

// A complete Visitor for a parse tree produced by Manuscript.
type ManuscriptVisitor interface {
	antlr.ParseTreeVisitor

	// Visit a parse tree produced by Manuscript#program.
	VisitProgram(ctx *ProgramContext) interface{}

	// Visit a parse tree produced by Manuscript#programItem.
	VisitProgramItem(ctx *ProgramItemContext) interface{}

	// Visit a parse tree produced by Manuscript#importStmt.
	VisitImportStmt(ctx *ImportStmtContext) interface{}

	// Visit a parse tree produced by Manuscript#importItem.
	VisitImportItem(ctx *ImportItemContext) interface{}

	// Visit a parse tree produced by Manuscript#externStmt.
	VisitExternStmt(ctx *ExternStmtContext) interface{}

	// Visit a parse tree produced by Manuscript#externItem.
	VisitExternItem(ctx *ExternItemContext) interface{}

	// Visit a parse tree produced by Manuscript#exportStmt.
	VisitExportStmt(ctx *ExportStmtContext) interface{}

	// Visit a parse tree produced by Manuscript#letDecl.
	VisitLetDecl(ctx *LetDeclContext) interface{}

	// Visit a parse tree produced by Manuscript#letAssignment.
	VisitLetAssignment(ctx *LetAssignmentContext) interface{}

	// Visit a parse tree produced by Manuscript#letPattern.
	VisitLetPattern(ctx *LetPatternContext) interface{}

	// Visit a parse tree produced by Manuscript#arrayPattn.
	VisitArrayPattn(ctx *ArrayPattnContext) interface{}

	// Visit a parse tree produced by Manuscript#objectPattn.
	VisitObjectPattn(ctx *ObjectPattnContext) interface{}

	// Visit a parse tree produced by Manuscript#fnDecl.
	VisitFnDecl(ctx *FnDeclContext) interface{}

	// Visit a parse tree produced by Manuscript#parameters.
	VisitParameters(ctx *ParametersContext) interface{}

	// Visit a parse tree produced by Manuscript#param.
	VisitParam(ctx *ParamContext) interface{}

	// Visit a parse tree produced by Manuscript#typeDecl.
	VisitTypeDecl(ctx *TypeDeclContext) interface{}

	// Visit a parse tree produced by Manuscript#fieldDecl.
	VisitFieldDecl(ctx *FieldDeclContext) interface{}

	// Visit a parse tree produced by Manuscript#ifaceDecl.
	VisitIfaceDecl(ctx *IfaceDeclContext) interface{}

	// Visit a parse tree produced by Manuscript#methodDecl.
	VisitMethodDecl(ctx *MethodDeclContext) interface{}

	// Visit a parse tree produced by Manuscript#methodBlockDecl.
	VisitMethodBlockDecl(ctx *MethodBlockDeclContext) interface{}

	// Visit a parse tree produced by Manuscript#methodImpl.
	VisitMethodImpl(ctx *MethodImplContext) interface{}

	// Visit a parse tree produced by Manuscript#typeAnnotation.
	VisitTypeAnnotation(ctx *TypeAnnotationContext) interface{}

	// Visit a parse tree produced by Manuscript#baseTypeAnnotation.
	VisitBaseTypeAnnotation(ctx *BaseTypeAnnotationContext) interface{}

	// Visit a parse tree produced by Manuscript#functionType.
	VisitFunctionType(ctx *FunctionTypeContext) interface{}

	// Visit a parse tree produced by Manuscript#stmt.
	VisitStmt(ctx *StmtContext) interface{}

	// Visit a parse tree produced by Manuscript#exprStmt.
	VisitExprStmt(ctx *ExprStmtContext) interface{}

	// Visit a parse tree produced by Manuscript#returnStmt.
	VisitReturnStmt(ctx *ReturnStmtContext) interface{}

	// Visit a parse tree produced by Manuscript#yieldStmt.
	VisitYieldStmt(ctx *YieldStmtContext) interface{}

	// Visit a parse tree produced by Manuscript#ifStmt.
	VisitIfStmt(ctx *IfStmtContext) interface{}

	// Visit a parse tree produced by Manuscript#forStmt.
	VisitForStmt(ctx *ForStmtContext) interface{}

	// Visit a parse tree produced by Manuscript#forInitPattn.
	VisitForInitPattn(ctx *ForInitPattnContext) interface{}

	// Visit a parse tree produced by Manuscript#loopPattern.
	VisitLoopPattern(ctx *LoopPatternContext) interface{}

	// Visit a parse tree produced by Manuscript#whileStmt.
	VisitWhileStmt(ctx *WhileStmtContext) interface{}

	// Visit a parse tree produced by Manuscript#codeBlock.
	VisitCodeBlock(ctx *CodeBlockContext) interface{}

	// Visit a parse tree produced by Manuscript#expr.
	VisitExpr(ctx *ExprContext) interface{}

	// Visit a parse tree produced by Manuscript#assignmentExpr.
	VisitAssignmentExpr(ctx *AssignmentExprContext) interface{}

	// Visit a parse tree produced by Manuscript#logicalOrExpr.
	VisitLogicalOrExpr(ctx *LogicalOrExprContext) interface{}

	// Visit a parse tree produced by Manuscript#logicalAndExpr.
	VisitLogicalAndExpr(ctx *LogicalAndExprContext) interface{}

	// Visit a parse tree produced by Manuscript#equalityExpr.
	VisitEqualityExpr(ctx *EqualityExprContext) interface{}

	// Visit a parse tree produced by Manuscript#comparisonExpr.
	VisitComparisonExpr(ctx *ComparisonExprContext) interface{}

	// Visit a parse tree produced by Manuscript#additiveExpr.
	VisitAdditiveExpr(ctx *AdditiveExprContext) interface{}

	// Visit a parse tree produced by Manuscript#multiplicativeExpr.
	VisitMultiplicativeExpr(ctx *MultiplicativeExprContext) interface{}

	// Visit a parse tree produced by Manuscript#unaryExpr.
	VisitUnaryExpr(ctx *UnaryExprContext) interface{}

	// Visit a parse tree produced by Manuscript#awaitExpr.
	VisitAwaitExpr(ctx *AwaitExprContext) interface{}

	// Visit a parse tree produced by Manuscript#postfixExpr.
	VisitPostfixExpr(ctx *PostfixExprContext) interface{}

	// Visit a parse tree produced by Manuscript#primaryExpr.
	VisitPrimaryExpr(ctx *PrimaryExprContext) interface{}

	// Visit a parse tree produced by Manuscript#fnExpr.
	VisitFnExpr(ctx *FnExprContext) interface{}

	// Visit a parse tree produced by Manuscript#lambdaExpr.
	VisitLambdaExpr(ctx *LambdaExprContext) interface{}

	// Visit a parse tree produced by Manuscript#tryBlockExpr.
	VisitTryBlockExpr(ctx *TryBlockExprContext) interface{}

	// Visit a parse tree produced by Manuscript#matchExpr.
	VisitMatchExpr(ctx *MatchExprContext) interface{}

	// Visit a parse tree produced by Manuscript#caseClause.
	VisitCaseClause(ctx *CaseClauseContext) interface{}

	// Visit a parse tree produced by Manuscript#singleQuotedString.
	VisitSingleQuotedString(ctx *SingleQuotedStringContext) interface{}

	// Visit a parse tree produced by Manuscript#multiQuotedString.
	VisitMultiQuotedString(ctx *MultiQuotedStringContext) interface{}

	// Visit a parse tree produced by Manuscript#stringPart.
	VisitStringPart(ctx *StringPartContext) interface{}

	// Visit a parse tree produced by Manuscript#interpolation.
	VisitInterpolation(ctx *InterpolationContext) interface{}

	// Visit a parse tree produced by Manuscript#literal.
	VisitLiteral(ctx *LiteralContext) interface{}

	// Visit a parse tree produced by Manuscript#stringLiteral.
	VisitStringLiteral(ctx *StringLiteralContext) interface{}

	// Visit a parse tree produced by Manuscript#numberLiteral.
	VisitNumberLiteral(ctx *NumberLiteralContext) interface{}

	// Visit a parse tree produced by Manuscript#booleanLiteral.
	VisitBooleanLiteral(ctx *BooleanLiteralContext) interface{}

	// Visit a parse tree produced by Manuscript#arrayLiteral.
	VisitArrayLiteral(ctx *ArrayLiteralContext) interface{}

	// Visit a parse tree produced by Manuscript#objectLiteral.
	VisitObjectLiteral(ctx *ObjectLiteralContext) interface{}

	// Visit a parse tree produced by Manuscript#objectField.
	VisitObjectField(ctx *ObjectFieldContext) interface{}

	// Visit a parse tree produced by Manuscript#mapLiteral.
	VisitMapLiteral(ctx *MapLiteralContext) interface{}

	// Visit a parse tree produced by Manuscript#mapField.
	VisitMapField(ctx *MapFieldContext) interface{}

	// Visit a parse tree produced by Manuscript#setLiteral.
	VisitSetLiteral(ctx *SetLiteralContext) interface{}

	// Visit a parse tree produced by Manuscript#tupleLiteral.
	VisitTupleLiteral(ctx *TupleLiteralContext) interface{}

	// Visit a parse tree produced by Manuscript#importStr.
	VisitImportStr(ctx *ImportStrContext) interface{}

	// Visit a parse tree produced by Manuscript#tupleType.
	VisitTupleType(ctx *TupleTypeContext) interface{}
}
