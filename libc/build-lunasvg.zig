const std = @import("std");

const common_flags = [_][]const u8{
    "-fno-omit-frame-pointer", "-fvisibility=hidden", "-O2",
    "-DLUNASVG_BUILD_STATIC", "-DPLUTOVG_BUILD_STATIC",
};

// WASI has no mmap and no system font directories, and its setjmp is a hard
// #error. The vendored sources stay pristine: the font cache is compiled out
// through plutovg's own guard, and the rest is patched by the preprocessor via
// a forced-include shim (see shim/wasm_compat.h).
const wasm_flags = [_][]const u8{
    "-DPLUTOVG_DISABLE_FONT_FACE_CACHE_LOAD",
};

const c_flags = common_flags ++ [_][]const u8{"-std=c99"};

const cpp_flags = common_flags ++ [_][]const u8{
    "-std=c++17", "-fno-exceptions", "-fno-rtti", "-fno-threadsafe-statics",
};

const wasm_c_flags = c_flags ++ wasm_flags;
const wasm_cpp_flags = cpp_flags ++ wasm_flags;

const plutovg_sources = [_][]const u8{
    "plutovg-blend.c", "plutovg-canvas.c", "plutovg-font.c", "plutovg-ft-math.c",
    "plutovg-ft-raster.c", "plutovg-ft-stroker.c", "plutovg-matrix.c", "plutovg-paint.c",
    "plutovg-path.c", "plutovg-rasterize.c", "plutovg-surface.c",
};

// lunasvg.cpp is compiled from a generated copy instead; see patchedLunasvg.
const lunasvg_sources = [_][]const u8{
    "graphics.cpp", "svgelement.cpp", "svggeometryelement.cpp",
    "svglayoutstate.cpp", "svgpaintelement.cpp", "svgparser.cpp", "svgproperty.cpp",
    "svgrenderstate.cpp", "svgtextelement.cpp",
};

// Document::loadFromFile is the sole reason lunasvg.cpp includes <fstream>, and
// it drags in ~30 out-of-line std::basic_istream/locale symbols that would
// otherwise have to be satisfied by linking libc++ itself. Assets always arrive
// as memory here, so the body is rewritten to fail in a generated copy of the
// file -- the submodule itself stays pristine.
const loadfromfile_original =
    \\std::unique_ptr<Document> Document::loadFromFile(const std::string& filename)
    \\{
    \\    std::ifstream fs;
    \\    fs.open(filename);
    \\    if(!fs.is_open())
    \\        return nullptr;
    \\    std::string content;
    \\    std::getline(fs, content, '\0');
    \\    fs.close();
    \\    return loadFromData(content);
    \\}
;

const loadfromfile_replacement =
    \\std::unique_ptr<Document> Document::loadFromFile(const std::string&)
    \\{
    \\    return nullptr;
    \\}
;

const Target = struct { out: []const u8, query: std.Target.Query };
const targets = [_]Target{
    .{ .out = "windows", .query = .{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .msvc } },
    .{ .out = "linux", .query = .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu } },
    .{ .out = "macos", .query = .{ .cpu_arch = .x86_64, .os_tag = .macos } },
    .{ .out = "wasm", .query = .{ .cpu_arch = .wasm32, .os_tag = .wasi } },
};

fn patchedLunasvg(b: *std.Build) std.Build.LazyPath {
    const source = std.fs.cwd().readFileAlloc(
        b.allocator,
        b.path("lunasvg/source/lunasvg.cpp").getPath(b),
        4 * 1024 * 1024,
    ) catch @panic("cannot read lunasvg.cpp");
    
    const normalized = std.mem.replaceOwned(u8, b.allocator, source, "\r\n", "\n") catch @panic("OOM");

    const no_include = std.mem.replaceOwned(
        u8,
        b.allocator,
        normalized,
        "#include <fstream>\n",
        "",
    ) catch @panic("OOM");
    if (no_include.len == normalized.len) @panic("lunasvg.cpp no longer includes <fstream>");

    const patched = std.mem.replaceOwned(
        u8,
        b.allocator,
        no_include,
        loadfromfile_original,
        loadfromfile_replacement,
    ) catch @panic("OOM");
    if (patched.len == no_include.len) @panic("lunasvg.cpp: loadFromFile body no longer matches");

    return b.addWriteFiles().add("lunasvg.cpp", patched);
}

fn withForcedInclude(b: *std.Build, base: []const []const u8, header: []const u8) []const []const u8 {
    const out = b.allocator.alloc([]const u8, base.len + 2) catch @panic("OOM");
    @memcpy(out[0..base.len], base);
    out[base.len] = "-include";
    out[base.len + 1] = header;
    return out;
}

pub fn build(b: *std.Build) void {
    const compat = b.path("shim/lunasvg_wasm.h").getPath(b);
    const lunasvg_cpp = patchedLunasvg(b);

    for (targets) |t| {
        const is_wasm = t.query.cpu_arch == .wasm32;
        const cf: []const []const u8 = if (is_wasm)
            withForcedInclude(b, &wasm_c_flags, compat)
        else
            &c_flags;
        const cppf: []const []const u8 = if (is_wasm)
            withForcedInclude(b, &wasm_cpp_flags, compat)
        else
            &cpp_flags;
        const lib = b.addLibrary(.{
            .name = "lunasvg", .linkage = .static,
            .root_module = b.createModule(.{ .target = b.resolveTargetQuery(t.query), .optimize = .ReleaseFast }),
        });
        lib.root_module.addCSourceFiles(.{ .root = b.path("plutovg/source"), .files = &plutovg_sources, .flags = cf, .language = .c });
        lib.root_module.addCSourceFiles(.{ .root = b.path("lunasvg/source"), .files = &lunasvg_sources, .flags = cppf, .language = .cpp });
        lib.root_module.addCSourceFile(.{ .file = lunasvg_cpp, .flags = cppf, .language = .cpp });
        lib.root_module.addCSourceFiles(.{ .root = b.path("shim"), .files = &.{ "lunasvg_shim.cpp", "cxx_shim.cpp", "lunasvg_libcpp.cpp" }, .flags = cppf, .language = .cpp });
        lib.root_module.addIncludePath(b.path("shim"));
        lib.root_module.addIncludePath(b.path("plutovg/include"));
        lib.root_module.addIncludePath(b.path("plutovg/source"));
        lib.root_module.addIncludePath(b.path("lunasvg/include"));
        lib.root_module.addIncludePath(b.path("lunasvg/source"));
        lib.root_module.link_libcpp = true;
        lib.bundle_compiler_rt = true;
        const install = b.addInstallArtifact(lib, .{ .dest_dir = .{ .override = .{ .custom = b.fmt("../lunasvg/build/{s}", .{t.out}) } } });
        b.getInstallStep().dependOn(&install.step);
    }
}
