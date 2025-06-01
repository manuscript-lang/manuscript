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

// EnterLetDecl is called when production letDecl is entered.
func (s *BaseManuscriptListener) EnterLetDecl(ctx *LetDeclContext) {}

// ExitLetDecl is called when production letDecl is exited.
func (s *BaseManuscriptListener) ExitLetDecl(ctx *LetDeclContext) {}

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

// EnterLabelStmtTry is called when production LabelStmtTry is entered.
func (s *BaseManuscriptListener) EnterLabelStmtTry(ctx *LabelStmtTryContext) {}

// ExitLabelStmtTry is called when production LabelStmtTry is exited.
func (s *BaseManuscriptListener) ExitLabelStmtTry(ctx *LabelStmtTryContext) {}

// EnterLabelStmtPiped is called when production LabelStmtPiped is entered.
func (s *BaseManuscriptListener) EnterLabelStmtPiped(ctx *LabelStmtPipedContext) {}

// ExitLabelStmtPiped is called when production LabelStmtPiped is exited.
func (s *BaseManuscriptListener) ExitLabelStmtPiped(ctx *LabelStmtPipedContext) {}

// EnterLabelStmtAsync is called when production LabelStmtAsync is entered.
func (s *BaseManuscriptListener) EnterLabelStmtAsync(ctx *LabelStmtAsyncContext) {}

// ExitLabelStmtAsync is called when production LabelStmtAsync is exited.
func (s *BaseManuscriptListener) ExitLabelStmtAsync(ctx *LabelStmtAsyncContext) {}

// EnterLabelStmtGo is called when production LabelStmtGo is entered.
func (s *BaseManuscriptListener) EnterLabelStmtGo(ctx *LabelStmtGoContext) {}

// ExitLabelStmtGo is called when production LabelStmtGo is exited.
func (s *BaseManuscriptListener) ExitLabelStmtGo(ctx *LabelStmtGoContext) {}

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

// EnterAsyncStmt is called when production asyncStmt is entered.
func (s *BaseManuscriptListener) EnterAsyncStmt(ctx *AsyncStmtContext) {}

// ExitAsyncStmt is called when production asyncStmt is exited.
func (s *BaseManuscriptListener) ExitAsyncStmt(ctx *AsyncStmtContext) {}

// EnterGoStmt is called when production goStmt is entered.
func (s *BaseManuscriptListener) EnterGoStmt(ctx *GoStmtContext) {}

// ExitGoStmt is called when production goStmt is exited.
func (s *BaseManuscriptListener) ExitGoStmt(ctx *GoStmtContext) {}

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

// EnterPipedStmt is called when production pipedStmt is entered.
func (s *BaseManuscriptListener) EnterPipedStmt(ctx *PipedStmtContext) {}

// ExitPipedStmt is called when production pipedStmt is exited.
func (s *BaseManuscriptListener) ExitPipedStmt(ctx *PipedStmtContext) {}

// EnterPipedArgs is called when production pipedArgs is entered.
func (s *BaseManuscriptListener) EnterPipedArgs(ctx *PipedArgsContext) {}

// ExitPipedArgs is called when production pipedArgs is exited.
func (s *BaseManuscriptListener) ExitPipedArgs(ctx *PipedArgsContext) {}

// EnterPipedArg is called when production pipedArg is entered.
func (s *BaseManuscriptListener) EnterPipedArg(ctx *PipedArgContext) {}

// ExitPipedArg is called when production pipedArg is exited.
func (s *BaseManuscriptListener) ExitPipedArg(ctx *PipedArgContext) {}

// EnterExpr is called when production expr is entered.
func (s *BaseManuscriptListener) EnterExpr(ctx *ExprContext) {}

// ExitExpr is called when production expr is exited.
func (s *BaseManuscriptListener) ExitExpr(ctx *ExprContext) {}

