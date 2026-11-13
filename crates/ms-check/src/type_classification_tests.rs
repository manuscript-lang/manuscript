//! Nominal recursion uses declaration identity and preserves resource payloads.
use crate::{
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
        native: crate::types::Native::Source,
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
            positional: false,
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
            include_str!(
                "../../../tests/conformance/fixtures/e2e/projects/nominal_cycle_identity/inner.ms"
            ),
        ),
        (
            "bridge.ms",
            include_str!(
                "../../../tests/conformance/fixtures/e2e/projects/nominal_cycle_identity/bridge.ms"
            ),
        ),
        (
            "outer.ms",
            include_str!(
                "../../../tests/conformance/fixtures/e2e/projects/nominal_cycle_identity/outer.ms"
            ),
        ),
        (
            "shared.ms",
            include_str!(
                "../../../tests/conformance/fixtures/e2e/projects/nominal_cycle_identity/shared.ms"
            ),
        ),
        (
            "conformance_test.ms",
            include_str!(
                "../../../tests/conformance/fixtures/e2e/projects/nominal_cycle_identity/conformance_test.ms"
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
            crate::load_module(syms, &parsed)
        })
        .collect();
    let p = crate::check(syms, modules, imports, CheckOptions::default());
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
        p.ownership
            .binding_facts
            .has(held.uid, crate::ownership::BindingFact::ImplicitClose)
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
            positional: false,
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
            positional: false,
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
        let mut branch = Type::new(syms, n("Branch"), n("test/Branch"), Kind::Type);
        branch.args = vec![arg.clone(), arg];
        arg = Rc::new(branch);
    }
    let t = nominal(
        &mut kept,
        "Phantom",
        "test/Phantom",
        Kind::Type,
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
        positional: false,
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
            positional: false,
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
            Kind::Type,
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

#[test]
fn nominal_types_without_payloads_do_not_need_argument_bindings() {
    let syms = ms_syntax::Names::global();
    let parameter = Rc::new(Type::new(syms, n("T"), n("test/Empty/T"), Kind::Variable));
    let mut kept = vec![];
    for kind in [Kind::Type, Kind::Alternative] {
        let empty = nominal(
            &mut kept,
            "Empty",
            &format!("test/Empty/{kind:?}"),
            kind,
            vec![parameter.clone()],
            vec![int()],
            vec![],
        );
        let def = empty.def.as_ref().unwrap();
        // Neither type fields nor case payloads use a parameter. Classification
        // therefore remains available while unused parameter metadata is being filled.
        let _parameters = def.variables.borrow_mut();
        assert_eq!(
            classifier().class(syms, &empty),
            if kind == Kind::Type {
                Class::Move
            } else {
                Class::Copy
            }
        );
        assert!(classifier().clonable(syms, &empty));
    }
}

#[test]
fn payloads_after_empty_cases_keep_argument_bounds_fresh() {
    let syms = ms_syntax::Names::global();
    let parameter = Rc::new(Type::new(syms, n("A"), n("test/Cases/A"), Kind::Variable));
    let argument = Rc::new(Type::new(syms, n("T"), n("test/Cases/T"), Kind::Variable));
    argument.bounds.borrow_mut().push(Rc::new(Type::new(
        syms,
        n("Closeable"),
        n("@std/Closeable"),
        Kind::Contract,
    )));
    let mut kept = vec![];
    let cases = nominal(
        &mut kept,
        "Cases",
        "test/LeadingEmpty/Cases",
        Kind::Alternative,
        vec![parameter.clone()],
        vec![argument.clone()],
        vec![],
    );
    cases.def.as_ref().unwrap().cases.borrow_mut().extend([
        Case {
            name: n("AlsoEmpty"),
            fields: vec![],
        },
        Case {
            name: n("PlainPayload"),
            fields: vec![Param::new(n("plain"), int())],
        },
        Case {
            name: n("BetweenPayloads"),
            fields: vec![],
        },
        Case {
            name: n("Payload"),
            fields: vec![Param::new(n("value"), parameter)],
        },
        Case {
            name: n("LastEmpty"),
            fields: vec![],
        },
    ]);
    let classifier = classifier();
    assert_eq!(classifier.class(syms, &cases), Class::Resource);
    assert!(!classifier.clonable(syms, &cases));
    argument.bounds.borrow_mut().clear();
    assert_eq!(classifier.class(syms, &cases), Class::Move);
    assert!(!classifier.clonable(syms, &cases));
    argument.bounds.borrow_mut().push(Rc::new(Type::new(
        syms,
        n("Clonable"),
        n("@std/Clonable"),
        Kind::Contract,
    )));
    assert!(classifier.clonable(syms, &cases));
}

#[test]
fn readonly_bound_queries_preserve_independent_snapshots_and_release_borrows() {
    let syms = ms_syntax::Names::global();
    let parameter = Rc::new(Type::new(
        syms,
        n("T"),
        n("test/ReadBounds/T"),
        Kind::Variable,
    ));
    let data = Rc::new(Type::new(syms, n("Data"), n("@std/Data"), Kind::Contract));
    let foreign = Rc::new(Type::new(
        syms,
        n("Closeable"),
        n("foreign/Closeable"),
        Kind::Contract,
    ));
    let closeable = Rc::new(Type::new(
        syms,
        n("Closeable"),
        n("@std/Closeable"),
        Kind::Contract,
    ));
    *parameter.bounds.borrow_mut() = vec![data, foreign];
    let plain = sub(&parameter, &Subst::new());
    let resource = sub(&parameter, &Subst::new());
    resource.bounds.borrow_mut().push(closeable.clone());
    let classifier = classifier();
    assert_eq!(classifier.class(syms, &resource), Class::Resource);
    assert!(!classifier.clonable(syms, &resource));
    assert_eq!(classifier.class(syms, &plain), Class::Move);
    {
        let _shared = plain.bounds.borrow();
        assert!(classifier.clonable(syms, &plain));
    }
    assert!(plain.bounds.try_borrow_mut().is_ok());
    assert_eq!(parameter.bounds.borrow().len(), 2);
    assert_eq!(plain.bounds.borrow().len(), 2);
    // Both early-positive predicates release their read guards on return.
    *resource.bounds.borrow_mut() = vec![closeable];
    assert_eq!(classifier.class(syms, &resource), Class::Resource);
    assert!(resource.bounds.try_borrow_mut().is_ok());
    plain.bounds.borrow_mut().clear();
    assert_eq!(classifier.class(syms, &plain), Class::Move);
    assert!(!classifier.clonable(syms, &plain));
    assert!(classifier.clonable(syms, &parameter));
}

fn declared_type(kind: Kind, name: &str, id: &str, args: Vec<Ty>) -> Ty {
    let mut ty = Type::new(ms_syntax::Names::global(), n(name), n(id), kind);
    ty.args = args;
    Rc::new(ty)
}

fn trait_fact(receiver: &Ty, contract: Option<Ty>, clone_decl: bool) -> MethodRef {
    let syms = ms_syntax::Names::global();
    let decl = clone_decl.then(|| {
        let file: Arc<str> = Arc::from("clone_decl.ms");
        let parsed =
            ms_syntax::parser::parse(&file, include_str!("type_classification/clone_decl.ms"))
                .expect("clone declaration parses");
        crate::syntax::FuncRef::of_decl(crate::syntax::DeclRef::new(
            parsed.decls.into_iter().next().unwrap(),
        ))
    });
    let mut signature = Type::new(syms, n("fn"), n("fn"), Kind::Function);
    signature.result = Some(receiver.clone());
    Rc::new(Method {
        id: n("test/Fact/method"),
        module: n("test/Fact"),
        local: false,
        receiver: receiver.clone(),
        contract,
        ty: Rc::new(signature),
        variables: vec![],
        decl,
        native: crate::types::Native::Source,
    })
}

#[test]
fn declaration_facts_preserve_resource_priority_and_argument_clonability() {
    let syms = ms_syntax::Names::global();
    let close = declared_type(Kind::Contract, "Closeable", "@std/Closeable", vec![]);
    let both = declared_type(Kind::Native, "Both", "test/Both", vec![]);
    let copied = declared_type(Kind::Native, "Decimal", "@std/Decimal", vec![]);
    let clone_only = declared_type(Kind::Native, "CloneOnly", "test/CloneOnly", vec![]);
    for reversed in [false, true] {
        let mut facts = vec![trait_fact(&both, Some(close.clone()), false)];
        if reversed {
            facts.reverse();
        }
        facts.extend([
            trait_fact(&both, None, true),
            trait_fact(&copied, None, false),
            trait_fact(&clone_only, None, true),
        ]);
        let program = Program {
            methods: facts,
            ..Program::default()
        };
        let classifier = Classifier::new(&program);
        for _ in 0..2 {
            assert_eq!(classifier.class(syms, &both), Class::Resource);
            assert!(classifier.closes_itself(&both));
            assert!(!classifier.clonable(syms, &both));
            assert_eq!(classifier.class(syms, &copied), Class::Copy);
            assert!(!classifier.closes_itself(&copied));
            assert!(classifier.clonable(syms, &copied));
            assert_eq!(classifier.class(syms, &clone_only), Class::Move);
            assert!(classifier.clonable(syms, &clone_only));
        }
        for argument in [
            close.clone(),
            declared_type(Kind::Function, "fn", "fn", vec![]),
        ] {
            let parameterized = with_args(&copied, vec![argument]);
            assert_eq!(classifier.class(syms, &parameterized), Class::Copy);
            assert!(!classifier.clonable(syms, &parameterized));
        }
    }
}

#[test]
fn declaration_facts_keep_qualified_ids_nominal_rules_and_collection_overrides() {
    let syms = ms_syntax::Names::global();
    let close = declared_type(Kind::Contract, "Closeable", "@std/Closeable", vec![]);
    let foreign = declared_type(Kind::Contract, "Closeable", "foreign/Closeable", vec![]);
    let decimal = declared_type(Kind::Type, "Decimal", "@std/Decimal", vec![]);
    let first = declared_type(Kind::Native, "Decimal", "@std/Decimal", vec![]);
    let second = declared_type(Kind::Native, "Same", "second/Same", vec![]);
    let list = declared_type(Kind::Native, "List", "@std/List", vec![close.clone()]);
    let map = declared_type(Kind::Native, "Map", "@std/Map", vec![int(), int()]);
    let mut program = Program {
        methods: vec![
            trait_fact(&decimal, None, false),
            trait_fact(&first, None, false),
            trait_fact(&second, Some(foreign), false),
        ],
        ..Program::default()
    };
    let prior = Classifier::new(&program);
    assert_eq!(prior.class(syms, &decimal), Class::Move);
    assert!(!prior.closes_itself(&decimal));
    // Facts are keyed by the same qualified receiver ID across receiver kinds.
    assert_eq!(prior.class(syms, &first), Class::Copy);
    assert_eq!(prior.class(syms, &second), Class::Move);
    assert!(!prior.closes_itself(&second));
    assert_eq!(prior.class(syms, &list), Class::Resource);
    assert_eq!(prior.class(syms, &map), Class::Move);
    program.methods.push(trait_fact(&map, Some(close), false));
    let current = Classifier::new(&program);
    assert_eq!(current.class(syms, &map), Class::Resource);
    assert!(!current.clonable(syms, &map));
    assert_eq!(prior.class(syms, &map), Class::Move);
}

#[test]
fn shared_first_children_keep_cutoff_and_late_resource_rules() {
    let syms = ms_syntax::Names::global();
    let closeable = Rc::new(Type::new(
        syms,
        n("Closeable"),
        n("@std/Closeable"),
        Kind::Contract,
    ));
    let mut kept = vec![];
    let mut child = closeable.clone();
    for depth in 1..=65 {
        child = nominal(
            &mut kept,
            &format!("SharedLayer{depth}"),
            &format!("test/SharedLayer{depth}"),
            Kind::Type,
            vec![],
            vec![],
            vec![child],
        );
        if depth >= 64 {
            let root = nominal(
                &mut kept,
                "SharedRoot",
                "test/SharedRoot",
                Kind::Type,
                vec![],
                vec![],
                vec![child.clone(), child.clone()],
            );
            assert_eq!(
                classifier().class(syms, &root),
                if depth == 64 {
                    Class::Resource
                } else {
                    Class::Move
                }
            );
            let inner_native =
                declared_type(Kind::Native, "List", "@std/List", vec![child.clone()]);
            let through_native =
                declared_type(Kind::Native, "List", "@std/List", vec![inner_native]);
            let held = nominal(
                &mut kept,
                "NativeBoundary",
                "test/NativeBoundary",
                Kind::Type,
                vec![],
                vec![],
                vec![through_native],
            );
            assert_eq!(
                classifier().class(syms, &held),
                if depth == 64 {
                    Class::Resource
                } else {
                    Class::Move
                }
            );
        }
    }
    let cycle = nominal(
        &mut kept,
        "Cycle",
        "test/SharedCycle",
        Kind::Type,
        vec![],
        vec![],
        vec![],
    );
    cycle
        .def
        .as_ref()
        .unwrap()
        .fields
        .borrow_mut()
        .push(Param::new(n("next"), cycle.clone()));
    let wrapped_cycle = declared_type(Kind::Native, "List", "@std/List", vec![cycle.clone()]);
    assert_eq!(classifier().class(syms, &wrapped_cycle), Class::Move);
    let root = nominal(
        &mut kept,
        "LateResource",
        "test/LateResource",
        Kind::Type,
        vec![],
        vec![],
        vec![cycle.clone(), cycle, closeable],
    );
    assert_eq!(classifier().class(syms, &root), Class::Resource);
    let wrapped_root = declared_type(Kind::Native, "List", "@std/List", vec![root]);
    assert_eq!(classifier().class(syms, &wrapped_root), Class::Resource);
}

#[test]
fn named_native_clone_facts_keep_name_kind_and_result_guards() {
    let syms = ms_syntax::Names::global();
    let ordinary = declared_type(Kind::Native, "Ordinary", "test/Ordinary", vec![]);
    let valid = declared_type(Kind::Native, "Valid", "test/ValidClone", vec![]);
    let wrong = declared_type(Kind::Native, "Wrong", "test/WrongClone", vec![]);
    let nonnative = declared_type(Kind::Type, "NonNative", "test/NonNativeClone", vec![]);
    let probe = declared_type(Kind::Native, "NonNative", "test/NonNativeClone", vec![]);
    let file: Arc<str> = Arc::from("clone_decl.ms");
    let parsed =
        ms_syntax::parser::parse(&file, include_str!("type_classification/clone_decl.ms")).unwrap();
    let decl = crate::syntax::FuncRef::of_decl(crate::syntax::DeclRef::new(
        parsed.decls.into_iter().nth(1).unwrap(),
    ));
    let mut named_other = trait_fact(&ordinary, None, true);
    Rc::get_mut(&mut named_other).unwrap().decl = Some(decl);
    let mut bad_result = trait_fact(&wrong, None, true);
    Rc::get_mut(&mut bad_result).unwrap().ty = function(syms, vec![], int());
    let p = Program {
        methods: vec![
            named_other,
            trait_fact(&valid, None, true),
            bad_result,
            trait_fact(&nonnative, None, true),
        ],
        ..Program::default()
    };
    let classifier = Classifier::new(&p);
    assert!(!classifier.clonable(syms, &ordinary));
    assert!(classifier.clonable(syms, &valid));
    assert!(!classifier.clonable(syms, &wrong));
    assert!(!classifier.clonable(syms, &probe));
}

#[test]
fn native_collection_walk_keeps_declared_priority_and_argument_selection() {
    let syms = ms_syntax::Names::global();
    let resource = declared_type(Kind::Contract, "Closeable", "@std/Closeable", vec![]);
    let both = declared_type(Kind::Native, "Both", "test/LoopBoth", vec![]);
    let owned_copy = declared_type(
        Kind::Native,
        "Decimal",
        "@std/Decimal",
        vec![resource.clone()],
    );
    let p = Program {
        methods: vec![
            trait_fact(&both, Some(resource.clone()), false),
            trait_fact(&owned_copy, None, false),
        ],
        ..Program::default()
    };
    let classes = Classifier::new(&p);
    let list = |element: Ty| declared_type(Kind::Native, "List", "@std/List", vec![element]);
    let map = |key: Ty, value: Ty| declared_type(Kind::Native, "Map", "@std/Map", vec![key, value]);
    assert_eq!(classes.class(syms, &owned_copy), Class::Copy);
    assert_eq!(classes.class(syms, &list(owned_copy)), Class::Move);
    assert_eq!(classes.class(syms, &both), Class::Resource);
    assert_eq!(classes.class(syms, &list(both)), Class::Resource);
    assert_eq!(
        classes.class(syms, &list(map(resource.clone(), int()))),
        Class::Move
    );
    assert_eq!(
        classes.class(syms, &list(map(int(), resource.clone()))),
        Class::Resource
    );
    for probe in [
        declared_type(Kind::Native, "List", "@std/List", vec![]),
        declared_type(Kind::Native, "Map", "@std/Map", vec![resource.clone()]),
        declared_type(
            Kind::Native,
            "List",
            "@std/List",
            vec![int(), resource.clone()],
        ),
        declared_type(
            Kind::Native,
            "Opaque",
            "test/Opaque",
            vec![resource.clone()],
        ),
    ] {
        assert_eq!(classes.class(syms, &list(probe)), Class::Move);
    }
    let plain = declared_type(Kind::Native, "Decimal", "@std/Decimal", vec![]);
    let p = Program {
        methods: vec![trait_fact(&plain, None, false)],
        ..Program::default()
    };
    let classes = Classifier::new(&p);
    assert_eq!(classes.class(syms, &plain), Class::Copy);
    for wrapper in [list(plain.clone()), map(int(), plain.clone())] {
        assert_eq!(classes.class(syms, &wrapper), Class::Move);
    }
}
