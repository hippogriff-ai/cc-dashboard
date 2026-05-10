export interface ScoreResult {
  score: number;
  hits: string[];
  early_hits: string[];
  recent_hits: string[];
  cwd_hits: string[];
}

export function scoreWindow(
  windowTokens: Set<string>,
  earlyTokens: Set<string>,
  recentTokens: Set<string>,
  cwdTokens: Set<string>,
): ScoreResult {
  const inter = (a: Set<string>, b: Set<string>): Set<string> => {
    const r = new Set<string>();
    for (const v of a) if (b.has(v)) r.add(v);
    return r;
  };
  const earlyHit = inter(windowTokens, earlyTokens);
  const recentHit = inter(windowTokens, recentTokens);
  const cwdHit = inter(windowTokens, cwdTokens);

  const counted = new Set<string>();
  let score = 0;
  for (const t of earlyHit) if (!counted.has(t)) { score += 3; counted.add(t); }
  for (const t of cwdHit) if (!counted.has(t)) { score += 2; counted.add(t); }
  for (const t of recentHit) if (!counted.has(t)) { score += 1; counted.add(t); }

  const sortS = (s: Set<string>): string[] => [...s].sort();
  return {
    score,
    hits: sortS(counted),
    early_hits: sortS(earlyHit),
    recent_hits: sortS(new Set([...recentHit].filter((t) => !earlyHit.has(t)))),
    cwd_hits: sortS(new Set([...cwdHit].filter((t) => !earlyHit.has(t)))),
  };
}
