# The C lowering makes one copy per type-argument list

- The checker records the type arguments it inferred at each generic call (`call_type_args_at/len`, pool `type_args`, in the order of the callee's variables). The lowering never re-infers them.
- `lb_instance` (`compiler/src/check/lower_body.c`) makes the stub of a copy at the call, named `name`, `name.1`, ... in creation order; `lb_drain_instances` lowers the bodies after the module's own functions. `lb_ty` reads a type variable of the copy being lowered as its argument, matched by `tys.id`, not by the interned index (two interned variables share an id).
- A copy that fails is remembered across passes (`dead_insts`), so its callers fail like callers of any function the pass cannot lower. Only scalar arguments are handled; a type built from variables (`List[T]`) fails.
- `lower-diff.sh` reads `@name.N` as `@name` and keys a function by name and signature: Rust takes bodies from a stack and C in declaration order, so the numbering differs and is not a property worth copying.
- A generic body that calls another generic with a value of type `T` is rejected by the ownership walk (the class of a variable is not decided), so nested generic calls wait for it.
