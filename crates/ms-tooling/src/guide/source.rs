//! Source text with a lazily lexed token list, for recovering written default
//! expressions and leading comments.

use ms_syntax::token::Tok;
use std::cell::OnceCell;
use std::sync::Arc;

/// One module's source.
pub struct Source {
    text: Arc<str>,
    tokens: OnceCell<Option<Vec<(Tok, usize)>>>,
    inherent_impls: OnceCell<Vec<u32>>,
}

impl Source {
    /// Wraps source text.
    pub fn new(text: Arc<str>) -> Source {
        Source {
            text,
            tokens: OnceCell::new(),
            inherent_impls: OnceCell::new(),
        }
    }

    /// The text.
    pub fn text(&self) -> &str {
        &self.text
    }

    /// Original inherent impl positions, before the checker synthesizes contracts.
    pub fn is_inherent_impl(&self, offset: u32) -> bool {
        self.inherent_impls.get_or_init(|| {
            let file = Arc::from("documentation.ms");
            ms_syntax::parser::parse(&file, &self.text)
                .map(|module| module.decls.iter().filter_map(|decl| {
                    matches!(&decl.kind, ms_syntax::DeclKind::Impl(implementation) if implementation.contract.is_none())
                        .then_some(decl.pos.offset)
                }).collect())
                .unwrap_or_default()
        }).contains(&offset)
    }

    /// Token kinds with original start offsets; `None` when the source does not lex.
    pub fn tokens(&self) -> Option<&[(Tok, usize)]> {
        self.tokens
            .get_or_init(|| {
                let file: Arc<str> = Arc::from("documentation.ms");
                let lexed = ms_syntax::lexer::lex(&file, &self.text).ok()?;
                Some(
                    lexed
                        .tokens
                        .iter()
                        .map(|t| (t.kind, t.pos.offset as usize))
                        .collect(),
                )
            })
            .as_deref()
    }
}

/// The `//` lines and `/* */` blocks that end on the line directly above the declaration
/// containing `offset`, else a trailing `//` on the declaration's line. A blank line detaches the
/// block. Markers are removed; text is otherwise preserved.
pub fn leading_comment(source: &str, offset: usize) -> String {
    if offset > source.len() || !source.is_char_boundary(offset) {
        return String::new();
    }
    let before = &source[..offset];
    let line_start = before.rfind('\n').map_or(0, |n| n + 1);
    let own_line = &before[line_start..];
    // Names of cases and operations follow their keyword; inline payload fields
    // do not begin a declaration line and must not inherit a case description.
    if !matches!(own_line.trim(), "" | "export" | "fn" | "var fn" | "case") {
        return String::new();
    }
    let indent = own_line.len() - own_line.trim_start_matches([' ', '\t']).len();
    let above = ms_syntax::doc::comments_above(source, line_start, Some(indent));
    if !above.is_empty() {
        return above;
    }
    ms_syntax::doc::trailing_comment(source, offset)
}
