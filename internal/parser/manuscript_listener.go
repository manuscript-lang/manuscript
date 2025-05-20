// Code generated from Manuscript.g4 by ANTLR 4.13.1. DO NOT EDIT.

package parser // Manuscript

import "github.com/antlr4-go/antlr/v4"

// ManuscriptListener is a complete listener for a parse tree produced by Manuscript.
type ManuscriptListener interface {
	antlr.ParseTreeListener

	// EnterProgram is called when entering the program production.
	EnterProgram(c *ProgramContext)

	// EnterDeclaration is called when entering the declaration production.
	EnterDeclaration(c *DeclarationContext)

	// EnterImportDecl is called when entering the importDecl production.
	EnterImportDecl(c *ImportDeclContext)

	// EnterExportDecl is called when entering the exportDecl production.
	EnterExportDecl(c *ExportDeclContext)

	// EnterExternDecl is called when entering the externDecl production.
	EnterExternDecl(c *ExternDeclContext)

	// EnterExportedItem is called when entering the exportedItem production.
	EnterExportedItem(c *ExportedItemContext)

	// EnterModuleImport is called when entering the moduleImport production.
	EnterModuleImport(c *ModuleImportContext)

	// EnterDestructuredImport is called when entering the destructuredImport production.
	EnterDestructuredImport(c *DestructuredImportContext)

	// EnterTargetImport is called when entering the targetImport production.
	EnterTargetImport(c *TargetImportContext)

	// EnterImportItemList is called when entering the importItemList production.
	EnterImportItemList(c *ImportItemListContext)

	// EnterImportItem is called when entering the importItem production.
	EnterImportItem(c *ImportItemContext)

	// EnterImportStr is called when entering the importStr production.
	EnterImportStr(c *ImportStrContext)

	// EnterLetDecl is called when entering the letDecl production.
	EnterLetDecl(c *LetDeclContext)

	// EnterLetSingle is called when entering the letSingle production.
	EnterLetSingle(c *LetSingleContext)

	// EnterLetBlock is called when entering the letBlock production.
	EnterLetBlock(c *LetBlockContext)

	// EnterLetBlockItemList is called when entering the letBlockItemList production.
	EnterLetBlockItemList(c *LetBlockItemListContext)

	// EnterLetBlockItemSep is called when entering the letBlockItemSep production.
	EnterLetBlockItemSep(c *LetBlockItemSepContext)

	// EnterLetBlockItemSingle is called when entering the LetBlockItemSingle production.
	EnterLetBlockItemSingle(c *LetBlockItemSingleContext)

	// EnterLetBlockItemDestructuredObj is called when entering the LetBlockItemDestructuredObj production.
	EnterLetBlockItemDestructuredObj(c *LetBlockItemDestructuredObjContext)

	// EnterLetBlockItemDestructuredArray is called when entering the LetBlockItemDestructuredArray production.
	EnterLetBlockItemDestructuredArray(c *LetBlockItemDestructuredArrayContext)

	// EnterLetDestructuredObj is called when entering the letDestructuredObj production.
	EnterLetDestructuredObj(c *LetDestructuredObjContext)

	// EnterLetDestructuredArray is called when entering the letDestructuredArray production.
	EnterLetDestructuredArray(c *LetDestructuredArrayContext)

	// EnterTypedIDList is called when entering the typedIDList production.
	EnterTypedIDList(c *TypedIDListContext)

	// EnterTypedID is called when entering the typedID production.
	EnterTypedID(c *TypedIDContext)

	// EnterTypeDecl is called when entering the typeDecl production.
	EnterTypeDecl(c *TypeDeclContext)

	// EnterTypeDefBody is called when entering the typeDefBody production.
	EnterTypeDefBody(c *TypeDefBodyContext)

	// EnterTypeAlias is called when entering the typeAlias production.
	EnterTypeAlias(c *TypeAliasContext)

	// EnterFieldList is called when entering the fieldList production.
	EnterFieldList(c *FieldListContext)

	// EnterFieldDecl is called when entering the fieldDecl production.
	EnterFieldDecl(c *FieldDeclContext)

	// EnterTypeList is called when entering the typeList production.
	EnterTypeList(c *TypeListContext)

	// EnterInterfaceDecl is called when entering the interfaceDecl production.
	EnterInterfaceDecl(c *InterfaceDeclContext)

	// EnterInterfaceMethod is called when entering the interfaceMethod production.
	EnterInterfaceMethod(c *InterfaceMethodContext)

	// EnterFnDecl is called when entering the fnDecl production.
	EnterFnDecl(c *FnDeclContext)

	// EnterFnSignature is called when entering the fnSignature production.
	EnterFnSignature(c *FnSignatureContext)

	// EnterParameters is called when entering the parameters production.
	EnterParameters(c *ParametersContext)

	// EnterParam is called when entering the param production.
	EnterParam(c *ParamContext)

	// EnterMethodsDecl is called when entering the methodsDecl production.
	EnterMethodsDecl(c *MethodsDeclContext)

	// EnterMethodImplList is called when entering the methodImplList production.
	EnterMethodImplList(c *MethodImplListContext)

	// EnterMethodImplSep is called when entering the methodImplSep production.
	EnterMethodImplSep(c *MethodImplSepContext)

	// EnterMethodImpl is called when entering the methodImpl production.
	EnterMethodImpl(c *MethodImplContext)

	// EnterStmtLet is called when entering the StmtLet production.
	EnterStmtLet(c *StmtLetContext)

	// EnterStmtExpr is called when entering the StmtExpr production.
	EnterStmtExpr(c *StmtExprContext)

	// EnterStmtReturn is called when entering the StmtReturn production.
	EnterStmtReturn(c *StmtReturnContext)

	// EnterStmtYield is called when entering the StmtYield production.
	EnterStmtYield(c *StmtYieldContext)

	// EnterStmtIf is called when entering the StmtIf production.
	EnterStmtIf(c *StmtIfContext)

	// EnterStmtFor is called when entering the StmtFor production.
	EnterStmtFor(c *StmtForContext)

	// EnterStmtWhile is called when entering the StmtWhile production.
	EnterStmtWhile(c *StmtWhileContext)

	// EnterStmtBlock is called when entering the StmtBlock production.
	EnterStmtBlock(c *StmtBlockContext)

	// EnterStmtBreak is called when entering the StmtBreak production.
	EnterStmtBreak(c *StmtBreakContext)

	// EnterStmtContinue is called when entering the StmtContinue production.
	EnterStmtContinue(c *StmtContinueContext)

	// EnterStmtCheck is called when entering the StmtCheck production.
	EnterStmtCheck(c *StmtCheckContext)

	// EnterStmtDefer is called when entering the StmtDefer production.
	EnterStmtDefer(c *StmtDeferContext)

	// EnterReturnStmt is called when entering the returnStmt production.
	EnterReturnStmt(c *ReturnStmtContext)

	// EnterYieldStmt is called when entering the yieldStmt production.
	EnterYieldStmt(c *YieldStmtContext)

	// EnterDeferStmt is called when entering the deferStmt production.
	EnterDeferStmt(c *DeferStmtContext)

	// EnterExprList is called when entering the exprList production.
	EnterExprList(c *ExprListContext)

	// EnterIfStmt is called when entering the ifStmt production.
	EnterIfStmt(c *IfStmtContext)

	// EnterForStmt is called when entering the forStmt production.
	EnterForStmt(c *ForStmtContext)

	// EnterForLoop is called when entering the ForLoop production.
	EnterForLoop(c *ForLoopContext)

	// EnterForInLoop is called when entering the ForInLoop production.
	EnterForInLoop(c *ForInLoopContext)

	// EnterForTrinity is called when entering the forTrinity production.
	EnterForTrinity(c *ForTrinityContext)

	// EnterForInit is called when entering the forInit production.
	EnterForInit(c *ForInitContext)

	// EnterForCond is called when entering the forCond production.
	EnterForCond(c *ForCondContext)

	// EnterForPost is called when entering the forPost production.
	EnterForPost(c *ForPostContext)

	// EnterWhileStmt is called when entering the whileStmt production.
	EnterWhileStmt(c *WhileStmtContext)

	// EnterLoopBody is called when entering the loopBody production.
	EnterLoopBody(c *LoopBodyContext)

	// EnterCodeBlock is called when entering the codeBlock production.
	EnterCodeBlock(c *CodeBlockContext)

	// EnterBreakStmt is called when entering the breakStmt production.
	EnterBreakStmt(c *BreakStmtContext)

	// EnterContinueStmt is called when entering the continueStmt production.
	EnterContinueStmt(c *ContinueStmtContext)

	// EnterCheckStmt is called when entering the checkStmt production.
	EnterCheckStmt(c *CheckStmtContext)

	// EnterExpr is called when entering the expr production.
	EnterExpr(c *ExprContext)

	// EnterAssignmentExpr is called when entering the assignmentExpr production.
	EnterAssignmentExpr(c *AssignmentExprContext)

	// EnterAssignmentOp is called when entering the assignmentOp production.
	EnterAssignmentOp(c *AssignmentOpContext)

	// EnterTernaryExpr is called when entering the ternaryExpr production.
	EnterTernaryExpr(c *TernaryExprContext)

	// EnterLogicalOrExpr is called when entering the logicalOrExpr production.
	EnterLogicalOrExpr(c *LogicalOrExprContext)

	// EnterLogicalAndExpr is called when entering the logicalAndExpr production.
	EnterLogicalAndExpr(c *LogicalAndExprContext)

	// EnterBitwiseOrExpr is called when entering the bitwiseOrExpr production.
	EnterBitwiseOrExpr(c *BitwiseOrExprContext)

	// EnterBitwiseXorExpr is called when entering the bitwiseXorExpr production.
	EnterBitwiseXorExpr(c *BitwiseXorExprContext)

	// EnterBitwiseAndExpr is called when entering the bitwiseAndExpr production.
	EnterBitwiseAndExpr(c *BitwiseAndExprContext)

	// EnterEqualityExpr is called when entering the equalityExpr production.
	EnterEqualityExpr(c *EqualityExprContext)

	// EnterComparisonExpr is called when entering the comparisonExpr production.
	EnterComparisonExpr(c *ComparisonExprContext)

	// EnterShiftExpr is called when entering the shiftExpr production.
	EnterShiftExpr(c *ShiftExprContext)

	// EnterAdditiveExpr is called when entering the additiveExpr production.
	EnterAdditiveExpr(c *AdditiveExprContext)

	// EnterMultiplicativeExpr is called when entering the multiplicativeExpr production.
	EnterMultiplicativeExpr(c *MultiplicativeExprContext)

	// EnterUnaryExpr is called when entering the unaryExpr production.
	EnterUnaryExpr(c *UnaryExprContext)

	// EnterAwaitExpr is called when entering the awaitExpr production.
	EnterAwaitExpr(c *AwaitExprContext)

	// EnterPostfixExpr is called when entering the postfixExpr production.
	EnterPostfixExpr(c *PostfixExprContext)

	// EnterPostfixOp is called when entering the postfixOp production.
	EnterPostfixOp(c *PostfixOpContext)

	// EnterPrimaryExpr is called when entering the primaryExpr production.
	EnterPrimaryExpr(c *PrimaryExprContext)

	// EnterFnExpr is called when entering the fnExpr production.
	EnterFnExpr(c *FnExprContext)

	// EnterMatchExpr is called when entering the matchExpr production.
	EnterMatchExpr(c *MatchExprContext)

	// EnterCaseClause is called when entering the caseClause production.
	EnterCaseClause(c *CaseClauseContext)

	// EnterDefaultClause is called when entering the defaultClause production.
	EnterDefaultClause(c *DefaultClauseContext)

	// EnterSingleQuotedString is called when entering the singleQuotedString production.
	EnterSingleQuotedString(c *SingleQuotedStringContext)

	// EnterMultiQuotedString is called when entering the multiQuotedString production.
	EnterMultiQuotedString(c *MultiQuotedStringContext)

	// EnterDoubleQuotedString is called when entering the doubleQuotedString production.
	EnterDoubleQuotedString(c *DoubleQuotedStringContext)

	// EnterMultiDoubleQuotedString is called when entering the multiDoubleQuotedString production.
	EnterMultiDoubleQuotedString(c *MultiDoubleQuotedStringContext)

	// EnterStringPart is called when entering the stringPart production.
	EnterStringPart(c *StringPartContext)

	// EnterInterpolation is called when entering the interpolation production.
	EnterInterpolation(c *InterpolationContext)

	// EnterLiteral is called when entering the literal production.
	EnterLiteral(c *LiteralContext)

	// EnterStringLiteral is called when entering the stringLiteral production.
	EnterStringLiteral(c *StringLiteralContext)

	// EnterNumberLiteral is called when entering the numberLiteral production.
	EnterNumberLiteral(c *NumberLiteralContext)

	// EnterBooleanLiteral is called when entering the booleanLiteral production.
	EnterBooleanLiteral(c *BooleanLiteralContext)

	// EnterArrayLiteral is called when entering the arrayLiteral production.
	EnterArrayLiteral(c *ArrayLiteralContext)

	// EnterObjectLiteral is called when entering the objectLiteral production.
	EnterObjectLiteral(c *ObjectLiteralContext)

	// EnterObjectFieldList is called when entering the objectFieldList production.
	EnterObjectFieldList(c *ObjectFieldListContext)

	// EnterObjectField is called when entering the objectField production.
	EnterObjectField(c *ObjectFieldContext)

	// EnterObjectFieldName is called when entering the objectFieldName production.
	EnterObjectFieldName(c *ObjectFieldNameContext)

	// EnterMapLiteral is called when entering the mapLiteral production.
	EnterMapLiteral(c *MapLiteralContext)

	// EnterMapFieldList is called when entering the mapFieldList production.
	EnterMapFieldList(c *MapFieldListContext)

	// EnterMapField is called when entering the mapField production.
	EnterMapField(c *MapFieldContext)

	// EnterSetLiteral is called when entering the setLiteral production.
	EnterSetLiteral(c *SetLiteralContext)

	// EnterTaggedBlockString is called when entering the taggedBlockString production.
	EnterTaggedBlockString(c *TaggedBlockStringContext)

	// EnterStructInitExpr is called when entering the structInitExpr production.
	EnterStructInitExpr(c *StructInitExprContext)

	// EnterStructFieldList is called when entering the structFieldList production.
	EnterStructFieldList(c *StructFieldListContext)

	// EnterStructField is called when entering the structField production.
	EnterStructField(c *StructFieldContext)

	// EnterTypeAnnotation is called when entering the typeAnnotation production.
	EnterTypeAnnotation(c *TypeAnnotationContext)

	// EnterTupleType is called when entering the tupleType production.
	EnterTupleType(c *TupleTypeContext)

	// EnterArrayType is called when entering the arrayType production.
	EnterArrayType(c *ArrayTypeContext)

	// EnterFnType is called when entering the fnType production.
	EnterFnType(c *FnTypeContext)

	// EnterStmt_sep is called when entering the stmt_sep production.
	EnterStmt_sep(c *Stmt_sepContext)

	// ExitProgram is called when exiting the program production.
	ExitProgram(c *ProgramContext)

	// ExitDeclaration is called when exiting the declaration production.
	ExitDeclaration(c *DeclarationContext)

	// ExitImportDecl is called when exiting the importDecl production.
	ExitImportDecl(c *ImportDeclContext)

	// ExitExportDecl is called when exiting the exportDecl production.
	ExitExportDecl(c *ExportDeclContext)

	// ExitExternDecl is called when exiting the externDecl production.
	ExitExternDecl(c *ExternDeclContext)

	// ExitExportedItem is called when exiting the exportedItem production.
	ExitExportedItem(c *ExportedItemContext)

	// ExitModuleImport is called when exiting the moduleImport production.
	ExitModuleImport(c *ModuleImportContext)

	// ExitDestructuredImport is called when exiting the destructuredImport production.
	ExitDestructuredImport(c *DestructuredImportContext)

	// ExitTargetImport is called when exiting the targetImport production.
	ExitTargetImport(c *TargetImportContext)

	// ExitImportItemList is called when exiting the importItemList production.
	ExitImportItemList(c *ImportItemListContext)

	// ExitImportItem is called when exiting the importItem production.
	ExitImportItem(c *ImportItemContext)

	// ExitImportStr is called when exiting the importStr production.
	ExitImportStr(c *ImportStrContext)

	// ExitLetDecl is called when exiting the letDecl production.
	ExitLetDecl(c *LetDeclContext)

	// ExitLetSingle is called when exiting the letSingle production.
	ExitLetSingle(c *LetSingleContext)

	// ExitLetBlock is called when exiting the letBlock production.
	ExitLetBlock(c *LetBlockContext)

	// ExitLetBlockItemList is called when exiting the letBlockItemList production.
	ExitLetBlockItemList(c *LetBlockItemListContext)

	// ExitLetBlockItemSep is called when exiting the letBlockItemSep production.
	ExitLetBlockItemSep(c *LetBlockItemSepContext)

	// ExitLetBlockItemSingle is called when exiting the LetBlockItemSingle production.
	ExitLetBlockItemSingle(c *LetBlockItemSingleContext)

	// ExitLetBlockItemDestructuredObj is called when exiting the LetBlockItemDestructuredObj production.
	ExitLetBlockItemDestructuredObj(c *LetBlockItemDestructuredObjContext)

	// ExitLetBlockItemDestructuredArray is called when exiting the LetBlockItemDestructuredArray production.
	ExitLetBlockItemDestructuredArray(c *LetBlockItemDestructuredArrayContext)

	// ExitLetDestructuredObj is called when exiting the letDestructuredObj production.
	ExitLetDestructuredObj(c *LetDestructuredObjContext)

	// ExitLetDestructuredArray is called when exiting the letDestructuredArray production.
	ExitLetDestructuredArray(c *LetDestructuredArrayContext)

	// ExitTypedIDList is called when exiting the typedIDList production.
	ExitTypedIDList(c *TypedIDListContext)

	// ExitTypedID is called when exiting the typedID production.
	ExitTypedID(c *TypedIDContext)

	// ExitTypeDecl is called when exiting the typeDecl production.
	ExitTypeDecl(c *TypeDeclContext)

	// ExitTypeDefBody is called when exiting the typeDefBody production.
	ExitTypeDefBody(c *TypeDefBodyContext)

	// ExitTypeAlias is called when exiting the typeAlias production.
	ExitTypeAlias(c *TypeAliasContext)

	// ExitFieldList is called when exiting the fieldList production.
	ExitFieldList(c *FieldListContext)

	// ExitFieldDecl is called when exiting the fieldDecl production.
	ExitFieldDecl(c *FieldDeclContext)

	// ExitTypeList is called when exiting the typeList production.
	ExitTypeList(c *TypeListContext)

	// ExitInterfaceDecl is called when exiting the interfaceDecl production.
	ExitInterfaceDecl(c *InterfaceDeclContext)

	// ExitInterfaceMethod is called when exiting the interfaceMethod production.
	ExitInterfaceMethod(c *InterfaceMethodContext)

	// ExitFnDecl is called when exiting the fnDecl production.
	ExitFnDecl(c *FnDeclContext)

	// ExitFnSignature is called when exiting the fnSignature production.
	ExitFnSignature(c *FnSignatureContext)

	// ExitParameters is called when exiting the parameters production.
	ExitParameters(c *ParametersContext)

	// ExitParam is called when exiting the param production.
	ExitParam(c *ParamContext)

	// ExitMethodsDecl is called when exiting the methodsDecl production.
	ExitMethodsDecl(c *MethodsDeclContext)

	// ExitMethodImplList is called when exiting the methodImplList production.
	ExitMethodImplList(c *MethodImplListContext)

	// ExitMethodImplSep is called when exiting the methodImplSep production.
	ExitMethodImplSep(c *MethodImplSepContext)

	// ExitMethodImpl is called when exiting the methodImpl production.
	ExitMethodImpl(c *MethodImplContext)

	// ExitStmtLet is called when exiting the StmtLet production.
	ExitStmtLet(c *StmtLetContext)

	// ExitStmtExpr is called when exiting the StmtExpr production.
	ExitStmtExpr(c *StmtExprContext)

	// ExitStmtReturn is called when exiting the StmtReturn production.
	ExitStmtReturn(c *StmtReturnContext)

	// ExitStmtYield is called when exiting the StmtYield production.
	ExitStmtYield(c *StmtYieldContext)

	// ExitStmtIf is called when exiting the StmtIf production.
	ExitStmtIf(c *StmtIfContext)

	// ExitStmtFor is called when exiting the StmtFor production.
	ExitStmtFor(c *StmtForContext)

	// ExitStmtWhile is called when exiting the StmtWhile production.
	ExitStmtWhile(c *StmtWhileContext)

	// ExitStmtBlock is called when exiting the StmtBlock production.
	ExitStmtBlock(c *StmtBlockContext)

	// ExitStmtBreak is called when exiting the StmtBreak production.
	ExitStmtBreak(c *StmtBreakContext)

	// ExitStmtContinue is called when exiting the StmtContinue production.
	ExitStmtContinue(c *StmtContinueContext)

	// ExitStmtCheck is called when exiting the StmtCheck production.
	ExitStmtCheck(c *StmtCheckContext)

	// ExitStmtDefer is called when exiting the StmtDefer production.
	ExitStmtDefer(c *StmtDeferContext)

	// ExitReturnStmt is called when exiting the returnStmt production.
	ExitReturnStmt(c *ReturnStmtContext)

	// ExitYieldStmt is called when exiting the yieldStmt production.
	ExitYieldStmt(c *YieldStmtContext)

	// ExitDeferStmt is called when exiting the deferStmt production.
	ExitDeferStmt(c *DeferStmtContext)

	// ExitExprList is called when exiting the exprList production.
	ExitExprList(c *ExprListContext)

	// ExitIfStmt is called when exiting the ifStmt production.
	ExitIfStmt(c *IfStmtContext)

	// ExitForStmt is called when exiting the forStmt production.
	ExitForStmt(c *ForStmtContext)

	// ExitForLoop is called when exiting the ForLoop production.
	ExitForLoop(c *ForLoopContext)

	// ExitForInLoop is called when exiting the ForInLoop production.
	ExitForInLoop(c *ForInLoopContext)

	// ExitForTrinity is called when exiting the forTrinity production.
	ExitForTrinity(c *ForTrinityContext)

	// ExitForInit is called when exiting the forInit production.
	ExitForInit(c *ForInitContext)

	// ExitForCond is called when exiting the forCond production.
	ExitForCond(c *ForCondContext)

	// ExitForPost is called when exiting the forPost production.
	ExitForPost(c *ForPostContext)

	// ExitWhileStmt is called when exiting the whileStmt production.
	ExitWhileStmt(c *WhileStmtContext)

	// ExitLoopBody is called when exiting the loopBody production.
	ExitLoopBody(c *LoopBodyContext)

	// ExitCodeBlock is called when exiting the codeBlock production.
	ExitCodeBlock(c *CodeBlockContext)

	// ExitBreakStmt is called when exiting the breakStmt production.
	ExitBreakStmt(c *BreakStmtContext)

	// ExitContinueStmt is called when exiting the continueStmt production.
	ExitContinueStmt(c *ContinueStmtContext)

	// ExitCheckStmt is called when exiting the checkStmt production.
	ExitCheckStmt(c *CheckStmtContext)

	// ExitExpr is called when exiting the expr production.
	ExitExpr(c *ExprContext)

	// ExitAssignmentExpr is called when exiting the assignmentExpr production.
	ExitAssignmentExpr(c *AssignmentExprContext)

	// ExitAssignmentOp is called when exiting the assignmentOp production.
	ExitAssignmentOp(c *AssignmentOpContext)

	// ExitTernaryExpr is called when exiting the ternaryExpr production.
	ExitTernaryExpr(c *TernaryExprContext)

	// ExitLogicalOrExpr is called when exiting the logicalOrExpr production.
	ExitLogicalOrExpr(c *LogicalOrExprContext)

	// ExitLogicalAndExpr is called when exiting the logicalAndExpr production.
	ExitLogicalAndExpr(c *LogicalAndExprContext)

	// ExitBitwiseOrExpr is called when exiting the bitwiseOrExpr production.
	ExitBitwiseOrExpr(c *BitwiseOrExprContext)

	// ExitBitwiseXorExpr is called when exiting the bitwiseXorExpr production.
	ExitBitwiseXorExpr(c *BitwiseXorExprContext)

	// ExitBitwiseAndExpr is called when exiting the bitwiseAndExpr production.
	ExitBitwiseAndExpr(c *BitwiseAndExprContext)

	// ExitEqualityExpr is called when exiting the equalityExpr production.
	ExitEqualityExpr(c *EqualityExprContext)

	// ExitComparisonExpr is called when exiting the comparisonExpr production.
	ExitComparisonExpr(c *ComparisonExprContext)

	// ExitShiftExpr is called when exiting the shiftExpr production.
	ExitShiftExpr(c *ShiftExprContext)

	// ExitAdditiveExpr is called when exiting the additiveExpr production.
	ExitAdditiveExpr(c *AdditiveExprContext)

	// ExitMultiplicativeExpr is called when exiting the multiplicativeExpr production.
	ExitMultiplicativeExpr(c *MultiplicativeExprContext)

	// ExitUnaryExpr is called when exiting the unaryExpr production.
	ExitUnaryExpr(c *UnaryExprContext)

	// ExitAwaitExpr is called when exiting the awaitExpr production.
	ExitAwaitExpr(c *AwaitExprContext)

	// ExitPostfixExpr is called when exiting the postfixExpr production.
	ExitPostfixExpr(c *PostfixExprContext)

	// ExitPostfixOp is called when exiting the postfixOp production.
	ExitPostfixOp(c *PostfixOpContext)

	// ExitPrimaryExpr is called when exiting the primaryExpr production.
	ExitPrimaryExpr(c *PrimaryExprContext)

	// ExitFnExpr is called when exiting the fnExpr production.
	ExitFnExpr(c *FnExprContext)

	// ExitMatchExpr is called when exiting the matchExpr production.
	ExitMatchExpr(c *MatchExprContext)

	// ExitCaseClause is called when exiting the caseClause production.
	ExitCaseClause(c *CaseClauseContext)

	// ExitDefaultClause is called when exiting the defaultClause production.
	ExitDefaultClause(c *DefaultClauseContext)

	// ExitSingleQuotedString is called when exiting the singleQuotedString production.
	ExitSingleQuotedString(c *SingleQuotedStringContext)

	// ExitMultiQuotedString is called when exiting the multiQuotedString production.
	ExitMultiQuotedString(c *MultiQuotedStringContext)

	// ExitDoubleQuotedString is called when exiting the doubleQuotedString production.
	ExitDoubleQuotedString(c *DoubleQuotedStringContext)

	// ExitMultiDoubleQuotedString is called when exiting the multiDoubleQuotedString production.
	ExitMultiDoubleQuotedString(c *MultiDoubleQuotedStringContext)

	// ExitStringPart is called when exiting the stringPart production.
	ExitStringPart(c *StringPartContext)

	// ExitInterpolation is called when exiting the interpolation production.
	ExitInterpolation(c *InterpolationContext)

	// ExitLiteral is called when exiting the literal production.
	ExitLiteral(c *LiteralContext)

	// ExitStringLiteral is called when exiting the stringLiteral production.
	ExitStringLiteral(c *StringLiteralContext)

	// ExitNumberLiteral is called when exiting the numberLiteral production.
	ExitNumberLiteral(c *NumberLiteralContext)

	// ExitBooleanLiteral is called when exiting the booleanLiteral production.
	ExitBooleanLiteral(c *BooleanLiteralContext)

	// ExitArrayLiteral is called when exiting the arrayLiteral production.
	ExitArrayLiteral(c *ArrayLiteralContext)

	// ExitObjectLiteral is called when exiting the objectLiteral production.
	ExitObjectLiteral(c *ObjectLiteralContext)

	// ExitObjectFieldList is called when exiting the objectFieldList production.
	ExitObjectFieldList(c *ObjectFieldListContext)

	// ExitObjectField is called when exiting the objectField production.
	ExitObjectField(c *ObjectFieldContext)

	// ExitObjectFieldName is called when exiting the objectFieldName production.
	ExitObjectFieldName(c *ObjectFieldNameContext)

	// ExitMapLiteral is called when exiting the mapLiteral production.
	ExitMapLiteral(c *MapLiteralContext)

	// ExitMapFieldList is called when exiting the mapFieldList production.
	ExitMapFieldList(c *MapFieldListContext)

	// ExitMapField is called when exiting the mapField production.
	ExitMapField(c *MapFieldContext)

	// ExitSetLiteral is called when exiting the setLiteral production.
	ExitSetLiteral(c *SetLiteralContext)

	// ExitTaggedBlockString is called when exiting the taggedBlockString production.
	ExitTaggedBlockString(c *TaggedBlockStringContext)

	// ExitStructInitExpr is called when exiting the structInitExpr production.
	ExitStructInitExpr(c *StructInitExprContext)

	// ExitStructFieldList is called when exiting the structFieldList production.
	ExitStructFieldList(c *StructFieldListContext)

	// ExitStructField is called when exiting the structField production.
	ExitStructField(c *StructFieldContext)

	// ExitTypeAnnotation is called when exiting the typeAnnotation production.
	ExitTypeAnnotation(c *TypeAnnotationContext)

	// ExitTupleType is called when exiting the tupleType production.
	ExitTupleType(c *TupleTypeContext)

	// ExitArrayType is called when exiting the arrayType production.
	ExitArrayType(c *ArrayTypeContext)

	// ExitFnType is called when exiting the fnType production.
	ExitFnType(c *FnTypeContext)

	// ExitStmt_sep is called when exiting the stmt_sep production.
	ExitStmt_sep(c *Stmt_sepContext)
}
