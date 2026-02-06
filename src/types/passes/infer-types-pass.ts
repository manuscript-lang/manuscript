import type { Pass, PassContext } from "../pass-manager";
import { inferTypes } from "./infer-types";

export class InferTypesPass implements Pass {
  name = "infer-types";

  run(ctx: PassContext): void {
    const result = inferTypes({
      program: ctx.program,
      env: ctx.env,
      fnDecls: ctx.fnDecls,
    });
    ctx.errors.push(...result.errors);
    ctx.warnings.push(...result.warnings);
  }
}
