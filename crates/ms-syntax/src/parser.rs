//! The strict parser, producing a [`Module`] or the first diagnostic.

use crate::ast::*;
use crate::diag::{Diagnostic, DiagnosticFix, Phase};
use crate::lexer::{PResult, lex};
use crate::pos::Pos;
use crate::symbol::Symbol;
use crate::token::{Tok, Token};
use std::sync::Arc;

/// Bounds recursive descent so hostile input produces a diagnostic instead of
/// exhausting the stack.
pub const MAX_NESTING: usize = 1000;
/// Bounds left-nested operator, member, call and index chains.
pub const MAX_CHAIN: usize = 10000;

/// Parses `source` strictly. The first error aborts the parse.
pub fn parse(file: &Arc<str>, source: &str) -> PResult<Module> {
    let mut module = parse_chunk(file, source, 0, 0, 0)?;
    module.file = file.clone();
    module.source = Arc::from(source);
    Ok(module)
}

/// Parses a slice of a larger file whose first byte is at original offset
/// `base_offset` on line `base_line + 1`. Used by editor recovery.
pub(crate) fn parse_chunk(
    file: &Arc<str>,
    source: &str,
    base_offset: u32,
    base_line: u32,
    first_id: u32,
) -> PResult<Module> {
    let lexed = crate::lexer::lex_at(file, source, base_offset, base_line)?;
    let mut p = Parser::new(
        file,
        &lexed.source,
        lexed.tokens,
        &lexed.boundaries,
        0,
        0,
        first_id,
    );
    let mut module = Module::default();
    p.module(&mut module)?;
    module.node_count = p.next_id;
    Ok(module)
}

struct Parser<'a> {
    file: &'a Arc<str>,
    src: &'a str,
    tokens: Vec<Token>,
    boundaries: &'a crate::lexer::ScanBoundaries,
    /// Start of `src` in the normalized source scanned by the outer lexer.
    source_origin: usize,
    at: usize,
    inline_statement: bool,
    inline_return: bool,
    block_lambda: bool,
    depth: usize,
    /// Bindings after the first of a `let (...)` group until `statements` collects them.
    queued: Vec<Stmt>,
    next_id: u32,
    /// While positive, failures are speculative: their messages are never shown.
    speculative: u32,
    /// The next statement is the `elif` of an `if` chain.
    elif: bool,
}

fn describe(src: &str, t: Token) -> String {
    match t.kind {
        Tok::Newline => "end of line".into(),
        Tok::Indent => "an unexpected indented block".into(),
        Tok::Dedent => "the end of the block".into(),
        Tok::Eof => "end of file".into(),
        Tok::Name => format!("name '{}'", &src[t.lo as usize..t.hi as usize]),
        Tok::Number => format!("number {}", &src[t.lo as usize..t.hi as usize]),
        Tok::String => format!("text {}", &src[t.lo as usize..t.hi as usize]),
        k => format!("'{}'", k.as_str()),
    }
}

fn describe_kind(kind: &str) -> String {
    match kind {
        "NEWLINE" => "end of line".into(),
        "INDENT" => "an indented block".into(),
        "DEDENT" => "the end of the block".into(),
        "EOF" => "end of file".into(),
        "NAME" => "a name".into(),
        "NUMBER" => "a number".into(),
        "STRING" => "text in double quotes".into(),
        k => format!("'{}'", k),
    }
}

/// Adds the usual fix for the punctuation that is most often missing.
fn need_hint(kind: &str, found: Tok, found_text: &str) -> String {
    match kind {
        ":" => "; block headers (def, if, elif, else, for, while, match, case, with, type, impl, test) end with ':' before their indented body".into(),
        ")" => "; close the parenthesis, separating items with commas".into(),
        "]" => "; close the bracket, separating items with commas".into(),
        "}" => "; close the brace, separating items with commas".into(),
        "(" if found == Tok::Lt => {
            "; type parameters use square brackets, e.g. def identity[T](value: T) -> T:".into()
        }
        "(" => "; a call or parameter list starts with '('".into(),
        "import" => "; imports read: from \"path.ms\" import name, other".into(),
        "in" => "; loops read: for item in items:".into(),
        "=" if found == Tok::Newline => {
            "; every let/var binding needs an initial value, e.g. var count: Int = 0".into()
        }
        "NAME" => {
            if found == Tok::SelfKw {
                "; 'self' is reserved: a method's receiver is implicit, so leave it out of the parameter list and write self.field in the body".into()
            } else if found == Tok::Case {
                "; 'case' starts a match arm (case Paid(receipt):) or declares a case of a type".into()
            } else if found == Tok::LParen {
                "; give it a name, e.g. def add(a: Int, b: Int) -> Int:".into()
            } else if found_text == "_" {
                "; '_' is a reserved word and cannot be used as a name: loops, parameters and bindings need a real name such as item, unused or ignored".into()
            } else if found.as_str() == found_text {
                format!("; '{}' is a reserved word and cannot be used as a name", found_text)
            } else {
                String::new()
            }
        }
        "NEWLINE" => "; end the statement with a line break".into(),
        "INDENT" => "; indent the block body by four spaces under its header".into(),
        _ => String::new(),
    }
}

/// Declaration words from other languages: the message and the Manuscript
/// spelling to replace the word with, when there is one.
fn foreign_declaration(t: Token, text: &str) -> Option<(String, Option<&'static str>)> {
    if t.kind == Tok::Var {
        return Some(("module level holds only 'let' constants; keep mutable state in a 'var' inside a fn, or in a field of a type".into(), None));
    }
    if t.kind != Tok::Name {
        return None;
    }
    let (replacement, advice) = match text {
        "function" | "fn" | "func" | "fun" | "sub" => (
            Some("def"),
            "declare a function as 'def name(a: Int) -> Int:' with the result type after '->'",
        ),
        "class" | "struct" | "record" | "data" => (
            Some("type"),
            "declare a record with 'type Name:' and 'field: Type' lines, then add methods in 'impl Name:'",
        ),
        "enum" | "union" | "variant" | "sealed" => (
            Some("type"),
            "declare alternatives with 'type Name:' and one 'case Variant' or 'case Variant(field: Type)' line each",
        ),
        "trait" | "protocol" | "abstract" => (
            Some("interface"),
            "declare a contract with 'interface Name:' and method signatures, then implement it with 'impl Name for Type:'",
        ),
        "const" | "val" | "final" => (
            Some("let"),
            "write 'let NAME = value' for a module constant",
        ),
        "pub" | "public" => (
            Some("export"),
            "write 'export' before the declaration to make it visible to other modules",
        ),
        "use" | "require" | "include" | "using" => {
            (None, "imports read: from \"path.ms\" import name, other")
        }
        "static" | "private" | "internal" | "async" | "extern" | "package" | "namespace"
        | "module" => (
            None,
            "there is no such modifier; top level holds only from-imports, let, def, type, interface, impl, and test, optionally prefixed by export",
        ),
        _ => return None,
    };
    Some((
        format!("'{text}' is not a Manuscript declaration keyword; {advice}"),
        replacement,
    ))
}

/// Precedence of `..`: above comparisons, below `+` and `-`.
const RANGE_LEVEL: u8 = 5;

fn binary_op(kind: Tok) -> Option<BinaryOp> {
    Some(match kind {
        Tok::Or => BinaryOp::Or,
        Tok::And => BinaryOp::And,
        Tok::EqEq => BinaryOp::Eq,
        Tok::NotEq => BinaryOp::Ne,
        Tok::Lt => BinaryOp::Lt,
        Tok::Gt => BinaryOp::Gt,
        Tok::Le => BinaryOp::Le,
        Tok::Ge => BinaryOp::Ge,
        Tok::Plus => BinaryOp::Add,
        Tok::Minus => BinaryOp::Sub,
        Tok::Star => BinaryOp::Mul,
        Tok::Slash => BinaryOp::Div,
        Tok::Percent => BinaryOp::Rem,
        _ => return None,
    })
}

fn arith_op(kind: Tok) -> Option<BinaryOp> {
    match kind {
        Tok::Plus | Tok::Minus | Tok::Star | Tok::Slash | Tok::Percent => binary_op(kind),
        _ => None,
    }
}

