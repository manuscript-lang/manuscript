parser grammar Manuscript;

options {
	tokenVocab = ManuscriptLexer;
}

// --- Program Structure ---
program:
	stmt_sep* (declaration (stmt_sep+ declaration)*)? stmt_sep* EOF;

declaration:
	importDecl		  # DeclImport
	| exportDecl	  # DeclExport
	| externDecl	  # DeclExtern
	| letDecl		    # DeclLet
	| typeDecl		  # DeclType
	| interfaceDecl	# DeclInterface
	| fnDecl		    # DeclFn
	| methodsDecl	  # DeclMethods;

// --- Imports/Exports/Extern ---
importDecl: IMPORT moduleImport SEMICOLON?;
exportDecl: EXPORT exportedItem SEMICOLON?;
externDecl: EXTERN moduleImport SEMICOLON?;

exportedItem:
	fnDecl			    # ExportedFn
	| letDecl		    # ExportedLet
	| typeDecl		  # ExportedType
	| interfaceDecl	# ExportedInterface;
moduleImport:
	destructuredImport	# ModuleImportDestructured
	| targetImport		  # ModuleImportTarget;
destructuredImport:
	LBRACE importItemList? RBRACE FROM importStr;
targetImport: ID FROM importStr;
importItemList: importItem (COMMA importItem)* (COMMA)?;
importItem: ID (AS ID)?;
importStr: singleQuotedString;

// --- Let Declarations ---
letDecl:
	LET letSingle SEMICOLON?				# LetDeclSingle
	| LET letBlock SEMICOLON?				# LetDeclBlock
	| LET letDestructuredObj SEMICOLON?		# LetDeclDestructuredObj
	| LET letDestructuredArray SEMICOLON?	# LetDeclDestructuredArray;

letSingle: typedID (EQUALS expr)?;
letBlock: LPAREN letBlockItemList? RPAREN;
letBlockItemList:
	letBlockItemSep* letBlockItem (letBlockItemSep+ letBlockItem)* letBlockItemSep*;
letBlockItemSep: COMMA | stmt_sep;
letBlockItem:
	typedID EQUALS expr						# LetBlockItemSingle
	| LBRACE typedIDList RBRACE EQUALS expr	# LetBlockItemDestructuredObj
	| LSQBR typedIDList RSQBR EQUALS expr	# LetBlockItemDestructuredArray;
letDestructuredObj: LBRACE typedIDList RBRACE EQUALS expr;
letDestructuredArray: LSQBR typedIDList RSQBR EQUALS expr;

typedIDList: typedID (COMMA typedID)* (COMMA)?;
typedID: ID (typeAnnotation)?;

// --- Type & Interface Declarations ---
typeDecl: TYPE ID (typeDefBody | typeAlias);
typeDefBody: (EXTENDS typeList)? LBRACE (
		stmt_sep* fieldDecl (stmt_sep* COMMA stmt_sep* fieldDecl)* (
			stmt_sep* COMMA
		)? stmt_sep*
	)? RBRACE;
typeAlias: EQUALS typeAnnotation (EXTENDS typeList)?;
fieldList: fieldDecl (COMMA fieldDecl)* (COMMA)?;
fieldDecl: ID (QUESTION)? typeAnnotation;

typeList: typeAnnotation (COMMA typeAnnotation)* (COMMA)?;

interfaceDecl:
	INTERFACE ID (EXTENDS typeList)? LBRACE (
		stmt_sep* interfaceMethod stmt_sep*
	)+ RBRACE;
interfaceMethod:
	ID LPAREN parameters? RPAREN (typeAnnotation)? (EXCLAMATION)?;

// --- Function & Methods ---
fnDecl: fnSignature codeBlock;
fnSignature:
	FN ID LPAREN parameters? RPAREN (typeAnnotation)? (
		EXCLAMATION
	)?;
parameters: param (COMMA param)* (COMMA)?;
param: ID typeAnnotation (EQUALS expr)?;

methodsDecl: METHODS ID AS ID LBRACE methodImplList? RBRACE;
methodImplList:
	stmt_sep* methodImpl (stmt_sep+ methodImpl)* stmt_sep*;
methodImpl: interfaceMethod codeBlock;

// --- Statements ---
stmt:
	letDecl				# StmtLet
	| expr SEMICOLON?	# StmtExpr
	| returnStmt		# StmtReturn
	| yieldStmt			# StmtYield
	| ifStmt			# StmtIf
	| forStmt			# StmtFor
	| whileStmt			# StmtWhile
	| codeBlock			# StmtBlock
	| breakStmt			# StmtBreak
	| continueStmt		# StmtContinue
	| checkStmt			# StmtCheck
	| deferStmt			# StmtDefer;

