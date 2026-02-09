// Declaration Generators
import type * as AST from "../parser/ast";
import type { Ctx, GenOpts } from "./types";
import { emit, pushIndent, popIndent, tempVar } from "./types";
import { genExpr } from "./expressions";
import { genBlock } from "./statements";
import { EXTERN_TYPES } from "../builtin";
import { isStdlibImport } from "../shared/constants";

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
export function genImport(ctx: Ctx, decl: AST.ImportDecl, _opts: GenOpts): void {
  // Stdlib imports destructure from __ms_runtime
  if (isStdlibImport(decl.source)) {
    const items = decl.names.map(item => {
      if (item.alias) return `${item.name}: ${item.alias}`;
      return item.name;
    });
    emit(ctx, `const { ${items.join(", ")} } = __ms_runtime;`);
    return;
  }

  const items = decl.names.map(item => {
    if (item.alias) return `${item.name} as ${item.alias}`;
    return item.name;
  });
  const path = ctx.options.importEmitPaths?.get(decl.source) ?? decl.source;
  if (ctx.options.module === "esm") {
    emit(ctx, `import { ${items.join(", ")} } from "${path}";`);
  } else {
    emit(ctx, `const { ${items.join(", ")} } = require("${path}");`);
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

  // Get embedded fields for initialization
  const embeddedFields = fields.filter(f => f.embedded);

  // Generate factory function from fields
  if (fields.length > 0) {
    // Build params in declaration order
    const allParams = fields
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

// Generate test declaration
export function genTest(ctx: Ctx, decl: AST.TestDecl, opts: GenOpts): void {
  emit(ctx, `__ms_runtime.test(${JSON.stringify(decl.description)}, async () => {`);
  pushIndent(ctx);
  genBlock(ctx, decl.body, opts);
  popIndent(ctx);
  emit(ctx, "});");
  emit(ctx, "");
}
