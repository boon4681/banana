import { execSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { copyFileSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";

const root = dirname(fileURLToPath(import.meta.url));

const libs = [
    { build: "build-yoga.zig", dir: "yoga", name: "yogacore", cpp: true },
    { build: "build-harfbuzz.zig", dir: "harfbuzz", name: "harfbuzz", cpp: true },
    { build: "build-fribidi.zig", dir: "fribidi", name: "fribidi", cpp: false },
    { build: "build-msdfgen.zig", dir: "msdfgen", name: "msdfgen", cpp: true },
]

for (const lib of libs) {
    console.log("building libc " + JSON.stringify(lib.name))
    execSync(`zig build --build-file ${lib.build}`, {
        cwd: join(root, "libc"),
        stdio: "inherit",
    });

    mkdirSync(`./src/${lib.dir}/libc/windows`, { recursive: true })
    mkdirSync(`./src/${lib.dir}/libc/linux`, { recursive: true })
    mkdirSync(`./src/${lib.dir}/libc/macos`, { recursive: true })
    mkdirSync(`./src/${lib.dir}/libc/wasm`, { recursive: true })

    copyFileSync(`./libc/${lib.dir}/build/windows/${lib.name}.lib`, `./src/${lib.dir}/libc/windows/${lib.name}.lib`)
    copyFileSync(`./libc/${lib.dir}/build/linux/lib${lib.name}.a`, `./src/${lib.dir}/libc/linux/lib${lib.name}.a`)
    copyFileSync(`./libc/${lib.dir}/build/macos/lib${lib.name}.a`, `./src/${lib.dir}/libc/macos/lib${lib.name}.a`)

    execSync(`wasm-ld -r --whole-archive ./libc/${lib.dir}/build/wasm/lib${lib.name}.a -o ./src/${lib.dir}/libc/wasm/${lib.name}.o`, {
        cwd: root,
        stdio: "inherit",
    })
    if (lib.cpp) {
        stripAutolink(`./src/${lib.dir}/libc/windows/${lib.name}.lib`, "/DEFAULTLIB:libc++.lib")
    }
}

function stripAutolink(libPath, directive) {
    const buf = readFileSync(libPath)
    const needle = Buffer.from(directive, "ascii")
    let idx = 0, count = 0
    while ((idx = buf.indexOf(needle, idx)) !== -1) {
        buf.fill(0x20, idx, idx + needle.length)
        idx += needle.length
        count++
    }
    writeFileSync(libPath, buf)
    console.log(`patched ${count} '${directive}' autolink directive(s) in ${libPath}`)
}

console.log("build")
