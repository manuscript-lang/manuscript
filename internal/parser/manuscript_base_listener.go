// Code generated from Manuscript.g4 by ANTLR 4.13.1. DO NOT EDIT.

package parser // Manuscript

import "github.com/antlr4-go/antlr/v4"

// BaseManuscriptListener is a complete listener for a parse tree produced by Manuscript.
type BaseManuscriptListener struct{}

var _ ManuscriptListener = &BaseManuscriptListener{}

// VisitTerminal is called when a terminal node is visited.
func (s *BaseManuscriptListener) VisitTerminal(node antlr.TerminalNode) {}

// VisitErrorNode is called when an error node is visited.
func (s *BaseManuscriptListener) VisitErrorNode(node antlr.ErrorNode) {}

// EnterEveryRule is called when any rule is entered.
func (s *BaseManuscriptListener) EnterEveryRule(ctx antlr.ParserRuleContext) {}

// ExitEveryRule is called when any rule is exited.
func (s *BaseManuscriptListener) ExitEveryRule(ctx antlr.ParserRuleContext) {}

// EnterProgram is called when production program is entered.
func (s *BaseManuscriptListener) EnterProgram(ctx *ProgramContext) {}

// ExitProgram is called when production program is exited.
func (s *BaseManuscriptListener) ExitProgram(ctx *ProgramContext) {}

// EnterDeclaration is called when production declaration is entered.
func (s *BaseManuscriptListener) EnterDeclaration(ctx *DeclarationContext) {}

// ExitDeclaration is called when production declaration is exited.
func (s *BaseManuscriptListener) ExitDeclaration(ctx *DeclarationContext) {}

// EnterImportDecl is called when production importDecl is entered.
func (s *BaseManuscriptListener) EnterImportDecl(ctx *ImportDeclContext) {}

// ExitImportDecl is called when production importDecl is exited.
func (s *BaseManuscriptListener) ExitImportDecl(ctx *ImportDeclContext) {}

// EnterExportDecl is called when production exportDecl is entered.
func (s *BaseManuscriptListener) EnterExportDecl(ctx *ExportDeclContext) {}

// ExitExportDecl is called when production exportDecl is exited.
func (s *BaseManuscriptListener) ExitExportDecl(ctx *ExportDeclContext) {}

// EnterExternDecl is called when production externDecl is entered.
func (s *BaseManuscriptListener) EnterExternDecl(ctx *ExternDeclContext) {}

// ExitExternDecl is called when production externDecl is exited.
func (s *BaseManuscriptListener) ExitExternDecl(ctx *ExternDeclContext) {}

// EnterExportedItem is called when production exportedItem is entered.
func (s *BaseManuscriptListener) EnterExportedItem(ctx *ExportedItemContext) {}

// ExitExportedItem is called when production exportedItem is exited.
func (s *BaseManuscriptListener) ExitExportedItem(ctx *ExportedItemContext) {}

// EnterModuleImport is called when production moduleImport is entered.
func (s *BaseManuscriptListener) EnterModuleImport(ctx *ModuleImportContext) {}

// ExitModuleImport is called when production moduleImport is exited.
func (s *BaseManuscriptListener) ExitModuleImport(ctx *ModuleImportContext) {}

// EnterDestructuredImport is called when production destructuredImport is entered.
func (s *BaseManuscriptListener) EnterDestructuredImport(ctx *DestructuredImportContext) {}

// ExitDestructuredImport is called when production destructuredImport is exited.
func (s *BaseManuscriptListener) ExitDestructuredImport(ctx *DestructuredImportContext) {}

// EnterTargetImport is called when production targetImport is entered.
func (s *BaseManuscriptListener) EnterTargetImport(ctx *TargetImportContext) {}

// ExitTargetImport is called when production targetImport is exited.
func (s *BaseManuscriptListener) ExitTargetImport(ctx *TargetImportContext) {}

// EnterImportItemList is called when production importItemList is entered.
func (s *BaseManuscriptListener) EnterImportItemList(ctx *ImportItemListContext) {}

// ExitImportItemList is called when production importItemList is exited.
func (s *BaseManuscriptListener) ExitImportItemList(ctx *ImportItemListContext) {}

// EnterImportItem is called when production importItem is entered.
func (s *BaseManuscriptListener) EnterImportItem(ctx *ImportItemContext) {}

// ExitImportItem is called when production importItem is exited.
func (s *BaseManuscriptListener) ExitImportItem(ctx *ImportItemContext) {}

// EnterLabelLetDeclSingle is called when production LabelLetDeclSingle is entered.
func (s *BaseManuscriptListener) EnterLabelLetDeclSingle(ctx *LabelLetDeclSingleContext) {}

// ExitLabelLetDeclSingle is called when production LabelLetDeclSingle is exited.
func (s *BaseManuscriptListener) ExitLabelLetDeclSingle(ctx *LabelLetDeclSingleContext) {}

// EnterLabelLetDeclBlock is called when production LabelLetDeclBlock is entered.
func (s *BaseManuscriptListener) EnterLabelLetDeclBlock(ctx *LabelLetDeclBlockContext) {}

// ExitLabelLetDeclBlock is called when production LabelLetDeclBlock is exited.
func (s *BaseManuscriptListener) ExitLabelLetDeclBlock(ctx *LabelLetDeclBlockContext) {}

// EnterLabelLetDeclDestructuredObj is called when production LabelLetDeclDestructuredObj is entered.
func (s *BaseManuscriptListener) EnterLabelLetDeclDestructuredObj(ctx *LabelLetDeclDestructuredObjContext) {
}

// ExitLabelLetDeclDestructuredObj is called when production LabelLetDeclDestructuredObj is exited.
func (s *BaseManuscriptListener) ExitLabelLetDeclDestructuredObj(ctx *LabelLetDeclDestructuredObjContext) {
}

// EnterLabelLetDeclDestructuredArray is called when production LabelLetDeclDestructuredArray is entered.
func (s *BaseManuscriptListener) EnterLabelLetDeclDestructuredArray(ctx *LabelLetDeclDestructuredArrayContext) {
}

// ExitLabelLetDeclDestructuredArray is called when production LabelLetDeclDestructuredArray is exited.
func (s *BaseManuscriptListener) ExitLabelLetDeclDestructuredArray(ctx *LabelLetDeclDestructuredArrayContext) {
}

// EnterLetSingle is called when production letSingle is entered.
func (s *BaseManuscriptListener) EnterLetSingle(ctx *LetSingleContext) {}

// ExitLetSingle is called when production letSingle is exited.
func (s *BaseManuscriptListener) ExitLetSingle(ctx *LetSingleContext) {}

// EnterLetBlock is called when production letBlock is entered.
func (s *BaseManuscriptListener) EnterLetBlock(ctx *LetBlockContext) {}

// ExitLetBlock is called when production letBlock is exited.
func (s *BaseManuscriptListener) ExitLetBlock(ctx *LetBlockContext) {}

// EnterLetBlockItemList is called when production letBlockItemList is entered.
func (s *BaseManuscriptListener) EnterLetBlockItemList(ctx *LetBlockItemListContext) {}

// ExitLetBlockItemList is called when production letBlockItemList is exited.
func (s *BaseManuscriptListener) ExitLetBlockItemList(ctx *LetBlockItemListContext) {}

// EnterLetBlockItemSep is called when production letBlockItemSep is entered.
func (s *BaseManuscriptListener) EnterLetBlockItemSep(ctx *LetBlockItemSepContext) {}

// ExitLetBlockItemSep is called when production letBlockItemSep is exited.
func (s *BaseManuscriptListener) ExitLetBlockItemSep(ctx *LetBlockItemSepContext) {}

// EnterLabelLetBlockItemSingle is called when production LabelLetBlockItemSingle is entered.
func (s *BaseManuscriptListener) EnterLabelLetBlockItemSingle(ctx *LabelLetBlockItemSingleContext) {}

// ExitLabelLetBlockItemSingle is called when production LabelLetBlockItemSingle is exited.
func (s *BaseManuscriptListener) ExitLabelLetBlockItemSingle(ctx *LabelLetBlockItemSingleContext) {}

