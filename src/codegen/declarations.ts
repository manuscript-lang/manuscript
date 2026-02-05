// Declaration Generators
import type * as AST from "../parser/ast";
import type { Ctx, GenOpts } from "./types";
import { emit, pushIndent, popIndent, tempVar } from "./types";
import { genExpr } from "./expressions";
import { genBlock } from "./statements";
import { EXTERN_TYPES } from "../shared/stdlib";

// Generate function parameters
export function genParams(ctx: Ctx, params: AST.Parameter[], opts: GenOpts): string {
  return params.map(p => {
    let param = p.name;
    if (p.rest) param = `...${param}`;
    if (p.defaultValue) {
      param += ` = ${genExpr(ctx, p.defaultValue, opts)}`;
    }
    return param;
  }).join(", ");
}

// Generate import declaration
export function genImport(ctx: Ctx, decl: AST.ImportDecl, opts: GenOpts): void {
  const items = decl.names.map(item => {
    if (item.alias) return `${item.name} as ${item.alias}`;
    return item.name;
  });

  if (ctx.options.module === "esm") {
    emit(ctx, `import { ${items.join(", ")} } from "${decl.source}";`);
  } else {
    emit(ctx, `const { ${items.join(", ")} } = require("${decl.source}");`);
  }
}

// Generate function declaration
export function genFn(ctx: Ctx, decl: AST.FnDecl, opts: GenOpts): void {
  const params = genParams(ctx, decl.params, opts);
  const prefix = decl.isGenerator ? "function*" : "async function";

  emit(ctx, `${prefix} ${decl.name}(${params}) {`);
  pushIndent(ctx);

  // Pull context bindings from runtime stack
  if (decl.using && decl.using.bindings.length > 0) {
    for (const binding of decl.using.bindings) {
      const name = binding.name || tempVar(ctx, "_binding");
      const typeName = binding.type.kind === "NamedType" ? binding.type.name : "unknown";
      emit(ctx, `const ${name} = __ms_runtime.__getContext("${typeName}");`);
    }
  }

  genBlock(ctx, decl.body, { ...opts, implicitReturn: true });
  popIndent(ctx);
  emit(ctx, "}");
  emit(ctx, "");
}

