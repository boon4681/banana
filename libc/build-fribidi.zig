const std = @import("std");

const c_flags = [_][]const u8{
    "-std=c99",
    "-O2",
    "-fvisibility=hidden",
    "-DHAVE_STRINGIZE",
    "-DHAVE_STDLIB_H",
    "-DHAVE_STRING_H",
    "-DSTDC_HEADERS=1",
    "-DDONT_HAVE_FRIBIDI_CONFIG_H",
    "-DFRIBIDI_LIB_STATIC",
};

const native_flags = [_][]const u8{
    "-std=c99",
    "-DHAVE_STRINGIZE",
    "-DHAVE_STDLIB_H",
    "-DHAVE_STRING_H",
    "-DSTDC_HEADERS=1",
    "-DDONT_HAVE_FRIBIDI_CONFIG_H",
};

const lib_sources = [_][]const u8{
    "lib/fribidi.c",
    "lib/fribidi-arabic.c",
    "lib/fribidi-bidi.c",
    "lib/fribidi-bidi-types.c",
    "lib/fribidi-brackets.c",
    "lib/fribidi-char-sets.c",
    "lib/fribidi-char-sets-cap-rtl.c",
    "lib/fribidi-char-sets-cp1255.c",
    "lib/fribidi-char-sets-cp1256.c",
    "lib/fribidi-char-sets-iso8859-6.c",
    "lib/fribidi-char-sets-iso8859-8.c",
    "lib/fribidi-char-sets-utf8.c",
    "lib/fribidi-deprecated.c",
    "lib/fribidi-joining.c",
    "lib/fribidi-joining-types.c",
    "lib/fribidi-mirroring.c",
    "lib/fribidi-run.c",
    "lib/fribidi-shape.c",
};

const Tab = struct {
    name: []const u8,
    inputs: []const []const u8,
};

const tabs = [_]Tab{
    .{ .name = "bidi-type", .inputs = &.{"unidata/UnicodeData.txt"} },
    .{ .name = "joining-type", .inputs = &.{ "unidata/UnicodeData.txt", "unidata/ArabicShaping.txt" } },
    .{ .name = "arabic-shaping", .inputs = &.{"unidata/UnicodeData.txt"} },
    .{ .name = "mirroring", .inputs = &.{"unidata/BidiMirroring.txt"} },
    .{ .name = "brackets", .inputs = &.{ "unidata/BidiBrackets.txt", "unidata/UnicodeData.txt" } },
    .{ .name = "brackets-type", .inputs = &.{"unidata/BidiBrackets.txt"} },
};

const Target = struct {
    out: []const u8,
    query: std.Target.Query,
};

const targets = [_]Target{
    .{ .out = "windows", .query = .{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .msvc } },
    .{ .out = "linux", .query = .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu } },
    .{ .out = "macos", .query = .{ .cpu_arch = .x86_64, .os_tag = .macos } },
    .{ .out = "wasm", .query = .{ .cpu_arch = .wasm32, .os_tag = .wasi } },
};

pub fn build(b: *std.Build) void {
    const optimize: std.builtin.OptimizeMode = .ReleaseFast;
    const host = b.graph.host;

    const uv_dir = b.addWriteFiles();
    const tabs_dir = b.addWriteFiles();

    const gen_uv = b.addExecutable(.{
        .name = "gen-unicode-version",
        .root_module = b.createModule(.{ .target = host, .optimize = .Debug }),
    });
    gen_uv.root_module.addCSourceFiles(.{
        .root = b.path("fribidi"),
        .files = &.{"gen.tab/gen-unicode-version.c"},
        .flags = &native_flags,
    });
    gen_uv.root_module.addIncludePath(b.path("fribidi/lib"));
    gen_uv.linkLibC();

    const run_uv = b.addRunArtifact(gen_uv);
    run_uv.addFileArg(b.path("fribidi/gen.tab/unidata/ReadMe.txt"));
    run_uv.addFileArg(b.path("fribidi/gen.tab/unidata/BidiMirroring.txt"));
    run_uv.addArg("gen-unicode-version");
    _ = uv_dir.addCopyFile(run_uv.captureStdOut(), "fribidi-unicode-version.h");

    for (tabs) |tab| {
        const exe = b.addExecutable(.{
            .name = b.fmt("gen-{s}-tab", .{tab.name}),
            .root_module = b.createModule(.{ .target = host, .optimize = .Debug }),
        });
        exe.root_module.addCSourceFiles(.{
            .root = b.path("fribidi"),
            .files = &.{ b.fmt("gen.tab/gen-{s}-tab.c", .{tab.name}), "gen.tab/packtab.c" },
            .flags = &native_flags,
        });
        exe.root_module.addIncludePath(b.path("fribidi/lib"));
        exe.root_module.addIncludePath(uv_dir.getDirectory());
        exe.linkLibC();

        const run = b.addRunArtifact(exe);
        run.addArg("2"); // compression level, matches meson
        for (tab.inputs) |input| {
            run.addFileArg(b.path(b.fmt("fribidi/gen.tab/{s}", .{input})));
        }
        run.addArg(b.fmt("gen-{s}-tab", .{tab.name}));
        _ = tabs_dir.addCopyFile(run.captureStdOut(), b.fmt("{s}.tab.i", .{tab.name}));
    }

    for (targets) |t| {
        const resolved = b.resolveTargetQuery(t.query);

        const lib = b.addLibrary(.{
            .name = "fribidi",
            .linkage = .static,
            .root_module = b.createModule(.{
                .target = resolved,
                .optimize = optimize,
            }),
        });

        lib.root_module.addCSourceFiles(.{
            .root = b.path("fribidi"),
            .files = &lib_sources,
            .flags = &c_flags,
        });
        lib.root_module.addIncludePath(b.path("fribidi/lib"));
        lib.root_module.addIncludePath(uv_dir.getDirectory());
        lib.root_module.addIncludePath(tabs_dir.getDirectory());
        lib.root_module.link_libc = true;
        lib.bundle_compiler_rt = true;

        const install = b.addInstallArtifact(lib, .{
            .dest_dir = .{ .override = .{ .custom = b.fmt("../fribidi/build/{s}", .{t.out}) } },
        });
        b.getInstallStep().dependOn(&install.step);
    }
}
