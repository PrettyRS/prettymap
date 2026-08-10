#!/usr/bin/env node

import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

function fingerprint(filePath) {
    const contents = fs.readFileSync(filePath);
    return `${contents.length}:${crypto.createHash("sha256").update(contents).digest("hex")}`;
}

export function deduplicateAtlases(outputFolder, entries) {
    const canonicalByFingerprint = new Map();
    const canonicalByFilename = new Map();
    let duplicateCount = 0;
    let bytesSaved = 0;

    for (const entry of entries) {
        const filename = entry.filename;
        const knownCanonical = canonicalByFilename.get(filename);
        if (knownCanonical) {
            entry.resourceFilename = knownCanonical;
            continue;
        }

        const filePath = path.join(outputFolder, filename);
        const fileFingerprint = fingerprint(filePath);
        const canonical = canonicalByFingerprint.get(fileFingerprint);
        if (canonical) {
            bytesSaved += fs.statSync(filePath).size;
            fs.rmSync(filePath);
            duplicateCount += 1;
            canonicalByFilename.set(filename, canonical);
            entry.resourceFilename = canonical;
        } else {
            canonicalByFingerprint.set(fileFingerprint, filename);
            canonicalByFilename.set(filename, filename);
            entry.resourceFilename = filename;
        }
    }

    return { duplicateCount, bytesSaved };
}

export function deduplicateManifestAssets(pluginRoot) {
    const dataPath = path.join(pluginRoot, "data", "map_tiles.lua");
    const lines = fs.readFileSync(dataPath, "utf8").split("\n");
    const entriesByFolder = new Map();
    let currentFolder;
    let currentResourceFolder = "maps";

    for (let index = 0; index < lines.length; index += 1) {
        const folderMatch = lines[index].match(/folder = "([^"]+)"/);
        if (folderMatch) {
            currentFolder = folderMatch[1];
            currentResourceFolder = "maps";
            const groupKey = `${currentResourceFolder}/${currentFolder}`;
            if (!entriesByFolder.has(groupKey)) entriesByFolder.set(groupKey, []);
            continue;
        }
        if (!currentFolder) continue;
        if (lines[index].includes("}, icons = {")) {
            currentResourceFolder = "map_icons";
            const groupKey = `${currentResourceFolder}/${currentFolder}`;
            if (!entriesByFolder.has(groupKey)) entriesByFolder.set(groupKey, []);
            continue;
        }

        const entryMatch = lines[index].match(/^\s*\["(\d+):(\d+):(\d+)"\] = (true|"([^"]+)")/);
        if (!entryMatch) continue;
        const prefix = currentResourceFolder === "map_icons" ? "icon_" : "";
        const defaultFilename = `${prefix}${entryMatch[1]}_${entryMatch[2]}_${entryMatch[3]}.png`;
        entriesByFolder.get(`${currentResourceFolder}/${currentFolder}`).push({
            lineIndex: index,
            defaultFilename,
            filename: entryMatch[5] || defaultFilename,
        });
    }

    let duplicateCount = 0;
    let bytesSaved = 0;
    for (const [folder, entries] of entriesByFolder) {
        const result = deduplicateAtlases(
            path.join(pluginRoot, "resources", folder),
            entries,
        );
        duplicateCount += result.duplicateCount;
        bytesSaved += result.bytesSaved;
        for (const entry of entries) {
            const value = entry.resourceFilename === entry.defaultFilename
                ? "true"
                : `"${entry.resourceFilename}"`;
            lines[entry.lineIndex] = lines[entry.lineIndex].replace(/= (true|"[^"]+")/, `= ${value}`);
        }
    }

    fs.writeFileSync(dataPath, lines.join("\n"));
    return { duplicateCount, bytesSaved };
}

const invokedPath = process.argv[1] && path.resolve(process.argv[1]);
if (invokedPath === fileURLToPath(import.meta.url)) {
    const pluginRoot = process.argv[2];
    if (!pluginRoot) {
        console.error("Usage: node tools/map_asset_dedup.mjs <prettymap-root>");
        process.exit(1);
    }
    const result = deduplicateManifestAssets(path.resolve(pluginRoot));
    console.log(
        `Removed ${result.duplicateCount} duplicate map atlases; `
        + `saved ${(result.bytesSaved / 1024 / 1024).toFixed(2)} MiB`,
    );
}
