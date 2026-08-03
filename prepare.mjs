import { execSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { copyFileSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";

const root = dirname(fileURLToPath(import.meta.url));

const libs = [
    { build: "build-yoga.zig", dir: "yoga", name: "yogacore", cpp: true },
    { build: "build-harfbuzz.zig", dir: "harfbuzz", name: "harfbuzz", cpp: true, out: "./libc/.build/harfbuzz" },
    { build: "build-sheenbidi.zig", dir: "sheenbidi", name: "sheenbidi", cpp: false, out: "./libc/.build/sheenbidi" },
    { build: "build-textbreak.zig", dir: "textbreak", name: "textbreak", cpp: false, out: "./libc/.build/textbreak" },
    { build: "build-msdfgen.zig", dir: "msdfgen", name: "msdfgen", cpp: true },
    { build: "build-lunasvg.zig", dir: "lunasvg", name: "lunasvg", cpp: true },
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

    let prefix = lib.out ? lib.out : `./libc/${lib.dir}/build`
    copyFileSync(`${prefix}/windows/${lib.name}.lib`, `./src/${lib.dir}/libc/windows/${lib.name}.lib`)
    copyFileSync(`${prefix}/linux/lib${lib.name}.a`, `./src/${lib.dir}/libc/linux/lib${lib.name}.a`)
    copyFileSync(`${prefix}/macos/lib${lib.name}.a`, `./src/${lib.dir}/libc/macos/lib${lib.name}.a`)


    execSync(`wasm-ld -r --whole-archive ${prefix}/wasm/lib${lib.name}.a -o ./src/${lib.dir}/libc/wasm/${lib.name}.o`, {
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