returnStmt: RETURN exprList? SEMICOLON?;
yieldStmt: YIELD exprList? SEMICOLON?;
deferStmt: DEFER expr SEMICOLON?;
exprList: expr (COMMA expr)* (COMMA)?;

ifStmt: IF expr codeBlock (ELSE codeBlock)?;
forStmt: FOR forLoopType;
forLoopType:
	forTrinity							# ForLoop
	| (ID (COMMA ID)?) IN expr loopBody	# ForInLoop;
forTrinity:
	forInit SEMICOLON forCond SEMICOLON forPost loopBody;
forInit: letSingle # ForInitLet | /* empty */ # ForInitEmpty;
forCond: expr # ForCondExpr | /* empty */ # ForCondEmpty;
forPost: expr # ForPostExpr | /* empty */ # ForPostEmpty;
whileStmt: WHILE expr loopBody;
loopBody:
	LBRACE stmt_sep* (stmt (stmt_sep+ stmt)*)? stmt_sep* RBRACE;
codeBlock:
	LBRACE stmt_sep* (stmt (stmt_sep+ stmt)*)? stmt_sep* RBRACE;
breakStmt: BREAK SEMICOLON?;
continueStmt: CONTINUE SEMICOLON?;
checkStmt: CHECK expr COMMA stringLiteral SEMICOLON?;

// --- Expressions --- Entry point for all expressions
expr: assignmentExpr;

// Assignment expressions (right-associative)
assignmentExpr:
	ternaryExpr
	| left = ternaryExpr op = assignmentOp right = assignmentExpr;
assignmentOp:
	EQUALS			# AssignEq
	| PLUS_EQUALS	# AssignPlusEq
	| MINUS_EQUALS	# AssignMinusEq
	| STAR_EQUALS	# AssignStarEq
	| SLASH_EQUALS	# AssignSlashEq
	| MOD_EQUALS	# AssignModEq
	| CARET_EQUALS	# AssignCaretEq;

// Ternary conditional expression
ternaryExpr:
	logicalOrExpr
	| cond = logicalOrExpr QUESTION thenBranch = expr COLON elseExpr = ternaryExpr;

// Logical expressions
logicalOrExpr:
	logicalAndExpr
	| left = logicalOrExpr op = PIPE_PIPE right = logicalAndExpr;
logicalAndExpr:
	bitwiseOrExpr
	| left = logicalAndExpr op = AMP_AMP right = bitwiseOrExpr;

// Bitwise expressions
bitwiseOrExpr:
	bitwiseXorExpr
	| left = bitwiseOrExpr op = PIPE right = bitwiseXorExpr;
bitwiseXorExpr:
	bitwiseAndExpr
	| left = bitwiseXorExpr op = CARET right = bitwiseAndExpr;
bitwiseAndExpr:
	equalityExpr
	| left = bitwiseAndExpr op = AMP right = equalityExpr;

// Equality and comparison
equalityExpr:
	comparisonExpr
	| left = equalityExpr op = (EQUALS_EQUALS | NEQ) right = comparisonExpr;
comparisonOp: LT | LT_EQUALS | GT | GT_EQUALS;

comparisonExpr:
	shiftExpr
	| left = comparisonExpr op = comparisonOp right = shiftExpr;

// Arithmetic expressions
shiftExpr:
	additiveExpr
	| left = shiftExpr op = (PLUS | MINUS) right = additiveExpr;
additiveExpr:
	multiplicativeExpr
	| left = additiveExpr op = (PLUS | MINUS) right = multiplicativeExpr;
multiplicativeExpr:
	unaryExpr
	| left = multiplicativeExpr op = (STAR | SLASH | MOD) right = unaryExpr;

// Unary and postfix expressions
unaryExpr:
	op = (PLUS | MINUS | EXCLAMATION | TRY) unary = unaryExpr	# UnaryOpExpr
	| awaitExpr													# UnaryAwaitExpr;
awaitExpr: (TRY? AWAIT? ASYNC?) postfixExpr;
postfixExpr: primaryExpr | postfixExpr postfixOp;
postfixOp:
	LPAREN exprList? RPAREN	# PostfixCall
	| DOT ID				# PostfixDot
	| LSQBR expr RSQBR		# PostfixIndex;

