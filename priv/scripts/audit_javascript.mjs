import {createHash} from "node:crypto";
import {mkdir, readdir, readFile, stat, writeFile} from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import {fileURLToPath} from "node:url";
import {minify} from "terser";

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const argumentsSet = new Set(process.argv.slice(2));
const checkMode = argumentsSet.has("--check");
const jsonMode = argumentsSet.has("--json");
const outputArgumentIndex = process.argv.indexOf("--output");
const outputPath =
  outputArgumentIndex >= 0 && process.argv[outputArgumentIndex + 1]
    ? path.resolve(projectRoot, process.argv[outputArgumentIndex + 1])
    : null;

const roots = ["assets", "priv/static", "priv/scripts"];
const generatedPatterns = [
  /^priv\/static\/js\/bundle-public-[^/]+\.js$/,
  /^priv\/static\/js\/runtime-config\.js$/,
  /^priv\/static\/assets\/app\.js$/,
  /^priv\/static\/js\/(?:auth-redirect|blotter|image-hover|inline-expanding|manage-forms|mobile-style|navarrows2|options|post-filter|post-hover|poster-id-highlighting|search|show-own-posts-options|webm-settings|youtube)\.js$/,
  /^priv\/static\/js\/options\/(?:general|user-css|user-js)\.js$/
];
const vendorPatterns = [
  /(?:^|\/)jquery(?:-ui\.custom)?\.min\.js$/,
  /(?:^|\/)jquery\.mixitup\.min\.js$/,
  /(?:^|\/)strftime\.min\.js$/,
  /(?:^|\/)ruffle(?:\.min)?\.js$/,
  /(?:^|\/)core\.ruffle\.[A-Za-z0-9]+\.js$/,
  /(?:^|\/)wpaint\.js$/
];

