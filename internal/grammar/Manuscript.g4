parser grammar Manuscript;

options {
	tokenVocab = ManuscriptLexer;
}

// --- Program Structure ---
program: (stmt_sep* declaration)* stmt_sep* EOF;

declaration:
	importDecl
	| exportDecl
	| externDecl
	| letDecl
	| typeDecl
	| interfaceDecl
	| fnDecl
	| methodsDecl;

// --- Imports/Exports/Extern ---
importDecl: IMPORT moduleImport SEMICOLON?;
exportDecl: EXPORT exportedItem SEMICOLON?;
externDecl: EXTERN moduleImport SEMICOLON?;

exportedItem: fnDecl | letDecl | typeDecl | interfaceDecl;
moduleImport: destructuredImport | targetImport;
destructuredImport:
	LBRACE importItemList? RBRACE FROM importStr;
targetImport: ID FROM importStr;
importItemList: importItem (COMMA importItem)* (COMMA)?;
importItem: ID (AS ID)?;
importStr: singleQuotedString;

// --- Let Declarations ---
letDecl:
	LET letSingle SEMICOLON?
	| LET letBlock SEMICOLON?
	| LET letDestructuredObj SEMICOLON?
	| LET letDestructuredArray SEMICOLON?;

letSingle: typedID (EQUALS expr)?;
letBlock: LPAREN letBlockItemList? RPAREN;
letBlockItemList: letBlockItemSep* letBlockItem (letBlockItemSep+ letBlockItem)* letBlockItemSep*;
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
typeDefBody: (EXTENDS typeList)? LBRACE (stmt_sep* fieldDecl (stmt_sep* COMMA stmt_sep* fieldDecl)* (stmt_sep* COMMA)? stmt_sep*)? RBRACE;
typeAlias: EQUALS typeAnnotation (EXTENDS typeList)?;
fieldList: fieldDecl (COMMA fieldDecl)* (COMMA)?;
fieldDecl: ID (QUESTION)? typeAnnotation;

typeList: typeAnnotation (COMMA typeAnnotation)* (COMMA)?;

interfaceDecl:
	INTERFACE ID (EXTENDS typeList)? LBRACE (stmt_sep* interfaceMethod stmt_sep*)+ RBRACE;
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
methodImplList: methodImplSep* methodImpl (methodImplSep+ methodImpl)* methodImplSep*;
methodImplSep: stmt_sep;
methodImpl: interfaceMethod codeBlock;

// --- Statements ---
stmt:
	letDecl			# StmtLet
	| expr SEMICOLON?	# StmtExpr
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

returnStmt: RETURN exprList? SEMICOLON?;
yieldStmt: YIELD exprList? SEMICOLON?;
deferStmt: DEFER expr SEMICOLON?;
exprList: expr (COMMA expr)* (COMMA)?;

ifStmt: IF expr codeBlock (ELSE codeBlock)?;
forStmt: FOR forLoopType;
forLoopType:
	forTrinity							# ForLoop
	| (ID (COMMA ID)?) IN expr loopBody	# ForInLoop;
forTrinity: forInit SEMICOLON forCond SEMICOLON forPost loopBody;
forInit: letSingle | ;
forCond: expr | ;
forPost: expr | ;
whileStmt: WHILE expr loopBody;
loopBody: LBRACE (stmt_sep* stmt)* stmt_sep* RBRACE;
codeBlock: LBRACE (stmt_sep* stmt)* stmt_sep* RBRACE;
breakStmt: BREAK SEMICOLON?;
continueStmt: CONTINUE SEMICOLON?;
checkStmt: CHECK expr COMMA stringLiteral SEMICOLON?;

// --- Expressions ---
expr: assignmentExpr;
assignmentExpr: ternaryExpr (assignmentOp assignmentExpr)?;
assignmentOp:
	EQUALS
	| PLUS_EQUALS
	| MINUS_EQUALS
	| STAR_EQUALS
	| SLASH_EQUALS
	| MOD_EQUALS
	| CARET_EQUALS;