// Generate type declaration using factory function + shared null-prototype pattern
export function genType(ctx: Ctx, decl: AST.TypeDecl, opts: GenOpts): void {
  if (!decl.body) {
    emit(ctx, `// type ${decl.name} = ...`);
    return;
  }

  const fields: AST.FieldDecl[] = [];
  const methods: AST.MethodDecl[] = [];

  for (const member of decl.body.members) {
    if (member.kind === "FieldDecl") {
      fields.push(member);
    } else if (member.kind === "MethodDecl") {
      methods.push(member);
    }
  }

  // Collect all fields and methods including promoted from embedded types
  const classFields = new Set(fields.map(f => f.name));
  for (const method of methods) {
    classFields.add(method.name);
  }
  for (const field of fields) {
    if (field.embedded) {
      const embeddedFields = ctx.typeFields.get(field.name);
      if (embeddedFields) {
        for (const ef of embeddedFields) {
          classFields.add(ef);
        }
      }
    }
  }
  // Register this type's fields for future embedding
  ctx.typeFields.set(decl.name, classFields);
  
  const methodOpts = { ...opts, classFields };

  // Generate shared methods object (null prototype for security)
  if (methods.length > 0) {
    emit(ctx, `const ${decl.name}$methods = Object.assign(Object.create(null), {`);
    pushIndent(ctx);
    for (const method of methods) {
      const prefix = method.isGenerator ? "*" : "async ";
      const params = genParams(ctx, method.params, methodOpts);
      emit(ctx, `${prefix}${method.name}(${params}) {`);
      pushIndent(ctx);
      if (method.body) {
        genBlock(ctx, method.body, { ...methodOpts, implicitReturn: true });
      }
      popIndent(ctx);
      emit(ctx, `},`);
    }
    popIndent(ctx);
    emit(ctx, `});`);
    emit(ctx, "");
  }

  // Get embedded fields for initialization (skip Context - it's a marker type)
  const embeddedFields = fields.filter(f => f.embedded && f.name !== "Context");

  // Generate factory function from fields
  if (fields.length > 0) {
    // Build params in declaration order, skip Context (marker type)
    const allParams = fields
      .filter(f => !(f.embedded && f.name === "Context"))
      .map(f => {
        if (f.embedded) {
          const typeName = EXTERN_TYPES.has(f.name) ? `__ms_runtime.${f.name}` : f.name;
          return `_${f.name} = ${typeName}()`;
        } else if (f.optional || f.defaultValue || f.computed) {
          if (f.defaultValue) return `${f.name} = ${genExpr(ctx, f.defaultValue, opts)}`;
          return `${f.name} = undefined`;
        }
        return f.name;
      }).join(", ");

    emit(ctx, `function ${decl.name}(${allParams}) {`);
    pushIndent(ctx);
    
    if (methods.length > 0) {
      emit(ctx, `const self = Object.create(${decl.name}$methods);`);
    } else {
      emit(ctx, `const self = Object.create(null);`);
    }
    emit(ctx, `self.__typename = "${decl.name}";`);
    
    // Initialize regular (non-embedded) fields FIRST (for shadowing to work)
    for (const field of fields) {
      if (field.embedded) continue;
      if (field.computed && field.defaultValue) {
        emit(ctx, `Object.defineProperty(self, "${field.name}", { get() { return ${genExpr(ctx, field.defaultValue, { ...opts, selfVar: "self" })}; } });`);
      } else {
        emit(ctx, `self.${field.name} = ${field.name};`);
      }
    }
    
    // Initialize embedded types and forward their properties/methods
    for (const ef of embeddedFields) {
      const paramName = `_${ef.name}`;
      emit(ctx, `self.${ef.name} = ${paramName};`);
      // Forward embedded type's properties and methods (for...in includes inherited)
      // Skip properties that already exist in self (shadowing)
      emit(ctx, `for (const k in ${paramName}) {`);
      pushIndent(ctx);
      emit(ctx, `if (k !== '__typename' && !(k in self)) {`);
      pushIndent(ctx);
      emit(ctx, `const v = ${paramName}[k];`);
      emit(ctx, `if (typeof v === 'function') {`);
      pushIndent(ctx);
      emit(ctx, `self[k] = v.bind(${paramName});`);
      popIndent(ctx);
      emit(ctx, `} else {`);
      pushIndent(ctx);
      emit(ctx, `Object.defineProperty(self, k, {`);
      pushIndent(ctx);
      emit(ctx, `get() { return self.${ef.name}[k]; },`);
      emit(ctx, `set(v) { self.${ef.name}[k] = v; },`);
      emit(ctx, `enumerable: true`);
      popIndent(ctx);
      emit(ctx, `});`);
      popIndent(ctx);
      emit(ctx, `}`);
      popIndent(ctx);
      emit(ctx, `}`);
      popIndent(ctx);
      emit(ctx, `}`);
    }
    
    emit(ctx, `return self;`);
    popIndent(ctx);
    emit(ctx, "}");
    emit(ctx, "");
  } else {
    // Empty type (like Context marker)
    emit(ctx, `function ${decl.name}() {`);
    pushIndent(ctx);
    if (methods.length > 0) {
      emit(ctx, `return Object.create(${decl.name}$methods);`);
    } else {
      emit(ctx, `return Object.create(null);`);
    }
    popIndent(ctx);
    emit(ctx, "}");
    emit(ctx, "");
  }
}

// Generate enum declaration (old EnumDecl AST node)
export function genEnum(ctx: Ctx, decl: AST.EnumDecl, opts: GenOpts): void {
  emit(ctx, `const ${decl.name} = Object.freeze({`);
  pushIndent(ctx);

  for (let i = 0; i < decl.variants.length; i++) {
    const variant = decl.variants[i];
    if (!variant) continue;
    const comma = i < decl.variants.length - 1 ? "," : "";

    if (variant.value) {
      emit(ctx, `${variant.name}: ${genExpr(ctx, variant.value, opts)}${comma}`);
    } else {
      emit(ctx, `${variant.name}: "${variant.name}"${comma}`);
    }
  }

  popIndent(ctx);
  emit(ctx, "});");
  emit(ctx, "");
}