impl<'a> Parser<'a> {
    fn new(
        file: &'a Arc<str>,
        src: &'a str,
        tokens: Vec<Token>,
        boundaries: &'a crate::lexer::ScanBoundaries,
        source_origin: usize,
        depth: usize,
        next_id: u32,
    ) -> Parser<'a> {
        Parser {
            file,
            src,
            tokens,
            boundaries,
            source_origin,
            at: 0,
            inline_statement: false,
            inline_return: false,
            block_lambda: false,
            depth,
            queued: Vec::new(),
            next_id,
            speculative: 0,
            elif: false,
        }
    }

    fn id(&mut self) -> NodeId {
        let id = NodeId(self.next_id);
        self.next_id += 1;
        id
    }
    fn peek(&self) -> Token {
        self.tokens[self.at]
    }
    fn kind(&self) -> Tok {
        self.tokens[self.at].kind
    }
    /// Token `n` ahead of the current one, clamped to the final `Eof`.
    fn ahead(&self, n: usize) -> Token {
        self.tokens[(self.at + n).min(self.tokens.len() - 1)]
    }
    fn previous(&self) -> Token {
        self.tokens[self.at - 1]
    }
    fn text(&self, t: Token) -> &'a str {
        &self.src[t.lo as usize..t.hi as usize]
    }
    fn sym(&self, t: Token) -> Symbol {
        Symbol::intern(self.text(t))
    }
    fn take(&mut self, k: Tok) -> bool {
        if self.kind() == k {
            self.at += 1;
            true
        } else {
            false
        }
    }
    fn next(&mut self) -> Token {
        let t = self.peek();
        self.at += 1;
        t
    }
    fn dummy(&self) -> Box<Diagnostic> {
        Box::new(Diagnostic::parse(self.file, Pos::default(), String::new()))
    }
    fn need(&mut self, k: Tok) -> PResult<Token> {
        let t = self.peek();
        if t.kind == k {
            self.at += 1;
            return Ok(t);
        }
        if self.speculative > 0 {
            return Err(self.dummy());
        }
        if k == Tok::Colon && t.kind == Tok::LBrace {
            return self.fail_fix(
                t,
                "expected ':', found '{'; blocks are not braced: end the header with ':', indent the body four spaces on the following lines, and remove the closing '}'",
                ":",
            );
        }
        let msg = format!(
            "expected {}, found {}{}",
            describe_kind(k.as_str()),
            describe(self.src, t),
            need_hint(k.as_str(), t.kind, self.text(t))
        );
        self.fail(t, msg)
    }
    fn fail<T>(&self, t: Token, message: impl Into<String>) -> PResult<T> {
        let mut d = Diagnostic::parse(self.file, t.pos, message);
        if t.end.line > 0 {
            d.end = Some(t.end);
        }
        Err(Box::new(d))
    }
    /// Fails on `t` with a machine-applicable replacement of exactly its range.
    fn fail_fix<T>(&self, t: Token, message: impl Into<String>, replacement: &str) -> PResult<T> {
        self.fail_fix_range(t, t, message, replacement)
    }
    /// Fails on `first` with a replacement of the range `first.pos..last.end`.
    fn fail_fix_range<T>(
        &self,
        first: Token,
        last: Token,
        message: impl Into<String>,
        replacement: &str,
    ) -> PResult<T> {
        let mut d = Diagnostic::parse(self.file, first.pos, message);
        if last.end.line > 0 {
            d.end = Some(last.end);
            d.fix = Some(DiagnosticFix {
                pos: first.pos,
                end: last.end,
                replacement: replacement.to_string(),
            });
        }
        Err(Box::new(d))
    }
    /// The colon after a parameter or field name; a missing one is usually a
    /// type written directly after the name.
    fn need_name_colon(&mut self, name: Token) -> PResult<()> {
        let t = self.peek();
        if t.kind == Tok::Name && self.speculative == 0 {
            let at = Token {
                pos: name.end,
                end: name.end,
                ..name
            };
            let msg = format!(
                "expected ':' between '{}' and its type; parameters and fields are written name: Type",
                self.text(name)
            );
            return self.fail_fix(at, msg, ":");
        }
        self.need(Tok::Colon).map(|_| ())
    }
    fn newlines(&mut self) {
        while self.take(Tok::Newline) {}
    }
    fn link(&mut self, links: &mut usize) -> PResult<()> {
        *links += 1;
        if *links > MAX_CHAIN {
            let t = self.peek();
            return self.fail(
                t,
                format!(
                    "expression chain exceeds {} operators or accesses; split it into named parts",
                    MAX_CHAIN
                ),
            );
        }
        Ok(())
    }
    /// Counts one level of nesting; on success the caller must decrement `depth`.
    fn enter(&mut self) -> PResult<()> {
        self.depth += 1;
        if self.depth > MAX_NESTING {
            if self.speculative > 0 {
                return Err(self.dummy());
            }
            let t = self.peek();
            return self.fail(t, format!("nesting exceeds {} levels; split the expression, type, or block into named parts", MAX_NESTING));
        }
        Ok(())
    }

    fn end(&mut self) -> PResult<()> {
        if self.inline_statement {
            match self.kind() {
                Tok::Newline | Tok::Comma | Tok::RParen | Tok::RBracket | Tok::RBrace => {
                    return Ok(());
                }
                _ => {}
            }
            let t = self.peek();
            let msg = format!(
                "expected end of inline statement, found {}; an inline body holds one simple statement, so move more statements to an indented block",
                describe(self.src, t)
            );
            return self.fail(t, msg);
        }
        if self.take(Tok::Newline) {
            self.newlines();
            return Ok(());
        }
        if self.at > 0 && self.previous().kind == Tok::Dedent {
            return Ok(());
        }
        let t = self.peek();
        if self.block_lambda && t.kind == Tok::Comma {
            return self.fail(t, "a comma cannot end a statement in an indented function body; to separate enclosing arguments, put the comma on its own line dedented to the fn header, or group the function in parentheses");
        }
        if t.kind == Tok::Amp {
            return self.and_and(t);
        }
        if t.kind == Tok::Arrow || (t.kind == Tok::Assign && self.ahead(1).kind == Tok::Gt) {
            return self.fail(
                t,
                "there is no arrow function; anonymous functions are written lambda x: x + 1",
            );
        }
        let prev_new = self.at > 0 && self.text(self.previous()) == "new";
        let hint = match t.kind {
            Tok::Name if self.text(t) == "is" => {
                "; there is no 'is' operator: write '==' to compare values, or 'match value:' to test which alternative a value is"
            }
            Tok::Name if prev_new => {
                "; there is no 'new': construct a value by calling the type, Name(field: value)"
            }
            Tok::If => {
                "; put the condition on its own statement, or write a conditional expression as 'a if condition else b'"
            }
            Tok::Comma => {
                "; commas separate items only inside (), [] or {}: put each field, case, or statement on its own line"
            }
            Tok::LBrace => {
                "; '{' does not open a block: end the header with ':' and indent the body (an interface method is just its signature)"
            }
            _ => {
                "; put one statement per line, and join operands with an operator or a comma inside brackets"
            }
        };
        let msg = format!(
            "expected end of statement, found {}{hint}",
            describe(self.src, t)
        );
        self.fail(t, msg)
    }

    // ---- module ----

    fn module(&mut self, module: &mut Module) -> PResult<()> {
        while self.kind() != Tok::Eof {
            self.newlines();
            if self.kind() == Tok::Eof {
                break;
            }
            if self.kind() == Tok::Name
                && self.text(self.peek()) == "from"
                && self.ahead(1).kind == Tok::String
            {
                self.at += 1;
                self.import(module)?;
                continue;
            }
            if self.kind() == Tok::Import {
                let t = self.peek();
                return self.fail(t, "imports read: from \"path.ms\" import name, other");
            }
            let exported = self.take(Tok::Export);
            let decls = self.declarations()?;
            for mut d in decls {
                if exported && matches!(d.kind, DeclKind::Impl(_) | DeclKind::Test(_)) {
                    let t = self.previous();
                    return self.fail(t, "only types, interfaces, and named functions can be exported; remove 'export' before this impl, test, or bench");
                }
                d.export = exported;
                module.decls.push(d);
            }
        }
        Ok(())
    }

    /// Parses the rest of `from "path" import a, b` after `from`.
    fn import(&mut self, module: &mut Module) -> PResult<()> {
        let pos = self.previous().pos;
        let token = self.need(Tok::String)?;
        let mut parts = self.text_parts_of(token)?;
        let path = match (parts.len(), parts.pop()) {
            (1, Some(TextPart::Lit(text))) => text,
            _ => {
                return self.fail(token, "import paths are plain text; write the path as plain text without f-string interpolation");
            }
        };
        self.need(Tok::Import)?;
        if self.kind() == Tok::Star {
            let t = self.peek();
            return self.fail(t, "namespace and wildcard imports are unsupported; import individual exports with 'from \"./module.ms\" import Name, OtherName'");
        }
        let mut names: Vec<Token> = Vec::new();
        let grouped = self.take(Tok::LParen);
        loop {
            names.push(self.need(Tok::Name)?);
            if self.kind() == Tok::Name && self.text(self.peek()) == "as" {
                let t = self.peek();
                return self.fail(t, "imports cannot be renamed with 'as'; import the name as the module declares it");
            }
            if !self.take(Tok::Comma) {
                break;
            }
            if grouped && self.kind() == Tok::RParen {
                break;
            }
            if !grouped && matches!(self.kind(), Tok::Newline | Tok::Eof) {
                let t = self.peek();
                return self.fail(t, "a trailing comma needs parentheses; write from \"path.ms\" import (a, b,) or drop the comma");
            }
        }
        if grouped {
            self.need(Tok::RParen)?;
        }
        for name in names {
            let id = self.id();
            module.imports.push(Import {
                id,
                pos,
                name_pos: name.pos,
                name: self.sym(name),
                path: path.clone(),
            });
        }
        self.end()
    }

    // ---- types ----

    fn type_params(&mut self) -> PResult<Vec<TypeParam>> {
        let mut result = Vec::new();
        if !self.take(Tok::LBracket) {
            return Ok(result);
        }
        loop {
            let name = self.need(Tok::Name)?;
            let mut bounds = Vec::new();
            let mut default = None;
            if self.take(Tok::Colon) {
                bounds.push(self.named_type()?);
                while self.take(Tok::Amp) {
                    bounds.push(self.named_type()?);
                }
            }
            if self.take(Tok::Assign) {
                default = Some(self.typ()?);
            }
            let id = self.id();
            result.push(TypeParam {
                id,
                pos: name.pos,
                name: self.sym(name),
                bounds,
                default,
            });
            if !self.take(Tok::Comma) {
                break;
            }
            if self.kind() == Tok::RBracket {
                break;
            }
        }
        self.need(Tok::RBracket)?;
        Ok(result)
    }

    fn parameters(&mut self, defaults: bool, inferred: bool) -> PResult<Vec<Param>> {
        self.need(Tok::LParen)?;
        let mut params = Vec::new();
        if !self.take(Tok::RParen) {
            loop {
                let mutable = self.take(Tok::Var);
                let name = self.need(Tok::Name)?;
                let mut ty = None;
                let mut default = None;
                if self.take(Tok::Colon) {
                    ty = Some(self.typ()?);
                } else if !inferred || self.kind() == Tok::Name {
                    self.need_name_colon(name)?;
                }
                if self.take(Tok::Assign) {
                    if !defaults {
                        let t = self.previous();
                        return self.fail(t, "function types and case payloads cannot have defaults; put the default on a named function parameter or a record field instead");
                    }
                    default = Some(self.expression(0)?);
                }
                let id = self.id();
                params.push(Param {
                    id,
                    pos: name.pos,
                    name: self.sym(name),
                    ty,
                    default,
                    mutable,
                });
                if !self.take(Tok::Comma) {
                    break;
                }
                if self.kind() == Tok::RParen {
                    break;
                }
            }
            self.need(Tok::RParen)?;
        }
        Ok(params)
    }

    fn named_type(&mut self) -> PResult<TypeRef> {
        let name = self.need(Tok::Name)?;
        let mut full = self.sym(name);
        if self.kind() == Tok::Dot {
            let mut s = String::from(full.as_str());
            while self.take(Tok::Dot) {
                s.push('.');
                let part = self.need(Tok::Name)?;
                s.push_str(self.text(part));
            }
            full = Symbol::intern(&s);
        }
        let mut args = Vec::new();
        if self.take(Tok::LBracket) {
            args = self.type_args()?;
        }
        let lt = self.peek();
        if lt.kind == Tok::Lt
            && self.speculative == 0
            && lt.pos.offset == self.previous().end.offset
            && args.is_empty()
        {
            return self.fail(lt, format!("type arguments use square brackets, not angle brackets; write {full}[T] instead of {full}<T>"));
        }
        let id = self.id();
        Ok(TypeRef {
            id,
            pos: name.pos,
            kind: TypeKind::Named { name: full, args },
        })
    }

    fn type_args(&mut self) -> PResult<Vec<TypeRef>> {
        let mut types = Vec::new();
        loop {
            types.push(self.typ()?);
            if !self.take(Tok::Comma) {
                break;
            }
            if self.kind() == Tok::RBracket {
                break;
            }
        }
        self.need(Tok::RBracket)?;
        Ok(types)
    }

    /// Parses the type that follows a parameter list, rejecting the removed
    /// `->` and a missing type with the form to write instead.
    fn result_type(&mut self) -> PResult<(bool, TypeRef)> {
        let t = self.peek();
        if t.kind != Tok::Arrow {
            if self.speculative > 0 {
                return Err(self.dummy());
            }
            return self.fail(
                t,
                "every def declares its result type after '->', e.g. def f() -> Unit:",
            );
        }
        self.at += 1;
        let by_ref = self.take(Tok::Ref);
        Ok((by_ref, self.typ()?))
    }

    fn typ(&mut self) -> PResult<TypeRef> {
        self.enter()?;
        let r = self.typ_inner();
        self.depth -= 1;
        r
    }

    fn typ_inner(&mut self) -> PResult<TypeRef> {
        let first = self.peek();
        if first.kind == Tok::Name
            && self.text(first) == "Callable"
            && self.ahead(1).kind == Tok::LBracket
        {
            self.at += 2;
            self.need(Tok::LBracket)?;
            let mut params = Vec::new();
            if !self.take(Tok::RBracket) {
                loop {
                    let ty = self.typ()?;
                    let id = self.id();
                    params.push(Param {
                        id,
                        pos: ty.pos,
                        name: Symbol::intern(&format!("_{}", params.len())),
                        ty: Some(ty),
                        default: None,
                        mutable: false,
                    });
                    if !self.take(Tok::Comma) {
                        break;
                    }
                    if self.kind() == Tok::RBracket {
                        break;
                    }
                }
                self.need(Tok::RBracket)?;
            }
            self.need(Tok::Comma)?;
            let result = Box::new(self.typ()?);
            self.need(Tok::RBracket)?;
            let id = self.id();
            return Ok(TypeRef {
                id,
                pos: first.pos,
                kind: TypeKind::Fn { params, result },
            });
        }
        if self.take(Tok::LParen) {
            let t = self.typ()?;
            self.need(Tok::RParen)?;
            return Ok(t);
        }
        self.named_type()
    }

    // ---- declarations ----

    /// Parses one top-level item, or every constant of a `let (...)` group.
    fn declarations(&mut self) -> PResult<Vec<Decl>> {
        if self.kind() != Tok::Let || self.ahead(1).kind != Tok::LParen {
            return Ok(vec![self.declaration()?]);
        }
        let keyword = self.next();
        let mut result = Vec::new();
        self.binding_group(keyword, &mut |p: &mut Parser<'a>| {
            let pos = p.peek().pos;
            let c = p.constant(Some(keyword.pos))?;
            let id = p.id();
            result.push(Decl {
                id,
                pos,
                export: false,
                synthetic: false,
                kind: DeclKind::Const(c),
            });
            Ok(())
        })?;
        Ok(result)
    }

    /// Parses `name [: Type] = value` after `let`.
    fn constant(&mut self, group: Option<Pos>) -> PResult<ConstDecl> {
        let name = self.need(Tok::Name)?;
        let mut ty = None;
        if self.take(Tok::Colon) {
            ty = Some(self.typ()?);
        }
        self.need(Tok::Assign)?;
        // A binary expression's position is its operator, so the statement
        // starts at the first token of the initializer for source tooling.
        let init_pos = self.peek().pos;
        let value = self.expression(0)?;
        Ok(ConstDecl {
            name: self.sym(name),
            ty,
            value,
            init_pos,
            group,
        })
    }

    /// Parses the `( ... )` after a consumed `let` or `var`. The lexer ends
    /// each line of the group with a newline; `entry` parses one binding at the
    /// start of its line.
    fn binding_group(
        &mut self,
        keyword: Token,
        entry: &mut dyn FnMut(&mut Parser<'a>) -> PResult<()>,
    ) -> PResult<()> {
        let mut indent = keyword.pos.column;
        let mut i = self.at as isize - 2;
        while i >= 0
            && self.tokens[i as usize].pos.line == keyword.pos.line
            && self.tokens[i as usize].kind != Tok::Newline
        {
            indent = self.tokens[i as usize].pos.column;
            i -= 1;
        }
        let kw = keyword.kind.as_str();
        if self.inline_statement {
            let t = self.peek();
            return self.fail(t, format!("a binding group needs its own lines; put '{kw} (' on a line of its own with one binding per indented line, or write single '{kw} name = value' bindings"));
        }
        self.need(Tok::LParen)?;
        if self.kind() != Tok::Newline {
            let t = self.peek();
            return self.fail(t, format!("a binding group starts its entries on the next line; write '{kw} (' then one 'name = value' per indented line, or destructure with '{kw} [a, b] = value' or '{kw} {{x, y}} = value'"));
        }
        self.next();
        let mut count = 0;
        loop {
            self.newlines();
            let t = self.peek();
            if t.kind == Tok::RParen {
                if t.pos.column != indent {
                    return self.fail(t, format!("the closing ')' of a binding group aligns with its '{kw}' line, at column {indent}"));
                }
                break;
            } else if t.kind == Tok::Eof {
                self.need(Tok::RParen)?;
            } else if t.pos.column != indent + 4 {
                return self.fail(t, format!("binding group entries are indented four spaces past the '{kw}' line, to column {}", indent + 4));
            }
            entry(self)?;
            count += 1;
            if self.kind() == Tok::Comma {
                let t = self.peek();
                return self.fail(t, format!("a binding group holds one 'name = value' per line, not a comma list; to destructure write '{kw} [a, b] = value' or '{kw} {{x, y}} = value'"));
            }
            // A block lambda value ends at its dedent, which also ends the line.
            if self.previous().kind != Tok::Dedent {
                self.need(Tok::Newline)?;
            }
        }
        if count == 0 {
            let t = self.peek();
            return self.fail(
                t,
                "a binding group cannot be empty; add 'name = value' lines or remove the group",
            );
        }
        self.need(Tok::RParen)?;
        self.end()
    }

    fn method_signature(
        &mut self,
        name: Token,
        generics: bool,
        body: bool,
        mutating: bool,
    ) -> PResult<Method> {
        let type_params = if generics {
            self.type_params()?
        } else {
            Vec::new()
        };
        let params = self.parameters(true, false)?;
        let (result_ref, result) = self.result_type()?;
        let body = if body {
            self.statement_suite(false, true)?
        } else {
            Vec::new()
        };
        let id = self.id();
        Ok(Method {
            id,
            pos: name.pos,
            func: Func {
                name: self.sym(name),
                type_params,
                params,
                result,
                result_ref,
                body,
                external: false,
            },
            mutating,
        })
    }

    /// Parses the rest of `test "name":` or `bench "name":` after the keyword.
    fn test_block(&mut self, bench: bool) -> PResult<DeclKind> {
        let name = self.need(Tok::String)?;
        let mut parts = self.text_parts_of(name)?;
        let text = match (parts.len(), parts.pop()) {
            (1, Some(TextPart::Lit(text))) => text,
            _ if bench => {
                return self.fail(
                    name,
                    "bench names cannot interpolate; use plain text, e.g. bench \"sums a list\":",
                );
            }
            _ => {
                return self.fail(
                    name,
                    "test names cannot interpolate; use plain text, e.g. test \"adds numbers\":",
                );
            }
        };
        let mut per = 1;
        if bench && self.kind() == Tok::Name && self.text(self.peek()) == "per" {
            self.at += 1;
            let count = self.need(Tok::Number)?;
            per = match self.text(count).parse::<i64>() {
                Ok(n) if n > 0 => n,
                _ => {
                    return self.fail(
                        count,
                        "'per' takes a positive whole number of operations, e.g. bench \"sums a list\" per 1000:",
                    );
                }
            };
        }
        let body = self.suite()?;
        Ok(DeclKind::Test(TestDecl {
            name: text,
            body,
            bench,
            per,
        }))
    }

    fn declaration(&mut self) -> PResult<Decl> {
        let token = self.peek();
        let mut export_pos_dummy = ();
        let _ = &mut export_pos_dummy;
        let kind = match token.kind {
            Tok::Def => {
                self.at += 1;
                let name = self.need(Tok::Name)?;
                let type_params = self.type_params()?;
                let params = self.parameters(true, false)?;
                let (result_ref, result) = self.result_type()?;
                let body = self.statement_suite(false, true)?;
                DeclKind::Fn(Func {
                    name: self.sym(name),
                    type_params,
                    params,
                    result,
                    result_ref,
                    body,
                    external: false,
                })
            }
            Tok::Extern if self.ahead(1).kind == Tok::Type => {
                self.at += 1;
                self.at += 1;
                let name_tok = self.need(Tok::Name)?;
                let name = self.sym(name_tok);
                let type_params = self.type_params()?;
                if self.kind() == Tok::Colon {
                    let t = self.peek();
                    return self.fail(t, "an extern type has no body; remove the ':'");
                }
                self.end()?;
                DeclKind::Record(RecordDecl {
                    name,
                    type_params,
                    fields: Vec::new(),
                    external: true,
                })
            }
            Tok::Extern => {
                self.at += 1;
                self.need(Tok::Def)?;
                let name = self.need(Tok::Name)?;
                let type_params = self.type_params()?;
                let params = self.parameters(true, false)?;
                let (result_ref, result) = self.result_type()?;
                if self.kind() == Tok::Colon {
                    let t = self.peek();
                    return self.fail(t, "an extern def has no body; remove the ':'");
                }
                self.end()?;
                DeclKind::Fn(Func {
                    name: self.sym(name),
                    type_params,
                    params,
                    result,
                    result_ref,
                    body: Vec::new(),
                    external: true,
                })
            }
            Tok::Let => {
                self.at += 1;
                let c = self.constant(None)?;
                self.end()?;
                DeclKind::Const(c)
            }
            Tok::Test => {
                self.at += 1;
                self.test_block(false)?
            }
            Tok::Name if self.text(token) == "bench" && self.ahead(1).kind == Tok::String => {
                self.at += 1;
                self.test_block(true)?
            }
            Tok::Impl => {
                self.at += 1;
                // `impl Contract for Type:` implements a contract; `impl Type:`
                // declares the type's own methods.
                let first = self.named_type()?;
                let (contract, receiver) = if self.take(Tok::For) {
                    (Some(first), self.named_type()?)
                } else {
                    (None, first)
                };
                self.need(Tok::Colon)?;
                self.need(Tok::Newline)?;
                self.newlines();
                let mut methods = Vec::new();
                if self.take(Tok::Indent) {
                    while self.kind() != Tok::Dedent {
                        self.newlines();
                        if self.kind() == Tok::Dedent {
                            break;
                        }
                        let mutating = self.take(Tok::Var);
                        self.need(Tok::Def)?;
                        let name = self.need(Tok::Name)?;
                        methods.push(self.method_signature(name, true, true, mutating)?);
                    }
                    self.need(Tok::Dedent)?;
                }
                DeclKind::Impl(ImplDecl {
                    contract,
                    receiver,
                    methods,
                })
            }
            Tok::Type | Tok::Interface => return self.type_declaration(token),
            _ => {
                if let Some((msg, replacement)) = foreign_declaration(token, self.text(token)) {
                    return match replacement {
                        Some(r) => self.fail_fix(token, msg, r),
                        None => self.fail(token, msg),
                    };
                }
                if token.kind == Tok::Export {
                    return self.fail_fix(
                        token,
                        "'export' appears twice; write it once before the declaration",
                        "",
                    );
                }
                let msg = format!(
                    "expected a module declaration or import, found {}; top level holds only import, let constants, fn, type, interface, impl, and test (optionally prefixed by export), so put statements inside a fn",
                    describe(self.src, token)
                );
                return self.fail(token, msg);
            }
        };
        let id = self.id();
        Ok(Decl {
            id,
            pos: token.pos,
            export: false,
            synthetic: false,
            kind,
        })
    }

    fn type_declaration(&mut self, token: Token) -> PResult<Decl> {
        self.at += 1;
        let name_tok = self.need(Tok::Name)?;
        let name = self.sym(name_tok);
        let type_params = self.type_params()?;
        self.need(Tok::Colon)?;
        if token.kind == Tok::Type && self.take(Tok::Ellipsis) {
            self.end()?;
            let id = self.id();
            return Ok(Decl {
                id,
                pos: token.pos,
                export: false,
                synthetic: false,
                kind: DeclKind::Record(RecordDecl {
                    name,
                    type_params,
                    fields: Vec::new(),
                    external: false,
                }),
            });
        }
        self.need(Tok::Newline)?;
        self.need(Tok::Indent)?;
        #[derive(PartialEq, Clone, Copy)]
        enum Form {
            None,
            Record,
            Alternative,
            Interface,
        }
        let mut form = if token.kind == Tok::Interface {
            Form::Interface
        } else {
            Form::None
        };
        let mut fields: Vec<Param> = Vec::new();
        let mut cases: Vec<Case> = Vec::new();
        let mut methods: Vec<Method> = Vec::new();
        while self.kind() != Tok::Dedent {
            self.newlines();
            if self.kind() == Tok::Dedent {
                break;
            }
            let next = match self.kind() {
                Tok::Case => Form::Alternative,
                Tok::Def => Form::Interface,
                Tok::Var if self.ahead(1).kind == Tok::Def => Form::Interface,
                _ => Form::Record,
            };
            if token.kind == Tok::Interface && next != Form::Interface {
                let t = self.peek();
                return self.fail(t, "a type has only fields or cases; an interface has only operation signatures; declare fields as 'name: Type' in a type, and put method bodies in an 'impl' block");
            }
            if next != Form::Interface {
                if form != Form::None && form != next {
                    let t = self.peek();
                    return self.fail(t, "a type cannot mix fields and cases; use either fields (a record) or 'case' lines (an alternative), and wrap shared data in a case payload");
                }
                form = next;
            }
            if self.take(Tok::Case) {
                let name = self.need(Tok::Name)?;
                let mut payload = Vec::new();
                if self.kind() == Tok::LParen {
                    payload = self.parameters(false, false)?;
                    if payload.iter().any(|p| p.mutable) {
                        let t = self.previous();
                        return self.fail(t, "case payload fields cannot be 'var'; mutability belongs to the binding that holds the value");
                    }
                    if payload.is_empty() {
                        let n = self.text(name);
                        return self.fail(name, format!("nullary cases omit parentheses; write 'case {n}' instead of 'case {n}()'"));
                    }
                }
                let id = self.id();
                cases.push(Case {
                    id,
                    pos: name.pos,
                    name: self.sym(name),
                    fields: payload,
                });
                self.end()?;
            } else if self.kind() == Tok::Def
                || (self.kind() == Tok::Var && self.ahead(1).kind == Tok::Def)
            {
                let mutating = self.take(Tok::Var);
                self.need(Tok::Def)?;
                if token.kind == Tok::Type {
                    let t = self.previous();
                    let names = type_param_names(&type_params);
                    return self.fail(t, format!("a type declares only fields or cases; write its methods in an 'impl {name}{names}:' block, or implement an interface with 'impl <Interface> for {name}{names}:'"));
                }
                let mname = self.need(Tok::Name)?;
                let m = self.method_signature(mname, true, false, mutating)?;
                self.end()?;
                methods.push(m);
            } else {
                let fname = self.need(Tok::Name)?;
                self.need_name_colon(fname)?;
                let ty = self.typ()?;
                let mut default = None;
                if self.take(Tok::Assign) {
                    default = Some(self.expression(0)?);
                }
                let id = self.id();
                fields.push(Param {
                    id,
                    pos: fname.pos,
                    name: self.sym(fname),
                    ty: Some(ty),
                    default,
                    mutable: false,
                });
                self.end()?;
            }
        }
        self.need(Tok::Dedent)?;
        if token.kind == Tok::Interface && methods.is_empty() {
            return self.fail(token, "declaration body cannot be empty; an interface needs at least one 'def name(...) -> Type' operation");
        }
        let kind = match form {
            Form::Interface => DeclKind::Interface(InterfaceDecl {
                name,
                type_params,
                methods,
            }),
            Form::Alternative => DeclKind::Alternative(AlternativeDecl {
                name,
                type_params,
                cases,
            }),
            Form::Record | Form::None => DeclKind::Record(RecordDecl {
                name,
                type_params,
                fields,
                external: false,
            }),
        };
        let id = self.id();
        Ok(Decl {
            id,
            pos: token.pos,
            export: false,
            synthetic: false,
            kind,
        })
    }

    // ---- statements ----

    fn suite(&mut self) -> PResult<Vec<Stmt>> {
        self.statement_suite(false, false)
    }

    /// Parses `: body`. `expression` marks a lambda body (an inline body is its
    /// value); `fn_body` marks a function or method body (inline returns, may be empty).
    fn statement_suite(&mut self, expression: bool, fn_body: bool) -> PResult<Vec<Stmt>> {
        self.enter()?;
        let (outer, outer_return, outer_lambda) =
            (self.inline_statement, self.inline_return, self.block_lambda);
        let r = self.statement_suite_inner(expression, fn_body, outer, outer_lambda);
        self.inline_statement = outer;
        self.inline_return = outer_return;
        self.block_lambda = outer_lambda;
        self.depth -= 1;
        r
    }

    fn statement_suite_inner(
        &mut self,
        expression: bool,
        fn_body: bool,
        outer: bool,
        outer_lambda: bool,
    ) -> PResult<Vec<Stmt>> {
        self.need(Tok::Colon)?;
        if self.kind() == Tok::Ellipsis && fn_body {
            self.at += 1;
            self.end()?;
            return Ok(Vec::new());
        }
        if self.kind() != Tok::Newline {
            if matches!(self.kind(), Tok::If | Tok::While | Tok::For | Tok::With) {
                let t = self.peek();
                return self.fail(t, format!("inline bodies require one simple statement; put '{}' on its own line in an indented block", t.kind.as_str()));
            }
            self.inline_statement = true;
            self.inline_return = expression || fn_body;
            let body = vec![self.statement(false)?];
            self.inline_statement = outer;
            if !expression {
                self.end()?;
            }
            return Ok(body);
        }
        self.inline_statement = false;
        self.inline_return = false;
        self.block_lambda = outer_lambda || expression;
        self.need(Tok::Newline)?;
        self.need(Tok::Indent)?;
        let mut body = Vec::new();
        loop {
            self.newlines();
            if self.kind() == Tok::Dedent || self.kind() == Tok::Eof {
                break;
            }
            self.statements(false, &mut body)?;
        }
        self.need(Tok::Dedent)?;
        if body.is_empty() {
            let t = self.previous();
            return self.fail(t, "suite cannot be empty; add at least one statement, or write '...' after the colon for a runtime-bound declaration");
        }
        Ok(body)
    }

    /// Rejects `ref` after `let`, `var`, `for` or `match`: binding a place already borrows it.
    fn no_binding_ref(&mut self) -> PResult<()> {
        if self.kind() == Tok::Ref {
            let at = self.peek();
            return self.fail(at, "`ref` is written only before a result type; a binding of a place already borrows it, so drop `ref`");
        }
        Ok(())
    }

    /// Parses `pattern [: Type] = value` after let or var.
    fn binding(&mut self, mutable: bool, group: Option<Pos>, pos: Pos) -> PResult<Stmt> {
        self.no_binding_ref()?;
        let pattern = self.pattern()?;
        let mut ty = None;
        if matches!(pattern.kind, PatternKind::Name(_)) && self.take(Tok::Colon) {
            ty = Some(self.typ()?);
        }
        self.need(Tok::Assign)?;
        let value = self.expression(0)?;
        let id = self.id();
        Ok(Stmt {
            id,
            pos,
            kind: StmtKind::Bind {
                mutable,
                pattern,
                ty,
                value,
                group,
            },
        })
    }

    /// Parses one statement, plus the rest of its bindings for a group.
    fn statements(&mut self, allow_value: bool, out: &mut Vec<Stmt>) -> PResult<()> {
        let s = self.statement(allow_value)?;
        out.push(s);
        out.append(&mut self.queued);
        Ok(())
    }

    fn statement(&mut self, allow_value: bool) -> PResult<Stmt> {
        let t = self.peek();
        let pos = t.pos;
        let kind = match t.kind {
            Tok::Let | Tok::Var => {
                self.at += 1;
                let mutable = t.kind == Tok::Var;
                if self.kind() == Tok::LParen {
                    let mut entries: Vec<Stmt> = Vec::new();
                    self.binding_group(t, &mut |p: &mut Parser<'a>| {
                        let epos = p.peek().pos;
                        let e = p.binding(mutable, Some(t.pos), epos)?;
                        entries.push(e);
                        Ok(())
                    })?;
                    let mut it = entries.into_iter();
                    let first = it.next().expect("binding groups are nonempty");
                    self.queued = it.collect();
                    return Ok(first);
                }
                let s = self.binding(mutable, None, pos)?;
                self.end()?;
                return Ok(s);
            }
            Tok::Def => {
                self.at += 1;
                let name = self.need(Tok::Name)?;
                if self.kind() == Tok::LBracket {
                    let b = self.peek();
                    return self.fail(b, "a local def cannot take type parameters; declare a generic function at module level");
                }
                let params = self.parameters(true, false)?;
                let at = self.peek();
                let (by_ref, result) = self.result_type()?;
                if by_ref {
                    return self.fail(
                        at,
                        "a local def cannot return a 'ref'; only a declared def or method can lend",
                    );
                }
                let result = Box::new(result);
                let body = self.statement_suite(true, false)?;
                let pid = self.id();
                let value = self.mk(
                    t.pos,
                    ExprKind::Lambda(Lambda {
                        params,
                        result: Some(result),
                        body,
                    }),
                );
                StmtKind::Bind {
                    mutable: false,
                    pattern: Pattern {
                        id: pid,
                        pos: name.pos,
                        kind: PatternKind::Name(self.sym(name)),
                    },
                    ty: None,
                    value,
                    group: None,
                }
            }
            Tok::Return => {
                self.at += 1;
                let mut value = None;
                let k = self.kind();
                if k != Tok::Newline
                    && !(self.inline_statement
                        && matches!(k, Tok::Comma | Tok::RParen | Tok::RBracket | Tok::RBrace))
                {
                    value = Some(self.expression(0)?);
                }
                self.end()?;
                StmtKind::Return(value)
            }
            Tok::Break | Tok::Continue => {
                self.at += 1;
                self.end()?;
                if t.kind == Tok::Break {
                    StmtKind::Break
                } else {
                    StmtKind::Continue
                }
            }
            Tok::If | Tok::Elif => {
                if t.kind == Tok::Elif && !self.elif {
                    return self.fail(t, "'elif' continues an 'if' block: put it on its own line at the same indentation as that 'if', directly after the if body");
                }
                self.elif = false;
                self.at += 1;
                let mut binding = None;
                let mut mutable = false;
                if self.kind() == Tok::Let || self.kind() == Tok::Var {
                    mutable = self.kind() == Tok::Var;
                    self.at += 1;
                    let pat = self.pattern()?;
                    if !matches!(pat.kind, PatternKind::Name(_)) {
                        return self.fail(t, "if let binds one name; write 'if let value = optional:' and destructure the value inside the branch");
                    }
                    binding = Some(pat);
                    self.need(Tok::Assign)?;
                }
                let cond = self.expression(0)?;
                let body = self.suite()?;
                self.newlines();
                let mut else_body = Vec::new();
                if self.kind() == Tok::Elif {
                    self.elif = true;
                    else_body = vec![self.statement(false)?];
                } else if self.take(Tok::Else) {
                    if self.kind() == Tok::If {
                        let c = self.peek();
                        return self.fail_fix(
                            c,
                            "there is no 'else if'; write 'elif <condition>:' for a further branch",
                            "elif",
                        );
                    }
                    else_body = self.suite()?;
                }
                StmtKind::If {
                    binding,
                    mutable,
                    cond,
                    body,
                    else_body,
                }
            }
            Tok::While => {
                self.at += 1;
                let cond = self.expression(0)?;
                let body = self.suite()?;
                StmtKind::While { cond, body }
            }
            Tok::For => {
                self.at += 1;
                if self.kind() == Tok::LParen {
                    let c = self.peek();
                    return self.fail(c, "for does not take parentheses or a counter clause; write 'for item in items:' to visit a List, or 'for i in 0..n:' to count");
                }
                self.no_binding_ref()?;
                let name = self.need(Tok::Name)?;
                if self.kind() == Tok::Name && self.text(self.peek()) == "of" {
                    let c = self.peek();
                    return self.fail(c, "for uses 'in', not 'of'; write 'for item in items:'");
                }
                if self.kind() == Tok::Comma {
                    let c = self.peek();
                    return self.fail(c, "for binds one name; to read positions, loop over the entries, e.g. 'for entry in items.entries():' and use entry.index and entry.value");
                }
                self.need(Tok::In)?;
                let iter = self.expression(0)?;
                let body = self.suite()?;
                StmtKind::For {
                    name: self.sym(name),
                    iter,
                    body,
                }
            }
            Tok::With => {
                self.at += 1;
                let kind = self.peek();
                if kind.kind != Tok::Let && kind.kind != Tok::Var {
                    return self.fail(
                        kind,
                        "expected 'let' or 'var'; with binds its resource: with let file = open(path):",
                    );
                }
                self.at += 1;
                let name = self.need(Tok::Name)?;
                self.need(Tok::Assign)?;
                let value = self.expression(0)?;
                let body = self.suite()?;
                StmtKind::With {
                    name: self.sym(name),
                    mutable: kind.kind == Tok::Var,
                    value,
                    body,
                }
            }
            _ => self.expression_statement(t, allow_value)?,
        };
        let id = self.id();
        Ok(Stmt { id, pos, kind })
    }

    fn expression_statement(&mut self, t: Token, allow_value: bool) -> PResult<StmtKind> {
        let e = self.expression(0)?;
        let kind = if self.compound_assignment() {
            self.compound(t, e)?
        } else if self.take(Tok::Assign) {
            if index_parts(&e).is_some() {
                let value = self.expression(0)?;
                let kind = self.index_set(e, value);
                self.end()?;
                return Ok(kind);
            }
            let target = self.assign_target(t, e)?;
            let value = self.expression(0)?;
            StmtKind::Assign {
                target,
                compound: None,
                value,
            }
        } else {
            let try_call = matches!(&e.kind, ExprKind::Unary { op: UnaryOp::Try, operand } if matches!(operand.kind, ExprKind::Call { .. }));
            let is_call = matches!(e.kind, ExprKind::Call { .. } | ExprKind::Match { .. });
            if !self.inline_return && !is_call && !try_call && !allow_value {
                if let ExprKind::Name(n) = &e.kind {
                    match n.as_str() {
                        "pass" => return self.fail(t, "'pass' is not a keyword; write '()' for an empty block or match arm"),
                        "const" | "val" | "final" => {
                            return self.fail(t, format!("'{n}' is not a keyword; write 'let name = ...' for a binding that is not reassigned, or 'var name = ...' when it changes"));
                        }
                        "throw" | "raise" | "catch" => {
                            return self.fail(t, format!("'{n}' is not a keyword; failures are values, so return error(...) from a def returning Result and handle it with 'try' or 'if let'"));
                        }
                        "elseif" => return self.fail(t, "'elseif' is not a keyword; write 'elif <condition>:' for a further branch"),
                        "switch" => return self.fail(t, "'switch' is not a keyword; write 'match value:' with one arm per case of your own type, or 'if x == a:' with 'elif' for plain values"),
                        "except" | "finally" => return self.fail(t, format!("'{n}' is not a keyword; failures are values, so return error(...) from a def returning Result and handle it with 'try' or 'if let'")),
                        "loop" => return self.fail(t, "'loop' is not a keyword; write 'while True:' and leave it with 'break'"),
                        "foreach" => return self.fail(t, "'foreach' is not a keyword; write 'for item in items:'"),
                        "class" => return self.fail(t, "'class' is not a keyword inside a def; declare a record with 'type Name:' at module level"),
                        "del" => return self.fail(t, "'del' is not a keyword; remove from a collection with its methods, such as xs.remove(i) or m.remove(key)"),
                        "global" | "nonlocal" => return self.fail(t, format!("'{n}' is not a keyword; a def sees module 'let' constants directly, and mutable state lives in a 'var' or a field passed explicitly")),
                        "yield" => return self.fail(t, "'yield' is not a keyword; there are no generators, so build a list and return it"),
                        "async" | "await" => return self.fail(t, format!("'{n}' is not a keyword; call the function directly, or start concurrent work with a TaskGroup from \"@std/tasks.ms\" inside 'with'")),
                        "go" => return self.fail(t, "'go' is not a keyword; start concurrent work with a TaskGroup from \"@std/tasks.ms\": with let group = TaskGroup[T](): group.spawn(lambda ch: work())"),
                        _ => {}
                    }
                }
                return self.fail(t, "only a call, try call, or match can be a standalone expression statement; use 'let name = ...' to keep the value, 'return' to return it, or call a function");
            }
            if self.inline_return {
                StmtKind::Return(Some(e))
            } else {
                StmtKind::Call(e)
            }
        };
        self.end()?;
        Ok(kind)
    }

    /// `xs[i] = value` as the call of the member `[]=`, which the checker resolves to `set` on a
    /// List and `add` on a Map.
    fn index_set(&mut self, target: Expr, value: Expr) -> StmtKind {
        let (left, index) = match target.kind {
            ExprKind::Index { left, index } => (left, index),
            ExprKind::Apply {
                left,
                value: Some(index),
                ..
            } => (left, index),
            _ => unreachable!("index target"),
        };
        let pos = target.pos;
        let member = self.mk(
            pos,
            ExprKind::Member {
                left,
                name: Symbol::intern(INDEX_SET),
            },
        );
        let args = vec![
            Argument {
                pos: index.pos,
                name: None,
                value: *index,
                mutable: false,
            },
            Argument {
                pos: value.pos,
                name: None,
                value,
                mutable: false,
            },
        ];
        let call = self.mk(
            pos,
            ExprKind::Call {
                callee: Box::new(member),
                args,
            },
        );
        StmtKind::Call(call)
    }

    fn assign_target(&mut self, start: Token, e: Expr) -> PResult<AssignTarget> {
        match e.kind {
            ExprKind::Name(n) if n.as_str() != "self" && n.as_str() != "fixture" => Ok(AssignTarget::Name(n)),
            ExprKind::Member { .. } => Ok(AssignTarget::Member(e)),
            _ => self.fail(start, "assignment requires a local binding name or record field; the left side of '=' must be a name or a.field; to change a collection element, write xs[index] = value on a List or m[key] = value on a Map"),
        }
    }

    /// Parses `target op= value` as the assignment `target = target op value`.
    fn compound(&mut self, start: Token, e: Expr) -> PResult<StmtKind> {
        let op = self.peek();
        let equal = self.ahead(1);
        let plain = plain_chain(&e);
        let copy = if plain {
            Some(self.clone_chain(&e))
        } else {
            None
        };
        if let Some(copy) = &copy
            && index_parts(&e).is_some()
        {
            self.at += 2;
            let bop = arith_op(op.kind).expect("compound operator");
            let right = self.expression(0)?;
            let id = self.id();
            let value = Expr {
                id,
                pos: op.pos,
                end: right.end,
                kind: ExprKind::Binary {
                    op: bop,
                    left: Box::new(copy.clone()),
                    right: Box::new(right),
                },
            };
            return Ok(self.index_set(e, value));
        }
        let target = self.assign_target(start, e)?;
        let Some(left) = copy else {
            let text = op.kind.as_str();
            let mut d = Diagnostic::parse(
                self.file,
                op.pos,
                format!(
                    "compound assignment '{text}=' needs a name or a.field target whose receiver is names only; bind the receiver to a name first, or write the assignment out"
                ),
            );
            d.end = Some(equal.end);
            d.phase = Phase::Parse;
            return Err(Box::new(d));
        };
        self.at += 2;
        let bop = arith_op(op.kind).expect("compound operator");
        let right = self.expression(0)?;
        let id = self.id();
        let value = Expr {
            id,
            pos: op.pos,
            end: right.end,
            kind: ExprKind::Binary {
                op: bop,
                left: Box::new(left),
                right: Box::new(right),
            },
        };
        Ok(StmtKind::Assign {
            target,
            compound: Some(bop),
            value,
        })
    }

    fn clone_chain(&mut self, e: &Expr) -> Expr {
        let id = self.id();
        let kind = match &e.kind {
            ExprKind::Member { left, name } => ExprKind::Member {
                left: Box::new(self.clone_chain(left)),
                name: *name,
            },
            ExprKind::Index { left, index } => ExprKind::Index {
                left: Box::new(self.clone_chain(left)),
                index: Box::new(self.clone_chain(index)),
            },
            ExprKind::Apply { left, types, value } => ExprKind::Apply {
                left: Box::new(self.clone_chain(left)),
                types: self.copy_types(types),
                value: value.as_ref().map(|v| Box::new(self.clone_chain(v))),
            },
            other => other.clone(),
        };
        Expr {
            id,
            pos: e.pos,
            end: e.end,
            kind,
        }
    }

    fn compound_assignment(&self) -> bool {
        if arith_op(self.kind()).is_some() && self.at + 1 < self.tokens.len() {
            let next = self.tokens[self.at + 1];
            return next.kind == Tok::Assign && self.peek().end.offset == next.pos.offset;
        }
        false
    }

    // ---- patterns ----

    fn pattern(&mut self) -> PResult<Pattern> {
        self.enter()?;
        let r = self.pattern_inner();
        self.depth -= 1;
        r
    }

    fn pattern_inner(&mut self) -> PResult<Pattern> {
        let t = self.peek();
        if self.take(Tok::Name) {
            let id = self.id();
            return Ok(Pattern {
                id,
                pos: t.pos,
                kind: PatternKind::Name(self.sym(t)),
            });
        }
        // `_` binds a value nothing reads, such as a `Result` ignored on purpose.
        if self.take(Tok::Underscore) {
            let id = self.id();
            return Ok(Pattern {
                id,
                pos: t.pos,
                kind: PatternKind::Name(Symbol::intern("_")),
            });
        }
        if self.take(Tok::LBracket) {
            let mut elements = Vec::new();
            if !self.take(Tok::RBracket) {
                loop {
                    elements.push(self.pattern()?);
                    if !self.take(Tok::Comma) {
                        break;
                    }
                    if self.kind() == Tok::RBracket {
                        break;
                    }
                }
                self.need(Tok::RBracket)?;
            }
            let id = self.id();
            return Ok(Pattern {
                id,
                pos: t.pos,
                kind: PatternKind::List(elements),
            });
        }
        if self.take(Tok::LBrace) {
            let mut fields = Vec::new();
            loop {
                let name = self.need(Tok::Name)?;
                let child = if self.take(Tok::Colon) {
                    self.pattern()?
                } else {
                    let id = self.id();
                    Pattern {
                        id,
                        pos: name.pos,
                        kind: PatternKind::Name(self.sym(name)),
                    }
                };
                fields.push(PatternField {
                    pos: name.pos,
                    name: self.sym(name),
                    pattern: child,
                });
                if !self.take(Tok::Comma) {
                    break;
                }
                if self.kind() == Tok::RBrace {
                    break;
                }
            }
            self.need(Tok::RBrace)?;
            let id = self.id();
            return Ok(Pattern {
                id,
                pos: t.pos,
                kind: PatternKind::Record(fields),
            });
        }
        let msg = format!(
            "expected a binding name, list pattern, or record pattern, found {}; write a name, [a, b], or {{x, y}}",
            describe(self.src, t)
        );
        self.fail(t, msg)
    }

    // ---- expressions ----

    fn mk(&mut self, pos: Pos, kind: ExprKind) -> Expr {
        let id = self.id();
        let end = if self.at > 0 {
            self.previous().end
        } else {
            pos
        };
        Expr { id, pos, end, kind }
    }

    fn expression(&mut self, min: u8) -> PResult<Expr> {
        self.enter()?;
        let r = self.expression_inner(min);
        self.depth -= 1;
        r
    }

    fn expression_inner(&mut self, min: u8) -> PResult<Expr> {
        let t = self.peek();
        if t.kind == Tok::Not && min > 3 {
            return self.fail(t, "not requires grouping at this operator position; wrap it in parentheses, e.g. a == (not b)");
        }
        let mut e;
        if self.take(Tok::Not) {
            let operand = self.expression(3)?;
            e = self.mk(
                t.pos,
                ExprKind::Unary {
                    op: UnaryOp::Not,
                    operand: Box::new(operand),
                },
            );
        } else if matches!(t.kind, Tok::Plus | Tok::Minus | Tok::Try) {
            self.at += 1;
            let op = match t.kind {
                Tok::Plus => UnaryOp::Plus,
                Tok::Minus => UnaryOp::Neg,
                _ => UnaryOp::Try,
            };
            let operand = self.expression(8)?;
            e = self.mk(
                t.pos,
                ExprKind::Unary {
                    op,
                    operand: Box::new(operand),
                },
            );
        } else {
            e = self.primary()?;
        }
        let mut compared = false;
        let mut links = 0usize;
        loop {
            let op = self.peek();
            if self.compound_assignment() {
                break;
            }
            if op.kind == Tok::Amp {
                return self.and_and(op);
            }
            if op.kind == Tok::Pipe {
                if min > 0 {
                    break;
                }
                self.link(&mut links)?;
                e = self.pipe(e)?;
                if self.kind() == Tok::Dot {
                    e = self.postfix(e)?;
                }
                if binary_op(self.kind()).is_some() {
                    let t = self.peek();
                    return self.fail(t, "a pipe has the lowest precedence; parenthesize it to use its result in an operator, e.g. (x | f) == y");
                }
                continue;
            }
            if op.kind == Tok::DotDot {
                if min > RANGE_LEVEL {
                    break;
                }
                self.at += 1;
                let right = self.expression(RANGE_LEVEL + 1)?;
                if self.kind() == Tok::DotDot {
                    let t = self.peek();
                    return self.fail(t, "a range cannot chain; write one 'start..end', or use range_by for a step from \"@std/collections.ms\"");
                }
                e = self.range(e, right);
                continue;
            }
            let Some(bop) = binary_op(op.kind) else { break };
            let level = bop.precedence();
            if level < min {
                break;
            }
            if (op.kind == Tok::Plus || op.kind == Tok::Minus)
                && matches!(e.kind, ExprKind::Name(_))
                && self.ahead(1).kind == op.kind
                && self.ahead(2).kind == Tok::Newline
            {
                let n = match &e.kind {
                    ExprKind::Name(n) => *n,
                    _ => unreachable!(),
                };
                let o = op.kind.as_str();
                return self.fail(
                    op,
                    format!("Manuscript has no '{o}{o}' operator; write '{n} = {n} {o} 1'"),
                );
            }
            if level == 4 && compared {
                return self.fail(op, "comparison operators cannot chain; combine two comparisons with 'and', e.g. a < b and b < c");
            }
            self.at += 1;
            self.link(&mut links)?;
            let right = self.expression(level + 1)?;
            e = self.mk(
                op.pos,
                ExprKind::Binary {
                    op: bop,
                    left: Box::new(e),
                    right: Box::new(right),
                },
            );
            if level == 4 {
                compared = true;
            }
        }
        if min == 0 && self.kind() == Tok::If {
            e = self.conditional(e)?;
        }
        Ok(e)
    }

    /// `start..end` as the call `range(start, end)`; `..` names the standard `range`.
    fn range(&mut self, start: Expr, end: Expr) -> Expr {
        let pos = start.pos;
        let callee = self.mk(pos, ExprKind::Name(Symbol::from("..")));
        let args = [start, end]
            .into_iter()
            .map(|value| Argument {
                pos: value.pos,
                name: None,
                value,
                mutable: false,
            })
            .collect();
        self.mk(
            pos,
            ExprKind::Call {
                callee: Box::new(callee),
                args,
            },
        )
    }

    /// `a if c else b` as a match over the Bool `c`; the else branch may nest.
    fn conditional(&mut self, then: Expr) -> PResult<Expr> {
        let t = self.peek();
        self.at += 1;
        let cond = self.expression(1)?;
        let else_token = self.peek();
        if else_token.kind != Tok::Else {
            return self.fail(else_token, "a conditional expression needs an else branch; write 'a if condition else b', or use an if statement when no value is needed");
        }
        self.at += 1;
        let els = self.expression(0)?;
        let mut arms = Vec::new();
        for (value, branch, pos) in [(true, then, t.pos), (false, els, else_token.pos)] {
            let path = self.mk(pos, ExprKind::Bool(value));
            let id = self.id();
            arms.push(Arm {
                id,
                pos,
                path,
                bindings: Vec::new(),
                body: Vec::new(),
                value: Some(branch),
                from_if: true,
            });
        }
        Ok(self.mk(
            t.pos,
            ExprKind::Match {
                scrutinee: Box::new(cond),
                arms,
            },
        ))
    }

    /// `&&` (two `&` tokens) where `and` was meant.
    fn and_and<T>(&self, first: Token) -> PResult<T> {
        let last = if self.ahead(1).kind == Tok::Amp && self.ahead(1).pos.offset == first.end.offset
        {
            self.ahead(1)
        } else {
            first
        };
        self.fail_fix_range(
            first,
            last,
            "'&&' is not an operator; write 'and' for logical and",
            "and",
        )
    }

    /// Parses one `| step` after `lhs` and desugars it to the ordinary
    /// expression the step names (see the module docs of [`crate::ast`]).
    fn pipe(&mut self, lhs: Expr) -> PResult<Expr> {
        self.at += 1;
        if self.kind() == Tok::Pipe {
            let t = self.peek();
            let first = self.previous();
            return self.fail_fix_range(first, t, "'||' is not an operator; write 'or' for logical or, and '|' only to start a pipe step", "or");
        }
        let try_tok = self.peek();
        let tried = self.take(Tok::Try);
        let mut step;
        if self.kind() == Tok::Dot && !(tried && self.peek().pos.line != try_tok.pos.line) {
            step = self.postfix(lhs)?;
        } else if tried && self.kind() != Tok::Name {
            return Ok(self.mk(
                try_tok.pos,
                ExprKind::Unary {
                    op: UnaryOp::Try,
                    operand: Box::new(lhs),
                },
            ));
        } else {
            let name = self.peek();
            if name.kind != Tok::Name {
                let mut hint = "";
                if name.kind == Tok::Newline {
                    hint = "; to continue a flow on the next line, end this line before '|' and start the next line with '|'";
                }
                let msg = format!(
                    "a pipe step is a function name, a call without its first argument, or a '.method' step; write x | f, x | f(a: 1), or x | .method(a: 1), found {}{}",
                    describe(self.src, name),
                    hint
                );
                return self.fail(name, msg);
            }
            self.at += 1;
            let mut callee = self.mk(name.pos, ExprKind::Name(self.sym(name)));
            let mut links = 0;
            // A '.' on a later line continues the flow and applies to the step's
            // result, so it never extends the step's name path.
            while self.kind() == Tok::Dot
                && self.peek().pos.line == self.tokens[self.at - 1].pos.line
            {
                self.link(&mut links)?;
                self.at += 1;
                let member = self.need(Tok::Name)?;
                callee = self.mk(
                    member.pos,
                    ExprKind::Member {
                        left: Box::new(callee),
                        name: self.sym(member),
                    },
                );
            }
            if self.kind() == Tok::LBracket {
                let t = self.peek();
                return self.fail(t, format!("a pipe step cannot take type arguments; bind the instance to a name first, e.g. let step = {}[Int], then write x | step", self.text(name)));
            }
            let mut args = vec![Argument {
                pos: lhs.pos,
                name: None,
                value: lhs,
                mutable: false,
            }];
            if self.take(Tok::LParen) {
                args.extend(self.call_arguments()?);
            }
            step = self.mk(
                name.pos,
                ExprKind::Call {
                    callee: Box::new(callee),
                    args,
                },
            );
        }
        if tried {
            step = self.mk(
                try_tok.pos,
                ExprKind::Unary {
                    op: UnaryOp::Try,
                    operand: Box::new(step),
                },
            );
        }
        Ok(step)
    }

    fn case_path(&mut self) -> PResult<Expr> {
        let t = self.need(Tok::Name)?;
        let mut e = self.mk(t.pos, ExprKind::Name(self.sym(t)));
        if self.take(Tok::LBracket) {
            let types = self.type_args()?;
            e = self.mk(
                t.pos,
                ExprKind::Apply {
                    left: Box::new(e),
                    types,
                    value: None,
                },
            );
        }
        let mut links = 0;
        while self.take(Tok::Dot) {
            self.link(&mut links)?;
            let name = self.need(Tok::Name)?;
            e = self.mk(
                name.pos,
                ExprKind::Member {
                    left: Box::new(e),
                    name: self.sym(name),
                },
            );
        }
        Ok(e)
    }

    fn primary(&mut self) -> PResult<Expr> {
        let t = self.peek();
        self.at += 1;
        let e = match t.kind {
            Tok::Name | Tok::SelfKw | Tok::Fixture => self.mk(t.pos, ExprKind::Name(self.sym(t))),
            Tok::Number => self.mk(t.pos, ExprKind::Number(self.sym(t))),
            Tok::True => self.mk(t.pos, ExprKind::Bool(true)),
            Tok::False => self.mk(t.pos, ExprKind::Bool(false)),
            Tok::String => {
                let parts = self.text_parts_of(t)?;
                self.mk(t.pos, ExprKind::Text(parts))
            }
            Tok::LParen if self.kind() == Tok::RParen => {
                self.at += 1;
                self.mk(t.pos, ExprKind::Unit)
            }
            Tok::LParen => {
                let e = self.expression(0)?;
                if self.kind() == Tok::Comma {
                    let c = self.peek();
                    return self.fail(c, "Manuscript has no tuples; declare a record with 'type Pair:' and named fields, or use a List when the items share one type");
                }
                self.need(Tok::RParen)?;
                e
            }
            Tok::LBracket => {
                let mut items = Vec::new();
                if !self.take(Tok::RBracket) {
                    loop {
                        items.push(self.expression(0)?);
                        if !self.take(Tok::Comma) {
                            break;
                        }
                        if self.kind() == Tok::RBracket {
                            break;
                        }
                    }
                    self.need(Tok::RBracket)?;
                }
                self.mk(t.pos, ExprKind::List(items))
            }
            Tok::Match => {
                self.no_binding_ref()?;
                let scrutinee = self.expression(0)?;
                let arms = self.match_arms(t)?;
                self.mk(
                    t.pos,
                    ExprKind::Match {
                        scrutinee: Box::new(scrutinee),
                        arms,
                    },
                )
            }
            Tok::LBrace => {
                let mut entries = Vec::new();
                if !self.take(Tok::RBrace) {
                    loop {
                        let key = self.expression(0)?;
                        self.need(Tok::Colon)?;
                        let value = self.expression(0)?;
                        entries.push(MapEntry { key, value });
                        if !self.take(Tok::Comma) || self.kind() == Tok::RBrace {
                            break;
                        }
                    }
                    self.need(Tok::RBrace)?;
                }
                self.mk(t.pos, ExprKind::Map(entries))
            }
            Tok::Lambda => {
                let mut result = None;
                let params = if self.kind() == Tok::LParen {
                    let params = self.parameters(true, true)?;
                    if self.take(Tok::Arrow) {
                        result = Some(Box::new(self.typ()?));
                    }
                    params
                } else {
                    let mut params = Vec::new();
                    while self.kind() == Tok::Name {
                        let name = self.next();
                        let id = self.id();
                        params.push(Param {
                            id,
                            pos: name.pos,
                            name: self.sym(name),
                            ty: None,
                            default: None,
                            mutable: false,
                        });
                        if !self.take(Tok::Comma) {
                            break;
                        }
                    }
                    params
                };
                let body = self.statement_suite(true, false)?;
                self.mk(
                    t.pos,
                    ExprKind::Lambda(Lambda {
                        params,
                        result,
                        body,
                    }),
                )
            }
            _ => {
                let before = if self.at > 1 {
                    self.tokens[self.at - 2].kind
                } else {
                    Tok::Eof
                };
                let hint = match (t.kind, before) {
                    (Tok::Else, _) => {
                        "'else' continues an 'if' block: put it on its own line at the same indentation as that 'if', directly after the if body"
                    }
                    (Tok::Colon, Tok::Try) => {
                        "'try' is a prefix on a call, not a block: write 'try f(x)' to unwrap a Result or return its error, and 'if let' to handle failure locally"
                    }
                    (Tok::Star, Tok::Slash) => {
                        "'/*' does not start a comment; comments start with '#'"
                    }
                    (Tok::Slash, Tok::Slash) => {
                        "'//' does not start a comment; comments start with '#'"
                    }
                    (Tok::Gt, Tok::Lt) => "'<>' is not an operator; write '!=' for inequality",
                    (Tok::Star, Tok::Star) => {
                        "there is no '**' power operator; multiply explicitly or call a function from @std/math.ms"
                    }
                    (Tok::Comma | Tok::RParen, Tok::Colon) => {
                        "a label before ':' needs a value, e.g. count: 1"
                    }
                    (Tok::Comma, _) => "remove the extra comma or add the missing value before it",
                    _ => "write a value, name, call, or literal here",
                };
                let msg = format!(
                    "expected an expression, found {}; {hint}",
                    describe(self.src, t)
                );
                return self.fail(t, msg);
            }
        };
        self.postfix(e)
    }

    /// Applies member access, indexing and calls to `e`.
    fn postfix(&mut self, mut e: Expr) -> PResult<Expr> {
        let mut links = 0usize;
        loop {
            if self.take(Tok::Dot) {
                self.link(&mut links)?;
                if self.kind() == Tok::Number {
                    let t = self.peek();
                    return self.fail(t, "a number has at most one decimal point and member access needs a name; write the number once, e.g. 1.2");
                }
                let name = self.need(Tok::Name)?;
                e = self.mk(
                    name.pos,
                    ExprKind::Member {
                        left: Box::new(e),
                        name: self.sym(name),
                    },
                );
            } else if self.take(Tok::LBracket) {
                self.link(&mut links)?;
                e = self.bracket(e)?;
            } else if self.take(Tok::LParen) {
                self.link(&mut links)?;
                let pos = e.pos;
                let args = self.call_arguments()?;
                e = self.mk(
                    pos,
                    ExprKind::Call {
                        callee: Box::new(e),
                        args,
                    },
                );
            } else {
                break;
            }
        }
        Ok(e)
    }

    /// Parses the arguments after an opening parenthesis, through `)`.
    fn call_arguments(&mut self) -> PResult<Vec<Argument>> {
        let mut args = Vec::new();
        if !self.take(Tok::RParen) {
            loop {
                let pos = self.peek().pos;
                let mut name = None;
                if self.kind() == Tok::Name && self.ahead(1).kind == Tok::Colon {
                    name = Some(self.sym(self.peek()));
                    self.at += 2;
                }
                if self.kind() == Tok::Name && self.ahead(1).kind == Tok::Assign {
                    let eq = self.ahead(1);
                    let n = self.text(self.peek());
                    return self.fail(eq, format!("argument labels use a colon; write {n}: value"));
                }
                let mutable = self.take(Tok::Var);
                let value = self.expression(0)?;
                if let ExprKind::Name(n) = &value.kind
                    && self.kind() == Tok::Arrow
                {
                    let a = self.peek();
                    return self.fail(a, format!("arrow lambdas are not supported; write 'lambda {n}: {n} + 1', or 'lambda ({n}: Int) -> Int: {n} + 1' with explicit types"));
                }
                args.push(Argument {
                    pos,
                    name,
                    value,
                    mutable,
                });
                if !self.take(Tok::Comma) {
                    break;
                }
                if self.kind() == Tok::RParen {
                    break;
                }
            }
            self.need(Tok::RParen)?;
        }
        Ok(args)
    }

    // ---- text ----

    /// Decodes a text token into literal and interpolated parts.
    fn text_parts_of(&mut self, token: Token) -> PResult<Vec<TextPart>> {
        let full = self.text(token);
        let fstring = full.starts_with('f');
        let prefix = usize::from(fstring);
        let raw = &full[1 + prefix..full.len() - 1];
        if !raw.bytes().any(|b| b == b'\\' || (fstring && b == b'{')) {
            return Ok(vec![TextPart::Lit(raw.into())]);
        }
        self.text_parts(token, raw, fstring)
    }

    fn text_parts(&mut self, token: Token, raw: &str, fstring: bool) -> PResult<Vec<TextPart>> {
        let prefix = usize::from(fstring);
        let rb = raw.as_bytes();
        let mut parts: Vec<TextPart> = Vec::new();
        let mut literal: Vec<u8> = Vec::new();
        let flush = |literal: &mut Vec<u8>, parts: &mut Vec<TextPart>| {
            if !literal.is_empty() {
                let s = String::from_utf8(std::mem::take(literal)).expect("text is valid UTF-8");
                parts.push(TextPart::Lit(s.into_boxed_str()));
            }
        };
        let mut i = 0;
        while i < rb.len() {
            let mut c = rb[i];
            i += 1;
            if c == b'\\' {
                c = rb[i];
                i += 1;
                match c {
                    b'n' => literal.push(b'\n'),
                    b'r' => literal.push(b'\r'),
                    b't' => literal.push(b'\t'),
                    b'u' => {
                        let start = i + 1;
                        i = start;
                        while rb[i] != b'}' {
                            i += 1;
                        }
                        let n = u32::from_str_radix(&raw[start..i], 16).unwrap_or(0xfffd);
                        let ch = char::from_u32(n).unwrap_or('\u{fffd}');
                        let mut buf = [0u8; 4];
                        literal.extend_from_slice(ch.encode_utf8(&mut buf).as_bytes());
                        i += 1;
                    }
                    other => literal.push(other),
                }
                continue;
            }
            if c != b'{' || !fstring {
                literal.push(c);
                continue;
            }
            flush(&mut literal, &mut parts);
            let start = i;
            let brace = self.source_origin + token.lo as usize + prefix + start;
            i = self
                .boundaries
                .interpolation_end(brace)
                .expect("validated interpolation")
                - (self.source_origin + token.lo as usize + 1 + prefix);
            let source = &raw[start..i - 1];
            let value = self.interpolation(token, start + prefix, source)?;
            parts.push(TextPart::Interp(value));
        }
        flush(&mut literal, &mut parts);
        if parts.is_empty() {
            parts.push(TextPart::Lit("".into()));
        }
        Ok(parts)
    }

    /// Lexes and parses the expression inside one `{...}` of a text literal.
    /// Failures also state the escape for a literal brace.
    fn interpolation(&mut self, token: Token, start: usize, source: &str) -> PResult<Expr> {
        let suffix = format!(
            " ('{{' at column {} starts an interpolation; write \\{{ and \\}} for literal braces)",
            token.pos.column as usize + start
        );
        let origin = self.source_origin + token.lo as usize + start + 1;
        let shift = |p: Pos| -> Pos {
            let offset = (p.offset as usize + 1).min(source.len() + 1);
            Pos {
                line: token.pos.line,
                column: (token.pos.column as usize + start + offset) as u32,
                offset: (token.pos.offset as usize + start + offset) as u32,
            }
        };
        let mut tokens =
            match crate::lexer::lex_interpolation(self.file, source, origin, self.boundaries) {
                Ok(tokens) => tokens,
                Err(_) => return self.interpolation_wrapped(token, start, source),
            };
        for t in &mut tokens {
            t.pos = shift(t.pos);
            t.end = shift(t.end);
        }
        let mut nested = Parser::new(
            self.file,
            source,
            tokens,
            self.boundaries,
            origin,
            self.depth,
            self.next_id,
        );
        let result: PResult<Expr> = (|| {
            let value = nested.expression(0)?;
            nested.newlines();
            nested.need(Tok::Eof)?;
            Ok(value)
        })();
        self.next_id = nested.next_id;
        match result {
            Ok(v) => Ok(v),
            Err(mut d) => {
                d.message.push_str(&suffix);
                Err(d)
            }
        }
    }

    // ---- match ----

    fn match_arms(&mut self, header: Token) -> PResult<Vec<Arm>> {
        let mut arms: Vec<Arm> = Vec::new();
        self.need(Tok::Colon)?;
        self.need(Tok::Newline)?;
        self.need(Tok::Indent)?;
        loop {
            self.newlines();
            if self.kind() == Tok::Dedent {
                if arms.is_empty() {
                    return self.fail(header, "match requires at least one arm; add a case pattern or '_' arm under the header");
                }
                break;
            }
            if self.kind() != Tok::Case {
                let t = self.peek();
                return self.fail_fix(
                    t,
                    "match arms start with 'case', e.g. case Paid(receipt):",
                    &format!("case {}", self.text(t)),
                );
            }
            self.at += 1;
            let start = self.peek();
            let k = start.kind;
            let literal = matches!(k, Tok::Number | Tok::True | Tok::False | Tok::String)
                || (k == Tok::Minus && self.ahead(1).kind == Tok::Number);
            let mut bindings = Vec::new();
            let path;
            if literal {
                path = self.expression(0)?;
            } else if self.take(Tok::Underscore) {
                path = self.mk(start.pos, ExprKind::Name(Symbol::intern("_")));
            } else {
                path = self.case_path()?;
                if self.take(Tok::LParen) {
                    loop {
                        let tok = self.peek();
                        if !self.take(Tok::Underscore) {
                            self.need(Tok::Name)?;
                        }
                        bindings.push(ArmBinding {
                            name: self.sym(tok),
                            pos: tok.pos,
                        });
                        if self.kind() == Tok::LParen {
                            let t = self.peek();
                            return self.fail(t, "patterns cannot be nested; bind the outer payload, then handle it in a separate match or helper function");
                        }
                        if !self.take(Tok::Comma) {
                            break;
                        }
                        if self.kind() == Tok::RParen {
                            break;
                        }
                    }
                    self.need(Tok::RParen)?;
                }
            }
            let id = self.id();
            let mut arm = Arm {
                id,
                pos: start.pos,
                path,
                bindings,
                body: Vec::new(),
                value: None,
                from_if: false,
            };
            self.value_arm(&mut arm)?;
            arms.push(arm);
        }
        self.need(Tok::Dedent)?;
        Ok(arms)
    }

    /// An arm's final expression supplies its value; a statement-only arm yields Unit.
    fn value_arm(&mut self, a: &mut Arm) -> PResult<()> {
        let (outer, outer_return) = (self.inline_statement, self.inline_return);
        let r = self.value_arm_inner(a);
        self.inline_statement = outer;
        self.inline_return = outer_return;
        r
    }

    fn value_arm_inner(&mut self, a: &mut Arm) -> PResult<()> {
        self.inline_return = false;
        self.need(Tok::Colon)?;
        let indented = self.take(Tok::Newline);
        if indented {
            self.need(Tok::Indent)?;
        }
        self.inline_statement = !indented;
        loop {
            self.statements(true, &mut a.body)?;
            if !indented {
                break;
            }
            self.newlines();
            if self.kind() == Tok::Dedent || self.kind() == Tok::Eof {
                break;
            }
        }
        if matches!(a.body.last().map(|s| &s.kind), Some(StmtKind::Call(_)))
            && let Some(Stmt {
                kind: StmtKind::Call(e),
                ..
            }) = a.body.pop()
        {
            a.value = Some(e);
        }
        for s in &a.body {
            if let StmtKind::Call(e) = &s.kind {
                let is_try = matches!(
                    e.kind,
                    ExprKind::Unary {
                        op: UnaryOp::Try,
                        ..
                    }
                );
                if !matches!(e.kind, ExprKind::Call { .. } | ExprKind::Match { .. }) && !is_try {
                    return Err(Box::new(Diagnostic::parse(
                        self.file,
                        s.pos,
                        "an arm value must be its final expression",
                    )));
                }
            }
        }
        if indented {
            self.need(Tok::Dedent)?;
        } else {
            self.inline_statement = false;
            self.end()?;
        }
        Ok(())
    }

    // ---- brackets ----

    /// Brackets may contain types or a value. A single name/application keeps
    /// both interpretations until name resolution identifies the receiver.
    fn bracket(&mut self, left: Expr) -> PResult<Expr> {
        let start = self.at;
        let saved_depth = self.depth;
        let mut types = None;
        // A type starts with a name, `fn` or `(`; anything else is a value.
        if matches!(self.kind(), Tok::Name | Tok::LParen) {
            self.speculative += 1;
            let r = self.type_args();
            self.speculative -= 1;
            match r {
                Ok(t) => types = Some(t),
                Err(_) => {
                    self.at = start;
                    // Unwinding restores nesting except for a failed `enter`,
                    // as deferred leave functions would.
                    let _ = saved_depth;
                }
            }
        }
        if let Some(types) = types {
            let pos = left.pos;
            let value = if types.len() == 1 {
                self.type_value(&types[0]).map(Box::new)
            } else {
                None
            };
            let types = if value.is_some() {
                self.copy_types(&types)
            } else {
                types
            };
            return Ok(self.mk(
                pos,
                ExprKind::Apply {
                    left: Box::new(left),
                    types,
                    value,
                },
            ));
        }
        let index = self.expression(0)?;
        if self.kind() == Tok::Colon {
            let t = self.peek();
            return self.fail(
                t,
                "there is no slice syntax; call slice(start: 0, end: 2) on a List or String",
            );
        }
        self.need(Tok::RBracket)?;
        let pos = left.pos;
        Ok(self.mk(
            pos,
            ExprKind::Index {
                left: Box::new(left),
                index: Box::new(index),
            },
        ))
    }

    /// Reinterprets a type as the value expression that spells it.
    fn type_value(&mut self, t: &TypeRef) -> Option<Expr> {
        let TypeKind::Named { name, args } = &t.kind else {
            return None;
        };
        let mut names = name.as_str().split('.');
        let first = names.next().unwrap_or("");
        let mut e = self.mk(t.pos, ExprKind::Name(Symbol::intern(first)));
        let token = self.tokens.partition_point(|k| k.pos.offset < t.pos.offset);
        for (index, part) in names.enumerate() {
            let pos = self.tokens[token + 2 * (index + 1)].pos;
            e = self.mk(
                pos,
                ExprKind::Member {
                    left: Box::new(e),
                    name: Symbol::intern(part),
                },
            );
        }
        if !args.is_empty() {
            let types = self.copy_types(args);
            let value = if args.len() == 1 {
                self.type_value(&args[0]).map(Box::new)
            } else {
                None
            };
            e = self.mk(
                t.pos,
                ExprKind::Apply {
                    left: Box::new(e),
                    types,
                    value,
                },
            );
        }
        Some(e)
    }

    /// The two bracket interpretations own their nodes independently.
    fn copy_types(&mut self, types: &[TypeRef]) -> Vec<TypeRef> {
        types.iter().map(|t| self.copy_type(t)).collect()
    }

    fn copy_type(&mut self, t: &TypeRef) -> TypeRef {
        let id = self.id();
        let kind = match &t.kind {
            TypeKind::Named { name, args } => TypeKind::Named {
                name: *name,
                args: self.copy_types(args),
            },
            TypeKind::Fn { params, result } => TypeKind::Fn {
                params: params
                    .iter()
                    .map(|p| {
                        let id = self.id();
                        Param {
                            id,
                            pos: p.pos,
                            name: p.name,
                            ty: p.ty.as_ref().map(|t| self.copy_type(t)),
                            default: p.default.clone(),
                            mutable: p.mutable,
                        }
                    })
                    .collect(),
                result: Box::new(self.copy_type(result)),
            },
        };
        TypeRef {
            id,
            pos: t.pos,
            kind,
        }
    }

    /// Preserve the historical wrapper path for expressions whose lexical
    /// error depends on its physical closing parenthesis.
    fn interpolation_wrapped(&mut self, token: Token, start: usize, source: &str) -> PResult<Expr> {
        let suffix = format!(
            " ('{{' at column {} starts an interpolation; write \\{{ and \\}} for literal braces)",
            token.pos.column as usize + start
        );
        let wrapped = format!("({source})");
        let shift = |p: Pos| -> Pos {
            let offset = (p.offset as usize).min(source.len() + 1);
            Pos {
                line: token.pos.line,
                column: (token.pos.column as usize + start + offset) as u32,
                offset: (token.pos.offset as usize + start + offset) as u32,
            }
        };
        let mut lexed = match lex(self.file, &wrapped) {
            Ok(l) => l,
            Err(mut d) => {
                d.pos = shift(d.pos);
                d.end = d.end.map(shift);
                if let Some(fix) = &mut d.fix {
                    fix.pos = shift(fix.pos);
                    fix.end = shift(fix.end);
                }
                d.message.push_str(&suffix);
                return Err(d);
            }
        };
        let closing = lexed.tokens.len() - 3;
        lexed.tokens.remove(closing);
        lexed.tokens.remove(0);
        for t in &mut lexed.tokens {
            t.pos = shift(t.pos);
            t.end = shift(t.end);
        }
        let origin = self.source_origin + token.lo as usize + start;
        let mut nested = Parser::new(
            self.file,
            &lexed.source,
            lexed.tokens,
            self.boundaries,
            origin,
            self.depth,
            self.next_id,
        );
        let result: PResult<Expr> = (|| {
            let value = nested.expression(0)?;
            nested.newlines();
            nested.need(Tok::Eof)?;
            Ok(value)
        })();
        self.next_id = nested.next_id;
        match result {
            Ok(v) => Ok(v),
            Err(mut d) => {
                d.message.push_str(&suffix);
                Err(d)
            }
        }
    }
}

