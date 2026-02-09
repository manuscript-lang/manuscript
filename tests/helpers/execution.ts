// E2E Test Execution Helpers
import { compile, check } from "../../src/compile";
import { __ms_runtime } from "../../src/runtime/runtime";

/**
 * Execute compiled Manuscript code and return the result
 */
export async function execute(source: string): Promise<any> {
  const result = compile(source, { emitRuntimeImport: false });
  if (!result.success) {
    throw new Error(result.errors.map(e => e.message).join("\n"));
  }
  
  const wrappedCode = `const __ms_runtime = arguments[0];
return (async () => {
${result.code}
})();`;
  const fn = new Function(wrappedCode);
  return await fn(__ms_runtime);
}

/**
 * Execute and capture printed output
 */
// Format a value for output (similar to how Manuscript would display it)
function formatValue(val: any): string {
  if (val === null) return "null";
  if (val === undefined) return "undefined";
  if (Array.isArray(val)) {
    return "[" + val.map(formatValue).join(", ") + "]";
  }
  if (typeof val === "object") {
    const entries = Object.entries(val).map(([k, v]) => `${k}: ${formatValue(v)}`);
    return "{" + entries.join(", ") + "}";
  }
  return String(val);
}

export async function executeWithOutput(source: string): Promise<{ result: any; output: string[] }> {
  const output: string[] = [];
  const mockRuntime = {
    ...__ms_runtime,
    print: (...args: any[]) => output.push(args.map(formatValue).join(" ")),
    log: (...args: any[]) => output.push(args.map(formatValue).join(" ")),
  };
  
  const result = compile(source, { emitRuntimeImport: false });
  if (!result.success) {
    throw new Error(result.errors.map(e => e.message).join("\n"));
  }
  
  const wrappedCode = `const __ms_runtime = arguments[0];
return (async () => {
${result.code}
})();`;
  const fn = new Function(wrappedCode);
  const returnValue = await fn(mockRuntime);
  
  return { result: returnValue, output };
}

/**
 * Check if code compiles successfully
 */
export function compiles(source: string, typeCheck: boolean = true): boolean {
  const result = compile(source, { emitRuntimeImport: false, typeCheck });
  return result.success;
}

/**
 * Get compilation errors
 */
export function getErrors(source: string, typeCheck: boolean = true): string[] {
  const result = compile(source, { emitRuntimeImport: false, typeCheck });
  return result.errors.map(e => e.message);
}

/**
 * Execute code without type checking
 */
export async function executeWithOutputNoTypeCheck(source: string): Promise<{ result: any; output: string[] }> {
  const output: string[] = [];
  const mockRuntime = {
    ...__ms_runtime,
    print: (...args: any[]) => output.push(args.map(formatValue).join(" ")),
    log: (...args: any[]) => output.push(args.map(formatValue).join(" ")),
  };
  
  const result = compile(source, { emitRuntimeImport: false, typeCheck: false });
  if (!result.success) {
    throw new Error(result.errors.map(e => e.message).join("\n"));
  }
  
  const wrappedCode = `const __ms_runtime = arguments[0];
return (async () => {
${result.code}
})();`;
  const fn = new Function(wrappedCode);
  const returnValue = await fn(mockRuntime);
  
  return { result: returnValue, output };
}

/**
 * Check if code has a specific error type
 */
export function hasError(source: string, errorPattern: string | RegExp): boolean {
  const errors = getErrors(source);
  if (typeof errorPattern === "string") {
    return errors.some(e => e.includes(errorPattern));
  }
  return errors.some(e => errorPattern.test(e));
}
