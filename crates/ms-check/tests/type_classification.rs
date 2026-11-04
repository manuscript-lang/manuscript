//! Nominal recursion uses declaration identity and preserves resource payloads.
use ms_check::{
    CheckOptions, ImportMap, Program,
    ownership::{Class, Classifier},
    types::*,
};
use std::{cell::RefCell, rc::Rc, sync::Arc};
fn nominal(
    kept: &mut Vec<SymRef>,
    name: &str,
    id: &str,
    kind: Kind,
    vars: Vec<Ty>,
    args: Vec<Ty>,
    fields: Vec<Ty>,
) -> Ty {
    let syms = ms_syntax::Names::global();
    let sym = Rc::new(Sym {
        name: n(name),
        id: n(id),
        kind: SymKind::Type,
        module: n("bench.ms"),
        native: n(""),
        export: true,
        ty: RefCell::new(None),
        variables: RefCell::new(vec![]),
        decl: None,
    });
    let def = Definition::new(&sym, kind);
    *def.variables.borrow_mut() = vars;
    let params = fields
        .into_iter()
        .enumerate()
        .map(|(i, ty)| Param {
            name: n(&format!("f{i}")),
            ty,
            mutable: false,
        })
        .collect();
    if kind == Kind::Alternative {
        def.cases.borrow_mut().push(Case {
            name: n("Some"),
            fields: params,
        });
    } else {
        *def.fields.borrow_mut() = params;
    }
    let mut t = Type::new(syms, sym.name, sym.id, kind);
    t.def = Some(def);
    t.args = args;
    let t = Rc::new(t);
    *sym.ty.borrow_mut() = Some(t.clone());
    kept.push(sym);
    t
}

