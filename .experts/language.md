# Language lessons

### Read the current decision before restoring an older design

Decision: the language rebuild was directed to use the new design on `main`. Earlier designs and assistant proposals can conflict with subsequent user corrections. Establish the target contract from the latest direction and canonical pages before borrowing old implementation ideas.

Apply when: rebuilding a feature, reusing historical code, or reconciling branches.
Evidence: [user correction in Build out the language](codex://threads/01a12c08-60dd-731b-a496-4a932d9b6000); [design index](../design/_index.md).
Verify: the accepted/rejected source cases agree with the intended design, and any checkout mismatch is identified before being treated as a rule.

### Removing a construct includes its surrounding APIs

Decision: the request to remove `assert` required follow-up corrections to remove assertion helpers, bindings, docs, and even residual tests. The user wanted ordinary `if`/`return` control flow. Removing the syntax alone did not satisfy the requested surface.

Apply when: removing or renaming language constructs or standard APIs.
Evidence: [successive corrections in Remove assert; use if return](codex://threads/01a12e19-ae70-752b-8c66-be8d59177006).
Verify: inventory related exported helpers and aliases before editing, regenerate references, then check every surface covered by the removal request. Follow an explicit zero-reference request when deciding whether rejection tests should retain the old spelling.

### Latest choices can supersede an apparently accepted alternative

Decision: keep `Equal` and `Hashable` derived and `Shareable` compiler-verified. The user briefly requested custom equality implementations, then explicitly reversed that choice. Explicit closure capture lists were also rejected; the rejection did not establish a replacement sharing design.

Apply when: changing bounds, equality, capture syntax, or callable sharing.
Evidence: [equality reversal](codex://threads/01a12aed-fa8a-7d93-b522-38e95f93fdf5); [capture-list rejection](codex://threads/01a12bf3-438d-7c72-a846-7443cea58e3a); [canonical equality rules](../design/core-language/types/equality-and-hashing.md); [current callable sharing rules](../design/ownership-and-cleanup/values/sharing.md#function-values).
Verify: examples follow current derivation and callable-proof rules. Rejected alternatives remain rejected unless the user deliberately reopens them; an earlier “yes” does not override a later correction.

### Syntax improvements need examples across their boundaries

Decision: support grouped symbol imports, and allow an omitted call label for a function with one parameter while requiring labels for functions with more than one parameter. The single-parameter request measures declaration arity, not the number of arguments supplied. These are user decisions; verify their availability in the branch being changed.

Apply when: changing imports, calls, grammar, or editor assistance.
Evidence: [grouped-import request](codex://threads/01a12e1a-7d2d-7646-b5fc-2dc8fdd60038); [single-parameter request](codex://threads/01a12e4a-98e8-775e-9e6c-c101a8ac300d).
Verify: grouped imports resolve each symbol and its editor location; one-parameter calls exercise both spellings, multi-parameter calls require labels, and missing arguments still fail. Consult current grammar and compatibility rules for methods, constructors, and function values rather than assuming identical boundaries.