const rules = [
  {
    id: "dynamic-eval",
    severity: "error",
    pattern: /\beval\s*\(|\bnew\s+Function\s*\(/,
    message: "dynamic JavaScript evaluation"
  },
  {
    id: "document-write",
    severity: "error",
    pattern: /\bdocument\.(?:write|writeln)\s*\(/,
    message: "parser-stream document.write usage"
  },
  {
    id: "string-timer",
    severity: "error",
    pattern: /\bset(?:Timeout|Interval)\s*\(\s*["'`]/,
    message: "string-evaluating timer"
  },
  {
    id: "html-sink",
    severity: "warning",
    pattern: /\.innerHTML\s*=|\.insertAdjacentHTML\s*\(|\.html\s*\(/,
    message: "HTML-producing DOM sink; verify the value is fixed or sanitized"
  },
  {
    id: "javascript-url",
    severity: "warning",
    pattern: /javascript\s*:/i,
    message: "javascript: URL"
  },
  {
    id: "weak-randomness",
    severity: "warning",
    pattern: /Math\.random\s*\(/,
    message: "Math.random usage; do not use for credentials or tokens"
  },
  {
    id: "password-storage",
    severity: "warning",
    pattern: /(?:localStorage|sessionStorage)(?:\.|\[[^\]]+\]).{0,80}password|password.{0,80}(?:localStorage|sessionStorage)/is,
    message: "password-like value stored in Web Storage"
  },
  {
    id: "dynamic-script",
    severity: "warning",
    pattern: /createElement\s*\(\s*["']script["']\s*\)/i,
    message: "dynamic script creation or assignment"
  }
];

function slash(relativePath) {
  return relativePath.split(path.sep).join("/");
}

async function walk(relativeDirectory) {
  const absoluteDirectory = path.join(projectRoot, relativeDirectory);
  let entries;

  try {
    entries = await readdir(absoluteDirectory, {withFileTypes: true});
  } catch (error) {
    if (error.code === "ENOENT") return [];
    throw error;
  }

  const files = [];

  for (const entry of entries) {
    if (entry.name === "node_modules" || entry.name === ".git") continue;
    const relativePath = path.join(relativeDirectory, entry.name);

    if (entry.isDirectory()) {
      files.push(...(await walk(relativePath)));
    } else if (entry.isFile() && /\.(?:js|mjs)$/i.test(entry.name)) {
      files.push(slash(relativePath));
    }
  }

  return files;
}

function classify(relativePath) {
  if (generatedPatterns.some((pattern) => pattern.test(relativePath))) return "generated";
  if (vendorPatterns.some((pattern) => pattern.test(relativePath))) return "vendor";
  if (relativePath.startsWith("assets/")) return "maintained-source";
  if (relativePath.startsWith("priv/scripts/")) return "tooling";
  return "legacy-first-party";
}

function hash(contents) {
  return createHash("sha256").update(contents).digest("hex");
}

async function syntaxError(relativePath, contents) {
  try {
    await minify(contents, {
      compress: false,
      mangle: false,
      module: relativePath.endsWith(".mjs"),
      format: {beautify: false}
    });
    return null;
  } catch (error) {
    return `${error.name || "SyntaxError"}: ${error.message}`;
  }
}

const files = (await Promise.all(roots.map(walk))).flat().sort();
const records = [];
const duplicateIndex = new Map();

for (const relativePath of files) {
  const absolutePath = path.join(projectRoot, relativePath);
  const contents = await readFile(absolutePath, "utf8");
  const fileStat = await stat(absolutePath);
  const category = classify(relativePath);
  const digest = hash(contents);
  const findings = [];
  const parseError = await syntaxError(relativePath, contents);

  if (parseError) {
    findings.push({id: "syntax", severity: "error", message: parseError});
  }

  if (category !== "generated" && category !== "vendor" && category !== "tooling") {
    for (const rule of rules) {
      if (rule.pattern.test(contents)) {
        findings.push({id: rule.id, severity: rule.severity, message: rule.message});
      }
    }
  }

  records.push({
    path: relativePath,
    category,
    bytes: fileStat.size,
    sha256: digest,
    findings
  });

  if (category !== "generated") {
    const paths = duplicateIndex.get(digest) || [];
    paths.push(relativePath);
    duplicateIndex.set(digest, paths);
  }
}

const duplicates = Array.from(duplicateIndex.entries())
  .filter(([, paths]) => paths.length > 1)
  .map(([sha256, paths]) => ({sha256, paths}))
  .sort((left, right) => left.paths[0].localeCompare(right.paths[0]));

const errors = records.flatMap((record) =>
  record.findings
    .filter((finding) => finding.severity === "error")
    .map((finding) => ({path: record.path, ...finding}))
);
const warnings = records.flatMap((record) =>
  record.findings
    .filter((finding) => finding.severity === "warning")
    .map((finding) => ({path: record.path, ...finding}))
);
const summary = {
  files: records.length,
  bytes: records.reduce((total, record) => total + record.bytes, 0),
  categories: records.reduce((counts, record) => {
    counts[record.category] = (counts[record.category] || 0) + 1;
    return counts;
  }, {}),
  errors: errors.length,
  warnings: warnings.length,
  duplicate_groups: duplicates.length
};
const report = {format: 1, summary, files: records, duplicates, errors, warnings};

function markdownReport(value) {
  const lines = [
    "# JavaScript inventory and static audit",
    "",
    `Files: **${value.summary.files}**  `,
    `Bytes: **${value.summary.bytes}**  `,
    `Errors: **${value.summary.errors}**  `,
    `Warnings: **${value.summary.warnings}**`,
    "",
    "## Inventory",
    "",
    "| Path | Category | Bytes | Findings |",
    "|---|---:|---:|---:|"
  ];

  for (const record of value.files) {
    lines.push(
      `| \`${record.path}\` | ${record.category} | ${record.bytes} | ${record.findings.length} |`
    );
  }

  lines.push("", "## Findings", "");

  if (value.errors.length === 0 && value.warnings.length === 0) {
    lines.push("No pattern-based findings.");
  } else {
    for (const finding of [...value.errors, ...value.warnings]) {
      lines.push(`- **${finding.severity.toUpperCase()}** \`${finding.path}\`: ${finding.message} (${finding.id})`);
    }
  }

  lines.push("", "## Duplicate files", "");
  if (value.duplicates.length === 0) {
    lines.push("No byte-identical non-generated JavaScript files.");
  } else {
    for (const duplicate of value.duplicates) {
      lines.push(`- ${duplicate.paths.map((item) => `\`${item}\``).join(", ")}`);
    }
  }

  return `${lines.join("\n")}\n`;
}

const rendered = jsonMode ? `${JSON.stringify(report, null, 2)}\n` : markdownReport(report);

if (outputPath) {
  await mkdir(path.dirname(outputPath), {recursive: true});
  await writeFile(outputPath, rendered, "utf8");
} else {
  process.stdout.write(rendered);
}

if (checkMode && errors.length > 0) {
  process.exitCode = 1;
}
