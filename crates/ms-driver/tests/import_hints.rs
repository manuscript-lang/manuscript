//! Import suggestions use the checked graph's source root, including their fixes.

mod common;

use common::*;
use ms_driver::{CheckRequest, LoadOptions, check_graph, load_file};
use ms_rt as _;
use ms_syntax::{Phase, Pos};

#[test]
fn project_import_fix_resolves_from_the_diagnostic_module() {
    let dir = TempDir::new();
    let manifest = write(dir.path(), "ms.toml", MANIFEST);
    let source = include_str!("import_hints/main.ms");
    write(dir.path(), "src/main.ms", source);
    write(
        dir.path(),
        "lib/blobs.ms",
        include_str!("import_hints/blobs.ms"),
    );
    let checked = check_graph(
        load_file(&manifest, LoadOptions::default()),
        CheckRequest::default(),
    );
    assert_eq!(checked.diagnostics.len(), 1, "{:?}", checked.diagnostics);
    let issue = &checked.diagnostics[0];
    assert_eq!(&*issue.file, "src/main.ms");
    assert_eq!(issue.phase, Phase::Resolution);
    assert_eq!(
        issue.message,
        "unknown type Bytes; add: import Bytes from \"../lib/blobs.ms\""
    );
    let fix = issue.fix.as_ref().expect("machine-applicable import fix");
    assert_eq!(fix.pos, Pos::new(0, 1, 1));
    assert_eq!(fix.end, fix.pos);
    assert_eq!(fix.replacement, "import Bytes from \"../lib/blobs.ms\"\n");
    write(
        dir.path(),
        "src/main.ms",
        &format!("{}{source}", fix.replacement),
    );
    let repaired = check_graph(
        load_file(&manifest, LoadOptions::default()),
        CheckRequest::default(),
    );
    assert!(repaired.success(), "{:?}", repaired.diagnostics);
}
