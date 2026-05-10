// backend/src/corpus/projections.ts
// Projection registry. Decision Log is the first concrete projection;
// future projections (gotchas, prompts-that-worked) plug in here.

import type { CorpusState, DecisionPair } from "./indices.ts";

export interface Projection<T> {
  name: string;
  query: (state: CorpusState, cwd: string) => T;
}

export const decisionsProjection: Projection<DecisionPair[]> = {
  name: "decisions",
  query: (state, cwd) => state.decisionsByCwd.get(cwd) ?? [],
};

export const REGISTRY: { [name: string]: Projection<unknown> } = {
  [decisionsProjection.name]: decisionsProjection as Projection<unknown>,
};
