#!/usr/bin/env node

import childProcess from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";
import { deduplicateManifestAssets } from "./map_asset_dedup.mjs";

const execFile = promisify(childProcess.execFile);
const workerCount = Math.max(1, Math.min(os.availableParallelism(), 12));

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

function isIndexedPng(target) {
    const header = Buffer.alloc(26);
    const descriptor = fs.openSync(target, "r");
    try {
        if (fs.readSync(descriptor, header, 0, header.length, 0) !== header.length) {
            throw new Error(`PNG header is truncated: ${target}`);
        }
    } finally {
        fs.closeSync(descriptor);
    }
    if (!header.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]))) {
        throw new Error(`Invalid PNG signature: ${target}`);
    }
    return header[25] === 3;
}

export async function optimizeAtlasPalette(target) {
    const before = fs.statSync(target).size;
    if (isIndexedPng(target)) {
        return { converted: false, alreadyIndexed: true, bytesSaved: 0 };
    }

    const candidate = path.join(
        path.dirname(target),
        `.${path.basename(target, ".png")}.${process.pid}.palette.png`,
    );
    try {
        await execFile("magick", [
            target,
            "-dither", "None",
            "-colors", "256",
            `PNG8:${candidate}`,
        ]);
        await execFile("optipng", ["-quiet", "-o2", candidate]);
        const after = fs.statSync(candidate).size;
        fs.renameSync(candidate, target);
        return { converted: true, alreadyIndexed: false, bytesSaved: before - after };
    } finally {
        fs.rmSync(candidate, { force: true });
    }
}

export async function optimizePluginPalette(pluginRoot) {
    const mapRoot = path.join(pluginRoot, "resources", "maps");
    const targets = [];
    for (const folder of ["z1", "z3"]) {
        const folderPath = path.join(mapRoot, folder);
        for (const filename of fs.readdirSync(folderPath)) {
            if (/^\d+_\d+_\d+\.png$/.test(filename)) {
                targets.push(path.join(folderPath, filename));
            }
        }
    }

    const summary = { total: targets.length, alreadyIndexed: 0, converted: 0, bytesSaved: 0 };
    await processConcurrently(targets, async (target) => {
        const result = await optimizeAtlasPalette(target);
        if (result.alreadyIndexed) {
            summary.alreadyIndexed += 1;
            return;
        }
        summary.converted += 1;
        summary.bytesSaved += result.bytesSaved;
    });
    return summary;
}

const invokedPath = process.argv[1] && path.resolve(process.argv[1]);
if (invokedPath === fileURLToPath(import.meta.url)) {
    const pluginRoot = process.argv[2];
    if (!pluginRoot) {
        console.error("Usage: node tools/map_asset_palette.mjs <prettymap-root>");
        process.exit(1);
    }
    const resolvedRoot = path.resolve(pluginRoot);
    const palette = await optimizePluginPalette(resolvedRoot);
    const deduplication = deduplicateManifestAssets(resolvedRoot);
    console.log(
        `Encoded all ${palette.total} atlases as PNG8 `
        + `(${palette.converted} converted, ${palette.alreadyIndexed} already indexed); `
        + `net saving ${(palette.bytesSaved / 1024 / 1024).toFixed(2)} MiB; `
        + `deduplicated ${deduplication.duplicateCount} additional atlases `
        + `(${(deduplication.bytesSaved / 1024 / 1024).toFixed(2)} MiB)`,
    );
}
