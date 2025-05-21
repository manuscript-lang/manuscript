// Code generated from Manuscript.g4 by ANTLR 4.13.1. DO NOT EDIT.

package parser // Manuscript

import "github.com/antlr4-go/antlr/v4"

// A complete Visitor for a parse tree produced by Manuscript.
type ManuscriptVisitor interface {
	antlr.ParseTreeVisitor

	// Visit a parse tree produced by Manuscript#program.
	VisitProgram(ctx *ProgramContext) interface{}

	// Visit a parse tree produced by Manuscript#DeclImport.
	VisitDeclImport(ctx *DeclImportContext) interface{}

	// Visit a parse tree produced by Manuscript#DeclExport.
	VisitDeclExport(ctx *DeclExportContext) interface{}

	// Visit a parse tree produced by Manuscript#DeclExtern.
	VisitDeclExtern(ctx *DeclExternContext) interface{}

	// Visit a parse tree produced by Manuscript#DeclLet.
	VisitDeclLet(ctx *DeclLetContext) interface{}

	// Visit a parse tree produced by Manuscript#DeclType.
	VisitDeclType(ctx *DeclTypeContext) interface{}

	// Visit a parse tree produced by Manuscript#DeclInterface.
	VisitDeclInterface(ctx *DeclInterfaceContext) interface{}

	// Visit a parse tree produced by Manuscript#DeclFn.
	VisitDeclFn(ctx *DeclFnContext) interface{}

	// Visit a parse tree produced by Manuscript#DeclMethods.
	VisitDeclMethods(ctx *DeclMethodsContext) interface{}

	// Visit a parse tree produced by Manuscript#stmt_list_items.
	VisitStmt_list_items(ctx *Stmt_list_itemsContext) interface{}

	// Visit a parse tree produced by Manuscript#importDecl.
	VisitImportDecl(ctx *ImportDeclContext) interface{}

	// Visit a parse tree produced by Manuscript#exportDecl.
	VisitExportDecl(ctx *ExportDeclContext) interface{}

	// Visit a parse tree produced by Manuscript#externDecl.
	VisitExternDecl(ctx *ExternDeclContext) interface{}

	// Visit a parse tree produced by Manuscript#ExportedFn.
	VisitExportedFn(ctx *ExportedFnContext) interface{}

	// Visit a parse tree produced by Manuscript#ExportedLet.
	VisitExportedLet(ctx *ExportedLetContext) interface{}

	// Visit a parse tree produced by Manuscript#ExportedType.
	VisitExportedType(ctx *ExportedTypeContext) interface{}

	// Visit a parse tree produced by Manuscript#ExportedInterface.
	VisitExportedInterface(ctx *ExportedInterfaceContext) interface{}

	// Visit a parse tree produced by Manuscript#ModuleImportDestructured.
	VisitModuleImportDestructured(ctx *ModuleImportDestructuredContext) interface{}

	// Visit a parse tree produced by Manuscript#ModuleImportTarget.
	VisitModuleImportTarget(ctx *ModuleImportTargetContext) interface{}

	// Visit a parse tree produced by Manuscript#destructuredImport.
	VisitDestructuredImport(ctx *DestructuredImportContext) interface{}

	// Visit a parse tree produced by Manuscript#targetImport.
	VisitTargetImport(ctx *TargetImportContext) interface{}

	// Visit a parse tree produced by Manuscript#importItemList.
	VisitImportItemList(ctx *ImportItemListContext) interface{}

	// Visit a parse tree produced by Manuscript#importItem.
	VisitImportItem(ctx *ImportItemContext) interface{}

	// Visit a parse tree produced by Manuscript#importStr.
	VisitImportStr(ctx *ImportStrContext) interface{}

	// Visit a parse tree produced by Manuscript#letDecl.
	VisitLetDecl(ctx *LetDeclContext) interface{}

	// Visit a parse tree produced by Manuscript#LetPatternSingle.
	VisitLetPatternSingle(ctx *LetPatternSingleContext) interface{}

	// Visit a parse tree produced by Manuscript#LetPatternBlock.
	VisitLetPatternBlock(ctx *LetPatternBlockContext) interface{}

	// Visit a parse tree produced by Manuscript#LetPatternDestructuredObj.
	VisitLetPatternDestructuredObj(ctx *LetPatternDestructuredObjContext) interface{}

	// Visit a parse tree produced by Manuscript#LetPatternDestructuredArray.
	VisitLetPatternDestructuredArray(ctx *LetPatternDestructuredArrayContext) interface{}

	// Visit a parse tree produced by Manuscript#letSingle.
	VisitLetSingle(ctx *LetSingleContext) interface{}

	// Visit a parse tree produced by Manuscript#letBlock.
	VisitLetBlock(ctx *LetBlockContext) interface{}

	// Visit a parse tree produced by Manuscript#LetBlockItemSingle.
	VisitLetBlockItemSingle(ctx *LetBlockItemSingleContext) interface{}

	// Visit a parse tree produced by Manuscript#LetBlockItemDestructuredObj.
	VisitLetBlockItemDestructuredObj(ctx *LetBlockItemDestructuredObjContext) interface{}

	// Visit a parse tree produced by Manuscript#LetBlockItemDestructuredArray.
	VisitLetBlockItemDestructuredArray(ctx *LetBlockItemDestructuredArrayContext) interface{}

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

	// Visit a parse tree produced by Manuscript#typeVariants.
	VisitTypeVariants(ctx *TypeVariantsContext) interface{}

	// Visit a parse tree produced by Manuscript#typeDefBody.
	VisitTypeDefBody(ctx *TypeDefBodyContext) interface{}

	// Visit a parse tree produced by Manuscript#typeAlias.
	VisitTypeAlias(ctx *TypeAliasContext) interface{}

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

	// Visit a parse tree produced by Manuscript#methodImpl.
	VisitMethodImpl(ctx *MethodImplContext) interface{}

	// Visit a parse tree produced by Manuscript#StmtLet.
	VisitStmtLet(ctx *StmtLetContext) interface{}

	// Visit a parse tree produced by Manuscript#StmtExpr.
	VisitStmtExpr(ctx *StmtExprContext) interface{}

	// Visit a parse tree produced by Manuscript#StmtReturn.
	VisitStmtReturn(ctx *StmtReturnContext) interface{}

	// Visit a parse tree produced by Manuscript#StmtYield.
	VisitStmtYield(ctx *StmtYieldContext) interface{}

	// Visit a parse tree produced by Manuscript#StmtIf.
	VisitStmtIf(ctx *StmtIfContext) interface{}

	// Visit a parse tree produced by Manuscript#StmtFor.
	VisitStmtFor(ctx *StmtForContext) interface{}

	// Visit a parse tree produced by Manuscript#StmtWhile.
	VisitStmtWhile(ctx *StmtWhileContext) interface{}

	// Visit a parse tree produced by Manuscript#StmtBlock.
	VisitStmtBlock(ctx *StmtBlockContext) interface{}

	// Visit a parse tree produced by Manuscript#StmtBreak.
	VisitStmtBreak(ctx *StmtBreakContext) interface{}

	// Visit a parse tree produced by Manuscript#StmtContinue.
	VisitStmtContinue(ctx *StmtContinueContext) interface{}

	// Visit a parse tree produced by Manuscript#StmtCheck.
	VisitStmtCheck(ctx *StmtCheckContext) interface{}

	// Visit a parse tree produced by Manuscript#StmtDefer.
	VisitStmtDefer(ctx *StmtDeferContext) interface{}

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

	// Visit a parse tree produced by Manuscript#forLoopType.
	VisitForLoopType(ctx *ForLoopTypeContext) interface{}

	// Visit a parse tree produced by Manuscript#forTrinity.
	VisitForTrinity(ctx *ForTrinityContext) interface{}

	// Visit a parse tree produced by Manuscript#forInit.
	VisitForInit(ctx *ForInitContext) interface{}

	// Visit a parse tree produced by Manuscript#forCond.
	VisitForCond(ctx *ForCondContext) interface{}

	// Visit a parse tree produced by Manuscript#forPost.
	VisitForPost(ctx *ForPostContext) interface{}

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

	// Visit a parse tree produced by Manuscript#bitwiseOrExpr.
	VisitBitwiseOrExpr(ctx *BitwiseOrExprContext) interface{}

	// Visit a parse tree produced by Manuscript#bitwiseXorExpr.
	VisitBitwiseXorExpr(ctx *BitwiseXorExprContext) interface{}

	// Visit a parse tree produced by Manuscript#bitwiseAndExpr.
	VisitBitwiseAndExpr(ctx *BitwiseAndExprContext) interface{}

	// Visit a parse tree produced by Manuscript#equalityExpr.
	VisitEqualityExpr(ctx *EqualityExprContext) interface{}

	// Visit a parse tree produced by Manuscript#comparisonExpr.
	VisitComparisonExpr(ctx *ComparisonExprContext) interface{}

	// Visit a parse tree produced by Manuscript#shiftExpr.
	VisitShiftExpr(ctx *ShiftExprContext) interface{}

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

	// Visit a parse tree produced by Manuscript#postfixOp.
	VisitPostfixOp(ctx *PostfixOpContext) interface{}

	// Visit a parse tree produced by Manuscript#primaryExpr.
	VisitPrimaryExpr(ctx *PrimaryExprContext) interface{}

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

	// Visit a parse tree produced by Manuscript#literal.
	VisitLiteral(ctx *LiteralContext) interface{}

	// Visit a parse tree produced by Manuscript#StringLiteralSingle.
	VisitStringLiteralSingle(ctx *StringLiteralSingleContext) interface{}

	// Visit a parse tree produced by Manuscript#StringLiteralMulti.
	VisitStringLiteralMulti(ctx *StringLiteralMultiContext) interface{}

	// Visit a parse tree produced by Manuscript#StringLiteralDouble.
	VisitStringLiteralDouble(ctx *StringLiteralDoubleContext) interface{}

	// Visit a parse tree produced by Manuscript#StringLiteralMultiDouble.
	VisitStringLiteralMultiDouble(ctx *StringLiteralMultiDoubleContext) interface{}

	// Visit a parse tree produced by Manuscript#NumberLiteralInt.
	VisitNumberLiteralInt(ctx *NumberLiteralIntContext) interface{}

	// Visit a parse tree produced by Manuscript#NumberLiteralFloat.
	VisitNumberLiteralFloat(ctx *NumberLiteralFloatContext) interface{}

	// Visit a parse tree produced by Manuscript#NumberLiteralHex.
	VisitNumberLiteralHex(ctx *NumberLiteralHexContext) interface{}

	// Visit a parse tree produced by Manuscript#NumberLiteralBin.
	VisitNumberLiteralBin(ctx *NumberLiteralBinContext) interface{}

	// Visit a parse tree produced by Manuscript#NumberLiteralOct.
	VisitNumberLiteralOct(ctx *NumberLiteralOctContext) interface{}

	// Visit a parse tree produced by Manuscript#BoolLiteralTrue.
	VisitBoolLiteralTrue(ctx *BoolLiteralTrueContext) interface{}

	// Visit a parse tree produced by Manuscript#BoolLiteralFalse.
	VisitBoolLiteralFalse(ctx *BoolLiteralFalseContext) interface{}

	// Visit a parse tree produced by Manuscript#arrayLiteral.
	VisitArrayLiteral(ctx *ArrayLiteralContext) interface{}

	// Visit a parse tree produced by Manuscript#objectLiteral.
	VisitObjectLiteral(ctx *ObjectLiteralContext) interface{}

	// Visit a parse tree produced by Manuscript#objectField.
	VisitObjectField(ctx *ObjectFieldContext) interface{}

	// Visit a parse tree produced by Manuscript#objectFieldName.
	VisitObjectFieldName(ctx *ObjectFieldNameContext) interface{}

	// Visit a parse tree produced by Manuscript#mapLiteral.
	VisitMapLiteral(ctx *MapLiteralContext) interface{}

	// Visit a parse tree produced by Manuscript#mapField.
	VisitMapField(ctx *MapFieldContext) interface{}

	// Visit a parse tree produced by Manuscript#setLiteral.
	VisitSetLiteral(ctx *SetLiteralContext) interface{}

	// Visit a parse tree produced by Manuscript#taggedBlockString.
	VisitTaggedBlockString(ctx *TaggedBlockStringContext) interface{}

	// Visit a parse tree produced by Manuscript#structInitExpr.
	VisitStructInitExpr(ctx *StructInitExprContext) interface{}

	// Visit a parse tree produced by Manuscript#structField.
	VisitStructField(ctx *StructFieldContext) interface{}

	// Visit a parse tree produced by Manuscript#typeAnnotation.
	VisitTypeAnnotation(ctx *TypeAnnotationContext) interface{}

	// Visit a parse tree produced by Manuscript#typeBase.
	VisitTypeBase(ctx *TypeBaseContext) interface{}

	// Visit a parse tree produced by Manuscript#tupleType.
	VisitTupleType(ctx *TupleTypeContext) interface{}

	// Visit a parse tree produced by Manuscript#arrayType.
	VisitArrayType(ctx *ArrayTypeContext) interface{}

	// Visit a parse tree produced by Manuscript#fnType.
	VisitFnType(ctx *FnTypeContext) interface{}

	// Visit a parse tree produced by Manuscript#stmt_sep.
	VisitStmt_sep(ctx *Stmt_sepContext) interface{}
}
