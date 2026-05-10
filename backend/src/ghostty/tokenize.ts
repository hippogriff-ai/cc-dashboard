const STOPWORDS = new Set([
  "the","a","an","is","are","was","were","to","of","for","in","on","at","by",
  "and","or","i","me","my","you","we","it","this","that","from","with","can",
  "how","what","do","does","be","been","has","have","had","will","would","should",
  "but","not","if","so","as","about","into","out","up","down","over","under",
  "just","please","want","need","here","there","now","then","some","any","all",
  "new","like","get","got","let","make","made","use","used","using","way","one",
]);

export function tokenize(text: string | undefined): Set<string> {
  if (!text) return new Set();
  // Strip diacritics: NFKD + remove non-ASCII
  let s = text.normalize("NFKD").replace(/[^\u0000-\u007f]/g, "");
  // Strip URL %-encoding before lowercasing
  s = s.replace(/%[0-9a-fA-F]{2}/g, " ").toLowerCase();
  s = s.replace(/[^a-z0-9\s]/g, " ");
  const out = new Set<string>();
  for (const w of s.split(/\s+/)) {
    if (w.length >= 3 && !/^\d+$/.test(w) && !STOPWORDS.has(w)) out.add(w);
  }
  return out;
}
