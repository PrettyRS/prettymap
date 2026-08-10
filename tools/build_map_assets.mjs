#!/usr/bin/env node

import childProcess from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { promisify } from "node:util";
import { deduplicateAtlases } from "./map_asset_dedup.mjs";
import { optimizeAtlasPalette } from "./map_asset_palette.mjs";

const args = process.argv.slice(2);
const renderRoot = args.shift();
if (!renderRoot) {
    console.error("Usage: node tools/build_map_assets.mjs <rs3cache-render-output> [plugin-root] --source-version VERSION --source-revision REVISION [--overlay-root PATH] [--resume]");
    process.exit(1);
}
const nestedPluginRoot = path.resolve(import.meta.dirname, "..", "prettymap");
const siblingPluginRoot = path.resolve(import.meta.dirname, "..", "..", "prettymap");
const defaultPluginRoot = fs.existsSync(nestedPluginRoot) ? nestedPluginRoot : siblingPluginRoot;
const pluginRoot = args[0] && !args[0].startsWith("--") ? args.shift() : defaultPluginRoot;
const externalOverlayRoots = [];
let resume = false;
let sourceVersion;
let sourceRevision;
while (args.length > 0) {
    const flag = args.shift();
    if (flag === "--resume") {
        resume = true;
    } else if (flag === "--overlay-root") {
        const root = args.shift();
        if (!root) throw new Error("--overlay-root requires a path");
        externalOverlayRoots.push(path.resolve(root));
    } else if (flag === "--source-version") {
        sourceVersion = args.shift();
        if (!sourceVersion) throw new Error("--source-version requires a value");
    } else if (flag === "--source-revision") {
        sourceRevision = args.shift();
        if (!sourceRevision) throw new Error("--source-revision requires a value");
    } else {
        throw new Error(`Unknown option: ${flag}`);
    }
}
if (!sourceVersion || !sourceRevision) {
    throw new Error("Asset provenance requires --source-version and --source-revision");
}

const SOURCE_SIZE = 256;
const GROUP_SIZE = 4;
const OPTIMIZE_MIN_BYTES = 50_000;
const levels = [
    { zoom: 1, folder: "z1", nativeScale: 2, sourceSpan: 128 },
    { zoom: 3, folder: "z3", nativeScale: 8, sourceSpan: 32 },
];
const excludedFolders = ["zm4", "zm1"];
const sourceLayerCandidates = ["mapsquares", "map_squares"];
const overlayLayerCandidates = ["icon_squares", "map_icon_squares"];
const outputRoot = path.join(pluginRoot, "resources", "maps");
const iconOutputRoot = path.join(pluginRoot, "resources", "map_icons");
const dataPath = path.join(pluginRoot, "data", "map_tiles.lua");
const reportPath = path.join(pluginRoot, "GENERATED_ASSETS.md");
const workRoot = fs.mkdtempSync(path.join(os.tmpdir(), "routefinder-map-assets-"));
const blank = path.join(workRoot, "blank.png");
const execFile = promisify(childProcess.execFile);
const workerCount = Math.max(1, Math.min(os.availableParallelism(), 20));

function firstLine(command, commandArgs) {
    return childProcess.execFileSync(command, commandArgs, { encoding: "utf8" })
        .split(/\r?\n/, 1)[0].trim();
}

function markdownValue(value) {
    return String(value).replaceAll("`", "\\`").replaceAll("\n", " ");
}

function packagedPngSummary() {
    let files = 0;
    let bytes = 0;
    for (const resourceFolder of [outputRoot, iconOutputRoot]) {
        if (!fs.existsSync(resourceFolder)) continue;
        for (const folder of fs.readdirSync(resourceFolder, { withFileTypes: true })) {
            if (!folder.isDirectory()) continue;
            const absoluteFolder = path.join(resourceFolder, folder.name);
            for (const filename of fs.readdirSync(absoluteFolder)) {
                if (!filename.endsWith(".png")) continue;
                files += 1;
                bytes += fs.statSync(path.join(absoluteFolder, filename)).size;
            }
        }
    }
    return { files, bytes };
}

function findLayerRoot(candidates) {
    const layer = candidates.find((candidate) => fs.existsSync(path.join(renderRoot, candidate, "-1")));
    return layer ? { layer, root: path.join(renderRoot, layer, "-1") } : undefined;
}

const sourceLayer = findLayerRoot(sourceLayerCandidates);
if (!sourceLayer) {
    throw new Error(`No world-map raster found under ${renderRoot}; expected ${sourceLayerCandidates.join(" or ")}`);
}
const discoveredOverlayLayers = overlayLayerCandidates
    .map((layer) => ({ layer, root: path.join(renderRoot, layer, "-1") }))
    .filter(({ root }) => fs.existsSync(root));
