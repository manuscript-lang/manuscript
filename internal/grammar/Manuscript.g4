parser grammar Manuscript;

options {
	tokenVocab = ManuscriptLexer;
}

// --- Program Structure ---
program: stmt_sep* (declaration stmt_sep*)* EOF;

declaration:
	importDecl		# DeclImport
	| exportDecl	# DeclExport
	| externDecl	# DeclExtern
	| letDecl		# DeclLet
	| typeDecl		# DeclType
	| interfaceDecl	# DeclInterface
	| fnDecl		# DeclFn
	| methodsDecl	# DeclMethods;

// --- Helper Rules ---
// stmt_list: (stmt (stmt_sep+ stmt)*)? (stmt_sep)*; // Original problematic rule
stmt_list_items: stmt (stmt_sep+ stmt)*;

// --- Imports/Exports/Extern ---
importDecl: IMPORT moduleImport;
exportDecl: EXPORT exportedItem;
externDecl: EXTERN moduleImport;

exportedItem:
	fnDecl			# ExportedFn
	| letDecl		# ExportedLet
	| typeDecl		# ExportedType
	| interfaceDecl	# ExportedInterface;
moduleImport:
	destructuredImport	# ModuleImportDestructured
	| targetImport		# ModuleImportTarget;
destructuredImport:
	LBRACE importItemList? RBRACE FROM importStr;
targetImport: ID FROM importStr;
importItemList: importItem (COMMA importItem)*;
importItem: ID (AS ID)?;
importStr: singleQuotedString;

// --- Let Declarations ---
letDecl: LET letPattern;
letPattern:
	letSingle				# LetPatternSingle
	| letBlock				# LetPatternBlock
	| letDestructuredObj	# LetPatternDestructuredObj
	| letDestructuredArray	# LetPatternDestructuredArray;
letSingle: typedID (EQUALS expr)?;
letBlock: LPAREN letBlockItem (COMMA letBlockItem)* RPAREN;
letBlockItem:
	typedID EQUALS expr						# LetBlockItemSingle
	| LBRACE typedIDList RBRACE EQUALS expr	# LetBlockItemDestructuredObj
	| LSQBR typedIDList RSQBR EQUALS expr	# LetBlockItemDestructuredArray;
letDestructuredObj: LBRACE typedIDList RBRACE EQUALS expr;
letDestructuredArray: LSQBR typedIDList RSQBR EQUALS expr;

typedIDList: typedID (COMMA typedID)*;
typedID: ID (typeAnnotation)?;

// --- Type & Interface Declarations ---
typeDecl: TYPE ID typeVariants;
typeVariants: typeDefBody | typeAlias;
typeDefBody: (EXTENDS typeList)? LBRACE fieldDecl (COMMA fieldDecl)* RBRACE;
typeAlias: EQUALS typeAnnotation (EXTENDS typeList)?;
fieldDecl: ID (QUESTION)? typeAnnotation;

typeList: typeAnnotation (COMMA typeAnnotation)*;

interfaceDecl: INTERFACE ID (EXTENDS typeList)? LBRACE (stmt_sep* stmt_list_items)? stmt_sep* RBRACE;
interfaceMethod: ID LPAREN parameters RPAREN typeAnnotation?;

// --- Function & Methods ---
fnDecl: fnSignature codeBlock;
fnSignature: FN ID LPAREN parameters? RPAREN typeAnnotation?;
parameters: param (COMMA param)*;
param: ID typeAnnotation (EQUALS expr)?;
methodsDecl: METHODS ID AS ID LBRACE (stmt_sep* stmt_list_items)? stmt_sep* RBRACE;
methodImpl: interfaceMethod codeBlock;

// --- Statements ---
stmt:
	letDecl			# StmtLet
	| expr 			# StmtExpr
	| returnStmt	# StmtReturn
	| yieldStmt		# StmtYield
	| ifStmt		# StmtIf
	| forStmt		# StmtFor
	| whileStmt		# StmtWhile
	| codeBlock		# StmtBlock
	| breakStmt		# StmtBreak
	| continueStmt	# StmtContinue
	| checkStmt		# StmtCheck
	| deferStmt		# StmtDefer;

returnStmt: RETURN exprList?;
yieldStmt: YIELD exprList?;
deferStmt: DEFER expr;
exprList: expr (COMMA expr)*;
ifStmt: IF cond=expr thenBlock=codeBlock (ELSE elseBlock=codeBlock)?;
forStmt: FOR forLoopType;
forLoopType:
	forTrinity
	| (ID (COMMA ID)?) IN expr loopBody;
forTrinity: forInit stmt_sep forCond stmt_sep forPost loopBody;
forInit: letSingle | /* empty */;
forCond: expr | /* empty */;
forPost: expr | /* empty */;
whileStmt: WHILE expr loopBody;
loopBody: LBRACE (stmt_sep* stmt_list_items)? stmt_sep* RBRACE;
codeBlock: LBRACE (stmt_sep* stmt_list_items)? stmt_sep* RBRACE;
breakStmt: BREAK stmt_sep;
continueStmt: CONTINUE stmt_sep;
checkStmt: CHECK expr COMMA stringLiteral stmt_sep;

