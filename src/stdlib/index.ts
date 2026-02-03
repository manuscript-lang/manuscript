// Stdlib module - imports source from stdlib.ms at build time
import stdlibSourceContent from "./stdlib.ms" with { type: "text" };

export const STDLIB_PATH_URI = `manuscript://stdlib.ms`;
export const stdlibSource = stdlibSourceContent;