// EnterLabelLetBlockItemDestructuredObj is called when production LabelLetBlockItemDestructuredObj is entered.
func (s *BaseManuscriptListener) EnterLabelLetBlockItemDestructuredObj(ctx *LabelLetBlockItemDestructuredObjContext) {
}

// ExitLabelLetBlockItemDestructuredObj is called when production LabelLetBlockItemDestructuredObj is exited.
func (s *BaseManuscriptListener) ExitLabelLetBlockItemDestructuredObj(ctx *LabelLetBlockItemDestructuredObjContext) {
}

// EnterLabelLetBlockItemDestructuredArray is called when production LabelLetBlockItemDestructuredArray is entered.
func (s *BaseManuscriptListener) EnterLabelLetBlockItemDestructuredArray(ctx *LabelLetBlockItemDestructuredArrayContext) {
}

// ExitLabelLetBlockItemDestructuredArray is called when production LabelLetBlockItemDestructuredArray is exited.
func (s *BaseManuscriptListener) ExitLabelLetBlockItemDestructuredArray(ctx *LabelLetBlockItemDestructuredArrayContext) {
}

// EnterLetDestructuredObj is called when production letDestructuredObj is entered.
func (s *BaseManuscriptListener) EnterLetDestructuredObj(ctx *LetDestructuredObjContext) {}

// ExitLetDestructuredObj is called when production letDestructuredObj is exited.
func (s *BaseManuscriptListener) ExitLetDestructuredObj(ctx *LetDestructuredObjContext) {}

// EnterLetDestructuredArray is called when production letDestructuredArray is entered.
func (s *BaseManuscriptListener) EnterLetDestructuredArray(ctx *LetDestructuredArrayContext) {}

// ExitLetDestructuredArray is called when production letDestructuredArray is exited.
func (s *BaseManuscriptListener) ExitLetDestructuredArray(ctx *LetDestructuredArrayContext) {}

// EnterTypedIDList is called when production typedIDList is entered.
func (s *BaseManuscriptListener) EnterTypedIDList(ctx *TypedIDListContext) {}

// ExitTypedIDList is called when production typedIDList is exited.
func (s *BaseManuscriptListener) ExitTypedIDList(ctx *TypedIDListContext) {}

// EnterTypedID is called when production typedID is entered.
func (s *BaseManuscriptListener) EnterTypedID(ctx *TypedIDContext) {}

// ExitTypedID is called when production typedID is exited.
func (s *BaseManuscriptListener) ExitTypedID(ctx *TypedIDContext) {}

// EnterTypeDecl is called when production typeDecl is entered.
func (s *BaseManuscriptListener) EnterTypeDecl(ctx *TypeDeclContext) {}

// ExitTypeDecl is called when production typeDecl is exited.
func (s *BaseManuscriptListener) ExitTypeDecl(ctx *TypeDeclContext) {}

// EnterTypeDefBody is called when production typeDefBody is entered.
func (s *BaseManuscriptListener) EnterTypeDefBody(ctx *TypeDefBodyContext) {}

// ExitTypeDefBody is called when production typeDefBody is exited.
func (s *BaseManuscriptListener) ExitTypeDefBody(ctx *TypeDefBodyContext) {}

// EnterTypeAlias is called when production typeAlias is entered.
func (s *BaseManuscriptListener) EnterTypeAlias(ctx *TypeAliasContext) {}

// ExitTypeAlias is called when production typeAlias is exited.
func (s *BaseManuscriptListener) ExitTypeAlias(ctx *TypeAliasContext) {}

// EnterFieldList is called when production fieldList is entered.
func (s *BaseManuscriptListener) EnterFieldList(ctx *FieldListContext) {}

// ExitFieldList is called when production fieldList is exited.
func (s *BaseManuscriptListener) ExitFieldList(ctx *FieldListContext) {}

// EnterFieldDecl is called when production fieldDecl is entered.
func (s *BaseManuscriptListener) EnterFieldDecl(ctx *FieldDeclContext) {}

// ExitFieldDecl is called when production fieldDecl is exited.
func (s *BaseManuscriptListener) ExitFieldDecl(ctx *FieldDeclContext) {}

// EnterTypeList is called when production typeList is entered.
func (s *BaseManuscriptListener) EnterTypeList(ctx *TypeListContext) {}

// ExitTypeList is called when production typeList is exited.
func (s *BaseManuscriptListener) ExitTypeList(ctx *TypeListContext) {}

// EnterInterfaceDecl is called when production interfaceDecl is entered.
func (s *BaseManuscriptListener) EnterInterfaceDecl(ctx *InterfaceDeclContext) {}

// ExitInterfaceDecl is called when production interfaceDecl is exited.
func (s *BaseManuscriptListener) ExitInterfaceDecl(ctx *InterfaceDeclContext) {}

// EnterInterfaceMethod is called when production interfaceMethod is entered.
func (s *BaseManuscriptListener) EnterInterfaceMethod(ctx *InterfaceMethodContext) {}

// ExitInterfaceMethod is called when production interfaceMethod is exited.
func (s *BaseManuscriptListener) ExitInterfaceMethod(ctx *InterfaceMethodContext) {}

// EnterFnDecl is called when production fnDecl is entered.
func (s *BaseManuscriptListener) EnterFnDecl(ctx *FnDeclContext) {}

// ExitFnDecl is called when production fnDecl is exited.
func (s *BaseManuscriptListener) ExitFnDecl(ctx *FnDeclContext) {}

// EnterFnSignature is called when production fnSignature is entered.
func (s *BaseManuscriptListener) EnterFnSignature(ctx *FnSignatureContext) {}

// ExitFnSignature is called when production fnSignature is exited.
func (s *BaseManuscriptListener) ExitFnSignature(ctx *FnSignatureContext) {}

// EnterParameters is called when production parameters is entered.
func (s *BaseManuscriptListener) EnterParameters(ctx *ParametersContext) {}

// ExitParameters is called when production parameters is exited.
func (s *BaseManuscriptListener) ExitParameters(ctx *ParametersContext) {}

// EnterParam is called when production param is entered.
func (s *BaseManuscriptListener) EnterParam(ctx *ParamContext) {}

// ExitParam is called when production param is exited.
func (s *BaseManuscriptListener) ExitParam(ctx *ParamContext) {}

// EnterMethodsDecl is called when production methodsDecl is entered.
func (s *BaseManuscriptListener) EnterMethodsDecl(ctx *MethodsDeclContext) {}

// ExitMethodsDecl is called when production methodsDecl is exited.
func (s *BaseManuscriptListener) ExitMethodsDecl(ctx *MethodsDeclContext) {}

// EnterMethodImplList is called when production methodImplList is entered.
func (s *BaseManuscriptListener) EnterMethodImplList(ctx *MethodImplListContext) {}

// ExitMethodImplList is called when production methodImplList is exited.
func (s *BaseManuscriptListener) ExitMethodImplList(ctx *MethodImplListContext) {}

// EnterMethodImpl is called when production methodImpl is entered.
func (s *BaseManuscriptListener) EnterMethodImpl(ctx *MethodImplContext) {}

// ExitMethodImpl is called when production methodImpl is exited.
func (s *BaseManuscriptListener) ExitMethodImpl(ctx *MethodImplContext) {}

// EnterLabelStmtLet is called when production LabelStmtLet is entered.
func (s *BaseManuscriptListener) EnterLabelStmtLet(ctx *LabelStmtLetContext) {}

// ExitLabelStmtLet is called when production LabelStmtLet is exited.
func (s *BaseManuscriptListener) ExitLabelStmtLet(ctx *LabelStmtLetContext) {}

// EnterLabelStmtExpr is called when production LabelStmtExpr is entered.
func (s *BaseManuscriptListener) EnterLabelStmtExpr(ctx *LabelStmtExprContext) {}

// ExitLabelStmtExpr is called when production LabelStmtExpr is exited.
func (s *BaseManuscriptListener) ExitLabelStmtExpr(ctx *LabelStmtExprContext) {}

