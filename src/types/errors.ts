// Type Check Error - Shared error class for type checking
import type { SourceLocation } from "../parser/ast";

export class TypeCheckError extends Error {
  constructor(
    message: string,
    public loc: SourceLocation,
    public hint?: string
  ) {
    super(`${message} at line ${loc.line}, column ${loc.column}`);
    this.name = "TypeCheckError";
  }
}
