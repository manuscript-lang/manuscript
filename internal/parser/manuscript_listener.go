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

	// EnterLabelLetBlockItemSingle is called when entering the LabelLetBlockItemSingle production.
	EnterLabelLetBlockItemSingle(c *LabelLetBlockItemSingleContext)

	// EnterLabelLetBlockItemDestructuredObj is called when entering the LabelLetBlockItemDestructuredObj production.
	EnterLabelLetBlockItemDestructuredObj(c *LabelLetBlockItemDestructuredObjContext)

	// EnterLabelLetBlockItemDestructuredArray is called when entering the LabelLetBlockItemDestructuredArray production.
	EnterLabelLetBlockItemDestructuredArray(c *LabelLetBlockItemDestructuredArrayContext)

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

	// EnterMethodImpl is called when entering the methodImpl production.
	EnterMethodImpl(c *MethodImplContext)

	// EnterLabelStmtLet is called when entering the LabelStmtLet production.
	EnterLabelStmtLet(c *LabelStmtLetContext)

	// EnterLabelStmtExpr is called when entering the LabelStmtExpr production.
	EnterLabelStmtExpr(c *LabelStmtExprContext)

	// EnterLabelStmtReturn is called when entering the LabelStmtReturn production.
	EnterLabelStmtReturn(c *LabelStmtReturnContext)

	// EnterLabelStmtYield is called when entering the LabelStmtYield production.
	EnterLabelStmtYield(c *LabelStmtYieldContext)

	// EnterLabelStmtIf is called when entering the LabelStmtIf production.
	EnterLabelStmtIf(c *LabelStmtIfContext)

	// EnterLabelStmtFor is called when entering the LabelStmtFor production.
	EnterLabelStmtFor(c *LabelStmtForContext)

	// EnterLabelStmtWhile is called when entering the LabelStmtWhile production.
	EnterLabelStmtWhile(c *LabelStmtWhileContext)

	// EnterLabelStmtBlock is called when entering the LabelStmtBlock production.
	EnterLabelStmtBlock(c *LabelStmtBlockContext)

	// EnterLabelStmtBreak is called when entering the LabelStmtBreak production.
	EnterLabelStmtBreak(c *LabelStmtBreakContext)

	// EnterLabelStmtContinue is called when entering the LabelStmtContinue production.
	EnterLabelStmtContinue(c *LabelStmtContinueContext)

	// EnterLabelStmtCheck is called when entering the LabelStmtCheck production.
	EnterLabelStmtCheck(c *LabelStmtCheckContext)

	// EnterLabelStmtDefer is called when entering the LabelStmtDefer production.
	EnterLabelStmtDefer(c *LabelStmtDeferContext)

	// EnterLabelStmtTry is called when entering the LabelStmtTry production.
	EnterLabelStmtTry(c *LabelStmtTryContext)

	// EnterLabelStmtPiped is called when entering the LabelStmtPiped production.
	EnterLabelStmtPiped(c *LabelStmtPipedContext)

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

	// EnterLabelForLoop is called when entering the LabelForLoop production.
	EnterLabelForLoop(c *LabelForLoopContext)

	// EnterLabelForInLoop is called when entering the LabelForInLoop production.
	EnterLabelForInLoop(c *LabelForInLoopContext)

	// EnterForTrinity is called when entering the forTrinity production.
	EnterForTrinity(c *ForTrinityContext)

	// EnterLabelForInitLet is called when entering the LabelForInitLet production.
	EnterLabelForInitLet(c *LabelForInitLetContext)

	// EnterLabelForInitEmpty is called when entering the LabelForInitEmpty production.
	EnterLabelForInitEmpty(c *LabelForInitEmptyContext)

	// EnterLabelForCondExpr is called when entering the LabelForCondExpr production.
	EnterLabelForCondExpr(c *LabelForCondExprContext)

	// EnterLabelForCondEmpty is called when entering the LabelForCondEmpty production.
	EnterLabelForCondEmpty(c *LabelForCondEmptyContext)

	// EnterLabelForPostExpr is called when entering the LabelForPostExpr production.
	EnterLabelForPostExpr(c *LabelForPostExprContext)

	// EnterLabelForPostEmpty is called when entering the LabelForPostEmpty production.
	EnterLabelForPostEmpty(c *LabelForPostEmptyContext)

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

	// EnterPipedStmt is called when entering the pipedStmt production.
	EnterPipedStmt(c *PipedStmtContext)

	// EnterPipedArgs is called when entering the pipedArgs production.
	EnterPipedArgs(c *PipedArgsContext)

	// EnterPipedArg is called when entering the pipedArg production.
	EnterPipedArg(c *PipedArgContext)

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

	// EnterBitwiseXorExpr is called when entering the bitwiseXorExpr production.
	EnterBitwiseXorExpr(c *BitwiseXorExprContext)

	// EnterBitwiseAndExpr is called when entering the bitwiseAndExpr production.
	EnterBitwiseAndExpr(c *BitwiseAndExprContext)

	// EnterEqualityExpr is called when entering the equalityExpr production.
	EnterEqualityExpr(c *EqualityExprContext)

	// EnterComparisonOp is called when entering the comparisonOp production.
	EnterComparisonOp(c *ComparisonOpContext)

	// EnterComparisonExpr is called when entering the comparisonExpr production.
	EnterComparisonExpr(c *ComparisonExprContext)

	// EnterShiftExpr is called when entering the shiftExpr production.
	EnterShiftExpr(c *ShiftExprContext)

	// EnterAdditiveExpr is called when entering the additiveExpr production.
	EnterAdditiveExpr(c *AdditiveExprContext)

	// EnterMultiplicativeExpr is called when entering the multiplicativeExpr production.
	EnterMultiplicativeExpr(c *MultiplicativeExprContext)

	// EnterLabelUnaryOpExpr is called when entering the LabelUnaryOpExpr production.
	EnterLabelUnaryOpExpr(c *LabelUnaryOpExprContext)

	// EnterLabelUnaryAwaitExpr is called when entering the LabelUnaryAwaitExpr production.
	EnterLabelUnaryAwaitExpr(c *LabelUnaryAwaitExprContext)

	// EnterAwaitExpr is called when entering the awaitExpr production.
	EnterAwaitExpr(c *AwaitExprContext)

	// EnterPostfixExpr is called when entering the postfixExpr production.
	EnterPostfixExpr(c *PostfixExprContext)

	// EnterLabelPostfixCall is called when entering the LabelPostfixCall production.
	EnterLabelPostfixCall(c *LabelPostfixCallContext)

	// EnterLabelPostfixDot is called when entering the LabelPostfixDot production.
	EnterLabelPostfixDot(c *LabelPostfixDotContext)

	// EnterLabelPostfixIndex is called when entering the LabelPostfixIndex production.
	EnterLabelPostfixIndex(c *LabelPostfixIndexContext)

	// EnterLabelPrimaryLiteral is called when entering the LabelPrimaryLiteral production.
	EnterLabelPrimaryLiteral(c *LabelPrimaryLiteralContext)

	// EnterLabelPrimaryID is called when entering the LabelPrimaryID production.
	EnterLabelPrimaryID(c *LabelPrimaryIDContext)

	// EnterLabelPrimaryParen is called when entering the LabelPrimaryParen production.
	EnterLabelPrimaryParen(c *LabelPrimaryParenContext)

	// EnterLabelPrimaryArray is called when entering the LabelPrimaryArray production.
	EnterLabelPrimaryArray(c *LabelPrimaryArrayContext)

	// EnterLabelPrimaryObject is called when entering the LabelPrimaryObject production.
	EnterLabelPrimaryObject(c *LabelPrimaryObjectContext)

	// EnterLabelPrimaryMap is called when entering the LabelPrimaryMap production.
	EnterLabelPrimaryMap(c *LabelPrimaryMapContext)

	// EnterLabelPrimarySet is called when entering the LabelPrimarySet production.
	EnterLabelPrimarySet(c *LabelPrimarySetContext)

	// EnterLabelPrimaryFn is called when entering the LabelPrimaryFn production.
	EnterLabelPrimaryFn(c *LabelPrimaryFnContext)

	// EnterLabelPrimaryMatch is called when entering the LabelPrimaryMatch production.
	EnterLabelPrimaryMatch(c *LabelPrimaryMatchContext)

	// EnterLabelPrimaryVoid is called when entering the LabelPrimaryVoid production.
	EnterLabelPrimaryVoid(c *LabelPrimaryVoidContext)

	// EnterLabelPrimaryNull is called when entering the LabelPrimaryNull production.
	EnterLabelPrimaryNull(c *LabelPrimaryNullContext)

	// EnterLabelPrimaryTaggedBlock is called when entering the LabelPrimaryTaggedBlock production.
	EnterLabelPrimaryTaggedBlock(c *LabelPrimaryTaggedBlockContext)

	// EnterLabelPrimaryStructInit is called when entering the LabelPrimaryStructInit production.
	EnterLabelPrimaryStructInit(c *LabelPrimaryStructInitContext)

	// EnterTryExpr is called when entering the tryExpr production.
	EnterTryExpr(c *TryExprContext)

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

	// EnterLabelLiteralString is called when entering the LabelLiteralString production.
	EnterLabelLiteralString(c *LabelLiteralStringContext)

	// EnterLabelLiteralNumber is called when entering the LabelLiteralNumber production.
	EnterLabelLiteralNumber(c *LabelLiteralNumberContext)

	// EnterLabelLiteralBool is called when entering the LabelLiteralBool production.
	EnterLabelLiteralBool(c *LabelLiteralBoolContext)

	// EnterLabelLiteralNull is called when entering the LabelLiteralNull production.
	EnterLabelLiteralNull(c *LabelLiteralNullContext)

	// EnterLabelLiteralVoid is called when entering the LabelLiteralVoid production.
	EnterLabelLiteralVoid(c *LabelLiteralVoidContext)

	// EnterStringLiteral is called when entering the stringLiteral production.
	EnterStringLiteral(c *StringLiteralContext)

	// EnterLabelNumberLiteralInt is called when entering the LabelNumberLiteralInt production.
	EnterLabelNumberLiteralInt(c *LabelNumberLiteralIntContext)

	// EnterLabelNumberLiteralFloat is called when entering the LabelNumberLiteralFloat production.
	EnterLabelNumberLiteralFloat(c *LabelNumberLiteralFloatContext)

	// EnterLabelNumberLiteralHex is called when entering the LabelNumberLiteralHex production.
	EnterLabelNumberLiteralHex(c *LabelNumberLiteralHexContext)

	// EnterLabelNumberLiteralBin is called when entering the LabelNumberLiteralBin production.
	EnterLabelNumberLiteralBin(c *LabelNumberLiteralBinContext)

	// EnterLabelNumberLiteralOct is called when entering the LabelNumberLiteralOct production.
	EnterLabelNumberLiteralOct(c *LabelNumberLiteralOctContext)

	// EnterLabelBoolLiteralTrue is called when entering the LabelBoolLiteralTrue production.
	EnterLabelBoolLiteralTrue(c *LabelBoolLiteralTrueContext)

	// EnterLabelBoolLiteralFalse is called when entering the LabelBoolLiteralFalse production.
	EnterLabelBoolLiteralFalse(c *LabelBoolLiteralFalseContext)

	// EnterArrayLiteral is called when entering the arrayLiteral production.
	EnterArrayLiteral(c *ArrayLiteralContext)

	// EnterObjectLiteral is called when entering the objectLiteral production.
	EnterObjectLiteral(c *ObjectLiteralContext)

	// EnterObjectFieldList is called when entering the objectFieldList production.
	EnterObjectFieldList(c *ObjectFieldListContext)

	// EnterObjectField is called when entering the objectField production.
	EnterObjectField(c *ObjectFieldContext)

	// EnterLabelObjectFieldNameID is called when entering the LabelObjectFieldNameID production.
	EnterLabelObjectFieldNameID(c *LabelObjectFieldNameIDContext)

	// EnterLabelObjectFieldNameStr is called when entering the LabelObjectFieldNameStr production.
	EnterLabelObjectFieldNameStr(c *LabelObjectFieldNameStrContext)

	// EnterLabelMapLiteralEmpty is called when entering the LabelMapLiteralEmpty production.
	EnterLabelMapLiteralEmpty(c *LabelMapLiteralEmptyContext)

	// EnterLabelMapLiteralNonEmpty is called when entering the LabelMapLiteralNonEmpty production.
	EnterLabelMapLiteralNonEmpty(c *LabelMapLiteralNonEmptyContext)

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

	// EnterLabelTypeAnnID is called when entering the LabelTypeAnnID production.
	EnterLabelTypeAnnID(c *LabelTypeAnnIDContext)

	// EnterLabelTypeAnnArray is called when entering the LabelTypeAnnArray production.
	EnterLabelTypeAnnArray(c *LabelTypeAnnArrayContext)

	// EnterLabelTypeAnnTuple is called when entering the LabelTypeAnnTuple production.
	EnterLabelTypeAnnTuple(c *LabelTypeAnnTupleContext)

	// EnterLabelTypeAnnFn is called when entering the LabelTypeAnnFn production.
	EnterLabelTypeAnnFn(c *LabelTypeAnnFnContext)

	// EnterLabelTypeAnnVoid is called when entering the LabelTypeAnnVoid production.
	EnterLabelTypeAnnVoid(c *LabelTypeAnnVoidContext)

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

	// ExitLabelLetBlockItemSingle is called when exiting the LabelLetBlockItemSingle production.
	ExitLabelLetBlockItemSingle(c *LabelLetBlockItemSingleContext)

	// ExitLabelLetBlockItemDestructuredObj is called when exiting the LabelLetBlockItemDestructuredObj production.
	ExitLabelLetBlockItemDestructuredObj(c *LabelLetBlockItemDestructuredObjContext)

	// ExitLabelLetBlockItemDestructuredArray is called when exiting the LabelLetBlockItemDestructuredArray production.
	ExitLabelLetBlockItemDestructuredArray(c *LabelLetBlockItemDestructuredArrayContext)

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

	// ExitMethodImpl is called when exiting the methodImpl production.
	ExitMethodImpl(c *MethodImplContext)

	// ExitLabelStmtLet is called when exiting the LabelStmtLet production.
	ExitLabelStmtLet(c *LabelStmtLetContext)

	// ExitLabelStmtExpr is called when exiting the LabelStmtExpr production.
	ExitLabelStmtExpr(c *LabelStmtExprContext)

	// ExitLabelStmtReturn is called when exiting the LabelStmtReturn production.
	ExitLabelStmtReturn(c *LabelStmtReturnContext)

	// ExitLabelStmtYield is called when exiting the LabelStmtYield production.
	ExitLabelStmtYield(c *LabelStmtYieldContext)

	// ExitLabelStmtIf is called when exiting the LabelStmtIf production.
	ExitLabelStmtIf(c *LabelStmtIfContext)

	// ExitLabelStmtFor is called when exiting the LabelStmtFor production.
	ExitLabelStmtFor(c *LabelStmtForContext)

	// ExitLabelStmtWhile is called when exiting the LabelStmtWhile production.
	ExitLabelStmtWhile(c *LabelStmtWhileContext)

	// ExitLabelStmtBlock is called when exiting the LabelStmtBlock production.
	ExitLabelStmtBlock(c *LabelStmtBlockContext)

	// ExitLabelStmtBreak is called when exiting the LabelStmtBreak production.
	ExitLabelStmtBreak(c *LabelStmtBreakContext)

	// ExitLabelStmtContinue is called when exiting the LabelStmtContinue production.
	ExitLabelStmtContinue(c *LabelStmtContinueContext)

	// ExitLabelStmtCheck is called when exiting the LabelStmtCheck production.
	ExitLabelStmtCheck(c *LabelStmtCheckContext)

	// ExitLabelStmtDefer is called when exiting the LabelStmtDefer production.
	ExitLabelStmtDefer(c *LabelStmtDeferContext)

	// ExitLabelStmtTry is called when exiting the LabelStmtTry production.
	ExitLabelStmtTry(c *LabelStmtTryContext)

	// ExitLabelStmtPiped is called when exiting the LabelStmtPiped production.
	ExitLabelStmtPiped(c *LabelStmtPipedContext)

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

	// ExitLabelForLoop is called when exiting the LabelForLoop production.
	ExitLabelForLoop(c *LabelForLoopContext)

	// ExitLabelForInLoop is called when exiting the LabelForInLoop production.
	ExitLabelForInLoop(c *LabelForInLoopContext)

	// ExitForTrinity is called when exiting the forTrinity production.
	ExitForTrinity(c *ForTrinityContext)

	// ExitLabelForInitLet is called when exiting the LabelForInitLet production.
	ExitLabelForInitLet(c *LabelForInitLetContext)

	// ExitLabelForInitEmpty is called when exiting the LabelForInitEmpty production.
	ExitLabelForInitEmpty(c *LabelForInitEmptyContext)

	// ExitLabelForCondExpr is called when exiting the LabelForCondExpr production.
	ExitLabelForCondExpr(c *LabelForCondExprContext)

	// ExitLabelForCondEmpty is called when exiting the LabelForCondEmpty production.
	ExitLabelForCondEmpty(c *LabelForCondEmptyContext)

	// ExitLabelForPostExpr is called when exiting the LabelForPostExpr production.
	ExitLabelForPostExpr(c *LabelForPostExprContext)

	// ExitLabelForPostEmpty is called when exiting the LabelForPostEmpty production.
	ExitLabelForPostEmpty(c *LabelForPostEmptyContext)

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

	// ExitPipedStmt is called when exiting the pipedStmt production.
	ExitPipedStmt(c *PipedStmtContext)

	// ExitPipedArgs is called when exiting the pipedArgs production.
	ExitPipedArgs(c *PipedArgsContext)

	// ExitPipedArg is called when exiting the pipedArg production.
	ExitPipedArg(c *PipedArgContext)

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

	// ExitBitwiseXorExpr is called when exiting the bitwiseXorExpr production.
	ExitBitwiseXorExpr(c *BitwiseXorExprContext)

	// ExitBitwiseAndExpr is called when exiting the bitwiseAndExpr production.
	ExitBitwiseAndExpr(c *BitwiseAndExprContext)

	// ExitEqualityExpr is called when exiting the equalityExpr production.
	ExitEqualityExpr(c *EqualityExprContext)

	// ExitComparisonOp is called when exiting the comparisonOp production.
	ExitComparisonOp(c *ComparisonOpContext)

	// ExitComparisonExpr is called when exiting the comparisonExpr production.
	ExitComparisonExpr(c *ComparisonExprContext)

	// ExitShiftExpr is called when exiting the shiftExpr production.
	ExitShiftExpr(c *ShiftExprContext)

	// ExitAdditiveExpr is called when exiting the additiveExpr production.
	ExitAdditiveExpr(c *AdditiveExprContext)

	// ExitMultiplicativeExpr is called when exiting the multiplicativeExpr production.
	ExitMultiplicativeExpr(c *MultiplicativeExprContext)

	// ExitLabelUnaryOpExpr is called when exiting the LabelUnaryOpExpr production.
	ExitLabelUnaryOpExpr(c *LabelUnaryOpExprContext)

	// ExitLabelUnaryAwaitExpr is called when exiting the LabelUnaryAwaitExpr production.
	ExitLabelUnaryAwaitExpr(c *LabelUnaryAwaitExprContext)

	// ExitAwaitExpr is called when exiting the awaitExpr production.
	ExitAwaitExpr(c *AwaitExprContext)

	// ExitPostfixExpr is called when exiting the postfixExpr production.
	ExitPostfixExpr(c *PostfixExprContext)

	// ExitLabelPostfixCall is called when exiting the LabelPostfixCall production.
	ExitLabelPostfixCall(c *LabelPostfixCallContext)

	// ExitLabelPostfixDot is called when exiting the LabelPostfixDot production.
	ExitLabelPostfixDot(c *LabelPostfixDotContext)

	// ExitLabelPostfixIndex is called when exiting the LabelPostfixIndex production.
	ExitLabelPostfixIndex(c *LabelPostfixIndexContext)

	// ExitLabelPrimaryLiteral is called when exiting the LabelPrimaryLiteral production.
	ExitLabelPrimaryLiteral(c *LabelPrimaryLiteralContext)

	// ExitLabelPrimaryID is called when exiting the LabelPrimaryID production.
	ExitLabelPrimaryID(c *LabelPrimaryIDContext)

	// ExitLabelPrimaryParen is called when exiting the LabelPrimaryParen production.
	ExitLabelPrimaryParen(c *LabelPrimaryParenContext)

	// ExitLabelPrimaryArray is called when exiting the LabelPrimaryArray production.
	ExitLabelPrimaryArray(c *LabelPrimaryArrayContext)

	// ExitLabelPrimaryObject is called when exiting the LabelPrimaryObject production.
	ExitLabelPrimaryObject(c *LabelPrimaryObjectContext)

	// ExitLabelPrimaryMap is called when exiting the LabelPrimaryMap production.
	ExitLabelPrimaryMap(c *LabelPrimaryMapContext)

	// ExitLabelPrimarySet is called when exiting the LabelPrimarySet production.
	ExitLabelPrimarySet(c *LabelPrimarySetContext)

	// ExitLabelPrimaryFn is called when exiting the LabelPrimaryFn production.
	ExitLabelPrimaryFn(c *LabelPrimaryFnContext)

	// ExitLabelPrimaryMatch is called when exiting the LabelPrimaryMatch production.
	ExitLabelPrimaryMatch(c *LabelPrimaryMatchContext)

	// ExitLabelPrimaryVoid is called when exiting the LabelPrimaryVoid production.
	ExitLabelPrimaryVoid(c *LabelPrimaryVoidContext)

	// ExitLabelPrimaryNull is called when exiting the LabelPrimaryNull production.
	ExitLabelPrimaryNull(c *LabelPrimaryNullContext)

	// ExitLabelPrimaryTaggedBlock is called when exiting the LabelPrimaryTaggedBlock production.
	ExitLabelPrimaryTaggedBlock(c *LabelPrimaryTaggedBlockContext)

	// ExitLabelPrimaryStructInit is called when exiting the LabelPrimaryStructInit production.
	ExitLabelPrimaryStructInit(c *LabelPrimaryStructInitContext)

	// ExitTryExpr is called when exiting the tryExpr production.
	ExitTryExpr(c *TryExprContext)

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

	// ExitLabelLiteralString is called when exiting the LabelLiteralString production.
	ExitLabelLiteralString(c *LabelLiteralStringContext)

	// ExitLabelLiteralNumber is called when exiting the LabelLiteralNumber production.
	ExitLabelLiteralNumber(c *LabelLiteralNumberContext)

	// ExitLabelLiteralBool is called when exiting the LabelLiteralBool production.
	ExitLabelLiteralBool(c *LabelLiteralBoolContext)

	// ExitLabelLiteralNull is called when exiting the LabelLiteralNull production.
	ExitLabelLiteralNull(c *LabelLiteralNullContext)

	// ExitLabelLiteralVoid is called when exiting the LabelLiteralVoid production.
	ExitLabelLiteralVoid(c *LabelLiteralVoidContext)

	// ExitStringLiteral is called when exiting the stringLiteral production.
	ExitStringLiteral(c *StringLiteralContext)

	// ExitLabelNumberLiteralInt is called when exiting the LabelNumberLiteralInt production.
	ExitLabelNumberLiteralInt(c *LabelNumberLiteralIntContext)

	// ExitLabelNumberLiteralFloat is called when exiting the LabelNumberLiteralFloat production.
	ExitLabelNumberLiteralFloat(c *LabelNumberLiteralFloatContext)

	// ExitLabelNumberLiteralHex is called when exiting the LabelNumberLiteralHex production.
	ExitLabelNumberLiteralHex(c *LabelNumberLiteralHexContext)

	// ExitLabelNumberLiteralBin is called when exiting the LabelNumberLiteralBin production.
	ExitLabelNumberLiteralBin(c *LabelNumberLiteralBinContext)

	// ExitLabelNumberLiteralOct is called when exiting the LabelNumberLiteralOct production.
	ExitLabelNumberLiteralOct(c *LabelNumberLiteralOctContext)

	// ExitLabelBoolLiteralTrue is called when exiting the LabelBoolLiteralTrue production.
	ExitLabelBoolLiteralTrue(c *LabelBoolLiteralTrueContext)

	// ExitLabelBoolLiteralFalse is called when exiting the LabelBoolLiteralFalse production.
	ExitLabelBoolLiteralFalse(c *LabelBoolLiteralFalseContext)

	// ExitArrayLiteral is called when exiting the arrayLiteral production.
	ExitArrayLiteral(c *ArrayLiteralContext)

	// ExitObjectLiteral is called when exiting the objectLiteral production.
	ExitObjectLiteral(c *ObjectLiteralContext)

	// ExitObjectFieldList is called when exiting the objectFieldList production.
	ExitObjectFieldList(c *ObjectFieldListContext)

	// ExitObjectField is called when exiting the objectField production.
	ExitObjectField(c *ObjectFieldContext)

	// ExitLabelObjectFieldNameID is called when exiting the LabelObjectFieldNameID production.
	ExitLabelObjectFieldNameID(c *LabelObjectFieldNameIDContext)

	// ExitLabelObjectFieldNameStr is called when exiting the LabelObjectFieldNameStr production.
	ExitLabelObjectFieldNameStr(c *LabelObjectFieldNameStrContext)

	// ExitLabelMapLiteralEmpty is called when exiting the LabelMapLiteralEmpty production.
	ExitLabelMapLiteralEmpty(c *LabelMapLiteralEmptyContext)

	// ExitLabelMapLiteralNonEmpty is called when exiting the LabelMapLiteralNonEmpty production.
	ExitLabelMapLiteralNonEmpty(c *LabelMapLiteralNonEmptyContext)

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

	// ExitLabelTypeAnnID is called when exiting the LabelTypeAnnID production.
	ExitLabelTypeAnnID(c *LabelTypeAnnIDContext)

	// ExitLabelTypeAnnArray is called when exiting the LabelTypeAnnArray production.
	ExitLabelTypeAnnArray(c *LabelTypeAnnArrayContext)

	// ExitLabelTypeAnnTuple is called when exiting the LabelTypeAnnTuple production.
	ExitLabelTypeAnnTuple(c *LabelTypeAnnTupleContext)

	// ExitLabelTypeAnnFn is called when exiting the LabelTypeAnnFn production.
	ExitLabelTypeAnnFn(c *LabelTypeAnnFnContext)

	// ExitLabelTypeAnnVoid is called when exiting the LabelTypeAnnVoid production.
	ExitLabelTypeAnnVoid(c *LabelTypeAnnVoidContext)

	// ExitTupleType is called when exiting the tupleType production.
	ExitTupleType(c *TupleTypeContext)

	// ExitArrayType is called when exiting the arrayType production.
	ExitArrayType(c *ArrayTypeContext)

	// ExitFnType is called when exiting the fnType production.
	ExitFnType(c *FnTypeContext)

	// ExitStmt_sep is called when exiting the stmt_sep production.
	ExitStmt_sep(c *Stmt_sepContext)
}
