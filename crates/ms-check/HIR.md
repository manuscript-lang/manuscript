# Typed HIR and Program queries

`ms-check` does not build a second tree. The `ms-syntax` tree plus the per-module fact tables (`syntax::Facts`, indexed by `NodeId`) already are a typed, resolved tree, so the HIR is a **query view** (`hir.rs`) over a checked `Program`. A lowering pass walks bodies with `ms_syntax::visit` (or by hand) and asks the view what each node means. Nothing is re-derived: every answer is a fact the checker stored.

```rust
let program = ms_check::check(modules, imports, options);
let hir = program.hir();
for c in hir.callables() {
    let m = ModuleHir { data: c.module.clone() };
    match c.body() { Body::Block(stmts) => /* walk */, Body::Expr(e) => /* constant */ }
}
```

## API

| Query | Meaning |
| --- | --- |
| `Program::hir()` → `Hir` | entry point; `modules()`, `module(file)`, `callables()` |
| `ModuleHir::callables()` | functions, methods (inherent `impl`s are already desugared to `Type$methods` + `impl`), tests, constants |
| `Callable` | `kind`, `name`, `func`, `parameters`, `self_binding`, `fixture`, `body()`, `id()` |
| `ModuleHir::ty(e)` / `info(e)` | checked type / all facts of an expression |
| `ModuleHir::resolution(e)` | `Local`, `Constant`, `Function`, `Type`, `Constructor{ty, case}`, `Method`, `Native`, `Value` |
| `ModuleHir::call(e)` | resolved call: target, arguments in written order with resolved labels (`ArgSlot`) and the Optional wrap, instantiated type arguments, `constant_use` |
| `captures(lambda)`, `lambda_parameters(lambda)` | closure environment (snapshot at creation) and parameters |
| `pattern_binding(p)`, `stmt(s)`, `arm(a)`, `assigned(value)`, `type_ref(id)` | bindings and facts of patterns, statements (loop/`with` variable, cleanup method, fallthrough), match arms, assignments, written types |

## Contracts the lowering can rely on

- A **constant** is not a value: each use is `call(e)` with `constant_use == true`; evaluating it runs the initializer (`Body::Expr`).
- **Generics are not instantiated here.** `call(e).type_args` holds the inferred arguments and `Info.ty` is the generic-open type of the node; monomorphization belongs to `ms-mir`.
- **Dispatch**: `Resolution::Method` with `native == ""` is a source method (`decl` names it); `native == "contract"` is dynamic dispatch through an interface view; any other native string is a runtime operation.
- **Errors**: `Info.error_source`/`scoped_error` and `propagated_error`/`scoped_propagation` mark conversions at `try` and Error boundaries; `StmtFacts.cleanup` is the `close` method a `with` runs.
- Facts exist for nodes of checked modules only; a missing fact reads as `<invalid>` (`ty`) or `Resolution::Value`. Lower only programs whose `diagnostics` are empty.
- Node ids are unique per module. Synthetic default-method nodes (ids from `0x8000_0000`) carry no facts.

## Not here

Layouts, monomorphization, RC elaboration and optimization are `ms-mir`. Ownership/usage facts are in [OWNERSHIP.md](OWNERSHIP.md).