// EnterLabelStmtReturn is called when production LabelStmtReturn is entered.
func (s *BaseManuscriptListener) EnterLabelStmtReturn(ctx *LabelStmtReturnContext) {}

// ExitLabelStmtReturn is called when production LabelStmtReturn is exited.
func (s *BaseManuscriptListener) ExitLabelStmtReturn(ctx *LabelStmtReturnContext) {}

// EnterLabelStmtYield is called when production LabelStmtYield is entered.
func (s *BaseManuscriptListener) EnterLabelStmtYield(ctx *LabelStmtYieldContext) {}

// ExitLabelStmtYield is called when production LabelStmtYield is exited.
func (s *BaseManuscriptListener) ExitLabelStmtYield(ctx *LabelStmtYieldContext) {}

// EnterLabelStmtIf is called when production LabelStmtIf is entered.
func (s *BaseManuscriptListener) EnterLabelStmtIf(ctx *LabelStmtIfContext) {}

// ExitLabelStmtIf is called when production LabelStmtIf is exited.
func (s *BaseManuscriptListener) ExitLabelStmtIf(ctx *LabelStmtIfContext) {}

// EnterLabelStmtFor is called when production LabelStmtFor is entered.
func (s *BaseManuscriptListener) EnterLabelStmtFor(ctx *LabelStmtForContext) {}

// ExitLabelStmtFor is called when production LabelStmtFor is exited.
func (s *BaseManuscriptListener) ExitLabelStmtFor(ctx *LabelStmtForContext) {}

// EnterLabelStmtWhile is called when production LabelStmtWhile is entered.
func (s *BaseManuscriptListener) EnterLabelStmtWhile(ctx *LabelStmtWhileContext) {}

// ExitLabelStmtWhile is called when production LabelStmtWhile is exited.
func (s *BaseManuscriptListener) ExitLabelStmtWhile(ctx *LabelStmtWhileContext) {}

// EnterLabelStmtBlock is called when production LabelStmtBlock is entered.
func (s *BaseManuscriptListener) EnterLabelStmtBlock(ctx *LabelStmtBlockContext) {}

// ExitLabelStmtBlock is called when production LabelStmtBlock is exited.
func (s *BaseManuscriptListener) ExitLabelStmtBlock(ctx *LabelStmtBlockContext) {}

// EnterLabelStmtBreak is called when production LabelStmtBreak is entered.
func (s *BaseManuscriptListener) EnterLabelStmtBreak(ctx *LabelStmtBreakContext) {}

// ExitLabelStmtBreak is called when production LabelStmtBreak is exited.
func (s *BaseManuscriptListener) ExitLabelStmtBreak(ctx *LabelStmtBreakContext) {}

// EnterLabelStmtContinue is called when production LabelStmtContinue is entered.
func (s *BaseManuscriptListener) EnterLabelStmtContinue(ctx *LabelStmtContinueContext) {}

// ExitLabelStmtContinue is called when production LabelStmtContinue is exited.
func (s *BaseManuscriptListener) ExitLabelStmtContinue(ctx *LabelStmtContinueContext) {}

// EnterLabelStmtCheck is called when production LabelStmtCheck is entered.
func (s *BaseManuscriptListener) EnterLabelStmtCheck(ctx *LabelStmtCheckContext) {}

// ExitLabelStmtCheck is called when production LabelStmtCheck is exited.
func (s *BaseManuscriptListener) ExitLabelStmtCheck(ctx *LabelStmtCheckContext) {}

// EnterLabelStmtDefer is called when production LabelStmtDefer is entered.
func (s *BaseManuscriptListener) EnterLabelStmtDefer(ctx *LabelStmtDeferContext) {}

// ExitLabelStmtDefer is called when production LabelStmtDefer is exited.
func (s *BaseManuscriptListener) ExitLabelStmtDefer(ctx *LabelStmtDeferContext) {}

// EnterReturnStmt is called when production returnStmt is entered.
func (s *BaseManuscriptListener) EnterReturnStmt(ctx *ReturnStmtContext) {}

// ExitReturnStmt is called when production returnStmt is exited.
func (s *BaseManuscriptListener) ExitReturnStmt(ctx *ReturnStmtContext) {}

// EnterYieldStmt is called when production yieldStmt is entered.
func (s *BaseManuscriptListener) EnterYieldStmt(ctx *YieldStmtContext) {}

// ExitYieldStmt is called when production yieldStmt is exited.
func (s *BaseManuscriptListener) ExitYieldStmt(ctx *YieldStmtContext) {}

// EnterDeferStmt is called when production deferStmt is entered.
func (s *BaseManuscriptListener) EnterDeferStmt(ctx *DeferStmtContext) {}

// ExitDeferStmt is called when production deferStmt is exited.
func (s *BaseManuscriptListener) ExitDeferStmt(ctx *DeferStmtContext) {}

// EnterExprList is called when production exprList is entered.
func (s *BaseManuscriptListener) EnterExprList(ctx *ExprListContext) {}

// ExitExprList is called when production exprList is exited.
func (s *BaseManuscriptListener) ExitExprList(ctx *ExprListContext) {}

// EnterIfStmt is called when production ifStmt is entered.
func (s *BaseManuscriptListener) EnterIfStmt(ctx *IfStmtContext) {}

// ExitIfStmt is called when production ifStmt is exited.
func (s *BaseManuscriptListener) ExitIfStmt(ctx *IfStmtContext) {}

// EnterForStmt is called when production forStmt is entered.
func (s *BaseManuscriptListener) EnterForStmt(ctx *ForStmtContext) {}

// ExitForStmt is called when production forStmt is exited.
func (s *BaseManuscriptListener) ExitForStmt(ctx *ForStmtContext) {}

// EnterLabelForLoop is called when production LabelForLoop is entered.
func (s *BaseManuscriptListener) EnterLabelForLoop(ctx *LabelForLoopContext) {}

// ExitLabelForLoop is called when production LabelForLoop is exited.
func (s *BaseManuscriptListener) ExitLabelForLoop(ctx *LabelForLoopContext) {}

// EnterLabelForInLoop is called when production LabelForInLoop is entered.
func (s *BaseManuscriptListener) EnterLabelForInLoop(ctx *LabelForInLoopContext) {}

// ExitLabelForInLoop is called when production LabelForInLoop is exited.
func (s *BaseManuscriptListener) ExitLabelForInLoop(ctx *LabelForInLoopContext) {}

// EnterForTrinity is called when production forTrinity is entered.
func (s *BaseManuscriptListener) EnterForTrinity(ctx *ForTrinityContext) {}

// ExitForTrinity is called when production forTrinity is exited.
func (s *BaseManuscriptListener) ExitForTrinity(ctx *ForTrinityContext) {}

// EnterLabelForInitLet is called when production LabelForInitLet is entered.
func (s *BaseManuscriptListener) EnterLabelForInitLet(ctx *LabelForInitLetContext) {}

// ExitLabelForInitLet is called when production LabelForInitLet is exited.
func (s *BaseManuscriptListener) ExitLabelForInitLet(ctx *LabelForInitLetContext) {}

// EnterLabelForInitEmpty is called when production LabelForInitEmpty is entered.
func (s *BaseManuscriptListener) EnterLabelForInitEmpty(ctx *LabelForInitEmptyContext) {}

// ExitLabelForInitEmpty is called when production LabelForInitEmpty is exited.
func (s *BaseManuscriptListener) ExitLabelForInitEmpty(ctx *LabelForInitEmptyContext) {}

// EnterLabelForCondExpr is called when production LabelForCondExpr is entered.
func (s *BaseManuscriptListener) EnterLabelForCondExpr(ctx *LabelForCondExprContext) {}

// ExitLabelForCondExpr is called when production LabelForCondExpr is exited.
func (s *BaseManuscriptListener) ExitLabelForCondExpr(ctx *LabelForCondExprContext) {}

// EnterLabelForCondEmpty is called when production LabelForCondEmpty is entered.
func (s *BaseManuscriptListener) EnterLabelForCondEmpty(ctx *LabelForCondEmptyContext) {}