/// Reports whether `e` is a name or member access over names.
fn plain_chain(e: &Expr) -> bool {
    let mut e = e;
    loop {
        match &e.kind {
            ExprKind::Member { left, .. } => e = left,
            ExprKind::Index { left, index } if plain_index(index) => e = left,
            ExprKind::Apply {
                left,
                types,
                value: Some(index),
            } if types.len() == 1 && plain_index(index) => e = left,
            _ => return matches!(e.kind, ExprKind::Name(_)),
        }
    }
}

/// The member name of an index assignment; no source name can spell it.
pub const INDEX_SET: &str = "[]=";

/// The receiver and index of `left[index]`, however the bracket was parsed.
fn index_parts(e: &Expr) -> Option<(&Expr, &Expr)> {
    match &e.kind {
        ExprKind::Index { left, index } => Some((left, index)),
        ExprKind::Apply {
            left,
            types,
            value: Some(index),
        } if types.len() == 1 => Some((left, index)),
        _ => None,
    }
}

/// An index that can be evaluated twice without effect: a name, a number or a text literal.
fn plain_index(e: &Expr) -> bool {
    match &e.kind {
        ExprKind::Name(_) | ExprKind::Number(_) => true,
        ExprKind::Text(parts) => parts.iter().all(|p| !matches!(p, TextPart::Interp(_))),
        _ => false,
    }
}

/// Spells a type's parameters as the arguments of its impl receiver.
fn type_param_names(params: &[TypeParam]) -> String {
    if params.is_empty() {
        return String::new();
    }
    let names: Vec<&str> = params.iter().map(|p| p.name.as_str()).collect();
    format!("[{}]", names.join(", "))
}
