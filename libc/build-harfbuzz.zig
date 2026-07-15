const std = @import("std");

const cpp_flags = [_][]const u8{
    "-std=c++17",
    "-fno-omit-frame-pointer",
    "-fno-exceptions",
    "-fno-rtti",
    "-fno-threadsafe-statics",
    "-fvisibility=hidden",
    "-O2",
    "-DHB_NO_MT",
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

    for (targets) |t| {
        const resolved = b.resolveTargetQuery(t.query);

        const lib = b.addLibrary(.{
            .name = "harfbuzz",
            .linkage = .static,
            .root_module = b.createModule(.{
                .target = resolved,
                .optimize = optimize,
            }),
        });

        lib.root_module.addCSourceFiles(.{
            .root = b.path("harfbuzz"),
            .files = &.{"src/harfbuzz.cc"},
            .flags = &cpp_flags,
            .language = .cpp,
        });
        if (t.query.os_tag != .wasi) {
            lib.root_module.addCSourceFiles(.{
                .root = b.path("shim"),
                .files = &.{"cxx_shim.cpp"},
                .flags = &cpp_flags,
                .language = .cpp,
            });
        }
        lib.root_module.addIncludePath(b.path("harfbuzz/src"));
        lib.root_module.link_libcpp = true;
        lib.bundle_compiler_rt = true;

        const install = b.addInstallArtifact(lib, .{
            .dest_dir = .{ .override = .{ .custom = b.fmt("../harfbuzz/build/{s}", .{t.out}) } },
        });
        b.getInstallStep().dependOn(&install.step);
    }
}