// EnterAssignmentExpr is called when production assignmentExpr is entered.
func (s *BaseManuscriptListener) EnterAssignmentExpr(ctx *AssignmentExprContext) {}

// ExitAssignmentExpr is called when production assignmentExpr is exited.
func (s *BaseManuscriptListener) ExitAssignmentExpr(ctx *AssignmentExprContext) {}

// EnterAssignmentOp is called when production assignmentOp is entered.
func (s *BaseManuscriptListener) EnterAssignmentOp(ctx *AssignmentOpContext) {}

// ExitAssignmentOp is called when production assignmentOp is exited.
func (s *BaseManuscriptListener) ExitAssignmentOp(ctx *AssignmentOpContext) {}

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

// EnterLabelUnaryPostfixExpr is called when production LabelUnaryPostfixExpr is entered.
func (s *BaseManuscriptListener) EnterLabelUnaryPostfixExpr(ctx *LabelUnaryPostfixExprContext) {}

// ExitLabelUnaryPostfixExpr is called when production LabelUnaryPostfixExpr is exited.
func (s *BaseManuscriptListener) ExitLabelUnaryPostfixExpr(ctx *LabelUnaryPostfixExprContext) {}

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

// EnterLabelPrimaryTypedObject is called when production LabelPrimaryTypedObject is entered.
func (s *BaseManuscriptListener) EnterLabelPrimaryTypedObject(ctx *LabelPrimaryTypedObjectContext) {}

// ExitLabelPrimaryTypedObject is called when production LabelPrimaryTypedObject is exited.
func (s *BaseManuscriptListener) ExitLabelPrimaryTypedObject(ctx *LabelPrimaryTypedObjectContext) {}

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

// EnterLabelPrimaryTaggedTemplate is called when production LabelPrimaryTaggedTemplate is entered.
func (s *BaseManuscriptListener) EnterLabelPrimaryTaggedTemplate(ctx *LabelPrimaryTaggedTemplateContext) {
}

// ExitLabelPrimaryTaggedTemplate is called when production LabelPrimaryTaggedTemplate is exited.
func (s *BaseManuscriptListener) ExitLabelPrimaryTaggedTemplate(ctx *LabelPrimaryTaggedTemplateContext) {
}

// EnterTryExpr is called when production tryExpr is entered.
func (s *BaseManuscriptListener) EnterTryExpr(ctx *TryExprContext) {}

// ExitTryExpr is called when production tryExpr is exited.
func (s *BaseManuscriptListener) ExitTryExpr(ctx *TryExprContext) {}

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

// EnterStringPart is called when production stringPart is entered.
func (s *BaseManuscriptListener) EnterStringPart(ctx *StringPartContext) {}

// ExitStringPart is called when production stringPart is exited.
func (s *BaseManuscriptListener) ExitStringPart(ctx *StringPartContext) {}

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

// EnterStringLiteral is called when production stringLiteral is entered.
func (s *BaseManuscriptListener) EnterStringLiteral(ctx *StringLiteralContext) {}

// ExitStringLiteral is called when production stringLiteral is exited.
func (s *BaseManuscriptListener) ExitStringLiteral(ctx *StringLiteralContext) {}

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

// EnterTaggedTemplate is called when production taggedTemplate is entered.
func (s *BaseManuscriptListener) EnterTaggedTemplate(ctx *TaggedTemplateContext) {}

// ExitTaggedTemplate is called when production taggedTemplate is exited.
func (s *BaseManuscriptListener) ExitTaggedTemplate(ctx *TaggedTemplateContext) {}

// EnterTypedObjectLiteral is called when production typedObjectLiteral is entered.
func (s *BaseManuscriptListener) EnterTypedObjectLiteral(ctx *TypedObjectLiteralContext) {}

// ExitTypedObjectLiteral is called when production typedObjectLiteral is exited.
func (s *BaseManuscriptListener) ExitTypedObjectLiteral(ctx *TypedObjectLiteralContext) {}

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
