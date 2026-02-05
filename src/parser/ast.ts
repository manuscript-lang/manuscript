import type { SourceLocation } from "../lexer/tokens";
import type { Type } from "../types/types";
export type { SourceLocation };

// Base AST node
export interface BaseNode {
  kind: string;
  loc: SourceLocation;
  resolvedType?: Type;  // Populated by type checker
}

// ============================================
// Programs and Declarations
// ============================================

export interface Program extends BaseNode {
  kind: "Program";
  body: Statement[];
}

export interface ImportDecl extends BaseNode {
  kind: "ImportDecl";
  names: { name: string; alias?: string }[];
  source: string;
}

export interface FnDecl extends BaseNode {
  kind: "FnDecl";
  name: string;
  typeParams?: TypeParam[];
  params: Parameter[];
  returnType?: TypeExpr;
  using?: UsingClause;
  body: Block;
  isGenerator: boolean;
  doc?: string;
}

export interface ExternFnDecl extends BaseNode {
  kind: "ExternFnDecl";
  name: string;
  typeParams?: TypeParam[];
  params: Parameter[];
  returnType?: TypeExpr;
  doc?: string;
}

export interface Parameter extends BaseNode {
  kind: "Parameter";
  name: string;
  type?: TypeExpr;
  optional: boolean;
  defaultValue?: Expr;
  rest: boolean; // ...args
}

export interface UsingClause extends BaseNode {
  kind: "UsingClause";
  bindings: ContextBinding[];
}

export interface ContextBinding extends BaseNode {
  kind: "ContextBinding";
  name?: string;  // Binding name (e.g., "fs" in "fs: Filesystem")
  type: TypeExpr; // The type required from context
}

export interface TypeDecl extends BaseNode {
  kind: "TypeDecl";
  name: string;
  typeParams?: TypeParam[];
  alias?: TypeExpr[];  // For type aliases: type Foo = Bar or type Message = A | B
  using?: UsingClause;
  where?: WhereClause[];
  body: TypeBody;
  isExtern?: boolean;  // extern type - all methods are implicitly extern
  isContextType?: boolean;  // context TypeName - capability type for with/using
  doc?: string;
}

export interface TypeParam extends BaseNode {
  kind: "TypeParam";
  name: string;
  constraint?: TypeExpr;
}

export interface WhereClause extends BaseNode {
  kind: "WhereClause";
  param: string;
  constraint: TypeExpr;
}

export interface TypeBody extends BaseNode {
  kind: "TypeBody";
  members: TypeMember[];
}

export type TypeMember = FieldDecl | MethodDecl;

export interface FieldDecl extends BaseNode {
  kind: "FieldDecl";
  name: string;
  type?: TypeExpr;
  optional: boolean;
  defaultValue?: Expr;
  computed: boolean; // () => expr
  embedded?: boolean; // Go-style embedding (e.g., "Animal" in type body)
  doc?: string;
}

export interface MethodDecl extends BaseNode {
  kind: "MethodDecl";
  name: string;
  typeParams?: TypeParam[];
  params: Parameter[];
  returnType?: TypeExpr;
  using?: UsingClause;
  body?: Block;
  isGenerator?: boolean;
  isExtern?: boolean;
  doc?: string;
}

export interface InterfaceDecl extends BaseNode {
  kind: "InterfaceDecl";
  name: string;
  typeParams?: TypeParam[];
  body: InterfaceBody;
  doc?: string;
}

export interface InterfaceBody extends BaseNode {
  kind: "InterfaceBody";
  members: InterfaceMember[];
}

export type InterfaceMember = MethodDecl | EmbeddedInterfaceDecl;

export interface EmbeddedInterfaceDecl extends BaseNode {
  kind: "EmbeddedInterfaceDecl";
  name: string;
}

export interface EnumDecl extends BaseNode {
  kind: "EnumDecl";
  name: string;
  variants: EnumVariant[];
}

export interface EnumVariant extends BaseNode {
  kind: "EnumVariant";
  name: string;
  value?: Expr;
}

export interface KeywordDecl extends BaseNode {
  kind: "KeywordDecl";
  sealed?: boolean;
  name: string;
  expansion: "type" | "fn";
  using?: UsingClause;
  returnType?: TypeExpr;      // For fn keywords
  body?: KeywordBody;         // Fields and methods with implementations
}

// Body of a keyword declaration - defines required fields, optional fields, and sealed methods
export interface KeywordBody extends BaseNode {
  kind: "KeywordBody";
  members: KeywordMember[];
}

export type KeywordMember = KeywordField | MethodDecl;

// Field specification in a keyword - can be required, optional, or have defaults
export interface KeywordField extends BaseNode {
  kind: "KeywordField";
  name: string;
  type: TypeExpr;
  optional: boolean;          // field?: Type
  defaultValue?: Expr;        // field: Type = value
  computed: boolean;          // field: () => expr
  doc?: string;
}

// Usage of a keyword-defined type (e.g., "agent Coder using (...)")
export interface KeywordTypeUse extends BaseNode {
  kind: "KeywordTypeUse";
  keyword: string;            // "agent", "workflow", etc.
  name: string;               // "Coder", "DataPipeline"
  using?: UsingClause;
  body: TypeBody;             // User-provided fields and methods
  doc?: string;
}