// ExitLabelForCondEmpty is called when production LabelForCondEmpty is exited.
func (s *BaseManuscriptListener) ExitLabelForCondEmpty(ctx *LabelForCondEmptyContext) {}

// EnterLabelForPostExpr is called when production LabelForPostExpr is entered.
func (s *BaseManuscriptListener) EnterLabelForPostExpr(ctx *LabelForPostExprContext) {}

// ExitLabelForPostExpr is called when production LabelForPostExpr is exited.
func (s *BaseManuscriptListener) ExitLabelForPostExpr(ctx *LabelForPostExprContext) {}

// EnterLabelForPostEmpty is called when production LabelForPostEmpty is entered.
func (s *BaseManuscriptListener) EnterLabelForPostEmpty(ctx *LabelForPostEmptyContext) {}

// ExitLabelForPostEmpty is called when production LabelForPostEmpty is exited.
func (s *BaseManuscriptListener) ExitLabelForPostEmpty(ctx *LabelForPostEmptyContext) {}

// EnterWhileStmt is called when production whileStmt is entered.
func (s *BaseManuscriptListener) EnterWhileStmt(ctx *WhileStmtContext) {}

// ExitWhileStmt is called when production whileStmt is exited.
func (s *BaseManuscriptListener) ExitWhileStmt(ctx *WhileStmtContext) {}

// EnterLoopBody is called when production loopBody is entered.
func (s *BaseManuscriptListener) EnterLoopBody(ctx *LoopBodyContext) {}

// ExitLoopBody is called when production loopBody is exited.
func (s *BaseManuscriptListener) ExitLoopBody(ctx *LoopBodyContext) {}

// EnterCodeBlock is called when production codeBlock is entered.
func (s *BaseManuscriptListener) EnterCodeBlock(ctx *CodeBlockContext) {}

// ExitCodeBlock is called when production codeBlock is exited.
func (s *BaseManuscriptListener) ExitCodeBlock(ctx *CodeBlockContext) {}

// EnterBreakStmt is called when production breakStmt is entered.
func (s *BaseManuscriptListener) EnterBreakStmt(ctx *BreakStmtContext) {}

// ExitBreakStmt is called when production breakStmt is exited.
func (s *BaseManuscriptListener) ExitBreakStmt(ctx *BreakStmtContext) {}

// EnterContinueStmt is called when production continueStmt is entered.
func (s *BaseManuscriptListener) EnterContinueStmt(ctx *ContinueStmtContext) {}

// ExitContinueStmt is called when production continueStmt is exited.
func (s *BaseManuscriptListener) ExitContinueStmt(ctx *ContinueStmtContext) {}

// EnterCheckStmt is called when production checkStmt is entered.
func (s *BaseManuscriptListener) EnterCheckStmt(ctx *CheckStmtContext) {}

// ExitCheckStmt is called when production checkStmt is exited.
func (s *BaseManuscriptListener) ExitCheckStmt(ctx *CheckStmtContext) {}

// EnterExpr is called when production expr is entered.
func (s *BaseManuscriptListener) EnterExpr(ctx *ExprContext) {}

// ExitExpr is called when production expr is exited.
func (s *BaseManuscriptListener) ExitExpr(ctx *ExprContext) {}

// EnterAssignmentExpr is called when production assignmentExpr is entered.
func (s *BaseManuscriptListener) EnterAssignmentExpr(ctx *AssignmentExprContext) {}

// ExitAssignmentExpr is called when production assignmentExpr is exited.
func (s *BaseManuscriptListener) ExitAssignmentExpr(ctx *AssignmentExprContext) {}

// EnterLabelAssignEq is called when production LabelAssignEq is entered.
func (s *BaseManuscriptListener) EnterLabelAssignEq(ctx *LabelAssignEqContext) {}

// ExitLabelAssignEq is called when production LabelAssignEq is exited.
func (s *BaseManuscriptListener) ExitLabelAssignEq(ctx *LabelAssignEqContext) {}

// EnterLabelAssignPlusEq is called when production LabelAssignPlusEq is entered.
func (s *BaseManuscriptListener) EnterLabelAssignPlusEq(ctx *LabelAssignPlusEqContext) {}

// ExitLabelAssignPlusEq is called when production LabelAssignPlusEq is exited.
func (s *BaseManuscriptListener) ExitLabelAssignPlusEq(ctx *LabelAssignPlusEqContext) {}

// EnterLabelAssignMinusEq is called when production LabelAssignMinusEq is entered.
func (s *BaseManuscriptListener) EnterLabelAssignMinusEq(ctx *LabelAssignMinusEqContext) {}

// ExitLabelAssignMinusEq is called when production LabelAssignMinusEq is exited.
func (s *BaseManuscriptListener) ExitLabelAssignMinusEq(ctx *LabelAssignMinusEqContext) {}

// EnterLabelAssignStarEq is called when production LabelAssignStarEq is entered.
func (s *BaseManuscriptListener) EnterLabelAssignStarEq(ctx *LabelAssignStarEqContext) {}

// ExitLabelAssignStarEq is called when production LabelAssignStarEq is exited.
func (s *BaseManuscriptListener) ExitLabelAssignStarEq(ctx *LabelAssignStarEqContext) {}

// EnterLabelAssignSlashEq is called when production LabelAssignSlashEq is entered.
func (s *BaseManuscriptListener) EnterLabelAssignSlashEq(ctx *LabelAssignSlashEqContext) {}

// ExitLabelAssignSlashEq is called when production LabelAssignSlashEq is exited.
func (s *BaseManuscriptListener) ExitLabelAssignSlashEq(ctx *LabelAssignSlashEqContext) {}

// EnterLabelAssignModEq is called when production LabelAssignModEq is entered.
func (s *BaseManuscriptListener) EnterLabelAssignModEq(ctx *LabelAssignModEqContext) {}

// ExitLabelAssignModEq is called when production LabelAssignModEq is exited.
func (s *BaseManuscriptListener) ExitLabelAssignModEq(ctx *LabelAssignModEqContext) {}

// EnterLabelAssignCaretEq is called when production LabelAssignCaretEq is entered.
func (s *BaseManuscriptListener) EnterLabelAssignCaretEq(ctx *LabelAssignCaretEqContext) {}

// ExitLabelAssignCaretEq is called when production LabelAssignCaretEq is exited.
func (s *BaseManuscriptListener) ExitLabelAssignCaretEq(ctx *LabelAssignCaretEqContext) {}

// EnterTernaryExpr is called when production ternaryExpr is entered.
func (s *BaseManuscriptListener) EnterTernaryExpr(ctx *TernaryExprContext) {}

// ExitTernaryExpr is called when production ternaryExpr is exited.
func (s *BaseManuscriptListener) ExitTernaryExpr(ctx *TernaryExprContext) {}

// EnterLogicalOrExpr is called when production logicalOrExpr is entered.
func (s *BaseManuscriptListener) EnterLogicalOrExpr(ctx *LogicalOrExprContext) {}

// ExitLogicalOrExpr is called when production logicalOrExpr is exited.
func (s *BaseManuscriptListener) ExitLogicalOrExpr(ctx *LogicalOrExprContext) {}

// EnterLogicalAndExpr is called when production logicalAndExpr is entered.
func (s *BaseManuscriptListener) EnterLogicalAndExpr(ctx *LogicalAndExprContext) {}

// ExitLogicalAndExpr is called when production logicalAndExpr is exited.
func (s *BaseManuscriptListener) ExitLogicalAndExpr(ctx *LogicalAndExprContext) {}

// EnterBitwiseOrExpr is called when production bitwiseOrExpr is entered.
func (s *BaseManuscriptListener) EnterBitwiseOrExpr(ctx *BitwiseOrExprContext) {}

// ExitBitwiseOrExpr is called when production bitwiseOrExpr is exited.
func (s *BaseManuscriptListener) ExitBitwiseOrExpr(ctx *BitwiseOrExprContext) {}

// EnterBitwiseXorExpr is called when production bitwiseXorExpr is entered.
func (s *BaseManuscriptListener) EnterBitwiseXorExpr(ctx *BitwiseXorExprContext) {}

