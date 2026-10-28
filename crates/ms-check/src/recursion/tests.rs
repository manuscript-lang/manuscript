//! Frontend-only regressions: do not invoke the public ownership-checking wrapper.
use super::*;
use crate::CheckOptions;
use std::sync::Arc;

fn diagnostics(sources: &[(&str, &str)]) -> Vec<(String, u32, u32, String)> {
    crate::stdlib::ensure_standard();
    let modules = sources
        .iter()
        .map(|(file, source)| {
            let file: Arc<str> = Arc::from(*file);
            let ast = ms_syntax::parser::parse(&file, source).expect("parses");
            crate::load_module(&ast)
        })
        .collect();
    Checker::new(&CheckOptions::default())
        .check_modules(modules, None)
        .diagnostics
        .into_iter()
        .map(|d| (d.file.to_string(), d.pos.line, d.pos.column, d.message))
        .collect()
}

#[test]
fn branch_exclusive_prefix_into_preserving_cycle() {
    let mut source = String::new();
    // Forty branch levels represent over a trillion paths, but only 41 declarations.
    for i in 0..40 {
        source.push_str(&format!("fn f{i}[T](n: Int) Int:\n    if n < 0:\n        return f{}[T](n)\n    return f{}[T](n)\n\n", i+1, i+1));
    }
    source.push_str(
        "fn f40[T](n: Int) Int:\n    if n <= 0:\n        return 0\n    return f40[T](n - 1)\n",
    );
    assert!(diagnostics(&[("branches.ms", &source)]).is_empty());
}

#[test]
fn distinct_diamond_arms_into_mutual_cycle() {
    let mut source = String::new();
    for i in 0..30 {
        source.push_str(&format!("fn f{i}[T](n: Int) Int:\n    if n < 0:\n        return left{i}[T](n)\n    return right{i}[T](n)\n\nfn left{i}[T](n: Int) Int:\n    return f{}[T](n)\n\nfn right{i}[T](n: Int) Int:\n    return f{}[T](n)\n\n", i+1, i+1));
    }
    source.push_str("fn f30[T](n: Int) Int:\n    if n <= 0:\n        return 0\n    return other[T](n - 1)\n\nfn other[U](n: Int) Int:\n    return f30[U](n)\n");
    assert!(diagnostics(&[("diamonds.ms", &source)]).is_empty());
}

const ERROR: &str = "recursive generic applications must preserve their parameters; a type may refer to itself only with the same type arguments (e.g. List[Node[T]] inside Node[T])";

#[test]
fn ancestor_context_and_failure_order_are_preserved() {
    let source = "fn root[T](n: Int) Unit:\n    b[Int](n)\n    a[List[T]](n)\n\nfn a[T](n: Int) Unit:\n    b[Int](n)\n\nfn b[T](n: Int) Unit:\n    a[Int](n)\n";
    assert_eq!(
        diagnostics(&[("ancestors.ms", source)]),
        vec![
            ("ancestors.ms".into(), 9, 5, ERROR.into()),
            ("ancestors.ms".into(), 6, 5, ERROR.into()),
        ]
    );
}

#[test]
fn reused_success_does_not_hide_a_later_changing_specialization() {
    let source = "fn root[T](n: Int) Unit:\n    fixed[Int](n)\n    fixed[T](n)\n    fixed[Int](n)\n    fixed[T](n)\n\nfn fixed[T](n: Int) Unit:\n    fixed[Int](n)\n";
    // The public frontend result deduplicates identical diagnostics; the graph oracle
    // below also checks the pre-deduplication sequence, including repeated failures.
    assert_eq!(
        diagnostics(&[("mixed.ms", source)]),
        vec![("mixed.ms".into(), 8, 5, ERROR.into())]
    );
}

// The original ancestor-sensitive traversal, retained only as a differential oracle.
fn reference(
    id: Name,
    args: Vec<Ty>,
    variables: &HashMap<Name, Vec<Ty>>,
    edges: &HashMap<Name, Vec<Edge>>,
    active: &mut HashMap<Name, Vec<Ty>>,
    errors: &mut Vec<Pos>,
) {
    active.insert(id, args.clone());
    let subst = variables[&id]
        .iter()
        .zip(args)
        .map(|(v, a)| (v.id, a))
        .collect();
    for edge in &edges[&id] {
        let next: Vec<_> = edge.arguments.iter().map(|a| sub(a, &subst)).collect();
        if let Some(previous) = active.get(&edge.target) {
            if previous.len() != next.len() || !previous.iter().zip(&next).all(|(a, b)| same(a, b))
            {
                errors.push(edge.pos);
            }
            continue;
        }
        reference(edge.target, next, variables, edges, active, errors);
    }
    active.remove(&id);
}

#[test]
fn all_three_node_graphs_match_original_diagnostics() {
    let ids = [n("a"), n("b"), n("c")];
    let variables: HashMap<_, _> = ids
        .iter()
        .map(|&id| {
            (
                id,
                vec![std::rc::Rc::new(Type::new(
                    n("T"),
                    n(&format!("{id}.T")),
                    Kind::Variable,
                ))],
            )
        })
        .collect();
    // All 512 directed graphs, preserving/constant/expanding edges, and two edge orders.
    for mask in 0..512 {
        for mode in 0..3 {
            for reversed in [false, true] {
                let edges: HashMap<_, _> = ids
                    .iter()
                    .enumerate()
                    .map(|(i, &id)| {
                        let mut outgoing = Vec::new();
                        for (j, &target) in ids.iter().enumerate() {
                            if mask & (1 << (i * 3 + j)) == 0 {
                                continue;
                            }
                            let arg = match mode {
                                0 => variables[&id][0].clone(),
                                1 if (i + j) % 2 == 0 => int(),
                                _ => {
                                    let mut t = Type::new(n("List"), n("List"), Kind::Record);
                                    t.args = variables[&id].clone();
                                    std::rc::Rc::new(t)
                                }
                            };
                            outgoing.push(Edge {
                                target,
                                arguments: vec![arg],
                                file: n("graph.ms"),
                                pos: Pos::new((i * 3 + j) as u32, (i * 3 + j + 1) as u32, 1),
                            });
                        }
                        if reversed {
                            outgoing.reverse();
                        }
                        (id, outgoing)
                    })
                    .collect();
                let components = components(&edges);
                let mut completed = HashSet::new();
                let mut checker = Checker::new(&CheckOptions::default());
                let mut expected = Vec::new();
                for &root in &ids {
                    reference(
                        root,
                        variables[&root].clone(),
                        &variables,
                        &edges,
                        &mut HashMap::new(),
                        &mut expected,
                    );
                    checker.visit_application(
                        root,
                        variables[&root].clone(),
                        &variables,
                        &edges,
                        &mut HashMap::new(),
                        &components,
                        &mut completed,
                    );
                }
                assert_eq!(
                    checker
                        .p
                        .diagnostics
                        .iter()
                        .map(|d| d.pos)
                        .collect::<Vec<_>>(),
                    expected,
                    "mask={mask}, mode={mode}, reversed={reversed}"
                );
            }
        }
    }
}