const overlayLayers = [...discoveredOverlayLayers];
for (const externalRoot of externalOverlayRoots) {
    if (fs.existsSync(path.join(externalRoot, "-1"))) {
        overlayLayers.push({ layer: path.basename(externalRoot), root: path.join(externalRoot, "-1") });
        continue;
    }
    let foundLayer = false;
    for (const layer of overlayLayerCandidates) {
        const root = path.join(externalRoot, layer, "-1");
        if (fs.existsSync(root)) {
            overlayLayers.push({ layer, root });
            foundLayer = true;
        }
    }
    if (!foundLayer) {
        throw new Error(`No icon_squares/-1 or map_icon_squares/-1 layer found under ${externalRoot}`);
    }
}
const uniqueOverlayLayers = [...new Map(
    overlayLayers.map((entry) => [path.resolve(entry.root), entry]),
).values()];

async function montage(inputs, target) {
    await execFile("magick", [
        "montage", ...inputs,
        "-background", "none",
        "-tile", `${GROUP_SIZE}x${GROUP_SIZE}`,
        "-geometry", `${SOURCE_SIZE}x${SOURCE_SIZE}+0+0`,
        "-depth", "8",
        target,
    ]);
}

async function processConcurrently(items, callback) {
    let nextIndex = 0;
    const worker = async () => {
        while (nextIndex < items.length) {
            const item = items[nextIndex];
            nextIndex += 1;
            await callback(item);
        }
    };
    await Promise.all(Array.from({ length: Math.min(workerCount, items.length) }, worker));
}

async function validateAndOptimizeAtlas(target) {
    const before = fs.statSync(target).size;
    if (before === 0) throw new Error(`Generated an empty map atlas: ${target}`);

    if (before >= OPTIMIZE_MIN_BYTES) {
        await execFile("optipng", ["-quiet", "-o2", target]);
    } else {
        // The simulation still decodes and validates small files without spending
        // more build time on atlases where compression gains are negligible.
        await execFile("optipng", ["-quiet", "-simulate", "-o0", target]);
    }

    const after = fs.statSync(target).size;
    if (after === 0) {
        throw new Error(`Map atlas became empty during optimization: ${target}`);
    }
    return Math.max(0, before - after);
}

childProcess.execFileSync("magick", ["-size", `${SOURCE_SIZE}x${SOURCE_SIZE}`, "xc:none", blank]);
if (!resume) {
    fs.rmSync(outputRoot, { recursive: true, force: true });
    fs.rmSync(iconOutputRoot, { recursive: true, force: true });
}
fs.mkdirSync(outputRoot, { recursive: true });
fs.mkdirSync(iconOutputRoot, { recursive: true });
for (const folder of excludedFolders) {
    fs.rmSync(path.join(outputRoot, folder), { recursive: true, force: true });
    fs.rmSync(path.join(iconOutputRoot, folder), { recursive: true, force: true });
}
fs.mkdirSync(path.dirname(dataPath), { recursive: true });

const lua = ["-- Generated by tools/build_map_assets.mjs; do not edit by hand.", "return {", "    levels = {"];
let atlasCount = 0;
let optimizedBytesSaved = 0;
let duplicateCount = 0;
let duplicateBytesSaved = 0;
let paletteCount = 0;
let paletteBytesSaved = 0;

