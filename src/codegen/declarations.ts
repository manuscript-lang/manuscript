// Declaration Generators
import type * as AST from "../parser/ast";
import type { Ctx, GenOpts } from "./types";
import { emit, pushIndent, popIndent, tempVar } from "./types";
import { genExpr } from "./expressions";
import { genBlock } from "./statements";

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

// Generate type declaration
export function genType(ctx: Ctx, decl: AST.TypeDecl, opts: GenOpts): void {
  if (!decl.body) {
    emit(ctx, `// type ${decl.name} = ...`);
    return;
  }

  let extendsClause = "";
  if (decl.extends && decl.extends.length > 0 && decl.extends[0]) {
    const parentType = decl.extends[0];
    let parentName = parentType.kind === "NamedType" ? parentType.name : "Object";
    if (parentName === "Context") {
      parentName = "__ms_runtime.Context";
    }
    extendsClause = ` extends ${parentName}`;
  }

  emit(ctx, `class ${decl.name}${extendsClause} {`);
  pushIndent(ctx);

  const fields: AST.FieldDecl[] = [];
  const methods: AST.MethodDecl[] = [];

  for (const member of decl.body.members) {
    if (member.kind === "FieldDecl") {
      fields.push(member);
    } else if (member.kind === "MethodDecl") {
      methods.push(member);
    }
  }

  // Generate constructor
  const requiredFields = fields.filter(f => !f.optional && !f.defaultValue);
  const optionalFields = fields.filter(f => f.optional || f.defaultValue);
  const hasExtends = decl.extends && decl.extends.length > 0;

  if (fields.length > 0 || hasExtends) {
    const ctorParams = requiredFields.map(f => f.name).join(", ");
    const optParams = optionalFields.map(f => {
      if (f.defaultValue) return `${f.name} = ${genExpr(ctx, f.defaultValue, opts)}`;
      return `${f.name} = undefined`;
    }).join(", ");

    const allParams = [ctorParams, optParams].filter(p => p).join(", ");

    emit(ctx, `constructor(${allParams}) {`);
    pushIndent(ctx);
    if (hasExtends) {
      emit(ctx, "super();");
    }
    for (const field of fields) {
      emit(ctx, `this.${field.name} = ${field.name};`);
    }
    popIndent(ctx);
    emit(ctx, "}");
    emit(ctx, "");
  }

  // Generate methods with class field context
  const classFields = new Set(fields.map(f => f.name));
  const methodOpts = { ...opts, classFields };

  for (const method of methods) {
    const prefix = method.isGenerator ? "*" : "async ";
    const params = genParams(ctx, method.params, methodOpts);

    emit(ctx, `${prefix}${method.name}(${params}) {`);
    pushIndent(ctx);
    if (method.body) {
      genBlock(ctx, method.body, { ...methodOpts, implicitReturn: true });
    }
    popIndent(ctx);
    emit(ctx, "}");
    emit(ctx, "");
  }

  popIndent(ctx);
  emit(ctx, "}");
  emit(ctx, "");
}

// Generate enum declaration
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

// Generate agent declaration
export function genAgent(ctx: Ctx, decl: AST.AgentDecl, opts: GenOpts): void {
  emit(ctx, `class ${decl.name} extends __ms_runtime.Agent {`);
  pushIndent(ctx);

  const bindings = decl.context?.map(c => c.name || "_binding") || [];
  emit(ctx, `constructor(${bindings.join(", ")}) {`);
  pushIndent(ctx);
  emit(ctx, "super();");
  for (const binding of bindings) {
    emit(ctx, `this.${binding} = ${binding};`);
  }
  popIndent(ctx);
  emit(ctx, "}");
  emit(ctx, "");

  if (decl.tools) {
    for (const tool of decl.tools) {
      const params = genParams(ctx, tool.params, opts);
      emit(ctx, `async ${tool.name}(${params}) {`);
      pushIndent(ctx);
      genBlock(ctx, tool.body, opts);
      popIndent(ctx);
      emit(ctx, "}");
      emit(ctx, "");
    }
  }

  if (decl.run) {
    const params = genParams(ctx, decl.run.params, opts);
    emit(ctx, `async run(${params}) {`);
    pushIndent(ctx);
    genBlock(ctx, decl.run.body, opts);
    popIndent(ctx);
    emit(ctx, "}");
  }

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
