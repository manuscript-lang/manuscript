use std::sync::Arc;

/// Applies each reported fix and reparses until the source is accepted.
fn repair(source: &str) -> String {
    let file = Arc::from("braced.ms");
    let mut text = source.to_string();
    for _ in 0..8 {
        let Err(error) = ms_syntax::parser::parse(&file, &text) else {
            return text;
        };
        let fix = error.fix.expect("every error in a braced block has a fix");
        text.replace_range(
            fix.pos.offset as usize..fix.end.offset as usize,
            &fix.replacement,
        );
    }
    panic!("fixes did not converge: {text}");
}

#[test]
fn braced_blocks_repair_to_colon_blocks() {
    for (source, expected) in [
        (
            "fn main() Void {\n    print(1)\n}\n",
            "fn main() Void:\n    print(1)\n\n",
        ),
        (
            "fn main() Void:\n    for i in 0..3 {\n        print(i)\n    }\n",
            "fn main() Void:\n    for i in 0..3:\n        print(i)\n    \n",
        ),
    ] {
        for (source, expected) in [
            (source.to_string(), expected.to_string()),
            (source.replace('\n', "\r\n"), expected.replace('\n', "\r\n")),
        ] {
            assert_eq!(repair(&source), expected, "{source}");
        }
    }
}