// Generate enum from keyword type use (enum Color with Red = 1, etc.)
function genEnumKeywordUse(ctx: Ctx, use: AST.KeywordTypeUse, opts: GenOpts): void {
  const fields = use.body.members.filter(m => m.kind === "FieldDecl") as AST.FieldDecl[];
  
  emit(ctx, `const ${use.name} = Object.freeze({`);
  pushIndent(ctx);

  for (let i = 0; i < fields.length; i++) {
    const field = fields[i];
    if (!field) continue;
    const comma = i < fields.length - 1 ? "," : "";

    if (field.defaultValue) {
      emit(ctx, `${field.name}: ${genExpr(ctx, field.defaultValue, opts)}${comma}`);
    } else {
      emit(ctx, `${field.name}: "${field.name}"${comma}`);
    }
  }

  popIndent(ctx);
  emit(ctx, "});");
  emit(ctx, "");
}

// Generate context declaration
export function genContext(ctx: Ctx, decl: AST.ContextDecl, opts: GenOpts): void {
  emit(ctx, `const ${decl.name} = {`);
  pushIndent(ctx);

  if (decl.bindings) {
    for (const binding of decl.bindings) {
      const value = genExpr(ctx, binding.value, opts);
      emit(ctx, `${binding.name}: ${value},`);
    }
  }

  if (decl.methods) {
    for (const method of decl.methods) {
      const params = genParams(ctx, method.params, opts);
      emit(ctx, `async ${method.name}(${params}) {`);
      pushIndent(ctx);
      if (method.body) {
        genBlock(ctx, method.body, opts);
      }
      popIndent(ctx);
      emit(ctx, "},");
    }
  }

  popIndent(ctx);
  emit(ctx, "};");
  emit(ctx, "");
}

// Generate agent declaration using factory function pattern
export function genAgent(ctx: Ctx, decl: AST.AgentDecl, opts: GenOpts): void {
  const bindings = decl.context?.map(c => c.name || "_binding") || [];
  const hasTools = decl.tools && decl.tools.length > 0;
  const hasRun = !!decl.run;

  // Generate shared methods object if there are tools or run method
  if (hasTools || hasRun) {
    emit(ctx, `const ${decl.name}$methods = Object.assign(Object.create(null), {`);
    pushIndent(ctx);

    if (decl.tools) {
      for (const tool of decl.tools) {
        const params = genParams(ctx, tool.params, opts);
        emit(ctx, `async ${tool.name}(${params}) {`);
        pushIndent(ctx);
        genBlock(ctx, tool.body, opts);
        popIndent(ctx);
        emit(ctx, "},");
      }
    }

    if (decl.run) {
      const params = genParams(ctx, decl.run.params, opts);
      emit(ctx, `async run(${params}) {`);
      pushIndent(ctx);
      genBlock(ctx, decl.run.body, opts);
      popIndent(ctx);
      emit(ctx, "},");
    }

    popIndent(ctx);
    emit(ctx, "});");
    emit(ctx, "");
  }

  // Generate factory function
  emit(ctx, `function ${decl.name}(${bindings.join(", ")}) {`);
  pushIndent(ctx);

  if (hasTools || hasRun) {
    emit(ctx, `const self = Object.create(${decl.name}$methods);`);
  } else {
    emit(ctx, `const self = Object.create(null);`);
  }
  emit(ctx, `self.__typename = "${decl.name}";`);

  for (const binding of bindings) {
    emit(ctx, `self.${binding} = ${binding};`);
  }

  emit(ctx, `return self;`);
  popIndent(ctx);
  emit(ctx, "}");
  emit(ctx, "");
}

// Generate test declaration
export function genTest(ctx: Ctx, decl: AST.TestDecl, opts: GenOpts): void {
  emit(ctx, `__ms_runtime.test(${JSON.stringify(decl.description)}, async () => {`);
  pushIndent(ctx);
  genBlock(ctx, decl.body, opts);
  popIndent(ctx);
  emit(ctx, "});");
  emit(ctx, "");
}

