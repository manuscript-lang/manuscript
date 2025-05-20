// Code generated from Manuscript.g4 by ANTLR 4.13.1. DO NOT EDIT.

package parser // Manuscript

import "github.com/antlr4-go/antlr/v4"

// ManuscriptListener is a complete listener for a parse tree produced by Manuscript.
type ManuscriptListener interface {
	antlr.ParseTreeListener

	// EnterProgram is called when entering the program production.
	EnterProgram(c *ProgramContext)

	// EnterProgramItem is called when entering the programItem production.
	EnterProgramItem(c *ProgramItemContext)

	// EnterImportStmt is called when entering the importStmt production.
	EnterImportStmt(c *ImportStmtContext)

	// EnterDestructuredImport is called when entering the DestructuredImport production.
	EnterDestructuredImport(c *DestructuredImportContext)

	// EnterTargetImport is called when entering the TargetImport production.
	EnterTargetImport(c *TargetImportContext)

	// EnterImportItem is called when entering the importItem production.
	EnterImportItem(c *ImportItemContext)

	// EnterImportStr is called when entering the importStr production.
	EnterImportStr(c *ImportStrContext)

	// EnterExternStmt is called when entering the externStmt production.
	EnterExternStmt(c *ExternStmtContext)

	// EnterExportStmt is called when entering the exportStmt production.
	EnterExportStmt(c *ExportStmtContext)

	// EnterLetDecl is called when entering the letDecl production.
	EnterLetDecl(c *LetDeclContext)

	// EnterLetSingle is called when entering the letSingle production.
	EnterLetSingle(c *LetSingleContext)

	// EnterLetBlockItemSingle is called when entering the letBlockItemSingle production.
	EnterLetBlockItemSingle(c *LetBlockItemSingleContext)

	// EnterLetBlockItemDestructuredObj is called when entering the letBlockItemDestructuredObj production.
	EnterLetBlockItemDestructuredObj(c *LetBlockItemDestructuredObjContext)

	// EnterLetBlockItemDestructuredArray is called when entering the letBlockItemDestructuredArray production.
	EnterLetBlockItemDestructuredArray(c *LetBlockItemDestructuredArrayContext)

	// EnterLetBlock is called when entering the letBlock production.
	EnterLetBlock(c *LetBlockContext)

	// EnterLetDestructuredObj is called when entering the letDestructuredObj production.
	EnterLetDestructuredObj(c *LetDestructuredObjContext)

	// EnterLetDestructuredArray is called when entering the letDestructuredArray production.
	EnterLetDestructuredArray(c *LetDestructuredArrayContext)

	// EnterNamedID is called when entering the namedID production.
	EnterNamedID(c *NamedIDContext)

	// EnterTypedID is called when entering the typedID production.
	EnterTypedID(c *TypedIDContext)

	// EnterTypedIDList is called when entering the typedIDList production.
	EnterTypedIDList(c *TypedIDListContext)

	// EnterTypeList is called when entering the typeList production.
	EnterTypeList(c *TypeListContext)

	// EnterFnDecl is called when entering the fnDecl production.
	EnterFnDecl(c *FnDeclContext)

	// EnterFnSignature is called when entering the fnSignature production.
	EnterFnSignature(c *FnSignatureContext)

	// EnterParameters is called when entering the parameters production.
	EnterParameters(c *ParametersContext)

	// EnterParam is called when entering the param production.
	EnterParam(c *ParamContext)

	// EnterTypeDecl is called when entering the typeDecl production.
	EnterTypeDecl(c *TypeDeclContext)

	// EnterTypeDefBody is called when entering the typeDefBody production.
	EnterTypeDefBody(c *TypeDefBodyContext)

	// EnterTypeAlias is called when entering the typeAlias production.
	EnterTypeAlias(c *TypeAliasContext)

	// EnterFieldDecl is called when entering the fieldDecl production.
	EnterFieldDecl(c *FieldDeclContext)

	// EnterInterfaceDecl is called when entering the interfaceDecl production.
	EnterInterfaceDecl(c *InterfaceDeclContext)

	// EnterInterfaceMethod is called when entering the interfaceMethod production.
	EnterInterfaceMethod(c *InterfaceMethodContext)

	// EnterMethodsDecl is called when entering the methodsDecl production.
	EnterMethodsDecl(c *MethodsDeclContext)

	// EnterMethodImpl is called when entering the methodImpl production.
	EnterMethodImpl(c *MethodImplContext)

	// EnterTypeAnnotation is called when entering the typeAnnotation production.
	EnterTypeAnnotation(c *TypeAnnotationContext)

	// EnterTupleType is called when entering the tupleType production.
	EnterTupleType(c *TupleTypeContext)

	// EnterStmt is called when entering the stmt production.
	EnterStmt(c *StmtContext)

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

	// EnterWhileStmt is called when entering the whileStmt production.
	EnterWhileStmt(c *WhileStmtContext)

	// EnterLoopBody is called when entering the loopBody production.
	EnterLoopBody(c *LoopBodyContext)

	// EnterCodeBlock is called when entering the codeBlock production.
	EnterCodeBlock(c *CodeBlockContext)

	// EnterExpr is called when entering the expr production.
	EnterExpr(c *ExprContext)

	// EnterAssignmentExpr is called when entering the assignmentExpr production.
	EnterAssignmentExpr(c *AssignmentExprContext)

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

	// EnterObjectFieldName is called when entering the objectFieldName production.
	EnterObjectFieldName(c *ObjectFieldNameContext)

	// EnterObjectField is called when entering the objectField production.
	EnterObjectField(c *ObjectFieldContext)

	// EnterMapLiteral is called when entering the mapLiteral production.
	EnterMapLiteral(c *MapLiteralContext)

	// EnterMapField is called when entering the mapField production.
	EnterMapField(c *MapFieldContext)

	// EnterSetLiteral is called when entering the setLiteral production.
	EnterSetLiteral(c *SetLiteralContext)

	// EnterBreakStmt is called when entering the breakStmt production.
	EnterBreakStmt(c *BreakStmtContext)

	// EnterContinueStmt is called when entering the continueStmt production.
	EnterContinueStmt(c *ContinueStmtContext)

	// EnterCheckStmt is called when entering the checkStmt production.
	EnterCheckStmt(c *CheckStmtContext)

	// EnterTaggedBlockString is called when entering the taggedBlockString production.
	EnterTaggedBlockString(c *TaggedBlockStringContext)

	// EnterStructInitExpr is called when entering the structInitExpr production.
	EnterStructInitExpr(c *StructInitExprContext)

	// EnterStructField is called when entering the structField production.
	EnterStructField(c *StructFieldContext)

	// EnterStmt_sep is called when entering the stmt_sep production.
	EnterStmt_sep(c *Stmt_sepContext)

	// EnterSep is called when entering the sep production.
	EnterSep(c *SepContext)

	// ExitProgram is called when exiting the program production.
	ExitProgram(c *ProgramContext)

	// ExitProgramItem is called when exiting the programItem production.
	ExitProgramItem(c *ProgramItemContext)

	// ExitImportStmt is called when exiting the importStmt production.
	ExitImportStmt(c *ImportStmtContext)

	// ExitDestructuredImport is called when exiting the DestructuredImport production.
	ExitDestructuredImport(c *DestructuredImportContext)

	// ExitTargetImport is called when exiting the TargetImport production.
	ExitTargetImport(c *TargetImportContext)

	// ExitImportItem is called when exiting the importItem production.
	ExitImportItem(c *ImportItemContext)

	// ExitImportStr is called when exiting the importStr production.
	ExitImportStr(c *ImportStrContext)

	// ExitExternStmt is called when exiting the externStmt production.
	ExitExternStmt(c *ExternStmtContext)

	// ExitExportStmt is called when exiting the exportStmt production.
	ExitExportStmt(c *ExportStmtContext)

	// ExitLetDecl is called when exiting the letDecl production.
	ExitLetDecl(c *LetDeclContext)

	// ExitLetSingle is called when exiting the letSingle production.
	ExitLetSingle(c *LetSingleContext)

	// ExitLetBlockItemSingle is called when exiting the letBlockItemSingle production.
	ExitLetBlockItemSingle(c *LetBlockItemSingleContext)

	// ExitLetBlockItemDestructuredObj is called when exiting the letBlockItemDestructuredObj production.
	ExitLetBlockItemDestructuredObj(c *LetBlockItemDestructuredObjContext)

	// ExitLetBlockItemDestructuredArray is called when exiting the letBlockItemDestructuredArray production.
	ExitLetBlockItemDestructuredArray(c *LetBlockItemDestructuredArrayContext)

	// ExitLetBlock is called when exiting the letBlock production.
	ExitLetBlock(c *LetBlockContext)

	// ExitLetDestructuredObj is called when exiting the letDestructuredObj production.
	ExitLetDestructuredObj(c *LetDestructuredObjContext)

	// ExitLetDestructuredArray is called when exiting the letDestructuredArray production.
	ExitLetDestructuredArray(c *LetDestructuredArrayContext)

	// ExitNamedID is called when exiting the namedID production.
	ExitNamedID(c *NamedIDContext)

	// ExitTypedID is called when exiting the typedID production.
	ExitTypedID(c *TypedIDContext)

	// ExitTypedIDList is called when exiting the typedIDList production.
	ExitTypedIDList(c *TypedIDListContext)

	// ExitTypeList is called when exiting the typeList production.
	ExitTypeList(c *TypeListContext)

	// ExitFnDecl is called when exiting the fnDecl production.
	ExitFnDecl(c *FnDeclContext)

	// ExitFnSignature is called when exiting the fnSignature production.
	ExitFnSignature(c *FnSignatureContext)

	// ExitParameters is called when exiting the parameters production.
	ExitParameters(c *ParametersContext)

	// ExitParam is called when exiting the param production.
	ExitParam(c *ParamContext)

	// ExitTypeDecl is called when exiting the typeDecl production.
	ExitTypeDecl(c *TypeDeclContext)

	// ExitTypeDefBody is called when exiting the typeDefBody production.
	ExitTypeDefBody(c *TypeDefBodyContext)

	// ExitTypeAlias is called when exiting the typeAlias production.
	ExitTypeAlias(c *TypeAliasContext)

	// ExitFieldDecl is called when exiting the fieldDecl production.
	ExitFieldDecl(c *FieldDeclContext)

	// ExitInterfaceDecl is called when exiting the interfaceDecl production.
	ExitInterfaceDecl(c *InterfaceDeclContext)

	// ExitInterfaceMethod is called when exiting the interfaceMethod production.
	ExitInterfaceMethod(c *InterfaceMethodContext)

	// ExitMethodsDecl is called when exiting the methodsDecl production.
	ExitMethodsDecl(c *MethodsDeclContext)

	// ExitMethodImpl is called when exiting the methodImpl production.
	ExitMethodImpl(c *MethodImplContext)

	// ExitTypeAnnotation is called when exiting the typeAnnotation production.
	ExitTypeAnnotation(c *TypeAnnotationContext)

	// ExitTupleType is called when exiting the tupleType production.
	ExitTupleType(c *TupleTypeContext)

	// ExitStmt is called when exiting the stmt production.
	ExitStmt(c *StmtContext)

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

	// ExitWhileStmt is called when exiting the whileStmt production.
	ExitWhileStmt(c *WhileStmtContext)

	// ExitLoopBody is called when exiting the loopBody production.
	ExitLoopBody(c *LoopBodyContext)

	// ExitCodeBlock is called when exiting the codeBlock production.
	ExitCodeBlock(c *CodeBlockContext)

	// ExitExpr is called when exiting the expr production.
	ExitExpr(c *ExprContext)

	// ExitAssignmentExpr is called when exiting the assignmentExpr production.
	ExitAssignmentExpr(c *AssignmentExprContext)

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

	// ExitObjectFieldName is called when exiting the objectFieldName production.
	ExitObjectFieldName(c *ObjectFieldNameContext)

	// ExitObjectField is called when exiting the objectField production.
	ExitObjectField(c *ObjectFieldContext)

	// ExitMapLiteral is called when exiting the mapLiteral production.
	ExitMapLiteral(c *MapLiteralContext)

	// ExitMapField is called when exiting the mapField production.
	ExitMapField(c *MapFieldContext)

	// ExitSetLiteral is called when exiting the setLiteral production.
	ExitSetLiteral(c *SetLiteralContext)

	// ExitBreakStmt is called when exiting the breakStmt production.
	ExitBreakStmt(c *BreakStmtContext)

	// ExitContinueStmt is called when exiting the continueStmt production.
	ExitContinueStmt(c *ContinueStmtContext)

	// ExitCheckStmt is called when exiting the checkStmt production.
	ExitCheckStmt(c *CheckStmtContext)

	// ExitTaggedBlockString is called when exiting the taggedBlockString production.
	ExitTaggedBlockString(c *TaggedBlockStringContext)

	// ExitStructInitExpr is called when exiting the structInitExpr production.
	ExitStructInitExpr(c *StructInitExprContext)

	// ExitStructField is called when exiting the structField production.
	ExitStructField(c *StructFieldContext)

	// ExitStmt_sep is called when exiting the stmt_sep production.
	ExitStmt_sep(c *Stmt_sepContext)

	// ExitSep is called when exiting the sep production.
	ExitSep(c *SepContext)
}
