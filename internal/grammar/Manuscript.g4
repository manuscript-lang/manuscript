parser grammar Manuscript;

options {
	tokenVocab = ManuscriptLexer;
}

// =============================================================================
// Program Structure
// =============================================================================
program: items += programItem* EOF;
programItem:
	importStmt 
	| externStmt 
	| exportStmt 
	| stmt       
	| typeDecl   
	| ifaceDecl  
	| fnDecl     
	| methodBlockDecl 
	;

// =============================================================================
// Imports & Exports
// =============================================================================

// --- Import/Extern --- // (Existing rules)
importStmt: IMPORT
    ( LBRACE (items += importItem (COMMA items += importItem)*)? RBRACE FROM path = importStr
    | target = ID FROM path = importStr
    ) SEMICOLON?;
importItem: name = ID (AS alias = ID)?;

externStmt: EXTERN
    ( LBRACE (items += externItem (COMMA items += externItem)*)? RBRACE FROM path = importStr
    | target = ID FROM path = importStr
    ) SEMICOLON?;
externItem: name = ID (AS alias = ID)?;

// --- Export ---
exportStmt: EXPORT (fnDecl | letDecl | typeDecl | ifaceDecl) SEMICOLON?; // Based on language design

// =============================================================================
// Declarations
// =============================================================================

// --- Variable Declarations ---
letDecl:
	LET (assignments += letAssignment (COMMA assignments += letAssignment)*) SEMICOLON?;
letAssignment:
	pattern = letPattern (EQUALS value = expr)?;
letPattern:
	simple = ID
	| array = arrayPattn
	| object = objectPattn;
arrayPattn:
	LSQBR (names += ID (COMMA names += ID)*)? RSQBR;
objectPattn:
	LBRACE (names += ID (COMMA names += ID)*)? RBRACE;

// --- Function Declaration ---
fnDecl:
	FN name = ID 
	  LPAREN params = parameters? RPAREN 
	  (COLON returnType = typeAnnotation)? 
	  (EXCLAMATION)? // Error indicator
	  block = codeBlock; // Assuming a codeBlock rule for function bodies

parameters: param (COMMA param)*;
param: (label = ID)? name = ID COLON type = typeAnnotation (EQUALS defaultValue = expr)?; // Added default value

// --- Type Declaration ---
typeDecl:
	TYPE name = ID 
	( // Struct definition with optional extends
	  (EXTENDS baseTypes += typeAnnotation (COMMA baseTypes += typeAnnotation)*)?
	  LBRACE (fields += fieldDecl)* RBRACE
	| // Type alias definition
	  EQUALS alias = typeAnnotation SEMICOLON?
	);

fieldDecl: name = ID (QUESTION)? COLON type = typeAnnotation SEMICOLON?; // Optional fields

// --- Interface Declaration ---
ifaceDecl:
	INTERFACE name = ID 
	  (EXTENDS baseIfaces += typeAnnotation (COMMA baseIfaces += typeAnnotation)*)?
	  LBRACE (methods += methodDecl)* RBRACE;

methodDecl: // Signature only within interface
	FN name = ID 
	  LPAREN params = parameters? RPAREN 
	  (COLON returnType = typeAnnotation)? 
	  (EXCLAMATION)? // Error indicator
	  SEMICOLON?;

// --- Methods Block Declaration --- (For implementing interfaces or adding methods to types)
methodBlockDecl:
	METHODS (ifaceName = typeAnnotation FOR)? typeName = typeAnnotation 
	 LBRACE (impls += methodImpl)* RBRACE;

methodImpl: // Full implementation within methods block
	FN name = ID 
	  LPAREN params = parameters? RPAREN 
	  (COLON returnType = typeAnnotation)? 
	  (EXCLAMATION)? // Error indicator
	  block = codeBlock;

// --- Type Annotation --- 
typeAnnotation: 
    base = baseTypeAnnotation 
    ( LSQBR RSQBR // Array modifier
    | LSQBR COLON mapValueType = typeAnnotation RSQBR // Map modifier [keyType: valueType] - keyType is the base
    | LT GT // Set modifier <valueType> - valueType is the base - This syntax might need review
    )*; 

baseTypeAnnotation:
    simpleType = ID
    | tuple = tupleType
    | function = functionType
    ; 

functionType: FN LPAREN (paramTypes += typeAnnotation (COMMA paramTypes += typeAnnotation)*)? RPAREN (returnType = typeAnnotation)?; // e.g., fn(int, string) bool. Trying MINUS GT for '->'

// =============================================================================
// Statements
// =============================================================================
stmt:
	letDecl
	| exprStmt // Expressions as statements
	| returnStmt
	| yieldStmt
	| ifStmt
	| forStmt
	| whileStmt
	| codeBlock // Block of statements
	| SEMICOLON // Empty statement
	;

exprStmt: expr SEMICOLON?; // Allow expressions followed by optional semicolon

returnStmt: RETURN (expr (COMMA expr)*)? SEMICOLON?; // Allow zero, one, or multiple return values
yieldStmt: YIELD expr? SEMICOLON?;

ifStmt: 
	IF condition = expr block = codeBlock (ELSE elseBlock = codeBlock)?; // Simplified if/else

// TODO: Define detailed loop structures based on language-design.md
forStmt:
	FOR 
	( 
	  // C-style loop: for init; condition; update { body }
	  init = forInitPattn? SEMICOLON 
	  condition = expr? SEMICOLON 
	  update = expr? 
	  block = codeBlock
	| // For-in loop: for pattern in iterable { body }
	  pattern = loopPattern IN iterable = expr 
	  block = codeBlock
	) SEMICOLON? ; // Optional semicolon after the loop