// --- Expressions ---
expr: assignmentExpr;
assignmentExpr:
	ternaryExpr
	| left=ternaryExpr op=assignmentOp right=assignmentExpr;
assignmentOp:
	EQUALS
	| PLUS_EQUALS
	| MINUS_EQUALS
	| STAR_EQUALS
	| SLASH_EQUALS
	| MOD_EQUALS
	| CARET_EQUALS;
ternaryExpr:
	logicalOrExpr
	| cond=logicalOrExpr QUESTION thenBranch=expr COLON elseExpr=ternaryExpr;
logicalOrExpr:
	logicalAndExpr
	| left=logicalOrExpr PIPE_PIPE right=logicalAndExpr;
logicalAndExpr:
	bitwiseOrExpr
	| left=logicalAndExpr AMP_AMP right=bitwiseOrExpr;
bitwiseOrExpr:
	bitwiseXorExpr
	| left=bitwiseOrExpr PIPE right=bitwiseXorExpr;
bitwiseXorExpr:
	bitwiseAndExpr
	| left=bitwiseXorExpr CARET right=bitwiseAndExpr;
bitwiseAndExpr:
	equalityExpr
	| left=bitwiseAndExpr AMP right=equalityExpr;
equalityExpr:
	comparisonExpr
	| left=equalityExpr op=(EQUALS_EQUALS | NEQ) right=comparisonExpr;
comparisonExpr:
	shiftExpr
	| left=comparisonExpr op=(LT | LT_EQUALS | GT | GT_EQUALS) right=shiftExpr;
shiftExpr:
	additiveExpr
	| left=shiftExpr op=(PLUS | MINUS) right=additiveExpr;
additiveExpr:
	multiplicativeExpr
	| left=additiveExpr op=(PLUS | MINUS) right=multiplicativeExpr;
multiplicativeExpr:
	unaryExpr
	| left=multiplicativeExpr op=(STAR | SLASH | MOD) right=unaryExpr;
unaryExpr:
	(PLUS | MINUS | EXCLAMATION | TRY) unaryExpr
	| awaitExpr;
awaitExpr: (TRY? AWAIT? ASYNC?) postfixExpr;
postfixExpr:
	primaryExpr
	| left=postfixExpr op=postfixOp;
postfixOp:
	LPAREN exprList RPAREN
	| DOT ID
	| LSQBR expr RSQBR;
primaryExpr:
	literal
	| ID
	| LPAREN expr RPAREN
	| arrayLiteral
	| objectLiteral
	| mapLiteral
	| setLiteral
	| fnExpr
	| matchExpr
	| VOID
	| NULL
	| taggedBlockString
	| structInitExpr;

// --- Function Expressions ---
fnExpr: FN LPAREN parameters? RPAREN typeAnnotation? codeBlock;

// --- Match Expressions ---
matchExpr: MATCH expr LBRACE (caseClause)* defaultClause? RBRACE;
caseClause: expr (COLON expr | codeBlock);
defaultClause: DEFAULT (COLON expr | codeBlock);

// --- String Literals ---
singleQuotedString: SINGLE_QUOTE_START stringPart* SINGLE_STR_END;
multiQuotedString: MULTI_QUOTE_START stringPart* MULTI_STR_END;
doubleQuotedString: DOUBLE_QUOTE_START stringPart* DOUBLE_STR_END;
multiDoubleQuotedString: MULTI_DOUBLE_QUOTE_START stringPart* MULTI_DOUBLE_STR_END;
stringPart:
	SINGLE_STR_CONTENT
	| MULTI_STR_CONTENT
	| DOUBLE_STR_CONTENT
	| MULTI_DOUBLE_STR_CONTENT
	| interpolation;
interpolation:
	(SINGLE_STR_INTERP_START
	| MULTI_STR_INTERP_START
	| DOUBLE_STR_INTERP_START
	| MULTI_DOUBLE_STR_INTERP_START)
	expr INTERP_RBRACE;

// --- Literals ---
literal:
	stringLiteral
	| numberLiteral
	| booleanLiteral
	| NULL
	| VOID;
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
objectLiteral: LBRACE (objectField (COMMA objectField)*)? RBRACE;
objectField: objectFieldName (COLON expr)?;
objectFieldName: ID | stringLiteral;
mapLiteral: LSQBR COLON RSQBR | LSQBR mapField (COMMA mapField)* RSQBR;
mapField: expr COLON expr;
setLiteral: LT (expr (COMMA expr)*)? GT;

taggedBlockString: ID (multiQuotedString | multiDoubleQuotedString);

structInitExpr: ID LPAREN structField (COMMA structField)* RPAREN;
structField: ID COLON expr;

// --- Type Annotations ---
typeAnnotation: typeBase EXCLAMATION?;
typeBase: ID | arrayType | tupleType | fnType | VOID;
tupleType: LPAREN typeList RPAREN;
arrayType: ID LSQBR RSQBR;
fnType: FN LPAREN parameters? RPAREN typeAnnotation?;

// --- Helper Rules ---
stmt_sep: SEMICOLON | NEWLINE;