// ExitBitwiseXorExpr is called when production bitwiseXorExpr is exited.
func (s *BaseManuscriptListener) ExitBitwiseXorExpr(ctx *BitwiseXorExprContext) {}

// EnterBitwiseAndExpr is called when production bitwiseAndExpr is entered.
func (s *BaseManuscriptListener) EnterBitwiseAndExpr(ctx *BitwiseAndExprContext) {}

// ExitBitwiseAndExpr is called when production bitwiseAndExpr is exited.
func (s *BaseManuscriptListener) ExitBitwiseAndExpr(ctx *BitwiseAndExprContext) {}

// EnterEqualityExpr is called when production equalityExpr is entered.
func (s *BaseManuscriptListener) EnterEqualityExpr(ctx *EqualityExprContext) {}

// ExitEqualityExpr is called when production equalityExpr is exited.
func (s *BaseManuscriptListener) ExitEqualityExpr(ctx *EqualityExprContext) {}

// EnterComparisonOp is called when production comparisonOp is entered.
func (s *BaseManuscriptListener) EnterComparisonOp(ctx *ComparisonOpContext) {}

// ExitComparisonOp is called when production comparisonOp is exited.
func (s *BaseManuscriptListener) ExitComparisonOp(ctx *ComparisonOpContext) {}

// EnterComparisonExpr is called when production comparisonExpr is entered.
func (s *BaseManuscriptListener) EnterComparisonExpr(ctx *ComparisonExprContext) {}

// ExitComparisonExpr is called when production comparisonExpr is exited.
func (s *BaseManuscriptListener) ExitComparisonExpr(ctx *ComparisonExprContext) {}

// EnterShiftExpr is called when production shiftExpr is entered.
func (s *BaseManuscriptListener) EnterShiftExpr(ctx *ShiftExprContext) {}

// ExitShiftExpr is called when production shiftExpr is exited.
func (s *BaseManuscriptListener) ExitShiftExpr(ctx *ShiftExprContext) {}

// EnterAdditiveExpr is called when production additiveExpr is entered.
func (s *BaseManuscriptListener) EnterAdditiveExpr(ctx *AdditiveExprContext) {}

// ExitAdditiveExpr is called when production additiveExpr is exited.
func (s *BaseManuscriptListener) ExitAdditiveExpr(ctx *AdditiveExprContext) {}

// EnterMultiplicativeExpr is called when production multiplicativeExpr is entered.
func (s *BaseManuscriptListener) EnterMultiplicativeExpr(ctx *MultiplicativeExprContext) {}

// ExitMultiplicativeExpr is called when production multiplicativeExpr is exited.
func (s *BaseManuscriptListener) ExitMultiplicativeExpr(ctx *MultiplicativeExprContext) {}

// EnterLabelUnaryOpExpr is called when production LabelUnaryOpExpr is entered.
func (s *BaseManuscriptListener) EnterLabelUnaryOpExpr(ctx *LabelUnaryOpExprContext) {}

// ExitLabelUnaryOpExpr is called when production LabelUnaryOpExpr is exited.
func (s *BaseManuscriptListener) ExitLabelUnaryOpExpr(ctx *LabelUnaryOpExprContext) {}

// EnterLabelUnaryAwaitExpr is called when production LabelUnaryAwaitExpr is entered.
func (s *BaseManuscriptListener) EnterLabelUnaryAwaitExpr(ctx *LabelUnaryAwaitExprContext) {}

// ExitLabelUnaryAwaitExpr is called when production LabelUnaryAwaitExpr is exited.
func (s *BaseManuscriptListener) ExitLabelUnaryAwaitExpr(ctx *LabelUnaryAwaitExprContext) {}

// EnterAwaitExpr is called when production awaitExpr is entered.
func (s *BaseManuscriptListener) EnterAwaitExpr(ctx *AwaitExprContext) {}

// ExitAwaitExpr is called when production awaitExpr is exited.
func (s *BaseManuscriptListener) ExitAwaitExpr(ctx *AwaitExprContext) {}

// EnterPostfixExpr is called when production postfixExpr is entered.
func (s *BaseManuscriptListener) EnterPostfixExpr(ctx *PostfixExprContext) {}

// ExitPostfixExpr is called when production postfixExpr is exited.
func (s *BaseManuscriptListener) ExitPostfixExpr(ctx *PostfixExprContext) {}

// EnterLabelPostfixCall is called when production LabelPostfixCall is entered.
func (s *BaseManuscriptListener) EnterLabelPostfixCall(ctx *LabelPostfixCallContext) {}

// ExitLabelPostfixCall is called when production LabelPostfixCall is exited.
func (s *BaseManuscriptListener) ExitLabelPostfixCall(ctx *LabelPostfixCallContext) {}

// EnterLabelPostfixDot is called when production LabelPostfixDot is entered.
func (s *BaseManuscriptListener) EnterLabelPostfixDot(ctx *LabelPostfixDotContext) {}

// ExitLabelPostfixDot is called when production LabelPostfixDot is exited.
func (s *BaseManuscriptListener) ExitLabelPostfixDot(ctx *LabelPostfixDotContext) {}

// EnterLabelPostfixIndex is called when production LabelPostfixIndex is entered.
func (s *BaseManuscriptListener) EnterLabelPostfixIndex(ctx *LabelPostfixIndexContext) {}

// ExitLabelPostfixIndex is called when production LabelPostfixIndex is exited.
func (s *BaseManuscriptListener) ExitLabelPostfixIndex(ctx *LabelPostfixIndexContext) {}

// EnterLabelPrimaryLiteral is called when production LabelPrimaryLiteral is entered.
func (s *BaseManuscriptListener) EnterLabelPrimaryLiteral(ctx *LabelPrimaryLiteralContext) {}

// ExitLabelPrimaryLiteral is called when production LabelPrimaryLiteral is exited.
func (s *BaseManuscriptListener) ExitLabelPrimaryLiteral(ctx *LabelPrimaryLiteralContext) {}

// EnterLabelPrimaryID is called when production LabelPrimaryID is entered.
func (s *BaseManuscriptListener) EnterLabelPrimaryID(ctx *LabelPrimaryIDContext) {}

// ExitLabelPrimaryID is called when production LabelPrimaryID is exited.
func (s *BaseManuscriptListener) ExitLabelPrimaryID(ctx *LabelPrimaryIDContext) {}

// EnterLabelPrimaryParen is called when production LabelPrimaryParen is entered.
func (s *BaseManuscriptListener) EnterLabelPrimaryParen(ctx *LabelPrimaryParenContext) {}

// ExitLabelPrimaryParen is called when production LabelPrimaryParen is exited.
func (s *BaseManuscriptListener) ExitLabelPrimaryParen(ctx *LabelPrimaryParenContext) {}

// EnterLabelPrimaryArray is called when production LabelPrimaryArray is entered.
func (s *BaseManuscriptListener) EnterLabelPrimaryArray(ctx *LabelPrimaryArrayContext) {}

// ExitLabelPrimaryArray is called when production LabelPrimaryArray is exited.
func (s *BaseManuscriptListener) ExitLabelPrimaryArray(ctx *LabelPrimaryArrayContext) {}

// EnterLabelPrimaryObject is called when production LabelPrimaryObject is entered.
func (s *BaseManuscriptListener) EnterLabelPrimaryObject(ctx *LabelPrimaryObjectContext) {}

// ExitLabelPrimaryObject is called when production LabelPrimaryObject is exited.
func (s *BaseManuscriptListener) ExitLabelPrimaryObject(ctx *LabelPrimaryObjectContext) {}

// EnterLabelPrimaryMap is called when production LabelPrimaryMap is entered.
func (s *BaseManuscriptListener) EnterLabelPrimaryMap(ctx *LabelPrimaryMapContext) {}

// ExitLabelPrimaryMap is called when production LabelPrimaryMap is exited.
func (s *BaseManuscriptListener) ExitLabelPrimaryMap(ctx *LabelPrimaryMapContext) {}