forInitPattn:
	letDecl | exprStmt; // Allow let declaration or expression statement as initializer

loopPattern: // Pattern for for-in loops
	varName = ID // for v in ...
	| LSQBR var1 = ID COMMA var2 = ID RSQBR; // for [v, i] in ... or for [k, v] in ... (ambiguity needs semantic check)

whileStmt: WHILE condition = expr block = codeBlock SEMICOLON?;

codeBlock: LBRACE (stmts += stmt)* RBRACE; // Sequence of statements

// =============================================================================
// Expressions
// =============================================================================

// --- Basic Expressions --- (Existing rules)
expr: assignmentExpr;
assignmentExpr:
	left = logicalOrExpr (op = EQUALS right = assignmentExpr)?;
logicalOrExpr:
	left = logicalAndExpr (op = PIPE_PIPE right = logicalAndExpr)*;
logicalAndExpr:
	left = equalityExpr (op = AMP_AMP right = equalityExpr)*;
equalityExpr:
	left = comparisonExpr (op = (EQUALS_EQUALS | NEQ) right = comparisonExpr)*;
comparisonExpr:
	left = additiveExpr (op = (LT | LT_EQUALS | GT | GT_EQUALS) right = additiveExpr)*;
additiveExpr:
	left = multiplicativeExpr (op = (PLUS | MINUS) right = multiplicativeExpr)*;
multiplicativeExpr:
	left = unaryExpr (op = (STAR | SLASH) right = unaryExpr)*;
unaryExpr:
	op = (PLUS | MINUS | EXCLAMATION | TRY | CHECK) unaryExpr // Added TRY and CHECK prefixes
	| awaitExpr;
awaitExpr:
	(TRY? AWAIT? ASYNC?) postfixExpr; // Allow combinations before postfixExpr
	// Old: op = (AWAIT | ASYNC | TRY) awaitExpr | postfixExpr;

postfixExpr:
	primaryExpr
	(
		LPAREN (args += expr (COMMA args += expr)*)? RPAREN // Function call
		| DOT member = ID                                   // Member access
		| LSQBR indexExpr = expr RSQBR                      // Index access
		// | op = PLUS_PLUS                                  // Postfix increment (Removed, check design doc)
		// | op = MINUS_MINUS                                // Postfix decrement (Removed, check design doc)
	)*;

primaryExpr:
	literal          
	| ID             // Variable reference
	| SELF           // Reference to self in methods
	| LPAREN parenExpr = expr RPAREN // Grouping
	| arrayLiteral   
	| objectLiteral  
	| mapLiteral     
	| setLiteral     
	| tupleLiteral   
	| fnExpr        
	| lambdaExpr     
	| tryBlockExpr   
	| matchExpr      
	| VOID
	| NULL;

// --- Function & Lambda Expressions ---
fnExpr:
	FN LPAREN params = parameters? RPAREN 
	   (COLON returnType = typeAnnotation)? 
	   block = codeBlock;
lambdaExpr:
	FN 
	  LPAREN params = parameters? RPAREN 
	  EQUALS body = expr; 

// --- Control Flow Expressions ---
tryBlockExpr: // Represents the try { a(); b() } construct
	TRY block = codeBlock;
	// This handles block-level try. Expression-level try is handled in unaryExpr.

matchExpr: 
	MATCH valueToMatch = expr LBRACE (cases += caseClause (COMMA cases += caseClause)*)? RBRACE;
caseClause:
	CASE pattern = expr COLON result = expr SEMICOLON?;

// =============================================================================
// Literals & String Parsing
// =============================================================================

// --- String Parsing Rules --- 
singleQuotedString:
	SINGLE_QUOTE_START parts += stringPart* SINGLE_STR_END ;
multiQuotedString:
	MULTI_QUOTE_START parts += stringPart* MULTI_STR_END ;
doubleQuotedString:
	DOUBLE_QUOTE_START parts += stringPart* DOUBLE_STR_END ;

stringPart:
	SINGLE_STR_CONTENT
	| MULTI_STR_CONTENT
	| DOUBLE_STR_CONTENT
	| interp = interpolation ;

interpolation: (SINGLE_STR_INTERP_START | MULTI_STR_INTERP_START | DOUBLE_STR_INTERP_START) value = expr INTERP_RBRACE;

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
	| doubleQuotedString;
numberLiteral:
	intValue=INTEGER
  | floatValue=FLOAT
  | hexValue=HEX_LITERAL
  | binaryValue=BINARY_LITERAL
  ; 
booleanLiteral: TRUE | FALSE;

arrayLiteral:
	LSQBR (elements += expr (COMMA elements += expr)*)? RSQBR; 

objectLiteral: // Represents { field: value, ... } syntax from language design
	LBRACE (fields += objectField (COMMA fields += objectField)*)? RBRACE; 
objectField: key = ID (COLON value = expr)?; // Field name must be ID 

mapLiteral:
	LSQBR COLON RSQBR // Empty map
	| LSQBR (fields += mapField (COMMA fields += mapField)*)? RSQBR; // Map with entries
mapField: key = expr COLON value = expr; 

setLiteral:
	LT GT // Empty set
	| LT (elements += expr (COMMA elements += expr)*)? GT; // Set with elements

tupleLiteral:
	LPAREN (elements += expr (COMMA elements += expr)*)? RPAREN; 

importStr: // Used by import/extern 
	pathSingle = singleQuotedString
	| pathMulti = multiQuotedString; 

// =============================================================================
// Types (Basic Definitions)
// =============================================================================

// Basic tuple type definition 
tupleType:
	LPAREN (types += typeAnnotation (COMMA types += typeAnnotation)*)? RPAREN;

