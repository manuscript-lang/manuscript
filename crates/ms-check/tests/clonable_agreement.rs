//! The contract checker's `Clonable` rule and the ownership `Classifier`'s `clonable` answer
//! the same for every type, so lowering and the checker never disagree about `.clone()`.

use ms_check::{CheckOptions, ImportMap, api::ownership::Classifier};
use std::sync::Arc;

const TYPES: &[&str] = &[
    "Int",
    "String",
    "Plain",
    "HasList",
    "HasFn",
    "Choice",
    "Payload",
    "Res",
    "HoldsRes",
    "ListOfRes",
    "OptRes",
    "Box[Int]",
    "Box[Res]",
    "Box[HasFn]",
    "List[String]",
    "Map[String, Int]",
    "Map[String, Res]",
    "Set[Int]",
    "Plain?",
    "Plain!",
    "Recur",
    "fn(Int) Int",
    "Closeable",
    "Error",
];

const DECLS: &str = include_str!("clonable_agreement/decls.ms");

fn run(source: &str) -> ms_check::Program {
    let syms = ms_syntax::Names::global();
    let file: Arc<str> = Arc::from("agree.ms");
    let module = ms_syntax::parser::parse(&file, source).expect("parses");
    ms_check::check(
        syms,
        vec![ms_check::load_module(syms, &module)],
        ImportMap::default(),
        CheckOptions::default(),
    )
}

#[test]
fn contracts_and_classifier_agree_on_clonable() {
    let syms = ms_syntax::Names::global();
    let mut disagreements = Vec::new();
    let mut seen = [false; 2];
    for ty in TYPES {
        let probe = format!("{DECLS}\nfn probe(x: {ty}) Unit:\n    need(x)\n");
        let program = run(&probe);
        let accepted = program.diagnostics.is_empty();
        if !accepted
            && !program
                .diagnostics
                .iter()
                .any(|d| d.message.contains("Clonable"))
        {
            panic!("`{ty}`: unexpected diagnostics {:?}", program.diagnostics);
        }
        let ty_of = program.symbols[&ms_syntax::Names::global().intern("agree.ms")]
            .borrow()
            .get(&syms.intern("probe"))
            .and_then(|s| s.ty.borrow().clone())
            .expect("probe type");
        let classifier = Classifier::new(&program);
        let param = ty_of.params[0].ty.clone();
        let classified = classifier.clonable(syms, &param);
        seen[usize::from(accepted)] = true;
        if classified != accepted {
            disagreements.push(format!(
                "{ty}: contracts accept {accepted}, classifier {classified}"
            ));
        }
    }
    assert_eq!(
        seen,
        [true, true],
        "the list must hold clonable and unclonable types"
    );
    assert!(disagreements.is_empty(), "{disagreements:#?}");
}