// EnterLabelPrimarySet is called when production LabelPrimarySet is entered.
func (s *BaseManuscriptListener) EnterLabelPrimarySet(ctx *LabelPrimarySetContext) {}

// ExitLabelPrimarySet is called when production LabelPrimarySet is exited.
func (s *BaseManuscriptListener) ExitLabelPrimarySet(ctx *LabelPrimarySetContext) {}

// EnterLabelPrimaryFn is called when production LabelPrimaryFn is entered.
func (s *BaseManuscriptListener) EnterLabelPrimaryFn(ctx *LabelPrimaryFnContext) {}

// ExitLabelPrimaryFn is called when production LabelPrimaryFn is exited.
func (s *BaseManuscriptListener) ExitLabelPrimaryFn(ctx *LabelPrimaryFnContext) {}

// EnterLabelPrimaryMatch is called when production LabelPrimaryMatch is entered.
func (s *BaseManuscriptListener) EnterLabelPrimaryMatch(ctx *LabelPrimaryMatchContext) {}

// ExitLabelPrimaryMatch is called when production LabelPrimaryMatch is exited.
func (s *BaseManuscriptListener) ExitLabelPrimaryMatch(ctx *LabelPrimaryMatchContext) {}

// EnterLabelPrimaryVoid is called when production LabelPrimaryVoid is entered.
func (s *BaseManuscriptListener) EnterLabelPrimaryVoid(ctx *LabelPrimaryVoidContext) {}

// ExitLabelPrimaryVoid is called when production LabelPrimaryVoid is exited.
func (s *BaseManuscriptListener) ExitLabelPrimaryVoid(ctx *LabelPrimaryVoidContext) {}

// EnterLabelPrimaryNull is called when production LabelPrimaryNull is entered.
func (s *BaseManuscriptListener) EnterLabelPrimaryNull(ctx *LabelPrimaryNullContext) {}

// ExitLabelPrimaryNull is called when production LabelPrimaryNull is exited.
func (s *BaseManuscriptListener) ExitLabelPrimaryNull(ctx *LabelPrimaryNullContext) {}

// EnterLabelPrimaryTaggedBlock is called when production LabelPrimaryTaggedBlock is entered.
func (s *BaseManuscriptListener) EnterLabelPrimaryTaggedBlock(ctx *LabelPrimaryTaggedBlockContext) {}

// ExitLabelPrimaryTaggedBlock is called when production LabelPrimaryTaggedBlock is exited.
func (s *BaseManuscriptListener) ExitLabelPrimaryTaggedBlock(ctx *LabelPrimaryTaggedBlockContext) {}

// EnterLabelPrimaryStructInit is called when production LabelPrimaryStructInit is entered.
func (s *BaseManuscriptListener) EnterLabelPrimaryStructInit(ctx *LabelPrimaryStructInitContext) {}

// ExitLabelPrimaryStructInit is called when production LabelPrimaryStructInit is exited.
func (s *BaseManuscriptListener) ExitLabelPrimaryStructInit(ctx *LabelPrimaryStructInitContext) {}

// EnterFnExpr is called when production fnExpr is entered.
func (s *BaseManuscriptListener) EnterFnExpr(ctx *FnExprContext) {}

// ExitFnExpr is called when production fnExpr is exited.
func (s *BaseManuscriptListener) ExitFnExpr(ctx *FnExprContext) {}

// EnterMatchExpr is called when production matchExpr is entered.
func (s *BaseManuscriptListener) EnterMatchExpr(ctx *MatchExprContext) {}

// ExitMatchExpr is called when production matchExpr is exited.
func (s *BaseManuscriptListener) ExitMatchExpr(ctx *MatchExprContext) {}

// EnterCaseClause is called when production caseClause is entered.
func (s *BaseManuscriptListener) EnterCaseClause(ctx *CaseClauseContext) {}

// ExitCaseClause is called when production caseClause is exited.
func (s *BaseManuscriptListener) ExitCaseClause(ctx *CaseClauseContext) {}

// EnterDefaultClause is called when production defaultClause is entered.
func (s *BaseManuscriptListener) EnterDefaultClause(ctx *DefaultClauseContext) {}

// ExitDefaultClause is called when production defaultClause is exited.
func (s *BaseManuscriptListener) ExitDefaultClause(ctx *DefaultClauseContext) {}

// EnterSingleQuotedString is called when production singleQuotedString is entered.
func (s *BaseManuscriptListener) EnterSingleQuotedString(ctx *SingleQuotedStringContext) {}

// ExitSingleQuotedString is called when production singleQuotedString is exited.
func (s *BaseManuscriptListener) ExitSingleQuotedString(ctx *SingleQuotedStringContext) {}

// EnterMultiQuotedString is called when production multiQuotedString is entered.
func (s *BaseManuscriptListener) EnterMultiQuotedString(ctx *MultiQuotedStringContext) {}

// ExitMultiQuotedString is called when production multiQuotedString is exited.
func (s *BaseManuscriptListener) ExitMultiQuotedString(ctx *MultiQuotedStringContext) {}

// EnterDoubleQuotedString is called when production doubleQuotedString is entered.
func (s *BaseManuscriptListener) EnterDoubleQuotedString(ctx *DoubleQuotedStringContext) {}

// ExitDoubleQuotedString is called when production doubleQuotedString is exited.
func (s *BaseManuscriptListener) ExitDoubleQuotedString(ctx *DoubleQuotedStringContext) {}

// EnterMultiDoubleQuotedString is called when production multiDoubleQuotedString is entered.
func (s *BaseManuscriptListener) EnterMultiDoubleQuotedString(ctx *MultiDoubleQuotedStringContext) {}

// ExitMultiDoubleQuotedString is called when production multiDoubleQuotedString is exited.
func (s *BaseManuscriptListener) ExitMultiDoubleQuotedString(ctx *MultiDoubleQuotedStringContext) {}

// EnterLabelStringPartSingle is called when production LabelStringPartSingle is entered.
func (s *BaseManuscriptListener) EnterLabelStringPartSingle(ctx *LabelStringPartSingleContext) {}

// ExitLabelStringPartSingle is called when production LabelStringPartSingle is exited.
func (s *BaseManuscriptListener) ExitLabelStringPartSingle(ctx *LabelStringPartSingleContext) {}

// EnterLabelStringPartMulti is called when production LabelStringPartMulti is entered.
func (s *BaseManuscriptListener) EnterLabelStringPartMulti(ctx *LabelStringPartMultiContext) {}

// ExitLabelStringPartMulti is called when production LabelStringPartMulti is exited.
func (s *BaseManuscriptListener) ExitLabelStringPartMulti(ctx *LabelStringPartMultiContext) {}

// EnterLabelStringPartDouble is called when production LabelStringPartDouble is entered.
func (s *BaseManuscriptListener) EnterLabelStringPartDouble(ctx *LabelStringPartDoubleContext) {}

// ExitLabelStringPartDouble is called when production LabelStringPartDouble is exited.
func (s *BaseManuscriptListener) ExitLabelStringPartDouble(ctx *LabelStringPartDoubleContext) {}

// EnterLabelStringPartMultiDouble is called when production LabelStringPartMultiDouble is entered.
func (s *BaseManuscriptListener) EnterLabelStringPartMultiDouble(ctx *LabelStringPartMultiDoubleContext) {
}

// ExitLabelStringPartMultiDouble is called when production LabelStringPartMultiDouble is exited.
func (s *BaseManuscriptListener) ExitLabelStringPartMultiDouble(ctx *LabelStringPartMultiDoubleContext) {
}

// EnterLabelStringPartInterp is called when production LabelStringPartInterp is entered.
func (s *BaseManuscriptListener) EnterLabelStringPartInterp(ctx *LabelStringPartInterpContext) {}

// ExitLabelStringPartInterp is called when production LabelStringPartInterp is exited.
func (s *BaseManuscriptListener) ExitLabelStringPartInterp(ctx *LabelStringPartInterpContext) {}

// EnterInterpolation is called when production interpolation is entered.
func (s *BaseManuscriptListener) EnterInterpolation(ctx *InterpolationContext) {}

