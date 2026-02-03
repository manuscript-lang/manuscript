export * from "./types";
export * from "./environment";
export * from "./checker";

// New modular exports (pass-based architecture)
export { TypeCheckError } from "./errors";
export {
  PassManager,
  CollectDeclarationsPass,
  InferTypesPass,
  ContextAnalysisPass,
  type Pass,
  type PassContext,
} from "./pass-manager";
export * from "./type-utils";
export * from "./ast-visitor";
