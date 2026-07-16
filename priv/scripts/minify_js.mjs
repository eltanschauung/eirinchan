import {createHash} from "node:crypto";
import {mkdir, readFile, rename, rm, writeFile} from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import {minify} from "terser";

function parseArguments(argv) {
  const options = {label: "javascript", output: null, sources: []};

  for (let index = 0; index < argv.length; index += 1) {
    const value = argv[index];

    if (value === "--output") {
      options.output = argv[++index];
    } else if (value === "--label") {
      options.label = argv[++index] || options.label;
    } else if (value === "--") {
      options.sources.push(...argv.slice(index + 1));
      break;
    } else {
      options.sources.push(value);
    }
  }

  if (!options.output || options.sources.length === 0) {
    throw new Error("usage: minify_js.mjs --output PATH [--label NAME] -- SOURCE...");
  }

  return options;
}

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

async function atomicWrite(destination, contents) {
  await mkdir(path.dirname(destination), {recursive: true});
  const temporary = `${destination}.tmp-${process.pid}-${Date.now()}`;

  try {
    await writeFile(temporary, contents, {encoding: "utf8", mode: 0o644});
    await rename(temporary, destination);
  } catch (error) {
    await rm(temporary, {force: true}).catch(() => undefined);
    throw error;
  }
}

const options = parseArguments(process.argv.slice(2));
const sourceParts = [];

for (const sourcePath of options.sources) {
  const source = await readFile(sourcePath, "utf8");
  sourceParts.push(`/* ${path.basename(sourcePath)} */\n${source.trim()}\n;`);
}

const input = sourceParts.join("\n");
const result = await minify(input, {
  compress: {
    arrows: false,
    booleans_as_integers: false,
    defaults: true,
    drop_console: false,
    passes: 2,
    pure_getters: false,
    unsafe: false
  },
  ecma: 2018,
  mangle: {
    keep_classnames: true,
    safari10: true
  },
  module: false,
  safari10: true,
  sourceMap: false,
  toplevel: false,
  format: {
    ascii_only: true,
    comments: /^!|@license|@preserve/i,
    semicolons: true
  }
});

if (!result.code) {
  throw new Error(`Terser produced no output for ${options.label}`);
}

const output = `${result.code}\n`;
await atomicWrite(options.output, output);

process.stdout.write(
  JSON.stringify({
    label: options.label,
    output: options.output,
    sources: options.sources,
    source_bytes: Buffer.byteLength(input),
    output_bytes: Buffer.byteLength(output),
    sha256: sha256(output)
  }) + "\n"
);
