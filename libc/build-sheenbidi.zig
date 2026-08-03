const std = @import("std");

const c_flags = [_][]const u8{
    "-std=c99",
    "-O3",
    "-fvisibility=hidden",
    "-DSB_CONFIG_UNITY",
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
            .name = "sheenbidi",
            .linkage = .static,
            .root_module = b.createModule(.{
                .target = b.resolveTargetQuery(t.query),
                .optimize = .ReleaseFast,
            }),
        });

        lib.root_module.addCSourceFiles(.{
            .root = b.path("sheenbidi"),
            .files = &.{"Source/SheenBidi.c"},
            .flags = &c_flags,
        });
        lib.root_module.addIncludePath(b.path("sheenbidi/Headers"));
        lib.root_module.addIncludePath(b.path("sheenbidi/Source"));
        lib.root_module.link_libc = true;
        const install = b.addInstallArtifact(lib, .{
            .dest_dir = .{ .override = .{ .custom = b.fmt("../.build/sheenbidi/{s}", .{t.out}) } },
        });
        b.getInstallStep().dependOn(&install.step);
    }
}
