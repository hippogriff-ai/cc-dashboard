// backend/src/util/ide.ts
import { existsSync } from "node:fs";

const IDE_PRIORITY: [string, string][] = [
  ["Cursor", "Cursor"],
  ["Visual Studio Code", "VS Code"],
  ["Zed", "Zed"],
  ["Windsurf", "Windsurf"],
  ["Sublime Text", "Sublime Text"],
  ["WebStorm", "WebStorm"],
  ["PyCharm", "PyCharm"],
  ["GoLand", "GoLand"],
  ["Rider", "Rider"],
  ["CLion", "CLion"],
  ["Xcode", "Xcode"],
];

export function detectIde(): { bundle: string; display: string } {
  const override = (process.env.CC_DASH_IDE ?? "").trim();
  if (override) return { bundle: override, display: override };
  for (const [bundle, display] of IDE_PRIORITY) {
    if (existsSync(`/Applications/${bundle}.app`)) return { bundle, display };
  }
  return { bundle: "", display: "Finder" };
}
