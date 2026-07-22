#!/usr/bin/env node
/*
 * qbjs-compile.js  --  headless QBJS compiler (BASIC -> JavaScript)
 *
 *   node qbjs-compile.js <input.bas> <output.js>
 *
 * This is a hardened drop-in for the upstream `qbc.js`. It behaves the same
 * (transpile a .bas file to a program.js that defines async __qbjs_run()), but
 * fixes two things that matter for local builds and CI:
 *
 *   1. func_Abs patch. In v0.11.1 the Node-side runtime (qb-console.js) is
 *      missing QB.func_Abs, which the compiler itself calls while converting
 *      integer division ("\"). Without it, ANY program using "\" crashes the
 *      compiler. QB is a Node global (see qb2js.js: `QB = require(...)` with no
 *      `var`), so we augment it here -- guarded, so it self-heals if upstream
 *      adds the function later. We never modify the upstream files.
 *
 *   2. Exit codes. Upstream qbc.js always exits 0, even on "File not found" or
 *      syntax errors -- so a broken build looks green in CI. This wrapper exits
 *      non-zero when the build should be considered failed (see shouldFailBuild).
 *
 * Errors/warnings are printed as:  ERROR:<line>:<text>  or  WARN:<line>:<text>
 * (the format the profile's tasks.json problemMatcher understands).
 */

"use strict";

const fs = require("fs");
const path = require("path");

// --- Missing compile-time helpers, patched onto the Node global QB ----------
// Only the helpers the COMPILER invokes on itself belong here (pure functions).
// Runtime helpers used by the *generated* program run in the browser's full
// qb.js, so they must NOT be shimmed here.
const QB_PATCHES = {
  func_Abs: (v) => Math.abs(v)
};

function patchConsoleQB(QB) {
  if (!QB) { return; }
  for (const name of Object.keys(QB_PATCHES)) {
    if (typeof QB[name] !== "function") {
      QB[name] = QB_PATCHES[name];
    }
  }
}

// --- CI failure policy -------------------------------------------------------
// DECISION POINT: what counts as a failed build?
//
// `warnings` is the array from qbc.getWarnings(); each entry has:
//   { line: <number>, text: <string>, mtype: <0 = warning, 1 = error> }
//
// Default policy: fail only on hard errors (mtype === 1), let plain warnings
// through. Set QBJS_STRICT=1 to also fail on warnings (recommended for CI on a
// release branch, where a warning often means an unsupported feature slipped in).
//
// Tune this to taste -- it's the one place your project's quality bar lives.
function shouldFailBuild(warnings) {
  const strict = process.env.QBJS_STRICT === "1";
  return warnings.some((w) => w.mtype === 1 || (strict && w.mtype === 0));
}

async function main() {
  const [, , sourceFile, outFile] = process.argv;
  if (!sourceFile || !outFile) {
    console.error("Usage: node qbjs-compile.js <input.bas> <output.js>");
    process.exit(2);
  }
  if (!fs.existsSync(sourceFile)) {
    console.error(`ERROR:0:Source file not found: ${sourceFile}`);
    process.exit(2);
  }

  // Requiring qb2js.js sets the Node global QB (to the qb-console.js runtime).
  const compilerModule = require("./qb2js.js");
  patchConsoleQB(global.QB);

  const qbc = await compilerModule.QBCompiler();
  const data = fs.readFileSync(sourceFile, "utf8");

  let result;
  if (sourceFile.endsWith("qb2js.bas")) {
    // Special case: recompiling the compiler itself.
    qbc.setSelfConvert();
    result = await qbc.compile(data);
  } else {
    result = "async function __qbjs_run() {\n" + (await qbc.compile(data)) + "\n}";
  }

  fs.mkdirSync(path.dirname(path.resolve(outFile)), { recursive: true });
  fs.writeFileSync(outFile, result, "utf8");

  const warnings = qbc.getWarnings();
  let errorCount = 0;
  for (const w of warnings) {
    const level = w.mtype ? "ERROR" : "WARN";
    if (w.mtype) { errorCount++; }
    console.log(`${level}:${w.line}:${w.text}`);
  }

  if (shouldFailBuild(warnings)) {
    console.error(`Build failed: ${errorCount} error(s).`);
    process.exit(1);
  }
  console.error(`Compiled ${path.basename(sourceFile)} -> ${outFile}` +
    (warnings.length ? ` (${warnings.length} message(s))` : ""));
}

main().catch((err) => {
  console.error("ERROR:0:" + (err && err.stack ? err.stack : err));
  process.exit(1);
});