ternaryExpr: logicalOrExpr (QUESTION expr COLON ternaryExpr)?;
logicalOrExpr: logicalAndExpr (PIPE_PIPE logicalAndExpr)*;
logicalAndExpr: bitwiseOrExpr (AMP_AMP bitwiseOrExpr)*;
bitwiseOrExpr: bitwiseXorExpr (PIPE bitwiseXorExpr)*;
bitwiseXorExpr: bitwiseAndExpr (CARET bitwiseAndExpr)*;
bitwiseAndExpr: equalityExpr (AMP equalityExpr)*;
equalityExpr:
	comparisonExpr ((EQUALS_EQUALS | NEQ) comparisonExpr)*;
comparisonExpr:
	shiftExpr ((LT | LT_EQUALS | GT | GT_EQUALS) shiftExpr)*;
shiftExpr: additiveExpr ((PLUS | MINUS) additiveExpr)*;
additiveExpr:
	multiplicativeExpr ((PLUS | MINUS) multiplicativeExpr)*;
multiplicativeExpr: unaryExpr ((STAR | SLASH | MOD) unaryExpr)*;
unaryExpr: op = (PLUS | MINUS | EXCLAMATION | TRY) unaryExpr
	| awaitExpr;
awaitExpr: (TRY? AWAIT? ASYNC?) postfixExpr;
postfixExpr: primaryExpr (postfixOp)*;
postfixOp: LPAREN exprList? RPAREN | DOT ID | LSQBR expr RSQBR;
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
fnExpr:
	FN LPAREN parameters? RPAREN (typeAnnotation)? codeBlock;

// --- Match Expressions ---
matchExpr: MATCH expr LBRACE stmt_sep* caseClause (stmt_sep+ caseClause)* stmt_sep* defaultClause? RBRACE;
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
	SINGLE_STR_CONTENT
	| MULTI_STR_CONTENT
	| DOUBLE_STR_CONTENT
	| MULTI_DOUBLE_STR_CONTENT
	| interpolation;
interpolation: (
		SINGLE_STR_INTERP_START
		| MULTI_STR_INTERP_START
		| DOUBLE_STR_INTERP_START
		| MULTI_DOUBLE_STR_INTERP_START
	) expr INTERP_RBRACE;

// --- Literals ---
literal:
	stringLiteral
	| numberLiteral
	| booleanLiteral
	| NULL
	| VOID;
stringLiteral:
	singleQuotedString
	| multiQuotedString
	| doubleQuotedString
	| multiDoubleQuotedString;
numberLiteral:
	INTEGER
	| FLOAT
	| HEX_LITERAL
	| BINARY_LITERAL
	| OCTAL_LITERAL;
booleanLiteral: TRUE | FALSE;

// --- Collections ---
arrayLiteral: LSQBR exprList? RSQBR;
objectLiteral: LBRACE objectFieldList? RBRACE;
objectFieldList: objectField (COMMA objectField)* (COMMA)?;
objectField: objectFieldName (COLON expr)?;
objectFieldName: ID | stringLiteral;
mapLiteral: LSQBR COLON RSQBR | LSQBR mapFieldList? RSQBR;
mapFieldList: mapField (COMMA mapField)* (COMMA)?;
mapField: expr COLON expr;
setLiteral: LT (expr (COMMA expr)* (COMMA)?)? GT;

taggedBlockString:
	ID (multiQuotedString | multiDoubleQuotedString);

structInitExpr: ID LPAREN structFieldList? RPAREN;
structFieldList: structField (COMMA structField)* (COMMA)?;
structField: ID COLON expr;

// --- Type Annotations ---
typeAnnotation: ID | arrayType | tupleType | fnType | VOID;
tupleType: LPAREN typeList? RPAREN;
arrayType: ID LSQBR RSQBR;
fnType: FN LPAREN parameters? RPAREN typeAnnotation?;

// --- Helper Rules ---
stmt_sep: SEMICOLON | NEWLINE;