// ExitInterpolation is called when production interpolation is exited.
func (s *BaseManuscriptListener) ExitInterpolation(ctx *InterpolationContext) {}

// EnterLabelLiteralString is called when production LabelLiteralString is entered.
func (s *BaseManuscriptListener) EnterLabelLiteralString(ctx *LabelLiteralStringContext) {}

// ExitLabelLiteralString is called when production LabelLiteralString is exited.
func (s *BaseManuscriptListener) ExitLabelLiteralString(ctx *LabelLiteralStringContext) {}

// EnterLabelLiteralNumber is called when production LabelLiteralNumber is entered.
func (s *BaseManuscriptListener) EnterLabelLiteralNumber(ctx *LabelLiteralNumberContext) {}

// ExitLabelLiteralNumber is called when production LabelLiteralNumber is exited.
func (s *BaseManuscriptListener) ExitLabelLiteralNumber(ctx *LabelLiteralNumberContext) {}

// EnterLabelLiteralBool is called when production LabelLiteralBool is entered.
func (s *BaseManuscriptListener) EnterLabelLiteralBool(ctx *LabelLiteralBoolContext) {}

// ExitLabelLiteralBool is called when production LabelLiteralBool is exited.
func (s *BaseManuscriptListener) ExitLabelLiteralBool(ctx *LabelLiteralBoolContext) {}

// EnterLabelLiteralNull is called when production LabelLiteralNull is entered.
func (s *BaseManuscriptListener) EnterLabelLiteralNull(ctx *LabelLiteralNullContext) {}

// ExitLabelLiteralNull is called when production LabelLiteralNull is exited.
func (s *BaseManuscriptListener) ExitLabelLiteralNull(ctx *LabelLiteralNullContext) {}

// EnterLabelLiteralVoid is called when production LabelLiteralVoid is entered.
func (s *BaseManuscriptListener) EnterLabelLiteralVoid(ctx *LabelLiteralVoidContext) {}

// ExitLabelLiteralVoid is called when production LabelLiteralVoid is exited.
func (s *BaseManuscriptListener) ExitLabelLiteralVoid(ctx *LabelLiteralVoidContext) {}

// EnterLabelStringLiteralSingle is called when production LabelStringLiteralSingle is entered.
func (s *BaseManuscriptListener) EnterLabelStringLiteralSingle(ctx *LabelStringLiteralSingleContext) {
}

// ExitLabelStringLiteralSingle is called when production LabelStringLiteralSingle is exited.
func (s *BaseManuscriptListener) ExitLabelStringLiteralSingle(ctx *LabelStringLiteralSingleContext) {}

// EnterLabelStringLiteralMulti is called when production LabelStringLiteralMulti is entered.
func (s *BaseManuscriptListener) EnterLabelStringLiteralMulti(ctx *LabelStringLiteralMultiContext) {}

// ExitLabelStringLiteralMulti is called when production LabelStringLiteralMulti is exited.
func (s *BaseManuscriptListener) ExitLabelStringLiteralMulti(ctx *LabelStringLiteralMultiContext) {}

// EnterLabelStringLiteralDouble is called when production LabelStringLiteralDouble is entered.
func (s *BaseManuscriptListener) EnterLabelStringLiteralDouble(ctx *LabelStringLiteralDoubleContext) {
}

// ExitLabelStringLiteralDouble is called when production LabelStringLiteralDouble is exited.
func (s *BaseManuscriptListener) ExitLabelStringLiteralDouble(ctx *LabelStringLiteralDoubleContext) {}

// EnterLabelStringLiteralMultiDouble is called when production LabelStringLiteralMultiDouble is entered.
func (s *BaseManuscriptListener) EnterLabelStringLiteralMultiDouble(ctx *LabelStringLiteralMultiDoubleContext) {
}

// ExitLabelStringLiteralMultiDouble is called when production LabelStringLiteralMultiDouble is exited.
func (s *BaseManuscriptListener) ExitLabelStringLiteralMultiDouble(ctx *LabelStringLiteralMultiDoubleContext) {
}

// EnterLabelNumberLiteralInt is called when production LabelNumberLiteralInt is entered.
func (s *BaseManuscriptListener) EnterLabelNumberLiteralInt(ctx *LabelNumberLiteralIntContext) {}

// ExitLabelNumberLiteralInt is called when production LabelNumberLiteralInt is exited.
func (s *BaseManuscriptListener) ExitLabelNumberLiteralInt(ctx *LabelNumberLiteralIntContext) {}

// EnterLabelNumberLiteralFloat is called when production LabelNumberLiteralFloat is entered.
func (s *BaseManuscriptListener) EnterLabelNumberLiteralFloat(ctx *LabelNumberLiteralFloatContext) {}

// ExitLabelNumberLiteralFloat is called when production LabelNumberLiteralFloat is exited.
func (s *BaseManuscriptListener) ExitLabelNumberLiteralFloat(ctx *LabelNumberLiteralFloatContext) {}

// EnterLabelNumberLiteralHex is called when production LabelNumberLiteralHex is entered.
func (s *BaseManuscriptListener) EnterLabelNumberLiteralHex(ctx *LabelNumberLiteralHexContext) {}

// ExitLabelNumberLiteralHex is called when production LabelNumberLiteralHex is exited.
func (s *BaseManuscriptListener) ExitLabelNumberLiteralHex(ctx *LabelNumberLiteralHexContext) {}

// EnterLabelNumberLiteralBin is called when production LabelNumberLiteralBin is entered.
func (s *BaseManuscriptListener) EnterLabelNumberLiteralBin(ctx *LabelNumberLiteralBinContext) {}

// ExitLabelNumberLiteralBin is called when production LabelNumberLiteralBin is exited.
func (s *BaseManuscriptListener) ExitLabelNumberLiteralBin(ctx *LabelNumberLiteralBinContext) {}

// EnterLabelNumberLiteralOct is called when production LabelNumberLiteralOct is entered.
func (s *BaseManuscriptListener) EnterLabelNumberLiteralOct(ctx *LabelNumberLiteralOctContext) {}

// ExitLabelNumberLiteralOct is called when production LabelNumberLiteralOct is exited.
func (s *BaseManuscriptListener) ExitLabelNumberLiteralOct(ctx *LabelNumberLiteralOctContext) {}

// EnterLabelBoolLiteralTrue is called when production LabelBoolLiteralTrue is entered.
func (s *BaseManuscriptListener) EnterLabelBoolLiteralTrue(ctx *LabelBoolLiteralTrueContext) {}

// ExitLabelBoolLiteralTrue is called when production LabelBoolLiteralTrue is exited.
func (s *BaseManuscriptListener) ExitLabelBoolLiteralTrue(ctx *LabelBoolLiteralTrueContext) {}

// EnterLabelBoolLiteralFalse is called when production LabelBoolLiteralFalse is entered.
func (s *BaseManuscriptListener) EnterLabelBoolLiteralFalse(ctx *LabelBoolLiteralFalseContext) {}

// ExitLabelBoolLiteralFalse is called when production LabelBoolLiteralFalse is exited.
func (s *BaseManuscriptListener) ExitLabelBoolLiteralFalse(ctx *LabelBoolLiteralFalseContext) {}

// EnterArrayLiteral is called when production arrayLiteral is entered.
func (s *BaseManuscriptListener) EnterArrayLiteral(ctx *ArrayLiteralContext) {}

// ExitArrayLiteral is called when production arrayLiteral is exited.
func (s *BaseManuscriptListener) ExitArrayLiteral(ctx *ArrayLiteralContext) {}

// EnterObjectLiteral is called when production objectLiteral is entered.
func (s *BaseManuscriptListener) EnterObjectLiteral(ctx *ObjectLiteralContext) {}

// ExitObjectLiteral is called when production objectLiteral is exited.
func (s *BaseManuscriptListener) ExitObjectLiteral(ctx *ObjectLiteralContext) {}

// EnterObjectFieldList is called when production objectFieldList is entered.
func (s *BaseManuscriptListener) EnterObjectFieldList(ctx *ObjectFieldListContext) {}

