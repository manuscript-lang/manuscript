lexer grammar ToyLexer;


LET: 'let';
FN: 'fn';

EQUALS: '=';

LPAREN: '(';
RPAREN: ')';
LBRACE: '{';
RBRACE: '}';


ID: [a-zA-Z]+;
WS: [ \t\r\n]+ -> skip;