// Generate keyword type use (similar to type declaration)
// Combines keyword's fields/methods with user's fields/methods
export function genKeywordTypeUse(ctx: Ctx, use: AST.KeywordTypeUse, opts: GenOpts): void {
  // Special case: enum generates Object.freeze with variants
  if (use.keyword === "enum") {
    genEnumKeywordUse(ctx, use, opts);
    return;
  }

  const fields: AST.FieldDecl[] = [];
  const methods: AST.MethodDecl[] = [];
  const userFieldNames = new Set<string>();
  const userMethodNames = new Set<string>();

  // Collect from user's body
  for (const member of use.body.members) {
    if (member.kind === "FieldDecl") {
      fields.push(member);
      userFieldNames.add(member.name);
    } else if (member.kind === "MethodDecl") {
      methods.push(member);
      userMethodNames.add(member.name);
    }
  }

  // Get keyword declaration to merge its methods
  const keywordDecl = ctx.keywordDecls.get(use.keyword);
  if (keywordDecl?.body) {
    // Add keyword's methods (user cannot override - enforced by semantic phase)
    for (const member of keywordDecl.body.members) {
      if (member.kind === "MethodDecl" && !userMethodNames.has(member.name)) {
        methods.push(member);
      }
    }
    // Add keyword's fields that aren't provided by user (for type info)
    for (const member of keywordDecl.body.members) {
      if (member.kind === "KeywordField" && !userFieldNames.has(member.name)) {
        // KeywordField -> FieldDecl conversion
        fields.push({
          kind: "FieldDecl",
          name: member.name,
          type: member.type,
          optional: member.optional,
          defaultValue: member.defaultValue,
          computed: member.computed,
          loc: member.loc,
          doc: member.doc,
        });
      }
    }
  }

  // Track fields for embedding
  const classFields = new Set(fields.map(f => f.name));
  for (const method of methods) {
    classFields.add(method.name);
  }
  ctx.typeFields.set(use.name, classFields);
  
  const methodOpts = { ...opts, classFields };

  // Generate shared methods object
  if (methods.length > 0) {
    emit(ctx, `const ${use.name}$methods = Object.assign(Object.create(null), {`);
    pushIndent(ctx);
    for (const method of methods) {
      const prefix = method.isGenerator ? "*" : "async ";
      const params = genParams(ctx, method.params, methodOpts);
      emit(ctx, `${prefix}${method.name}(${params}) {`);
      pushIndent(ctx);
      if (method.body) {
        genBlock(ctx, method.body, { ...methodOpts, implicitReturn: true });
      }
      popIndent(ctx);
      emit(ctx, `},`);
    }
    popIndent(ctx);
    emit(ctx, `});`);
    emit(ctx, "");
  }

  // Generate factory function
  if (fields.length > 0) {
    const allParams = fields.map(f => {
      if (f.optional || f.defaultValue || f.computed) {
        if (f.defaultValue) return `${f.name} = ${genExpr(ctx, f.defaultValue, opts)}`;
        return `${f.name} = undefined`;
      }
      return f.name;
    }).join(", ");

    emit(ctx, `function ${use.name}(${allParams}) {`);
    pushIndent(ctx);
    
    if (methods.length > 0) {
      emit(ctx, `const self = Object.create(${use.name}$methods);`);
    } else {
      emit(ctx, `const self = Object.create(null);`);
    }
    emit(ctx, `self.__typename = "${use.name}";`);
    
    for (const field of fields) {
      if (field.computed && field.defaultValue) {
        emit(ctx, `Object.defineProperty(self, "${field.name}", { get() { return ${genExpr(ctx, field.defaultValue, { ...opts, selfVar: "self" })}; } });`);
      } else {
        emit(ctx, `self.${field.name} = ${field.name};`);
      }
    }
    
    emit(ctx, `return self;`);
    popIndent(ctx);
    emit(ctx, "}");
    emit(ctx, "");
  } else {
    emit(ctx, `function ${use.name}() {`);
    pushIndent(ctx);
    if (methods.length > 0) {
      emit(ctx, `return Object.create(${use.name}$methods);`);
    } else {
      emit(ctx, `return Object.create(null);`);
    }
    popIndent(ctx);
    emit(ctx, "}");
    emit(ctx, "");
  }
}