export interface ContextDecl extends BaseNode {
  kind: "ContextDecl";
  name: string;
  bindings?: { name: string; value: Expr }[];
  methods?: MethodDecl[];
}

export interface AgentDecl extends BaseNode {
  kind: "AgentDecl";
  name: string;
  context?: ContextBinding[];
  fields?: FieldDecl[];
  tools?: FnDecl[];
  run?: FnDecl;
}

export interface TestDecl extends BaseNode {
  kind: "TestDecl";
  description: string;
  withClause?: Expr;
  body: Block;
}

// ============================================
// Statements
// ============================================

export type Statement =
  | ImportDecl
  | FnDecl
  | ExternFnDecl
  | TypeDecl
  | InterfaceDecl
  | EnumDecl
  | KeywordDecl
  | KeywordTypeUse
  | ContextDecl
  | AgentDecl
  | TestDecl
  | LetStmt
  | VarStmt
  | AssignStmt
  | IfStmt
  | ForStmt
  | MatchStmt
  | ReturnStmt
  | YieldStmt
  | BreakStmt
  | ContinueStmt
  | DeferStmt
  | TryStmt
  | ThrowStmt
  | WithStmt
  | ExprStmt;

export interface Block extends BaseNode {
  kind: "Block";
  statements: Statement[];
}

export interface LetStmt extends BaseNode {
  kind: "LetStmt";
  pattern: Pattern;
  type?: TypeExpr;
  value: Expr;
}

export interface VarStmt extends BaseNode {
  kind: "VarStmt";
  name: string;
  type?: TypeExpr;
  value: Expr;
}

export interface AssignStmt extends BaseNode {
  kind: "AssignStmt";
  target: Expr;
  op: "=" | "+=" | "-=" | "*=" | "/=" | "%=";
  value: Expr;
}

export interface IfStmt extends BaseNode {
  kind: "IfStmt";
  condition: Expr;
  then: Block | Statement;
  elseIfs: { condition: Expr; body: Block }[];
  else?: Block;
  // Guard form: if let pattern = expr else return/throw
  pattern?: Pattern;
  elseReturn?: Expr;
}

export interface ForStmt extends BaseNode {
  kind: "ForStmt";
  pattern?: Pattern;  // for item in items
  iterable?: Expr;    // the items
  body: Block;
  // Infinite loop if pattern is undefined
}

export interface MatchStmt extends BaseNode {
  kind: "MatchStmt";
  value: Expr;
  arms: MatchArm[];
}

export interface MatchArm extends BaseNode {
  kind: "MatchArm";
  pattern: Pattern;
  guard?: Expr;
  body: Expr | Block;
}

export interface ReturnStmt extends BaseNode {
  kind: "ReturnStmt";
  value?: Expr;
}

export interface YieldStmt extends BaseNode {
  kind: "YieldStmt";
  value: Expr;
}

export interface BreakStmt extends BaseNode {
  kind: "BreakStmt";
}

export interface ContinueStmt extends BaseNode {
  kind: "ContinueStmt";
}

export interface DeferStmt extends BaseNode {
  kind: "DeferStmt";
  body: Statement;
}

export interface TryStmt extends BaseNode {
  kind: "TryStmt";
  body: Block;
  catch?: { name: string; body: Block };
}

export interface ThrowStmt extends BaseNode {
  kind: "ThrowStmt";
  value: Expr;
}

export interface WithContext {
  expr: Expr;
  name?: string;  // with let name = expr
  nameLoc?: SourceLocation;  // loc of the binding name for LSP
}

export interface WithStmt extends BaseNode {
  kind: "WithStmt";
  contexts: WithContext[];
  body: Block;
}

export interface ExprStmt extends BaseNode {
  kind: "ExprStmt";
  expr: Expr;
}

// ============================================
// Patterns (for destructuring and matching)
// ============================================

export type Pattern =
  | IdentifierPattern
  | LiteralPattern
  | ObjectPattern
  | ArrayPattern
  | RestPattern
  | TypePattern
  | RangePattern
  | WildcardPattern;

export interface IdentifierPattern extends BaseNode {
  kind: "IdentifierPattern";
  name: string;
}

export interface LiteralPattern extends BaseNode {
  kind: "LiteralPattern";
  value: number | string | boolean | null;
}

export interface ObjectPattern extends BaseNode {
  kind: "ObjectPattern";
  properties: { key: string; pattern: Pattern }[];
}

export interface ArrayPattern extends BaseNode {
  kind: "ArrayPattern";
  elements: Pattern[];
}

export interface RestPattern extends BaseNode {
  kind: "RestPattern";
  name: string;
}

export interface TypePattern extends BaseNode {
  kind: "TypePattern";
  type: TypeExpr;
  binding?: string; // Type as binding
}

export interface RangePattern extends BaseNode {
  kind: "RangePattern";
  start: number;
  end: number;
}

export interface WildcardPattern extends BaseNode {
  kind: "WildcardPattern";
}

