// Code generated from Manuscript.g4 by ANTLR 4.13.1. DO NOT EDIT.

package parser // Manuscript

import "github.com/antlr4-go/antlr/v4"

// ManuscriptListener is a complete listener for a parse tree produced by Manuscript.
type ManuscriptListener interface {
	antlr.ParseTreeListener

	// EnterProgram is called when entering the program production.
	EnterProgram(c *ProgramContext)

	// EnterDeclImport is called when entering the DeclImport production.
	EnterDeclImport(c *DeclImportContext)

	// EnterDeclExport is called when entering the DeclExport production.
	EnterDeclExport(c *DeclExportContext)

	// EnterDeclExtern is called when entering the DeclExtern production.
	EnterDeclExtern(c *DeclExternContext)

	// EnterDeclLet is called when entering the DeclLet production.
	EnterDeclLet(c *DeclLetContext)

	// EnterDeclType is called when entering the DeclType production.
	EnterDeclType(c *DeclTypeContext)

	// EnterDeclInterface is called when entering the DeclInterface production.
	EnterDeclInterface(c *DeclInterfaceContext)

	// EnterDeclFn is called when entering the DeclFn production.
	EnterDeclFn(c *DeclFnContext)

	// EnterDeclMethods is called when entering the DeclMethods production.
	EnterDeclMethods(c *DeclMethodsContext)

	// EnterImportDecl is called when entering the importDecl production.
	EnterImportDecl(c *ImportDeclContext)

	// EnterExportDecl is called when entering the exportDecl production.
	EnterExportDecl(c *ExportDeclContext)

	// EnterExternDecl is called when entering the externDecl production.
	EnterExternDecl(c *ExternDeclContext)

	// EnterExportedFn is called when entering the ExportedFn production.
	EnterExportedFn(c *ExportedFnContext)

	// EnterExportedLet is called when entering the ExportedLet production.
	EnterExportedLet(c *ExportedLetContext)

	// EnterExportedType is called when entering the ExportedType production.
	EnterExportedType(c *ExportedTypeContext)

	// EnterExportedInterface is called when entering the ExportedInterface production.
	EnterExportedInterface(c *ExportedInterfaceContext)

	// EnterModuleImportDestructured is called when entering the ModuleImportDestructured production.
	EnterModuleImportDestructured(c *ModuleImportDestructuredContext)

	// EnterModuleImportTarget is called when entering the ModuleImportTarget production.
	EnterModuleImportTarget(c *ModuleImportTargetContext)

	// EnterDestructuredImport is called when entering the destructuredImport production.
	EnterDestructuredImport(c *DestructuredImportContext)

	// EnterTargetImport is called when entering the targetImport production.
	EnterTargetImport(c *TargetImportContext)

	// EnterImportItemList is called when entering the importItemList production.
	EnterImportItemList(c *ImportItemListContext)

	// EnterImportItem is called when entering the importItem production.
	EnterImportItem(c *ImportItemContext)

	// EnterLetDeclSingle is called when entering the LetDeclSingle production.
	EnterLetDeclSingle(c *LetDeclSingleContext)

	// EnterLetDeclBlock is called when entering the LetDeclBlock production.
	EnterLetDeclBlock(c *LetDeclBlockContext)

	// EnterLetDeclDestructuredObj is called when entering the LetDeclDestructuredObj production.
	EnterLetDeclDestructuredObj(c *LetDeclDestructuredObjContext)

	// EnterLetDeclDestructuredArray is called when entering the LetDeclDestructuredArray production.
	EnterLetDeclDestructuredArray(c *LetDeclDestructuredArrayContext)

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

	// EnterForInitLet is called when entering the ForInitLet production.
	EnterForInitLet(c *ForInitLetContext)

	// EnterForInitEmpty is called when entering the ForInitEmpty production.
	EnterForInitEmpty(c *ForInitEmptyContext)

	// EnterForCondExpr is called when entering the ForCondExpr production.
	EnterForCondExpr(c *ForCondExprContext)

	// EnterForCondEmpty is called when entering the ForCondEmpty production.
	EnterForCondEmpty(c *ForCondEmptyContext)

	// EnterForPostExpr is called when entering the ForPostExpr production.
	EnterForPostExpr(c *ForPostExprContext)

	// EnterForPostEmpty is called when entering the ForPostEmpty production.
	EnterForPostEmpty(c *ForPostEmptyContext)

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

	// EnterAssignEq is called when entering the AssignEq production.
	EnterAssignEq(c *AssignEqContext)

	// EnterAssignPlusEq is called when entering the AssignPlusEq production.
	EnterAssignPlusEq(c *AssignPlusEqContext)

	// EnterAssignMinusEq is called when entering the AssignMinusEq production.
	EnterAssignMinusEq(c *AssignMinusEqContext)

	// EnterAssignStarEq is called when entering the AssignStarEq production.
	EnterAssignStarEq(c *AssignStarEqContext)

	// EnterAssignSlashEq is called when entering the AssignSlashEq production.
	EnterAssignSlashEq(c *AssignSlashEqContext)

	// EnterAssignModEq is called when entering the AssignModEq production.
	EnterAssignModEq(c *AssignModEqContext)

	// EnterAssignCaretEq is called when entering the AssignCaretEq production.
	EnterAssignCaretEq(c *AssignCaretEqContext)

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

	// EnterUnaryOpExpr is called when entering the UnaryOpExpr production.
	EnterUnaryOpExpr(c *UnaryOpExprContext)

	// EnterUnaryAwaitExpr is called when entering the UnaryAwaitExpr production.
	EnterUnaryAwaitExpr(c *UnaryAwaitExprContext)

	// EnterAwaitExpr is called when entering the awaitExpr production.
	EnterAwaitExpr(c *AwaitExprContext)

	// EnterPostfixExpr is called when entering the postfixExpr production.
	EnterPostfixExpr(c *PostfixExprContext)

	// EnterPostfixCall is called when entering the PostfixCall production.
	EnterPostfixCall(c *PostfixCallContext)

	// EnterPostfixDot is called when entering the PostfixDot production.
	EnterPostfixDot(c *PostfixDotContext)

	// EnterPostfixIndex is called when entering the PostfixIndex production.
	EnterPostfixIndex(c *PostfixIndexContext)

	// EnterPrimaryLiteral is called when entering the PrimaryLiteral production.
	EnterPrimaryLiteral(c *PrimaryLiteralContext)

	// EnterPrimaryID is called when entering the PrimaryID production.
	EnterPrimaryID(c *PrimaryIDContext)

	// EnterPrimaryParen is called when entering the PrimaryParen production.
	EnterPrimaryParen(c *PrimaryParenContext)

	// EnterPrimaryArray is called when entering the PrimaryArray production.
	EnterPrimaryArray(c *PrimaryArrayContext)

	// EnterPrimaryObject is called when entering the PrimaryObject production.
	EnterPrimaryObject(c *PrimaryObjectContext)

	// EnterPrimaryMap is called when entering the PrimaryMap production.
	EnterPrimaryMap(c *PrimaryMapContext)

	// EnterPrimarySet is called when entering the PrimarySet production.
	EnterPrimarySet(c *PrimarySetContext)

	// EnterPrimaryFn is called when entering the PrimaryFn production.
	EnterPrimaryFn(c *PrimaryFnContext)

	// EnterPrimaryMatch is called when entering the PrimaryMatch production.
	EnterPrimaryMatch(c *PrimaryMatchContext)

	// EnterPrimaryVoid is called when entering the PrimaryVoid production.
	EnterPrimaryVoid(c *PrimaryVoidContext)

	// EnterPrimaryNull is called when entering the PrimaryNull production.
	EnterPrimaryNull(c *PrimaryNullContext)

	// EnterPrimaryTaggedBlock is called when entering the PrimaryTaggedBlock production.
	EnterPrimaryTaggedBlock(c *PrimaryTaggedBlockContext)

	// EnterPrimaryStructInit is called when entering the PrimaryStructInit production.
	EnterPrimaryStructInit(c *PrimaryStructInitContext)

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

	// EnterStringPartSingle is called when entering the StringPartSingle production.
	EnterStringPartSingle(c *StringPartSingleContext)

	// EnterStringPartMulti is called when entering the StringPartMulti production.
	EnterStringPartMulti(c *StringPartMultiContext)

	// EnterStringPartDouble is called when entering the StringPartDouble production.
	EnterStringPartDouble(c *StringPartDoubleContext)

	// EnterStringPartMultiDouble is called when entering the StringPartMultiDouble production.
	EnterStringPartMultiDouble(c *StringPartMultiDoubleContext)

	// EnterStringPartInterp is called when entering the StringPartInterp production.
	EnterStringPartInterp(c *StringPartInterpContext)

	// EnterInterpolation is called when entering the interpolation production.
	EnterInterpolation(c *InterpolationContext)

	// EnterLiteralString is called when entering the LiteralString production.
	EnterLiteralString(c *LiteralStringContext)

	// EnterLiteralNumber is called when entering the LiteralNumber production.
	EnterLiteralNumber(c *LiteralNumberContext)

	// EnterLiteralBool is called when entering the LiteralBool production.
	EnterLiteralBool(c *LiteralBoolContext)

	// EnterLiteralNull is called when entering the LiteralNull production.
	EnterLiteralNull(c *LiteralNullContext)

	// EnterLiteralVoid is called when entering the LiteralVoid production.
	EnterLiteralVoid(c *LiteralVoidContext)

	// EnterStringLiteralSingle is called when entering the StringLiteralSingle production.
	EnterStringLiteralSingle(c *StringLiteralSingleContext)

	// EnterStringLiteralMulti is called when entering the StringLiteralMulti production.
	EnterStringLiteralMulti(c *StringLiteralMultiContext)

	// EnterStringLiteralDouble is called when entering the StringLiteralDouble production.
	EnterStringLiteralDouble(c *StringLiteralDoubleContext)

	// EnterStringLiteralMultiDouble is called when entering the StringLiteralMultiDouble production.
	EnterStringLiteralMultiDouble(c *StringLiteralMultiDoubleContext)

	// EnterNumberLiteralInt is called when entering the NumberLiteralInt production.
	EnterNumberLiteralInt(c *NumberLiteralIntContext)

	// EnterNumberLiteralFloat is called when entering the NumberLiteralFloat production.
	EnterNumberLiteralFloat(c *NumberLiteralFloatContext)

	// EnterNumberLiteralHex is called when entering the NumberLiteralHex production.
	EnterNumberLiteralHex(c *NumberLiteralHexContext)

	// EnterNumberLiteralBin is called when entering the NumberLiteralBin production.
	EnterNumberLiteralBin(c *NumberLiteralBinContext)

	// EnterNumberLiteralOct is called when entering the NumberLiteralOct production.
	EnterNumberLiteralOct(c *NumberLiteralOctContext)

	// EnterBoolLiteralTrue is called when entering the BoolLiteralTrue production.
	EnterBoolLiteralTrue(c *BoolLiteralTrueContext)

	// EnterBoolLiteralFalse is called when entering the BoolLiteralFalse production.
	EnterBoolLiteralFalse(c *BoolLiteralFalseContext)

	// EnterArrayLiteral is called when entering the arrayLiteral production.
	EnterArrayLiteral(c *ArrayLiteralContext)

	// EnterObjectLiteral is called when entering the objectLiteral production.
	EnterObjectLiteral(c *ObjectLiteralContext)

	// EnterObjectFieldList is called when entering the objectFieldList production.
	EnterObjectFieldList(c *ObjectFieldListContext)

	// EnterObjectField is called when entering the objectField production.
	EnterObjectField(c *ObjectFieldContext)

	// EnterObjectFieldNameID is called when entering the ObjectFieldNameID production.
	EnterObjectFieldNameID(c *ObjectFieldNameIDContext)

	// EnterObjectFieldNameStr is called when entering the ObjectFieldNameStr production.
	EnterObjectFieldNameStr(c *ObjectFieldNameStrContext)

	// EnterMapLiteralEmpty is called when entering the MapLiteralEmpty production.
	EnterMapLiteralEmpty(c *MapLiteralEmptyContext)

	// EnterMapLiteralNonEmpty is called when entering the MapLiteralNonEmpty production.
	EnterMapLiteralNonEmpty(c *MapLiteralNonEmptyContext)

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

	// EnterTypeAnnID is called when entering the TypeAnnID production.
	EnterTypeAnnID(c *TypeAnnIDContext)

	// EnterTypeAnnArray is called when entering the TypeAnnArray production.
	EnterTypeAnnArray(c *TypeAnnArrayContext)

	// EnterTypeAnnTuple is called when entering the TypeAnnTuple production.
	EnterTypeAnnTuple(c *TypeAnnTupleContext)

	// EnterTypeAnnFn is called when entering the TypeAnnFn production.
	EnterTypeAnnFn(c *TypeAnnFnContext)

	// EnterTypeAnnVoid is called when entering the TypeAnnVoid production.
	EnterTypeAnnVoid(c *TypeAnnVoidContext)

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

	// ExitDeclImport is called when exiting the DeclImport production.
	ExitDeclImport(c *DeclImportContext)

	// ExitDeclExport is called when exiting the DeclExport production.
	ExitDeclExport(c *DeclExportContext)

	// ExitDeclExtern is called when exiting the DeclExtern production.
	ExitDeclExtern(c *DeclExternContext)

	// ExitDeclLet is called when exiting the DeclLet production.
	ExitDeclLet(c *DeclLetContext)

	// ExitDeclType is called when exiting the DeclType production.
	ExitDeclType(c *DeclTypeContext)

	// ExitDeclInterface is called when exiting the DeclInterface production.
	ExitDeclInterface(c *DeclInterfaceContext)

	// ExitDeclFn is called when exiting the DeclFn production.
	ExitDeclFn(c *DeclFnContext)

	// ExitDeclMethods is called when exiting the DeclMethods production.
	ExitDeclMethods(c *DeclMethodsContext)

	// ExitImportDecl is called when exiting the importDecl production.
	ExitImportDecl(c *ImportDeclContext)

	// ExitExportDecl is called when exiting the exportDecl production.
	ExitExportDecl(c *ExportDeclContext)

	// ExitExternDecl is called when exiting the externDecl production.
	ExitExternDecl(c *ExternDeclContext)

	// ExitExportedFn is called when exiting the ExportedFn production.
	ExitExportedFn(c *ExportedFnContext)

	// ExitExportedLet is called when exiting the ExportedLet production.
	ExitExportedLet(c *ExportedLetContext)

	// ExitExportedType is called when exiting the ExportedType production.
	ExitExportedType(c *ExportedTypeContext)

	// ExitExportedInterface is called when exiting the ExportedInterface production.
	ExitExportedInterface(c *ExportedInterfaceContext)

	// ExitModuleImportDestructured is called when exiting the ModuleImportDestructured production.
	ExitModuleImportDestructured(c *ModuleImportDestructuredContext)

	// ExitModuleImportTarget is called when exiting the ModuleImportTarget production.
	ExitModuleImportTarget(c *ModuleImportTargetContext)

	// ExitDestructuredImport is called when exiting the destructuredImport production.
	ExitDestructuredImport(c *DestructuredImportContext)

	// ExitTargetImport is called when exiting the targetImport production.
	ExitTargetImport(c *TargetImportContext)

	// ExitImportItemList is called when exiting the importItemList production.
	ExitImportItemList(c *ImportItemListContext)

	// ExitImportItem is called when exiting the importItem production.
	ExitImportItem(c *ImportItemContext)

	// ExitLetDeclSingle is called when exiting the LetDeclSingle production.
	ExitLetDeclSingle(c *LetDeclSingleContext)

	// ExitLetDeclBlock is called when exiting the LetDeclBlock production.
	ExitLetDeclBlock(c *LetDeclBlockContext)

	// ExitLetDeclDestructuredObj is called when exiting the LetDeclDestructuredObj production.
	ExitLetDeclDestructuredObj(c *LetDeclDestructuredObjContext)

	// ExitLetDeclDestructuredArray is called when exiting the LetDeclDestructuredArray production.
	ExitLetDeclDestructuredArray(c *LetDeclDestructuredArrayContext)

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

	// ExitForInitLet is called when exiting the ForInitLet production.
	ExitForInitLet(c *ForInitLetContext)

	// ExitForInitEmpty is called when exiting the ForInitEmpty production.
	ExitForInitEmpty(c *ForInitEmptyContext)

	// ExitForCondExpr is called when exiting the ForCondExpr production.
	ExitForCondExpr(c *ForCondExprContext)

	// ExitForCondEmpty is called when exiting the ForCondEmpty production.
	ExitForCondEmpty(c *ForCondEmptyContext)

	// ExitForPostExpr is called when exiting the ForPostExpr production.
	ExitForPostExpr(c *ForPostExprContext)

	// ExitForPostEmpty is called when exiting the ForPostEmpty production.
	ExitForPostEmpty(c *ForPostEmptyContext)

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

	// ExitAssignEq is called when exiting the AssignEq production.
	ExitAssignEq(c *AssignEqContext)

	// ExitAssignPlusEq is called when exiting the AssignPlusEq production.
	ExitAssignPlusEq(c *AssignPlusEqContext)

	// ExitAssignMinusEq is called when exiting the AssignMinusEq production.
	ExitAssignMinusEq(c *AssignMinusEqContext)

	// ExitAssignStarEq is called when exiting the AssignStarEq production.
	ExitAssignStarEq(c *AssignStarEqContext)

	// ExitAssignSlashEq is called when exiting the AssignSlashEq production.
	ExitAssignSlashEq(c *AssignSlashEqContext)

	// ExitAssignModEq is called when exiting the AssignModEq production.
	ExitAssignModEq(c *AssignModEqContext)

	// ExitAssignCaretEq is called when exiting the AssignCaretEq production.
	ExitAssignCaretEq(c *AssignCaretEqContext)

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

	// ExitUnaryOpExpr is called when exiting the UnaryOpExpr production.
	ExitUnaryOpExpr(c *UnaryOpExprContext)

	// ExitUnaryAwaitExpr is called when exiting the UnaryAwaitExpr production.
	ExitUnaryAwaitExpr(c *UnaryAwaitExprContext)

	// ExitAwaitExpr is called when exiting the awaitExpr production.
	ExitAwaitExpr(c *AwaitExprContext)

	// ExitPostfixExpr is called when exiting the postfixExpr production.
	ExitPostfixExpr(c *PostfixExprContext)

	// ExitPostfixCall is called when exiting the PostfixCall production.
	ExitPostfixCall(c *PostfixCallContext)

	// ExitPostfixDot is called when exiting the PostfixDot production.
	ExitPostfixDot(c *PostfixDotContext)

	// ExitPostfixIndex is called when exiting the PostfixIndex production.
	ExitPostfixIndex(c *PostfixIndexContext)

	// ExitPrimaryLiteral is called when exiting the PrimaryLiteral production.
	ExitPrimaryLiteral(c *PrimaryLiteralContext)

	// ExitPrimaryID is called when exiting the PrimaryID production.
	ExitPrimaryID(c *PrimaryIDContext)

	// ExitPrimaryParen is called when exiting the PrimaryParen production.
	ExitPrimaryParen(c *PrimaryParenContext)

	// ExitPrimaryArray is called when exiting the PrimaryArray production.
	ExitPrimaryArray(c *PrimaryArrayContext)

	// ExitPrimaryObject is called when exiting the PrimaryObject production.
	ExitPrimaryObject(c *PrimaryObjectContext)

	// ExitPrimaryMap is called when exiting the PrimaryMap production.
	ExitPrimaryMap(c *PrimaryMapContext)

	// ExitPrimarySet is called when exiting the PrimarySet production.
	ExitPrimarySet(c *PrimarySetContext)

	// ExitPrimaryFn is called when exiting the PrimaryFn production.
	ExitPrimaryFn(c *PrimaryFnContext)

	// ExitPrimaryMatch is called when exiting the PrimaryMatch production.
	ExitPrimaryMatch(c *PrimaryMatchContext)

	// ExitPrimaryVoid is called when exiting the PrimaryVoid production.
	ExitPrimaryVoid(c *PrimaryVoidContext)

	// ExitPrimaryNull is called when exiting the PrimaryNull production.
	ExitPrimaryNull(c *PrimaryNullContext)

	// ExitPrimaryTaggedBlock is called when exiting the PrimaryTaggedBlock production.
	ExitPrimaryTaggedBlock(c *PrimaryTaggedBlockContext)

	// ExitPrimaryStructInit is called when exiting the PrimaryStructInit production.
	ExitPrimaryStructInit(c *PrimaryStructInitContext)

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

	// ExitStringPartSingle is called when exiting the StringPartSingle production.
	ExitStringPartSingle(c *StringPartSingleContext)

	// ExitStringPartMulti is called when exiting the StringPartMulti production.
	ExitStringPartMulti(c *StringPartMultiContext)

	// ExitStringPartDouble is called when exiting the StringPartDouble production.
	ExitStringPartDouble(c *StringPartDoubleContext)

	// ExitStringPartMultiDouble is called when exiting the StringPartMultiDouble production.
	ExitStringPartMultiDouble(c *StringPartMultiDoubleContext)

	// ExitStringPartInterp is called when exiting the StringPartInterp production.
	ExitStringPartInterp(c *StringPartInterpContext)

	// ExitInterpolation is called when exiting the interpolation production.
	ExitInterpolation(c *InterpolationContext)

	// ExitLiteralString is called when exiting the LiteralString production.
	ExitLiteralString(c *LiteralStringContext)

	// ExitLiteralNumber is called when exiting the LiteralNumber production.
	ExitLiteralNumber(c *LiteralNumberContext)

	// ExitLiteralBool is called when exiting the LiteralBool production.
	ExitLiteralBool(c *LiteralBoolContext)

	// ExitLiteralNull is called when exiting the LiteralNull production.
	ExitLiteralNull(c *LiteralNullContext)

	// ExitLiteralVoid is called when exiting the LiteralVoid production.
	ExitLiteralVoid(c *LiteralVoidContext)

	// ExitStringLiteralSingle is called when exiting the StringLiteralSingle production.
	ExitStringLiteralSingle(c *StringLiteralSingleContext)

	// ExitStringLiteralMulti is called when exiting the StringLiteralMulti production.
	ExitStringLiteralMulti(c *StringLiteralMultiContext)

	// ExitStringLiteralDouble is called when exiting the StringLiteralDouble production.
	ExitStringLiteralDouble(c *StringLiteralDoubleContext)

	// ExitStringLiteralMultiDouble is called when exiting the StringLiteralMultiDouble production.
	ExitStringLiteralMultiDouble(c *StringLiteralMultiDoubleContext)

	// ExitNumberLiteralInt is called when exiting the NumberLiteralInt production.
	ExitNumberLiteralInt(c *NumberLiteralIntContext)

	// ExitNumberLiteralFloat is called when exiting the NumberLiteralFloat production.
	ExitNumberLiteralFloat(c *NumberLiteralFloatContext)

	// ExitNumberLiteralHex is called when exiting the NumberLiteralHex production.
	ExitNumberLiteralHex(c *NumberLiteralHexContext)

	// ExitNumberLiteralBin is called when exiting the NumberLiteralBin production.
	ExitNumberLiteralBin(c *NumberLiteralBinContext)

	// ExitNumberLiteralOct is called when exiting the NumberLiteralOct production.
	ExitNumberLiteralOct(c *NumberLiteralOctContext)

	// ExitBoolLiteralTrue is called when exiting the BoolLiteralTrue production.
	ExitBoolLiteralTrue(c *BoolLiteralTrueContext)

	// ExitBoolLiteralFalse is called when exiting the BoolLiteralFalse production.
	ExitBoolLiteralFalse(c *BoolLiteralFalseContext)

	// ExitArrayLiteral is called when exiting the arrayLiteral production.
	ExitArrayLiteral(c *ArrayLiteralContext)

	// ExitObjectLiteral is called when exiting the objectLiteral production.
	ExitObjectLiteral(c *ObjectLiteralContext)

	// ExitObjectFieldList is called when exiting the objectFieldList production.
	ExitObjectFieldList(c *ObjectFieldListContext)

	// ExitObjectField is called when exiting the objectField production.
	ExitObjectField(c *ObjectFieldContext)

	// ExitObjectFieldNameID is called when exiting the ObjectFieldNameID production.
	ExitObjectFieldNameID(c *ObjectFieldNameIDContext)

	// ExitObjectFieldNameStr is called when exiting the ObjectFieldNameStr production.
	ExitObjectFieldNameStr(c *ObjectFieldNameStrContext)

	// ExitMapLiteralEmpty is called when exiting the MapLiteralEmpty production.
	ExitMapLiteralEmpty(c *MapLiteralEmptyContext)

	// ExitMapLiteralNonEmpty is called when exiting the MapLiteralNonEmpty production.
	ExitMapLiteralNonEmpty(c *MapLiteralNonEmptyContext)

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

	// ExitTypeAnnID is called when exiting the TypeAnnID production.
	ExitTypeAnnID(c *TypeAnnIDContext)

	// ExitTypeAnnArray is called when exiting the TypeAnnArray production.
	ExitTypeAnnArray(c *TypeAnnArrayContext)

	// ExitTypeAnnTuple is called when exiting the TypeAnnTuple production.
	ExitTypeAnnTuple(c *TypeAnnTupleContext)

	// ExitTypeAnnFn is called when exiting the TypeAnnFn production.
	ExitTypeAnnFn(c *TypeAnnFnContext)

	// ExitTypeAnnVoid is called when exiting the TypeAnnVoid production.
	ExitTypeAnnVoid(c *TypeAnnVoidContext)

	// ExitTupleType is called when exiting the tupleType production.
	ExitTupleType(c *TupleTypeContext)

	// ExitArrayType is called when exiting the arrayType production.
	ExitArrayType(c *ArrayTypeContext)

	// ExitFnType is called when exiting the fnType production.
	ExitFnType(c *FnTypeContext)

	// ExitStmt_sep is called when exiting the stmt_sep production.
	ExitStmt_sep(c *Stmt_sepContext)
}
