import { execSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { mkdirSync, readFileSync } from "node:fs";
import { WASI } from "node:wasi";
const root = dirname(fileURLToPath(import.meta.url));

execSync(`odin test ./src/yoga`, {
    stdio: "inherit",
});

const buildDir = join(root, "build");
mkdirSync(buildDir, { recursive: true });

for (const pkg of ["yoga", "lunasvg"]) {
    const wasmOut = join(buildDir, `${pkg}.test.wasm`);
    execSync(`odin build ./src/${pkg}/wasm -target:wasi_wasm32 -collection:src=src -out:"${wasmOut}"`, {
        cwd: root,
        stdio: "inherit",
    });

    const wasi = new WASI({ version: "preview1", returnOnExit: true });
    const wasm = await WebAssembly.compile(readFileSync(wasmOut));
    const instance = await WebAssembly.instantiate(wasm, wasi.getImportObject());
    const code = wasi.start(instance);
    if (code !== 0) {
        console.error(`${pkg} wasm test failed with exit code ${code}`);
        process.exit(code);
    }
}
