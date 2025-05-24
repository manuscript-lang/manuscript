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

func (v *BaseManuscriptVisitor) VisitLabelLetBlockItemSingle(ctx *LabelLetBlockItemSingleContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLabelLetBlockItemDestructuredObj(ctx *LabelLetBlockItemDestructuredObjContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLabelLetBlockItemDestructuredArray(ctx *LabelLetBlockItemDestructuredArrayContext) interface{} {
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

func (v *BaseManuscriptVisitor) VisitMethodImpl(ctx *MethodImplContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLabelStmtLet(ctx *LabelStmtLetContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLabelStmtExpr(ctx *LabelStmtExprContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLabelStmtReturn(ctx *LabelStmtReturnContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLabelStmtYield(ctx *LabelStmtYieldContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLabelStmtIf(ctx *LabelStmtIfContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLabelStmtFor(ctx *LabelStmtForContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLabelStmtWhile(ctx *LabelStmtWhileContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLabelStmtBlock(ctx *LabelStmtBlockContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLabelStmtBreak(ctx *LabelStmtBreakContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLabelStmtContinue(ctx *LabelStmtContinueContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLabelStmtCheck(ctx *LabelStmtCheckContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLabelStmtDefer(ctx *LabelStmtDeferContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLabelStmtTry(ctx *LabelStmtTryContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLabelStmtPiped(ctx *LabelStmtPipedContext) interface{} {
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

func (v *BaseManuscriptVisitor) VisitLabelForLoop(ctx *LabelForLoopContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLabelForInLoop(ctx *LabelForInLoopContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitForTrinity(ctx *ForTrinityContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLabelForInitLet(ctx *LabelForInitLetContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLabelForInitEmpty(ctx *LabelForInitEmptyContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLabelForCondExpr(ctx *LabelForCondExprContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLabelForCondEmpty(ctx *LabelForCondEmptyContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLabelForPostExpr(ctx *LabelForPostExprContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLabelForPostEmpty(ctx *LabelForPostEmptyContext) interface{} {
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

func (v *BaseManuscriptVisitor) VisitPipedStmt(ctx *PipedStmtContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitPipedArgs(ctx *PipedArgsContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitPipedArg(ctx *PipedArgContext) interface{} {
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

func (v *BaseManuscriptVisitor) VisitBitwiseXorExpr(ctx *BitwiseXorExprContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitBitwiseAndExpr(ctx *BitwiseAndExprContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitEqualityExpr(ctx *EqualityExprContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitComparisonOp(ctx *ComparisonOpContext) interface{} {
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

func (v *BaseManuscriptVisitor) VisitLabelUnaryOpExpr(ctx *LabelUnaryOpExprContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLabelUnaryPostfixExpr(ctx *LabelUnaryPostfixExprContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitPostfixExpr(ctx *PostfixExprContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLabelPostfixCall(ctx *LabelPostfixCallContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLabelPostfixDot(ctx *LabelPostfixDotContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLabelPostfixIndex(ctx *LabelPostfixIndexContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLabelPrimaryLiteral(ctx *LabelPrimaryLiteralContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLabelPrimaryID(ctx *LabelPrimaryIDContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLabelPrimaryParen(ctx *LabelPrimaryParenContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLabelPrimaryArray(ctx *LabelPrimaryArrayContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLabelPrimaryObject(ctx *LabelPrimaryObjectContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLabelPrimaryMap(ctx *LabelPrimaryMapContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLabelPrimarySet(ctx *LabelPrimarySetContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLabelPrimaryFn(ctx *LabelPrimaryFnContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLabelPrimaryMatch(ctx *LabelPrimaryMatchContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLabelPrimaryVoid(ctx *LabelPrimaryVoidContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLabelPrimaryNull(ctx *LabelPrimaryNullContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLabelPrimaryTaggedBlock(ctx *LabelPrimaryTaggedBlockContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLabelPrimaryStructInit(ctx *LabelPrimaryStructInitContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitTryExpr(ctx *TryExprContext) interface{} {
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

func (v *BaseManuscriptVisitor) VisitLabelLiteralString(ctx *LabelLiteralStringContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLabelLiteralNumber(ctx *LabelLiteralNumberContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLabelLiteralBool(ctx *LabelLiteralBoolContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLabelLiteralNull(ctx *LabelLiteralNullContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLabelLiteralVoid(ctx *LabelLiteralVoidContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitStringLiteral(ctx *StringLiteralContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLabelNumberLiteralInt(ctx *LabelNumberLiteralIntContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLabelNumberLiteralFloat(ctx *LabelNumberLiteralFloatContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLabelNumberLiteralHex(ctx *LabelNumberLiteralHexContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLabelNumberLiteralBin(ctx *LabelNumberLiteralBinContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLabelNumberLiteralOct(ctx *LabelNumberLiteralOctContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLabelBoolLiteralTrue(ctx *LabelBoolLiteralTrueContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLabelBoolLiteralFalse(ctx *LabelBoolLiteralFalseContext) interface{} {
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

func (v *BaseManuscriptVisitor) VisitLabelObjectFieldNameID(ctx *LabelObjectFieldNameIDContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLabelObjectFieldNameStr(ctx *LabelObjectFieldNameStrContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLabelMapLiteralEmpty(ctx *LabelMapLiteralEmptyContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLabelMapLiteralNonEmpty(ctx *LabelMapLiteralNonEmptyContext) interface{} {
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

func (v *BaseManuscriptVisitor) VisitLabelTypeAnnID(ctx *LabelTypeAnnIDContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLabelTypeAnnArray(ctx *LabelTypeAnnArrayContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLabelTypeAnnTuple(ctx *LabelTypeAnnTupleContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLabelTypeAnnFn(ctx *LabelTypeAnnFnContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseManuscriptVisitor) VisitLabelTypeAnnVoid(ctx *LabelTypeAnnVoidContext) interface{} {
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