fn classifier() -> Classifier {
    Classifier::new(&Program::default())
}
#[test]
fn same_names_from_different_modules_keep_resource_cleanup() {
    let syms = ms_syntax::Names::global();
    let sources = [
        (
            "inner.ms",
            include_str!("../../../tests/e2e/testdata/projects/nominal_cycle_identity/inner.ms"),
        ),
        (
            "bridge.ms",
            include_str!("../../../tests/e2e/testdata/projects/nominal_cycle_identity/bridge.ms"),
        ),
        (
            "outer.ms",
            include_str!("../../../tests/e2e/testdata/projects/nominal_cycle_identity/outer.ms"),
        ),
        (
            "conformance_test.ms",
            include_str!(
                "../../../tests/e2e/testdata/projects/nominal_cycle_identity/conformance_test.ms"
            ),
        ),
    ];
    let mut imports = ImportMap::default();
    let modules = sources
        .into_iter()
        .map(|(file, source)| {
            let file: Arc<str> = Arc::from(file);
            let parsed = ms_syntax::parser::parse(&file, source).expect("fixture parses");
            for import in &parsed.imports {
                if let Some(target) = import.path.strip_prefix("./") {
                    imports.insert(n(&file), import.id, n(target));
                }
            }
            ms_check::load_module(syms, &parsed)
        })
        .collect();
    let p = ms_check::check(syms, modules, imports, CheckOptions::default());
    assert!(p.diagnostics.is_empty(), "{:?}", p.diagnostics);
    let classifier = Classifier::new(&p);
    let inner = p.symbols[&n("inner.ms")].borrow()[&n("Node")].ty(syms);
    let outer = p.symbols[&n("outer.ms")].borrow()[&n("Node")].ty(syms);
    assert_ne!(inner.id, outer.id);
    assert_eq!(classifier.class(syms, &inner), Class::Resource);
    assert_eq!(classifier.class(syms, &outer), Class::Resource);
    let module = p.modules.iter().find(|m| m.file == n("outer.ms")).unwrap();
    let facts = module.facts();
    let held = facts
        .exprs
        .iter()
        .flatten()
        .filter_map(|i| i.binding.as_ref())
        .find(|b| b.name == n("held"))
        .unwrap();
    assert!(
        p.binding_facts
            .has(held.uid, ms_check::ownership::BindingFact::ImplicitClose)
    );
}
#[test]
fn recursive_and_mutually_recursive_alternatives_stay_move() {
    let syms = ms_syntax::Names::global();
    let mut kept = vec![];
    let a = nominal(
        &mut kept,
        "A",
        "test/A",
        Kind::Alternative,
        vec![],
        vec![],
        vec![],
    );
    let b = nominal(
        &mut kept,
        "B",
        "test/B",
        Kind::Alternative,
        vec![],
        vec![],
        vec![a.clone()],
    );
    a.def.as_ref().unwrap().cases.borrow_mut().push(Case {
        name: n("Loop"),
        fields: vec![Param {
            name: n("next"),
            ty: a.clone(),
            mutable: false,
        }],
    });
    assert_eq!(classifier().class(syms, &a), Class::Move);
    a.def.as_ref().unwrap().cases.borrow_mut().clear();
    a.def.as_ref().unwrap().cases.borrow_mut().push(Case {
        name: n("Other"),
        fields: vec![Param {
            name: n("next"),
            ty: b.clone(),
            mutable: false,
        }],
    });
    assert_eq!(classifier().class(syms, &a), Class::Move);
    assert_eq!(classifier().class(syms, &b), Class::Move);
}
#[test]
fn nested_generic_instances_reach_resource_and_bounds_are_not_cached() {
    let syms = ms_syntax::Names::global();
    let mut kept = vec![];
    let v = Rc::new(Type::new(syms, n("T"), n("test/T"), Kind::Variable));
    let closeable = Rc::new(Type::new(
        syms,
        n("Closeable"),
        n("@std/Closeable"),
        Kind::Contract,
    ));
    let optional = nominal(
        &mut kept,
        "Optional",
        "@std/Optional",
        Kind::Alternative,
        vec![v.clone()],
        vec![closeable.clone()],
        vec![v.clone()],
    );
    let outer = with_args(&optional, vec![optional.clone()]);
    assert_eq!(classifier().class(syms, &outer), Class::Resource);
    let c = classifier();
    assert_eq!(c.class(syms, &v), Class::Move);
    v.bounds.borrow_mut().push(closeable);
    assert_eq!(c.class(syms, &v), Class::Resource);
    v.bounds.borrow_mut().clear();
    assert_eq!(c.class(syms, &v), Class::Move);
}
#[test]
fn shared_phantom_arguments_do_not_expand_into_display_strings() {
    let syms = ms_syntax::Names::global();
    let mut kept = vec![];
    let mut arg = int();
    for _ in 0..30 {
        let mut branch = Type::new(syms, n("Branch"), n("test/Branch"), Kind::Record);
        branch.args = vec![arg.clone(), arg];
        arg = Rc::new(branch);
    }
    let t = nominal(
        &mut kept,
        "Phantom",
        "test/Phantom",
        Kind::Record,
        vec![],
        vec![arg.clone(), arg],
        vec![int()],
    );
    assert_eq!(classifier().class(syms, &t), Class::Move);
}
#[test]
fn incomplete_definitions_and_function_arguments_remain_bounded() {
    let syms = ms_syntax::Names::global();
    let mut kept = vec![];
    let mut function = Type::new(syms, n("fn"), n("fn"), Kind::Function);
    function.params.push(Param {
        name: n("value"),
        ty: int(),
        mutable: false,
    });
    let a = nominal(
        &mut kept,
        "Node",
        "test/Node",
        Kind::Alternative,
        vec![],
        vec![Rc::new(function)],
        vec![int()],
    );
    assert_eq!(classifier().class(syms, &a), Class::Copy);
    a.def.as_ref().unwrap().cases.borrow_mut().push(Case {
        name: n("Loop"),
        fields: vec![Param {
            name: n("next"),
            ty: a.clone(),
            mutable: false,
        }],
    });
    assert_eq!(classifier().class(syms, &a), Class::Move);
    let incomplete = Rc::new(Type::new(
        syms,
        n("Missing"),
        n("test/Missing"),
        Kind::Alternative,
    ));
    assert_eq!(classifier().class(syms, &incomplete), Class::Copy);
}

#[test]
fn nominal_depth_cutoff_still_allows_sixty_five_active_frames() {
    let syms = ms_syntax::Names::global();
    let mut kept = vec![];
    let mut t = Rc::new(Type::new(
        syms,
        n("Closeable"),
        n("@std/Closeable"),
        Kind::Contract,
    ));
    for depth in 1..=66 {
        t = nominal(
            &mut kept,
            &format!("Layer{depth}"),
            &format!("test/Layer{depth}"),
            Kind::Record,
            vec![],
            vec![],
            vec![t],
        );
        assert_eq!(
            classifier().class(syms, &t),
            if depth <= 65 {
                Class::Resource
            } else {
                Class::Move
            }
        );
    }
}
