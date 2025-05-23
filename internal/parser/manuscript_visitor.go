// Code generated from Manuscript.g4 by ANTLR 4.13.1. DO NOT EDIT.

package parser // Manuscript

import "github.com/antlr4-go/antlr/v4"

// A complete Visitor for a parse tree produced by Manuscript.
type ManuscriptVisitor interface {
	antlr.ParseTreeVisitor

	// Visit a parse tree produced by Manuscript#program.
	VisitProgram(ctx *ProgramContext) interface{}

	// Visit a parse tree produced by Manuscript#declaration.
	VisitDeclaration(ctx *DeclarationContext) interface{}

	// Visit a parse tree produced by Manuscript#importDecl.
	VisitImportDecl(ctx *ImportDeclContext) interface{}

	// Visit a parse tree produced by Manuscript#exportDecl.
	VisitExportDecl(ctx *ExportDeclContext) interface{}

	// Visit a parse tree produced by Manuscript#externDecl.
	VisitExternDecl(ctx *ExternDeclContext) interface{}

	// Visit a parse tree produced by Manuscript#exportedItem.
	VisitExportedItem(ctx *ExportedItemContext) interface{}

	// Visit a parse tree produced by Manuscript#moduleImport.
	VisitModuleImport(ctx *ModuleImportContext) interface{}

	// Visit a parse tree produced by Manuscript#destructuredImport.
	VisitDestructuredImport(ctx *DestructuredImportContext) interface{}

	// Visit a parse tree produced by Manuscript#targetImport.
	VisitTargetImport(ctx *TargetImportContext) interface{}

	// Visit a parse tree produced by Manuscript#importItemList.
	VisitImportItemList(ctx *ImportItemListContext) interface{}

	// Visit a parse tree produced by Manuscript#importItem.
	VisitImportItem(ctx *ImportItemContext) interface{}

	// Visit a parse tree produced by Manuscript#letDecl.
	VisitLetDecl(ctx *LetDeclContext) interface{}

	// Visit a parse tree produced by Manuscript#letSingle.
	VisitLetSingle(ctx *LetSingleContext) interface{}

	// Visit a parse tree produced by Manuscript#letBlock.
	VisitLetBlock(ctx *LetBlockContext) interface{}

	// Visit a parse tree produced by Manuscript#letBlockItemList.
	VisitLetBlockItemList(ctx *LetBlockItemListContext) interface{}

	// Visit a parse tree produced by Manuscript#letBlockItemSep.
	VisitLetBlockItemSep(ctx *LetBlockItemSepContext) interface{}

	// Visit a parse tree produced by Manuscript#LabelLetBlockItemSingle.
	VisitLabelLetBlockItemSingle(ctx *LabelLetBlockItemSingleContext) interface{}

	// Visit a parse tree produced by Manuscript#LabelLetBlockItemDestructuredObj.
	VisitLabelLetBlockItemDestructuredObj(ctx *LabelLetBlockItemDestructuredObjContext) interface{}

	// Visit a parse tree produced by Manuscript#LabelLetBlockItemDestructuredArray.
	VisitLabelLetBlockItemDestructuredArray(ctx *LabelLetBlockItemDestructuredArrayContext) interface{}

	// Visit a parse tree produced by Manuscript#letDestructuredObj.
	VisitLetDestructuredObj(ctx *LetDestructuredObjContext) interface{}

	// Visit a parse tree produced by Manuscript#letDestructuredArray.
	VisitLetDestructuredArray(ctx *LetDestructuredArrayContext) interface{}

	// Visit a parse tree produced by Manuscript#typedIDList.
	VisitTypedIDList(ctx *TypedIDListContext) interface{}

	// Visit a parse tree produced by Manuscript#typedID.
	VisitTypedID(ctx *TypedIDContext) interface{}

	// Visit a parse tree produced by Manuscript#typeDecl.
	VisitTypeDecl(ctx *TypeDeclContext) interface{}

	// Visit a parse tree produced by Manuscript#typeDefBody.
	VisitTypeDefBody(ctx *TypeDefBodyContext) interface{}

	// Visit a parse tree produced by Manuscript#typeAlias.
	VisitTypeAlias(ctx *TypeAliasContext) interface{}

	// Visit a parse tree produced by Manuscript#fieldList.
	VisitFieldList(ctx *FieldListContext) interface{}

	// Visit a parse tree produced by Manuscript#fieldDecl.
	VisitFieldDecl(ctx *FieldDeclContext) interface{}

	// Visit a parse tree produced by Manuscript#typeList.
	VisitTypeList(ctx *TypeListContext) interface{}

	// Visit a parse tree produced by Manuscript#interfaceDecl.
	VisitInterfaceDecl(ctx *InterfaceDeclContext) interface{}

	// Visit a parse tree produced by Manuscript#interfaceMethod.
	VisitInterfaceMethod(ctx *InterfaceMethodContext) interface{}

	// Visit a parse tree produced by Manuscript#fnDecl.
	VisitFnDecl(ctx *FnDeclContext) interface{}

	// Visit a parse tree produced by Manuscript#fnSignature.
	VisitFnSignature(ctx *FnSignatureContext) interface{}

	// Visit a parse tree produced by Manuscript#parameters.
	VisitParameters(ctx *ParametersContext) interface{}

	// Visit a parse tree produced by Manuscript#param.
	VisitParam(ctx *ParamContext) interface{}

	// Visit a parse tree produced by Manuscript#methodsDecl.
	VisitMethodsDecl(ctx *MethodsDeclContext) interface{}

	// Visit a parse tree produced by Manuscript#methodImplList.
	VisitMethodImplList(ctx *MethodImplListContext) interface{}

	// Visit a parse tree produced by Manuscript#methodImpl.
	VisitMethodImpl(ctx *MethodImplContext) interface{}

	// Visit a parse tree produced by Manuscript#LabelStmtLet.
	VisitLabelStmtLet(ctx *LabelStmtLetContext) interface{}

	// Visit a parse tree produced by Manuscript#LabelStmtExpr.
	VisitLabelStmtExpr(ctx *LabelStmtExprContext) interface{}

	// Visit a parse tree produced by Manuscript#LabelStmtReturn.
	VisitLabelStmtReturn(ctx *LabelStmtReturnContext) interface{}

	// Visit a parse tree produced by Manuscript#LabelStmtYield.
	VisitLabelStmtYield(ctx *LabelStmtYieldContext) interface{}

	// Visit a parse tree produced by Manuscript#LabelStmtIf.
	VisitLabelStmtIf(ctx *LabelStmtIfContext) interface{}

	// Visit a parse tree produced by Manuscript#LabelStmtFor.
	VisitLabelStmtFor(ctx *LabelStmtForContext) interface{}

	// Visit a parse tree produced by Manuscript#LabelStmtWhile.
	VisitLabelStmtWhile(ctx *LabelStmtWhileContext) interface{}

	// Visit a parse tree produced by Manuscript#LabelStmtBlock.
	VisitLabelStmtBlock(ctx *LabelStmtBlockContext) interface{}

	// Visit a parse tree produced by Manuscript#LabelStmtBreak.
	VisitLabelStmtBreak(ctx *LabelStmtBreakContext) interface{}

	// Visit a parse tree produced by Manuscript#LabelStmtContinue.
	VisitLabelStmtContinue(ctx *LabelStmtContinueContext) interface{}

	// Visit a parse tree produced by Manuscript#LabelStmtCheck.
	VisitLabelStmtCheck(ctx *LabelStmtCheckContext) interface{}

	// Visit a parse tree produced by Manuscript#LabelStmtDefer.
	VisitLabelStmtDefer(ctx *LabelStmtDeferContext) interface{}

	// Visit a parse tree produced by Manuscript#LabelStmtTry.
	VisitLabelStmtTry(ctx *LabelStmtTryContext) interface{}

	// Visit a parse tree produced by Manuscript#LabelStmtPiped.
	VisitLabelStmtPiped(ctx *LabelStmtPipedContext) interface{}

	// Visit a parse tree produced by Manuscript#returnStmt.
	VisitReturnStmt(ctx *ReturnStmtContext) interface{}

	// Visit a parse tree produced by Manuscript#yieldStmt.
	VisitYieldStmt(ctx *YieldStmtContext) interface{}

	// Visit a parse tree produced by Manuscript#deferStmt.
	VisitDeferStmt(ctx *DeferStmtContext) interface{}

	// Visit a parse tree produced by Manuscript#exprList.
	VisitExprList(ctx *ExprListContext) interface{}

	// Visit a parse tree produced by Manuscript#ifStmt.
	VisitIfStmt(ctx *IfStmtContext) interface{}

	// Visit a parse tree produced by Manuscript#forStmt.
	VisitForStmt(ctx *ForStmtContext) interface{}

	// Visit a parse tree produced by Manuscript#LabelForLoop.
	VisitLabelForLoop(ctx *LabelForLoopContext) interface{}

	// Visit a parse tree produced by Manuscript#LabelForInLoop.
	VisitLabelForInLoop(ctx *LabelForInLoopContext) interface{}

	// Visit a parse tree produced by Manuscript#forTrinity.
	VisitForTrinity(ctx *ForTrinityContext) interface{}

	// Visit a parse tree produced by Manuscript#LabelForInitLet.
	VisitLabelForInitLet(ctx *LabelForInitLetContext) interface{}

	// Visit a parse tree produced by Manuscript#LabelForInitEmpty.
	VisitLabelForInitEmpty(ctx *LabelForInitEmptyContext) interface{}

	// Visit a parse tree produced by Manuscript#LabelForCondExpr.
	VisitLabelForCondExpr(ctx *LabelForCondExprContext) interface{}

	// Visit a parse tree produced by Manuscript#LabelForCondEmpty.
	VisitLabelForCondEmpty(ctx *LabelForCondEmptyContext) interface{}

	// Visit a parse tree produced by Manuscript#LabelForPostExpr.
	VisitLabelForPostExpr(ctx *LabelForPostExprContext) interface{}

	// Visit a parse tree produced by Manuscript#LabelForPostEmpty.
	VisitLabelForPostEmpty(ctx *LabelForPostEmptyContext) interface{}

	// Visit a parse tree produced by Manuscript#whileStmt.
	VisitWhileStmt(ctx *WhileStmtContext) interface{}

	// Visit a parse tree produced by Manuscript#loopBody.
	VisitLoopBody(ctx *LoopBodyContext) interface{}

	// Visit a parse tree produced by Manuscript#codeBlock.
	VisitCodeBlock(ctx *CodeBlockContext) interface{}

	// Visit a parse tree produced by Manuscript#breakStmt.
	VisitBreakStmt(ctx *BreakStmtContext) interface{}

	// Visit a parse tree produced by Manuscript#continueStmt.
	VisitContinueStmt(ctx *ContinueStmtContext) interface{}

	// Visit a parse tree produced by Manuscript#checkStmt.
	VisitCheckStmt(ctx *CheckStmtContext) interface{}

	// Visit a parse tree produced by Manuscript#pipedStmt.
	VisitPipedStmt(ctx *PipedStmtContext) interface{}

	// Visit a parse tree produced by Manuscript#pipedArgs.
	VisitPipedArgs(ctx *PipedArgsContext) interface{}

	// Visit a parse tree produced by Manuscript#pipedArg.
	VisitPipedArg(ctx *PipedArgContext) interface{}

	// Visit a parse tree produced by Manuscript#expr.
	VisitExpr(ctx *ExprContext) interface{}

	// Visit a parse tree produced by Manuscript#assignmentExpr.
	VisitAssignmentExpr(ctx *AssignmentExprContext) interface{}

	// Visit a parse tree produced by Manuscript#assignmentOp.
	VisitAssignmentOp(ctx *AssignmentOpContext) interface{}

	// Visit a parse tree produced by Manuscript#ternaryExpr.
	VisitTernaryExpr(ctx *TernaryExprContext) interface{}

	// Visit a parse tree produced by Manuscript#logicalOrExpr.
	VisitLogicalOrExpr(ctx *LogicalOrExprContext) interface{}

	// Visit a parse tree produced by Manuscript#logicalAndExpr.
	VisitLogicalAndExpr(ctx *LogicalAndExprContext) interface{}

	// Visit a parse tree produced by Manuscript#bitwiseXorExpr.
	VisitBitwiseXorExpr(ctx *BitwiseXorExprContext) interface{}

	// Visit a parse tree produced by Manuscript#bitwiseAndExpr.
	VisitBitwiseAndExpr(ctx *BitwiseAndExprContext) interface{}

	// Visit a parse tree produced by Manuscript#equalityExpr.
	VisitEqualityExpr(ctx *EqualityExprContext) interface{}

	// Visit a parse tree produced by Manuscript#comparisonOp.
	VisitComparisonOp(ctx *ComparisonOpContext) interface{}

	// Visit a parse tree produced by Manuscript#comparisonExpr.
	VisitComparisonExpr(ctx *ComparisonExprContext) interface{}

	// Visit a parse tree produced by Manuscript#shiftExpr.
	VisitShiftExpr(ctx *ShiftExprContext) interface{}

	// Visit a parse tree produced by Manuscript#additiveExpr.
	VisitAdditiveExpr(ctx *AdditiveExprContext) interface{}

	// Visit a parse tree produced by Manuscript#multiplicativeExpr.
	VisitMultiplicativeExpr(ctx *MultiplicativeExprContext) interface{}

	// Visit a parse tree produced by Manuscript#LabelUnaryOpExpr.
	VisitLabelUnaryOpExpr(ctx *LabelUnaryOpExprContext) interface{}

	// Visit a parse tree produced by Manuscript#LabelUnaryAwaitExpr.
	VisitLabelUnaryAwaitExpr(ctx *LabelUnaryAwaitExprContext) interface{}

	// Visit a parse tree produced by Manuscript#awaitExpr.
	VisitAwaitExpr(ctx *AwaitExprContext) interface{}

	// Visit a parse tree produced by Manuscript#postfixExpr.
	VisitPostfixExpr(ctx *PostfixExprContext) interface{}

	// Visit a parse tree produced by Manuscript#LabelPostfixCall.
	VisitLabelPostfixCall(ctx *LabelPostfixCallContext) interface{}

	// Visit a parse tree produced by Manuscript#LabelPostfixDot.
	VisitLabelPostfixDot(ctx *LabelPostfixDotContext) interface{}

	// Visit a parse tree produced by Manuscript#LabelPostfixIndex.
	VisitLabelPostfixIndex(ctx *LabelPostfixIndexContext) interface{}

	// Visit a parse tree produced by Manuscript#LabelPrimaryLiteral.
	VisitLabelPrimaryLiteral(ctx *LabelPrimaryLiteralContext) interface{}

	// Visit a parse tree produced by Manuscript#LabelPrimaryID.
	VisitLabelPrimaryID(ctx *LabelPrimaryIDContext) interface{}

	// Visit a parse tree produced by Manuscript#LabelPrimaryParen.
	VisitLabelPrimaryParen(ctx *LabelPrimaryParenContext) interface{}

	// Visit a parse tree produced by Manuscript#LabelPrimaryArray.
	VisitLabelPrimaryArray(ctx *LabelPrimaryArrayContext) interface{}

	// Visit a parse tree produced by Manuscript#LabelPrimaryObject.
	VisitLabelPrimaryObject(ctx *LabelPrimaryObjectContext) interface{}

	// Visit a parse tree produced by Manuscript#LabelPrimaryMap.
	VisitLabelPrimaryMap(ctx *LabelPrimaryMapContext) interface{}

	// Visit a parse tree produced by Manuscript#LabelPrimarySet.
	VisitLabelPrimarySet(ctx *LabelPrimarySetContext) interface{}

	// Visit a parse tree produced by Manuscript#LabelPrimaryFn.
	VisitLabelPrimaryFn(ctx *LabelPrimaryFnContext) interface{}

	// Visit a parse tree produced by Manuscript#LabelPrimaryMatch.
	VisitLabelPrimaryMatch(ctx *LabelPrimaryMatchContext) interface{}

	// Visit a parse tree produced by Manuscript#LabelPrimaryVoid.
	VisitLabelPrimaryVoid(ctx *LabelPrimaryVoidContext) interface{}

	// Visit a parse tree produced by Manuscript#LabelPrimaryNull.
	VisitLabelPrimaryNull(ctx *LabelPrimaryNullContext) interface{}

	// Visit a parse tree produced by Manuscript#LabelPrimaryTaggedBlock.
	VisitLabelPrimaryTaggedBlock(ctx *LabelPrimaryTaggedBlockContext) interface{}

	// Visit a parse tree produced by Manuscript#LabelPrimaryStructInit.
	VisitLabelPrimaryStructInit(ctx *LabelPrimaryStructInitContext) interface{}

	// Visit a parse tree produced by Manuscript#tryExpr.
	VisitTryExpr(ctx *TryExprContext) interface{}

	// Visit a parse tree produced by Manuscript#fnExpr.
	VisitFnExpr(ctx *FnExprContext) interface{}

	// Visit a parse tree produced by Manuscript#matchExpr.
	VisitMatchExpr(ctx *MatchExprContext) interface{}

	// Visit a parse tree produced by Manuscript#caseClause.
	VisitCaseClause(ctx *CaseClauseContext) interface{}

	// Visit a parse tree produced by Manuscript#defaultClause.
	VisitDefaultClause(ctx *DefaultClauseContext) interface{}

	// Visit a parse tree produced by Manuscript#singleQuotedString.
	VisitSingleQuotedString(ctx *SingleQuotedStringContext) interface{}

	// Visit a parse tree produced by Manuscript#multiQuotedString.
	VisitMultiQuotedString(ctx *MultiQuotedStringContext) interface{}

	// Visit a parse tree produced by Manuscript#doubleQuotedString.
	VisitDoubleQuotedString(ctx *DoubleQuotedStringContext) interface{}

	// Visit a parse tree produced by Manuscript#multiDoubleQuotedString.
	VisitMultiDoubleQuotedString(ctx *MultiDoubleQuotedStringContext) interface{}

	// Visit a parse tree produced by Manuscript#stringPart.
	VisitStringPart(ctx *StringPartContext) interface{}

	// Visit a parse tree produced by Manuscript#interpolation.
	VisitInterpolation(ctx *InterpolationContext) interface{}

	// Visit a parse tree produced by Manuscript#LabelLiteralString.
	VisitLabelLiteralString(ctx *LabelLiteralStringContext) interface{}

	// Visit a parse tree produced by Manuscript#LabelLiteralNumber.
	VisitLabelLiteralNumber(ctx *LabelLiteralNumberContext) interface{}

	// Visit a parse tree produced by Manuscript#LabelLiteralBool.
	VisitLabelLiteralBool(ctx *LabelLiteralBoolContext) interface{}

	// Visit a parse tree produced by Manuscript#LabelLiteralNull.
	VisitLabelLiteralNull(ctx *LabelLiteralNullContext) interface{}

	// Visit a parse tree produced by Manuscript#LabelLiteralVoid.
	VisitLabelLiteralVoid(ctx *LabelLiteralVoidContext) interface{}

	// Visit a parse tree produced by Manuscript#stringLiteral.
	VisitStringLiteral(ctx *StringLiteralContext) interface{}

	// Visit a parse tree produced by Manuscript#LabelNumberLiteralInt.
	VisitLabelNumberLiteralInt(ctx *LabelNumberLiteralIntContext) interface{}

	// Visit a parse tree produced by Manuscript#LabelNumberLiteralFloat.
	VisitLabelNumberLiteralFloat(ctx *LabelNumberLiteralFloatContext) interface{}

	// Visit a parse tree produced by Manuscript#LabelNumberLiteralHex.
	VisitLabelNumberLiteralHex(ctx *LabelNumberLiteralHexContext) interface{}

	// Visit a parse tree produced by Manuscript#LabelNumberLiteralBin.
	VisitLabelNumberLiteralBin(ctx *LabelNumberLiteralBinContext) interface{}

	// Visit a parse tree produced by Manuscript#LabelNumberLiteralOct.
	VisitLabelNumberLiteralOct(ctx *LabelNumberLiteralOctContext) interface{}

	// Visit a parse tree produced by Manuscript#LabelBoolLiteralTrue.
	VisitLabelBoolLiteralTrue(ctx *LabelBoolLiteralTrueContext) interface{}

	// Visit a parse tree produced by Manuscript#LabelBoolLiteralFalse.
	VisitLabelBoolLiteralFalse(ctx *LabelBoolLiteralFalseContext) interface{}

	// Visit a parse tree produced by Manuscript#arrayLiteral.
	VisitArrayLiteral(ctx *ArrayLiteralContext) interface{}

	// Visit a parse tree produced by Manuscript#objectLiteral.
	VisitObjectLiteral(ctx *ObjectLiteralContext) interface{}

	// Visit a parse tree produced by Manuscript#objectFieldList.
	VisitObjectFieldList(ctx *ObjectFieldListContext) interface{}

	// Visit a parse tree produced by Manuscript#objectField.
	VisitObjectField(ctx *ObjectFieldContext) interface{}

	// Visit a parse tree produced by Manuscript#LabelObjectFieldNameID.
	VisitLabelObjectFieldNameID(ctx *LabelObjectFieldNameIDContext) interface{}

	// Visit a parse tree produced by Manuscript#LabelObjectFieldNameStr.
	VisitLabelObjectFieldNameStr(ctx *LabelObjectFieldNameStrContext) interface{}

	// Visit a parse tree produced by Manuscript#LabelMapLiteralEmpty.
	VisitLabelMapLiteralEmpty(ctx *LabelMapLiteralEmptyContext) interface{}

	// Visit a parse tree produced by Manuscript#LabelMapLiteralNonEmpty.
	VisitLabelMapLiteralNonEmpty(ctx *LabelMapLiteralNonEmptyContext) interface{}

	// Visit a parse tree produced by Manuscript#mapFieldList.
	VisitMapFieldList(ctx *MapFieldListContext) interface{}

	// Visit a parse tree produced by Manuscript#mapField.
	VisitMapField(ctx *MapFieldContext) interface{}

	// Visit a parse tree produced by Manuscript#setLiteral.
	VisitSetLiteral(ctx *SetLiteralContext) interface{}

	// Visit a parse tree produced by Manuscript#taggedBlockString.
	VisitTaggedBlockString(ctx *TaggedBlockStringContext) interface{}

	// Visit a parse tree produced by Manuscript#structInitExpr.
	VisitStructInitExpr(ctx *StructInitExprContext) interface{}

	// Visit a parse tree produced by Manuscript#structFieldList.
	VisitStructFieldList(ctx *StructFieldListContext) interface{}

	// Visit a parse tree produced by Manuscript#structField.
	VisitStructField(ctx *StructFieldContext) interface{}

	// Visit a parse tree produced by Manuscript#LabelTypeAnnID.
	VisitLabelTypeAnnID(ctx *LabelTypeAnnIDContext) interface{}

	// Visit a parse tree produced by Manuscript#LabelTypeAnnArray.
	VisitLabelTypeAnnArray(ctx *LabelTypeAnnArrayContext) interface{}

	// Visit a parse tree produced by Manuscript#LabelTypeAnnTuple.
	VisitLabelTypeAnnTuple(ctx *LabelTypeAnnTupleContext) interface{}

	// Visit a parse tree produced by Manuscript#LabelTypeAnnFn.
	VisitLabelTypeAnnFn(ctx *LabelTypeAnnFnContext) interface{}

	// Visit a parse tree produced by Manuscript#LabelTypeAnnVoid.
	VisitLabelTypeAnnVoid(ctx *LabelTypeAnnVoidContext) interface{}

	// Visit a parse tree produced by Manuscript#tupleType.
	VisitTupleType(ctx *TupleTypeContext) interface{}

	// Visit a parse tree produced by Manuscript#arrayType.
	VisitArrayType(ctx *ArrayTypeContext) interface{}

	// Visit a parse tree produced by Manuscript#fnType.
	VisitFnType(ctx *FnTypeContext) interface{}

	// Visit a parse tree produced by Manuscript#stmt_sep.
	VisitStmt_sep(ctx *Stmt_sepContext) interface{}
}