// ============================================
// Expressions
// ============================================

export type Expr =
  | Literal
  | Identifier
  | BinaryExpr
  | UnaryExpr
  | CallExpr
  | IndexExpr
  | MemberExpr
  | PipeExpr
  | LambdaExpr
  | IfExpr
  | MatchExpr
  | ListExpr
  | SetExpr
  | MapExpr
  | TemplateLiteral
  | SpawnExpr
  | TypeAssertion
  | NullAssertion
  | RangeExpr;

export interface Literal extends BaseNode {
  kind: "Literal";
  value: number | string | boolean | null;
}

export interface Identifier extends BaseNode {
  kind: "Identifier";
  name: string;
}

export interface BinaryExpr extends BaseNode {
  kind: "BinaryExpr";
  op: string;
  left: Expr;
  right: Expr;
}

export interface UnaryExpr extends BaseNode {
  kind: "UnaryExpr";
  op: string;
  operand: Expr;
}

export interface CallExpr extends BaseNode {
  kind: "CallExpr";
  callee: Expr;
  args: (Expr | { name: string; value: Expr })[]; // positional or named
}

export interface IndexExpr extends BaseNode {
  kind: "IndexExpr";
  object: Expr;
  index: Expr;
  optional: boolean; // ?.[]
  // For slicing: obj[start:end:step]
  slice?: { start?: Expr; end?: Expr; step?: Expr };
  // For generic type instantiation: Type[A, B] - additional type args after first
  typeArgs?: Expr[];
}

export interface MemberExpr extends BaseNode {
  kind: "MemberExpr";
  object: Expr;
  property: string;
  optional: boolean; // ?.
}

export interface PipeExpr extends BaseNode {
  kind: "PipeExpr";
  left: Expr;
  right: Expr;
}

export interface LambdaExpr extends BaseNode {
  kind: "LambdaExpr";
  params: Parameter[];
  body: Expr | Block;
}

export interface IfExpr extends BaseNode {
  kind: "IfExpr";
  condition: Expr;
  then: Expr;
  else: Expr;
}

export interface MatchExpr extends BaseNode {
  kind: "MatchExpr";
  value: Expr;
  arms: MatchArm[];
}

export interface ListExpr extends BaseNode {
  kind: "ListExpr";
  elements: (Expr | SpreadElement)[];
}

export interface SpreadElement extends BaseNode {
  kind: "SpreadElement";
  expr: Expr;
}

export interface SetExpr extends BaseNode {
  kind: "SetExpr";
  elements: Expr[];
}

export interface MapExpr extends BaseNode {
  kind: "MapExpr";
  entries: MapEntry[];
}

export interface MapEntry extends BaseNode {
  kind: "MapEntry";
  key: Expr;
  value: Expr;
  spread?: boolean;
}

export interface TemplateLiteral extends BaseNode {
  kind: "TemplateLiteral";
  parts: (string | TemplateExpr)[];
}

export interface TemplateExpr extends BaseNode {
  kind: "TemplateExpr";
  expr: Expr;
  format?: string; // for filters
}

export interface SpawnExpr extends BaseNode {
  kind: "SpawnExpr";
  expr: Expr;
}

export interface TypeAssertion extends BaseNode {
  kind: "TypeAssertion";
  expr: Expr;
  type: TypeExpr;
}

export interface NullAssertion extends BaseNode {
  kind: "NullAssertion";
  expr: Expr;
}

export interface RangeExpr extends BaseNode {
  kind: "RangeExpr";
  start: Expr;
  end: Expr;
  inclusive: boolean;
}

// ============================================
// Type Expressions
// ============================================

export type TypeExpr =
  | NamedType
  | GenericType
  | FunctionType
  | TypePredicateExpr
  | UnionType
  | OptionalType
  | ListType
  | MapType;

export interface NamedType extends BaseNode {
  kind: "NamedType";
  name: string;
}

export interface GenericType extends BaseNode {
  kind: "GenericType";
  name: string;
  args: TypeExpr[];
}

export interface FunctionType extends BaseNode {
  kind: "FunctionType";
  params: TypeExpr[];
  returnType: TypeExpr;
}

// Type predicate for type guard functions: x is Type
export interface TypePredicateExpr extends BaseNode {
  kind: "TypePredicateExpr";
  paramName: string;   // The parameter name
  targetType: TypeExpr; // The type being asserted
}

export interface UnionType extends BaseNode {
  kind: "UnionType";
  types: TypeExpr[];
}

export interface OptionalType extends BaseNode {
  kind: "OptionalType";
  inner: TypeExpr;
}

export interface ListType extends BaseNode {
  kind: "ListType";
  elementType: TypeExpr;
}

export interface MapType extends BaseNode {
  kind: "MapType";
  keyType: TypeExpr;
  valueType: TypeExpr;
}

// Type alias for any AST node
export type ASTNode =
  | Program
  | Statement
  | Expr
  | Pattern
  | TypeExpr
  | TypeMember
  | KeywordMember
  | MatchArm
  | Parameter
  | Block
  | KeywordBody
  | InterfaceBody
  | InterfaceMember;
