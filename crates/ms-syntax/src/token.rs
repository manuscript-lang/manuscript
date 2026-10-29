//! Token kinds produced by the lexer.

use crate::pos::Pos;

macro_rules! tokens {
    ($($variant:ident => $text:expr),* $(,)?) => {
        /// Token kind. Layout tokens (`Newline`, `Indent`, `Dedent`, `Eof`)
        /// have empty text; keywords and punctuation are their own spelling.
        #[derive(Copy, Clone, Debug, PartialEq, Eq, Hash)]
        pub enum Tok { $($variant),* }
        impl Tok {
            /// The kind's name string.
            pub fn as_str(self) -> &'static str {
                match self { $(Tok::$variant => $text),* }
            }
        }
    };
}

tokens! {
    Comment => "#comment",
    Newline => "NEWLINE", Indent => "INDENT", Dedent => "DEDENT", Eof => "EOF",
    Name => "NAME", Number => "NUMBER", String => "STRING",
    And => "and", Break => "break", Case => "case", Continue => "continue", Else => "else",
    Export => "export", Extern => "extern", False => "false", Fixture => "fixture", Fn => "fn",
    For => "for", If => "if", Impl => "impl", Import => "import", In => "in",
    Interface => "interface", Let => "let", Match => "match", Not => "not",
    Or => "or", Ref => "ref", Return => "return", SelfKw => "self", Test => "test", True => "true", Try => "try",
    Type => "type", Unit => "unit", Var => "var", While => "while", Underscore => "_",
    LParen => "(", RParen => ")", LBracket => "[", RBracket => "]", LBrace => "{", RBrace => "}",
    Colon => ":", Comma => ",", Dot => ".", Plus => "+", Minus => "-", Star => "*", Slash => "/",
    Percent => "%", Lt => "<", Gt => ">", Assign => "=", Amp => "&", Pipe => "|", Ellipsis => "...", DotDot => "..",
    Arrow => "->", EqEq => "==", NotEq => "!=", Le => "<=", Ge => ">=",
}

impl Tok {
    /// Maps an identifier-shaped word to its keyword kind, or `Name`.
    pub fn from_word(word: &str) -> Tok {
        match word {
            "and" => Tok::And,
            "break" => Tok::Break,
            "case" => Tok::Case,
            "continue" => Tok::Continue,
            "else" => Tok::Else,
            "export" => Tok::Export,
            "extern" => Tok::Extern,
            "false" => Tok::False,
            "fixture" => Tok::Fixture,
            "fn" => Tok::Fn,
            "for" => Tok::For,
            "if" => Tok::If,
            "impl" => Tok::Impl,
            "import" => Tok::Import,
            "in" => Tok::In,
            "interface" => Tok::Interface,
            "let" => Tok::Let,
            "match" => Tok::Match,
            "not" => Tok::Not,
            "or" => Tok::Or,
            "ref" => Tok::Ref,
            "return" => Tok::Return,
            "self" => Tok::SelfKw,
            "test" => Tok::Test,
            "true" => Tok::True,
            "try" => Tok::Try,
            "type" => Tok::Type,
            "unit" => Tok::Unit,
            "var" => Tok::Var,
            "while" => Tok::While,
            "_" => Tok::Underscore,
            _ => Tok::Name,
        }
    }

    /// True for the layout tokens that have no source text.
    pub fn is_layout(self) -> bool {
        matches!(self, Tok::Newline | Tok::Indent | Tok::Dedent | Tok::Eof)
    }
}

/// The reserved words, sorted. `_` is lexed as its own
/// kind but is not in this list.
pub const KEYWORDS: &[&str] = &[
    "and",
    "break",
    "case",
    "continue",
    "else",
    "export",
    "extern",
    "false",
    "fixture",
    "fn",
    "for",
    "if",
    "impl",
    "import",
    "in",
    "interface",
    "let",
    "match",
    "not",
    "or",
    "ref",
    "return",
    "self",
    "test",
    "true",
    "try",
    "type",
    "unit",
    "var",
    "while",
];

/// One token. The text is `source[lo..hi]` of the (CRLF-normalised) source the
/// lexer returned; layout tokens have an empty range.
#[derive(Copy, Clone, Debug)]
pub struct Token {
    /// Kind.
    pub kind: Tok,
    /// Start in original-source coordinates.
    pub pos: Pos,
    /// Exclusive end in original-source coordinates.
    pub end: Pos,
    /// Start of the text in the normalised source.
    pub lo: u32,
    /// End of the text in the normalised source.
    pub hi: u32,
}
