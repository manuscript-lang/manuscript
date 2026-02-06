import type { Pass, PassContext } from "../pass-manager";
import { collectDeclarations } from "./collect-declarations";

export class CollectDeclarationsPass implements Pass {
  name = "collect-declarations";

  run(ctx: PassContext): void {
    const result = collectDeclarations({ program: ctx.program, env: ctx.env });
    ctx.env = result.env;
    ctx.fnDecls = result.fnDecls;
    ctx.errors.push(...result.errors);
  }
}
