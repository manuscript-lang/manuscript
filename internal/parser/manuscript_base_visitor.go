// Code generated from Manuscript.g4 by ANTLR 4.13.1. DO NOT EDIT.

package parser // Manuscript

import "github.com/antlr4-go/antlr/v4"

type BaseManuscriptVisitor struct {
	*antlr.BaseParseTreeVisitor
}

func (v *BaseManuscriptVisitor) VisitProgram(ctx *ProgramContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitDeclaration(ctx *DeclarationContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitImportDecl(ctx *ImportDeclContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitExportDecl(ctx *ExportDeclContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitExternDecl(ctx *ExternDeclContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitExportedItem(ctx *ExportedItemContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitModuleImport(ctx *ModuleImportContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitDestructuredImport(ctx *DestructuredImportContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitTargetImport(ctx *TargetImportContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitImportItemList(ctx *ImportItemListContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitImportItem(ctx *ImportItemContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitImportStr(ctx *ImportStrContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLetDecl(ctx *LetDeclContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLetSingle(ctx *LetSingleContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLetBlock(ctx *LetBlockContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLetBlockItemList(ctx *LetBlockItemListContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLetBlockItemSep(ctx *LetBlockItemSepContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLetBlockItemSingle(ctx *LetBlockItemSingleContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLetBlockItemDestructuredObj(ctx *LetBlockItemDestructuredObjContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLetBlockItemDestructuredArray(ctx *LetBlockItemDestructuredArrayContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLetDestructuredObj(ctx *LetDestructuredObjContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLetDestructuredArray(ctx *LetDestructuredArrayContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitTypedIDList(ctx *TypedIDListContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitTypedID(ctx *TypedIDContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitTypeDecl(ctx *TypeDeclContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitTypeDefBody(ctx *TypeDefBodyContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitTypeAlias(ctx *TypeAliasContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitFieldList(ctx *FieldListContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitFieldDecl(ctx *FieldDeclContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitTypeList(ctx *TypeListContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitInterfaceDecl(ctx *InterfaceDeclContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitInterfaceMethod(ctx *InterfaceMethodContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitFnDecl(ctx *FnDeclContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitFnSignature(ctx *FnSignatureContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitParameters(ctx *ParametersContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitParam(ctx *ParamContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitMethodsDecl(ctx *MethodsDeclContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitMethodImplList(ctx *MethodImplListContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitMethodImplSep(ctx *MethodImplSepContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitMethodImpl(ctx *MethodImplContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitStmtLet(ctx *StmtLetContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitStmtExpr(ctx *StmtExprContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitStmtReturn(ctx *StmtReturnContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitStmtYield(ctx *StmtYieldContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitStmtIf(ctx *StmtIfContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitStmtFor(ctx *StmtForContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitStmtWhile(ctx *StmtWhileContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitStmtBlock(ctx *StmtBlockContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitStmtBreak(ctx *StmtBreakContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitStmtContinue(ctx *StmtContinueContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitStmtCheck(ctx *StmtCheckContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitStmtDefer(ctx *StmtDeferContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitReturnStmt(ctx *ReturnStmtContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitYieldStmt(ctx *YieldStmtContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitDeferStmt(ctx *DeferStmtContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitExprList(ctx *ExprListContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitIfStmt(ctx *IfStmtContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitForStmt(ctx *ForStmtContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitForLoop(ctx *ForLoopContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitForInLoop(ctx *ForInLoopContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitForTrinity(ctx *ForTrinityContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitForInit(ctx *ForInitContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitForCond(ctx *ForCondContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitForPost(ctx *ForPostContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitWhileStmt(ctx *WhileStmtContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLoopBody(ctx *LoopBodyContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitCodeBlock(ctx *CodeBlockContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitBreakStmt(ctx *BreakStmtContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitContinueStmt(ctx *ContinueStmtContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitCheckStmt(ctx *CheckStmtContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitExpr(ctx *ExprContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitAssignmentExpr(ctx *AssignmentExprContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitAssignmentOp(ctx *AssignmentOpContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitTernaryExpr(ctx *TernaryExprContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLogicalOrExpr(ctx *LogicalOrExprContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLogicalAndExpr(ctx *LogicalAndExprContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitBitwiseOrExpr(ctx *BitwiseOrExprContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitBitwiseXorExpr(ctx *BitwiseXorExprContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitBitwiseAndExpr(ctx *BitwiseAndExprContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitEqualityExpr(ctx *EqualityExprContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitComparisonExpr(ctx *ComparisonExprContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitShiftExpr(ctx *ShiftExprContext) interface{} {
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

func (v *BaseManuscriptVisitor) VisitPostfixOp(ctx *PostfixOpContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitPrimaryExpr(ctx *PrimaryExprContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitFnExpr(ctx *FnExprContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitMatchExpr(ctx *MatchExprContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitCaseClause(ctx *CaseClauseContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitDefaultClause(ctx *DefaultClauseContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitSingleQuotedString(ctx *SingleQuotedStringContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitMultiQuotedString(ctx *MultiQuotedStringContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitDoubleQuotedString(ctx *DoubleQuotedStringContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitMultiDoubleQuotedString(ctx *MultiDoubleQuotedStringContext) interface{} {
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

func (v *BaseManuscriptVisitor) VisitObjectFieldList(ctx *ObjectFieldListContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitObjectField(ctx *ObjectFieldContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitObjectFieldName(ctx *ObjectFieldNameContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitMapLiteral(ctx *MapLiteralContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitMapFieldList(ctx *MapFieldListContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitMapField(ctx *MapFieldContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitSetLiteral(ctx *SetLiteralContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitTaggedBlockString(ctx *TaggedBlockStringContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitStructInitExpr(ctx *StructInitExprContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitStructFieldList(ctx *StructFieldListContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitStructField(ctx *StructFieldContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitTypeAnnotation(ctx *TypeAnnotationContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitTupleType(ctx *TupleTypeContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitArrayType(ctx *ArrayTypeContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitFnType(ctx *FnTypeContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitStmt_sep(ctx *Stmt_sepContext) interface{} {
	return v.VisitChildren(ctx)
}