try {
    for (const level of levels) {
        const sourceFolder = path.join(sourceLayer.root, String(level.zoom));
        if (!fs.existsSync(sourceFolder)) {
            throw new Error(`Missing zoom ${level.zoom} source folder: ${sourceFolder}`);
        }
        const overlayFolders = uniqueOverlayLayers
            .map(({ layer, root }) => ({ layer, folder: path.join(root, String(level.zoom)) }))
            .filter(({ folder }) => fs.existsSync(folder));
        const outputFolder = path.join(outputRoot, level.folder);
        fs.mkdirSync(outputFolder, { recursive: true });

        const collectGroups = (folders) => {
            const groups = new Map();
            for (const folder of folders) {
                for (const filename of fs.readdirSync(folder)) {
                    const match = filename.match(/^(\d+)_(\d+)_(\d+)\.png$/);
                    if (!match) continue;
                    const plane = Number(match[1]);
                    const x = Number(match[2]);
                    const z = Number(match[3]);
                    const atlasX = Math.floor(x / GROUP_SIZE);
                    const atlasZ = Math.floor(z / GROUP_SIZE);
                    groups.set(`${plane}:${atlasX}:${atlasZ}`, { plane, atlasX, atlasZ });
                }
            }
            return groups;
        };
        const groups = collectGroups([sourceFolder]);
        const iconGroups = collectGroups(overlayFolders.map(({ folder }) => folder));
        const orderedGroups = (groupMap) => [...groupMap.values()].sort((left, right) =>
            left.plane - right.plane || left.atlasX - right.atlasX || left.atlasZ - right.atlasZ);
        const ordered = orderedGroups(groups);
        const orderedIcons = orderedGroups(iconGroups);
        await processConcurrently(ordered, async (group) => {
            const inputs = [];
            for (let localZ = GROUP_SIZE - 1; localZ >= 0; localZ -= 1) {
                for (let localX = 0; localX < GROUP_SIZE; localX += 1) {
                    const filename = `${group.plane}_${group.atlasX * GROUP_SIZE + localX}_${group.atlasZ * GROUP_SIZE + localZ}.png`;
                    const source = path.join(sourceFolder, filename);
                    inputs.push(fs.existsSync(source) ? source : blank);
                }
            }
            const target = path.join(outputFolder, `${group.plane}_${group.atlasX}_${group.atlasZ}.png`);
            if (!(resume && fs.existsSync(target))) {
                await montage(inputs, target);
            }
            optimizedBytesSaved += await validateAndOptimizeAtlas(target);
            const palette = await optimizeAtlasPalette(target);
            if (palette.converted) {
                paletteCount += 1;
                paletteBytesSaved += palette.bytesSaved;
            }
            atlasCount += 1;
        });

        const atlasEntries = ordered.map((group) => ({
            group,
            filename: `${group.plane}_${group.atlasX}_${group.atlasZ}.png`,
        }));
        const deduplication = deduplicateAtlases(outputFolder, atlasEntries);
        duplicateCount += deduplication.duplicateCount;
        duplicateBytesSaved += deduplication.bytesSaved;
        const expectedAtlases = new Set();
        for (const entry of atlasEntries) {
            entry.group.resourceFilename = entry.resourceFilename;
            expectedAtlases.add(entry.resourceFilename);
        }
        for (const filename of fs.readdirSync(outputFolder)) {
            if (filename.endsWith(".png") && !expectedAtlases.has(filename)) {
                fs.rmSync(path.join(outputFolder, filename));
            }
        }

        lua.push(`        { zoom = ${level.zoom}, folder = "${level.folder}", nativeScale = ${level.nativeScale}, span = ${level.sourceSpan * GROUP_SIZE}, available = {`);
        for (const group of ordered) {
            const defaultFilename = `${group.plane}_${group.atlasX}_${group.atlasZ}.png`;
            const value = group.resourceFilename === defaultFilename
                ? "true"
                : `"${group.resourceFilename}"`;
            lua.push(`            ["${group.plane}:${group.atlasX}:${group.atlasZ}"] = ${value},`);
        }
        lua.push("        }, icons = {");

        const iconOutputFolder = path.join(iconOutputRoot, level.folder);
        fs.mkdirSync(iconOutputFolder, { recursive: true });
        await processConcurrently(orderedIcons, async (group) => {
            const target = path.join(iconOutputFolder, `icon_${group.plane}_${group.atlasX}_${group.atlasZ}.png`);
            if (!(resume && fs.existsSync(target))) {
                let rendered = false;
                for (let overlayIndex = 0; overlayIndex < overlayFolders.length; overlayIndex += 1) {
                    const { folder } = overlayFolders[overlayIndex];
                    const inputs = [];
                    let hasOverlay = false;
                    for (let localZ = GROUP_SIZE - 1; localZ >= 0; localZ -= 1) {
                        for (let localX = 0; localX < GROUP_SIZE; localX += 1) {
                            const filename = `${group.plane}_${group.atlasX * GROUP_SIZE + localX}_${group.atlasZ * GROUP_SIZE + localZ}.png`;
                            const source = path.join(folder, filename);
                            const exists = fs.existsSync(source);
                            hasOverlay ||= exists;
                            inputs.push(exists ? source : blank);
                        }
                    }
                    if (!hasOverlay) continue;
                    if (!rendered) {
                        await montage(inputs, target);
                        rendered = true;
                    } else {
                        const overlayAtlas = path.join(
                            workRoot,
                            `${level.folder}_${group.plane}_${group.atlasX}_${group.atlasZ}_${overlayIndex}.png`,
                        );
                        await montage(inputs, overlayAtlas);
                        await execFile("magick", [target, overlayAtlas, "-compose", "over", "-composite", target]);
                    }
                }
                if (!rendered) throw new Error(`No icon source found for atlas ${target}`);
            }
            optimizedBytesSaved += await validateAndOptimizeAtlas(target);
            const palette = await optimizeAtlasPalette(target);
            if (palette.converted) {
                paletteCount += 1;
                paletteBytesSaved += palette.bytesSaved;
            }
            atlasCount += 1;
        });

        const iconEntries = orderedIcons.map((group) => ({
            group,
            filename: `icon_${group.plane}_${group.atlasX}_${group.atlasZ}.png`,
        }));
        const iconDeduplication = deduplicateAtlases(iconOutputFolder, iconEntries);
        duplicateCount += iconDeduplication.duplicateCount;
        duplicateBytesSaved += iconDeduplication.bytesSaved;
        const expectedIconAtlases = new Set();
        for (const entry of iconEntries) {
            entry.group.resourceFilename = entry.resourceFilename;
            expectedIconAtlases.add(entry.resourceFilename);
        }
        for (const filename of fs.readdirSync(iconOutputFolder)) {
            if (filename.endsWith(".png") && !expectedIconAtlases.has(filename)) {
                fs.rmSync(path.join(iconOutputFolder, filename));
            }
        }
        for (const group of orderedIcons) {
            const defaultFilename = `icon_${group.plane}_${group.atlasX}_${group.atlasZ}.png`;
            const value = group.resourceFilename === defaultFilename
                ? "true"
                : `"${group.resourceFilename}"`;
            lua.push(`            ["${group.plane}:${group.atlasX}:${group.atlasZ}"] = ${value},`);
        }
        lua.push("        } },");
    }
} finally {
    fs.rmSync(workRoot, { recursive: true, force: true });
}