// ExitObjectFieldList is called when production objectFieldList is exited.
func (s *BaseManuscriptListener) ExitObjectFieldList(ctx *ObjectFieldListContext) {}

// EnterObjectField is called when production objectField is entered.
func (s *BaseManuscriptListener) EnterObjectField(ctx *ObjectFieldContext) {}

// ExitObjectField is called when production objectField is exited.
func (s *BaseManuscriptListener) ExitObjectField(ctx *ObjectFieldContext) {}

// EnterLabelObjectFieldNameID is called when production LabelObjectFieldNameID is entered.
func (s *BaseManuscriptListener) EnterLabelObjectFieldNameID(ctx *LabelObjectFieldNameIDContext) {}

// ExitLabelObjectFieldNameID is called when production LabelObjectFieldNameID is exited.
func (s *BaseManuscriptListener) ExitLabelObjectFieldNameID(ctx *LabelObjectFieldNameIDContext) {}

// EnterLabelObjectFieldNameStr is called when production LabelObjectFieldNameStr is entered.
func (s *BaseManuscriptListener) EnterLabelObjectFieldNameStr(ctx *LabelObjectFieldNameStrContext) {}

// ExitLabelObjectFieldNameStr is called when production LabelObjectFieldNameStr is exited.
func (s *BaseManuscriptListener) ExitLabelObjectFieldNameStr(ctx *LabelObjectFieldNameStrContext) {}

// EnterLabelMapLiteralEmpty is called when production LabelMapLiteralEmpty is entered.
func (s *BaseManuscriptListener) EnterLabelMapLiteralEmpty(ctx *LabelMapLiteralEmptyContext) {}

// ExitLabelMapLiteralEmpty is called when production LabelMapLiteralEmpty is exited.
func (s *BaseManuscriptListener) ExitLabelMapLiteralEmpty(ctx *LabelMapLiteralEmptyContext) {}

// EnterLabelMapLiteralNonEmpty is called when production LabelMapLiteralNonEmpty is entered.
func (s *BaseManuscriptListener) EnterLabelMapLiteralNonEmpty(ctx *LabelMapLiteralNonEmptyContext) {}

// ExitLabelMapLiteralNonEmpty is called when production LabelMapLiteralNonEmpty is exited.
func (s *BaseManuscriptListener) ExitLabelMapLiteralNonEmpty(ctx *LabelMapLiteralNonEmptyContext) {}

// EnterMapFieldList is called when production mapFieldList is entered.
func (s *BaseManuscriptListener) EnterMapFieldList(ctx *MapFieldListContext) {}

// ExitMapFieldList is called when production mapFieldList is exited.
func (s *BaseManuscriptListener) ExitMapFieldList(ctx *MapFieldListContext) {}

// EnterMapField is called when production mapField is entered.
func (s *BaseManuscriptListener) EnterMapField(ctx *MapFieldContext) {}

// ExitMapField is called when production mapField is exited.
func (s *BaseManuscriptListener) ExitMapField(ctx *MapFieldContext) {}

// EnterSetLiteral is called when production setLiteral is entered.
func (s *BaseManuscriptListener) EnterSetLiteral(ctx *SetLiteralContext) {}

// ExitSetLiteral is called when production setLiteral is exited.
func (s *BaseManuscriptListener) ExitSetLiteral(ctx *SetLiteralContext) {}

// EnterTaggedBlockString is called when production taggedBlockString is entered.
func (s *BaseManuscriptListener) EnterTaggedBlockString(ctx *TaggedBlockStringContext) {}

// ExitTaggedBlockString is called when production taggedBlockString is exited.
func (s *BaseManuscriptListener) ExitTaggedBlockString(ctx *TaggedBlockStringContext) {}

// EnterStructInitExpr is called when production structInitExpr is entered.
func (s *BaseManuscriptListener) EnterStructInitExpr(ctx *StructInitExprContext) {}

// ExitStructInitExpr is called when production structInitExpr is exited.
func (s *BaseManuscriptListener) ExitStructInitExpr(ctx *StructInitExprContext) {}

// EnterStructFieldList is called when production structFieldList is entered.
func (s *BaseManuscriptListener) EnterStructFieldList(ctx *StructFieldListContext) {}

// ExitStructFieldList is called when production structFieldList is exited.
func (s *BaseManuscriptListener) ExitStructFieldList(ctx *StructFieldListContext) {}

// EnterStructField is called when production structField is entered.
func (s *BaseManuscriptListener) EnterStructField(ctx *StructFieldContext) {}

// ExitStructField is called when production structField is exited.
func (s *BaseManuscriptListener) ExitStructField(ctx *StructFieldContext) {}

// EnterLabelTypeAnnID is called when production LabelTypeAnnID is entered.
func (s *BaseManuscriptListener) EnterLabelTypeAnnID(ctx *LabelTypeAnnIDContext) {}

// ExitLabelTypeAnnID is called when production LabelTypeAnnID is exited.
func (s *BaseManuscriptListener) ExitLabelTypeAnnID(ctx *LabelTypeAnnIDContext) {}

// EnterLabelTypeAnnArray is called when production LabelTypeAnnArray is entered.
func (s *BaseManuscriptListener) EnterLabelTypeAnnArray(ctx *LabelTypeAnnArrayContext) {}

// ExitLabelTypeAnnArray is called when production LabelTypeAnnArray is exited.
func (s *BaseManuscriptListener) ExitLabelTypeAnnArray(ctx *LabelTypeAnnArrayContext) {}

// EnterLabelTypeAnnTuple is called when production LabelTypeAnnTuple is entered.
func (s *BaseManuscriptListener) EnterLabelTypeAnnTuple(ctx *LabelTypeAnnTupleContext) {}

// ExitLabelTypeAnnTuple is called when production LabelTypeAnnTuple is exited.
func (s *BaseManuscriptListener) ExitLabelTypeAnnTuple(ctx *LabelTypeAnnTupleContext) {}

// EnterLabelTypeAnnFn is called when production LabelTypeAnnFn is entered.
func (s *BaseManuscriptListener) EnterLabelTypeAnnFn(ctx *LabelTypeAnnFnContext) {}

// ExitLabelTypeAnnFn is called when production LabelTypeAnnFn is exited.
func (s *BaseManuscriptListener) ExitLabelTypeAnnFn(ctx *LabelTypeAnnFnContext) {}

// EnterLabelTypeAnnVoid is called when production LabelTypeAnnVoid is entered.
func (s *BaseManuscriptListener) EnterLabelTypeAnnVoid(ctx *LabelTypeAnnVoidContext) {}

// ExitLabelTypeAnnVoid is called when production LabelTypeAnnVoid is exited.
func (s *BaseManuscriptListener) ExitLabelTypeAnnVoid(ctx *LabelTypeAnnVoidContext) {}

// EnterTupleType is called when production tupleType is entered.
func (s *BaseManuscriptListener) EnterTupleType(ctx *TupleTypeContext) {}

// ExitTupleType is called when production tupleType is exited.
func (s *BaseManuscriptListener) ExitTupleType(ctx *TupleTypeContext) {}

// EnterArrayType is called when production arrayType is entered.
func (s *BaseManuscriptListener) EnterArrayType(ctx *ArrayTypeContext) {}

// ExitArrayType is called when production arrayType is exited.
func (s *BaseManuscriptListener) ExitArrayType(ctx *ArrayTypeContext) {}

// EnterFnType is called when production fnType is entered.
func (s *BaseManuscriptListener) EnterFnType(ctx *FnTypeContext) {}

// ExitFnType is called when production fnType is exited.
func (s *BaseManuscriptListener) ExitFnType(ctx *FnTypeContext) {}

// EnterStmt_sep is called when production stmt_sep is entered.
func (s *BaseManuscriptListener) EnterStmt_sep(ctx *Stmt_sepContext) {}

// ExitStmt_sep is called when production stmt_sep is exited.
func (s *BaseManuscriptListener) ExitStmt_sep(ctx *Stmt_sepContext) {}
