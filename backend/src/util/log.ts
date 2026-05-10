const ts = (): string => new Date().toISOString();

const safeStringify = (ctx: unknown): string => {
  try {
    return JSON.stringify(ctx);
  } catch {
    return String(ctx);
  }
};

const emit = (level: "INFO " | "WARN " | "ERROR", msg: string, ctx?: unknown): void => {
  const tail = ctx === undefined ? "" : " " + safeStringify(ctx);
  console.error(`[${ts()}] ${level} ${msg}${tail}`);
};

export const log = {
  info: (msg: string, ctx?: unknown): void => emit("INFO ", msg, ctx),
  warn: (msg: string, ctx?: unknown): void => emit("WARN ", msg, ctx),
  error: (msg: string, ctx?: unknown): void => emit("ERROR", msg, ctx),
};