// Primary expressions (literals, identifiers, grouping, etc.)
primaryExpr:
	literal					# PrimaryLiteral
	| ID					# PrimaryID
	| LPAREN expr RPAREN	# PrimaryParen
	| arrayLiteral			# PrimaryArray
	| objectLiteral			# PrimaryObject
	| mapLiteral			# PrimaryMap
	| setLiteral			# PrimarySet
	| fnExpr				# PrimaryFn
	| matchExpr				# PrimaryMatch
	| VOID					# PrimaryVoid
	| NULL					# PrimaryNull
	| taggedBlockString		# PrimaryTaggedBlock
	| structInitExpr		# PrimaryStructInit;

// --- Function Expressions ---
fnExpr:
	FN LPAREN parameters? RPAREN (typeAnnotation)? codeBlock;

// --- Match Expressions ---
matchExpr:
	MATCH expr LBRACE stmt_sep* caseClause (stmt_sep+ caseClause)* stmt_sep* defaultClause? RBRACE;
caseClause: expr (COLON expr | codeBlock) SEMICOLON?;
defaultClause: DEFAULT (COLON expr | codeBlock) SEMICOLON?;

// --- String Literals ---
singleQuotedString:
	SINGLE_QUOTE_START stringPart* SINGLE_STR_END;
multiQuotedString: MULTI_QUOTE_START stringPart* MULTI_STR_END;
doubleQuotedString:
	DOUBLE_QUOTE_START stringPart* DOUBLE_STR_END;
multiDoubleQuotedString:
	MULTI_DOUBLE_QUOTE_START stringPart* MULTI_DOUBLE_STR_END;
stringPart:
	SINGLE_STR_CONTENT			# StringPartSingle
	| MULTI_STR_CONTENT			# StringPartMulti
	| DOUBLE_STR_CONTENT		# StringPartDouble
	| MULTI_DOUBLE_STR_CONTENT	# StringPartMultiDouble
	| interpolation				# StringPartInterp;
interpolation: (
		SINGLE_STR_INTERP_START
		| MULTI_STR_INTERP_START
		| DOUBLE_STR_INTERP_START
		| MULTI_DOUBLE_STR_INTERP_START
	) expr INTERP_RBRACE;

// --- Literals ---
literal:
	stringLiteral		# LiteralString
	| numberLiteral		# LiteralNumber
	| booleanLiteral	# LiteralBool
	| NULL				# LiteralNull
	| VOID				# LiteralVoid;
stringLiteral:
	singleQuotedString			# StringLiteralSingle
	| multiQuotedString			# StringLiteralMulti
	| doubleQuotedString		# StringLiteralDouble
	| multiDoubleQuotedString	# StringLiteralMultiDouble;
numberLiteral:
	INTEGER				# NumberLiteralInt
	| FLOAT				# NumberLiteralFloat
	| HEX_LITERAL		# NumberLiteralHex
	| BINARY_LITERAL	# NumberLiteralBin
	| OCTAL_LITERAL		# NumberLiteralOct;
booleanLiteral:
	TRUE	# BoolLiteralTrue
	| FALSE	# BoolLiteralFalse;

// --- Collections ---
arrayLiteral: LSQBR exprList? RSQBR;
objectLiteral: LBRACE objectFieldList? RBRACE;
objectFieldList: objectField (COMMA objectField)* (COMMA)?;
objectField: objectFieldName (COLON expr)?;
objectFieldName:
	ID				# ObjectFieldNameID
	| stringLiteral	# ObjectFieldNameStr;
mapLiteral:
	LSQBR COLON RSQBR			# MapLiteralEmpty
	| LSQBR mapFieldList? RSQBR	# MapLiteralNonEmpty;
mapFieldList: mapField (COMMA mapField)* (COMMA)?;
mapField: expr COLON expr;
setLiteral: LT (expr (COMMA expr)* (COMMA)?)? GT;

taggedBlockString:
	ID (multiQuotedString | multiDoubleQuotedString);

structInitExpr: ID LPAREN structFieldList? RPAREN;
structFieldList: structField (COMMA structField)* (COMMA)?;
structField: ID COLON expr;

// --- Type Annotations ---
typeAnnotation:
	ID			# TypeAnnID
	| arrayType	# TypeAnnArray
	| tupleType	# TypeAnnTuple
	| fnType	# TypeAnnFn
	| VOID		# TypeAnnVoid;
tupleType: LPAREN typeList? RPAREN;
arrayType: ID LSQBR RSQBR;
fnType: FN LPAREN parameters? RPAREN typeAnnotation?;

// --- Helper Rules ---
stmt_sep: SEMICOLON | NEWLINE;