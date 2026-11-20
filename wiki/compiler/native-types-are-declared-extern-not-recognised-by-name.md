# Native types are declared `extern type`, never recognised by name

The loader made `List` native by comparing its name (`NATIVE_WITH_FIELDS` in Rust, `sl_str_is(name,
"List")` in C) because it carries a constructor field, which an `extern type` could not. Chinmay chose
to reuse `extern type` instead: it takes type parameters and, with a `:` body, the fields a
constructor accepts (`export extern type List[T]:`). Both parsers and both loaders read the
declaration; no standard-library name decides a kind.

- A native module's type is registered by the loader; the scope pass now binds the declaration to that
  symbol (`scope_registered_symbol` also reads `std_types`) instead of declaring a second `#Name`
  twin without the built-in identity. A twin made `List[Int]` from a method row compare unequal to the
  written one and left the type outside `ms_body_is_list`.
- Classification changed with it: the twin had no fields, so `Result[Int, Error]` read as a copy.
  The ownership walk now treats `ok(...)` / `error(...)` as constructors (they move the argument into the
  Result), as it does a record.
- The effect scan charges only constructors of source types; a runtime-provided type (`Error`) has no
  body. Calls with type arguments are partial until the scan ports the operations Rust charges for them.
