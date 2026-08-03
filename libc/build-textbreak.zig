const std = @import("std");

const c_flags = [_][]const u8{
    "-std=c17",
    "-O3",
    "-fvisibility=hidden",
};

const unibreak_sources = [_][]const u8{
    "unibreakbase.c",
    "unibreakdef.c",
    "linebreak.c",
    "linebreakdata.c",
    "linebreakdef.c",
    "eastasianwidthdef.c",
    "emojidef.c",
    "graphemebreak.c",
    "wordbreak.c",
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
    for (targets) |t| {
        const lib = b.addLibrary(.{
            .name = "textbreak",
            .linkage = .static,
            .root_module = b.createModule(.{
                .target = b.resolveTargetQuery(t.query),
                .optimize = .ReleaseFast,
            }),
        });

        lib.root_module.addCSourceFiles(.{
            .root = b.path("libunibreak/src"),
            .files = &unibreak_sources,
            .flags = &c_flags,
        });
        lib.root_module.addCSourceFiles(.{
            .root = b.path("budouxc/src"),
            .files = &.{"budoux.c"},
            .flags = &c_flags,
        });
        lib.root_module.addCSourceFiles(.{
            .root = b.path("shim"),
            .files = &.{"textbreak.c"},
            .flags = &c_flags,
        });
        lib.root_module.addIncludePath(b.path("libunibreak/src"));
        lib.root_module.addIncludePath(b.path("budouxc/include"));
        lib.root_module.addIncludePath(b.path("budouxc/src"));
        lib.root_module.link_libc = true;

        const install = b.addInstallArtifact(lib, .{
            .dest_dir = .{ .override = .{ .custom = b.fmt("../.build/textbreak/{s}", .{t.out}) } },
        });
        b.getInstallStep().dependOn(&install.step);
    }
}
