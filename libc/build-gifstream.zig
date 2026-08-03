const std = @import("std");

const c_flags = [_][]const u8{
    "-std=c17",
    "-O3",
    "-fvisibility=default",
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
            .name = "gifstream",
            .linkage = .static,
            .root_module = b.createModule(.{
                .target = b.resolveTargetQuery(t.query),
                .optimize = .ReleaseFast,
            }),
        });

        lib.root_module.addCSourceFiles(.{
            .root = b.path("gifstream"),
            .files = &.{"gifstream.c"},
            .flags = &c_flags,
        });
        lib.root_module.addIncludePath(b.path("gifstream"));
        lib.root_module.link_libc = true;

        const install = b.addInstallArtifact(lib, .{
            .dest_dir = .{ .override = .{ .custom = b.fmt("../.build/gifstream/{s}", .{t.out}) } },
        });
        b.getInstallStep().dependOn(&install.step);
    }
}
