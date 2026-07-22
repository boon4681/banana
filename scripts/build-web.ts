import { execFileSync } from "node:child_process";
import { copyFileSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = dirname(fileURLToPath(import.meta.resolve("..")));
const webDir = join(root, "web");

mkdirSync(webDir, { recursive: true });

console.log("Building web/banana.wasm...");
execFileSync(
    "odin",
    [
        "build",
        ".",
        "-target:js_wasm32",
        "-collection:src=src",
        "-out:web/banana.wasm",
        "-o:size",
        "-extra-linker-flags:--allow-multiple-definition --strip-all",
    ],
    { cwd: root, stdio: "inherit" },
);

const odinRoot = execFileSync("odin", ["root"], {
    cwd: root,
    encoding: "utf8",
}).trim();
const runtimeSource = join(odinRoot, "core", "sys", "wasm", "js", "odin.js");
const runtimeTarget = join(webDir, "odin.js");

let runtime = readFileSync(runtimeSource, "utf8");
const rafCall = "window.requestAnimationFrame(step);";
if (!runtime.includes("if (exports.step) {") || !runtime.includes(rafCall)) {
    throw new Error("odin.js step-loop patch failed: upstream runtime changed");
}
runtime = runtime.replace(
    "if (exports.step) {",
    `if (exports.step) {
        const stepChannel = new MessageChannel();
        stepChannel.port1.onmessage = () => step(performance.now());
        const scheduleStep = () => stepChannel.port2.postMessage(null);`,
);
runtime = runtime.replaceAll(rafCall, "scheduleStep();");
writeFileSync(runtimeTarget, runtime);

// Fonts are fetched at runtime using helper from main.js
const fontsDir = join(webDir, "fonts");
mkdirSync(fontsDir, { recursive: true });
for (const font of ["segoeui.ttf", "leelawui.ttf", "msyh.ttc"]) {
    copyFileSync(join("C:/Windows/Fonts", font), join(fontsDir, font));
}

console.log("Web build complete: web/index.html");