lua.push("    },", "}", "");
fs.writeFileSync(dataPath, lua.join("\n"));
const manifestChecksum = crypto.createHash("sha256")
    .update(fs.readFileSync(dataPath)).digest("hex");
const packaged = packagedPngSummary();
const generatedAt = new Date().toISOString();
const generatorCommand = "node tools/build_map_assets.mjs <rs3cache-render-output> . "
    + `--source-version ${sourceVersion} --source-revision ${sourceRevision}`;
const report = [
    "# Generated asset provenance",
    "",
    "Files below `resources/maps`, `resources/map_icons`, and `data/map_tiles.lua` ",
    "are generated by `tools/build_map_assets.mjs`; do not edit them by hand.",
    "",
    "| Field | Value |",
    "| --- | --- |",
    `| Source renderer/cache version | \`${markdownValue(sourceVersion)}\` |`,
    `| Source revision/checksum | \`${markdownValue(sourceRevision)}\` |`,
    `| Generation date | ${generatedAt} |`,
    `| Node.js | ${process.version} |`,
    `| ImageMagick | ${markdownValue(firstLine("magick", ["-version"]))} |`,
    `| optipng | ${markdownValue(firstLine("optipng", ["-version"]))} |`,
    `| Generator command | \`${markdownValue(generatorCommand)}\` |`,
    `| Logical tile count | ${atlasCount.toLocaleString("en-US")} |`,
    `| Unique PNG count | ${packaged.files.toLocaleString("en-US")} |`,
    `| Deduplicated file count | ${duplicateCount.toLocaleString("en-US")} |`,
    `| Total packaged PNG bytes | ${packaged.bytes.toLocaleString("en-US")} |`,
    `| Manifest SHA-256 | \`${manifestChecksum}\` |`,
    "| Validation result | PASS: PNG decoding, optimization, deduplication, output pruning, and deterministic manifest generation completed |",
    "",
    "Run `./tests/run_tests.sh` after generation to verify references, dimensions,",
    "traversal safety, ordering, and the absence of unexpected assets.",
    "",
].join("\n");
fs.writeFileSync(reportPath, report);
console.log(
    `Built ${atlasCount} continuous-map atlases in ${path.join(pluginRoot, "resources")}; `
    + `packaged ${uniqueOverlayLayers.length} optional icon layer(s); `
    + `lossless optimization saved ${(optimizedBytesSaved / 1024 / 1024).toFixed(2)} MiB; `
    + `palette optimization saved ${(paletteBytesSaved / 1024 / 1024).toFixed(2)} MiB `
    + `across ${paletteCount} newly indexed atlases; `
    + `deduplicated ${duplicateCount} atlases (${(duplicateBytesSaved / 1024 / 1024).toFixed(2)} MiB)`,
);
