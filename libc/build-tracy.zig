const std = @import("std");

const common_flags = [_][]const u8{
    "-fno-omit-frame-pointer", "-O2",
    "-DTRACY_ENABLE",
    "-DTRACY_NO_CALLSTACK",
    "-DTRACY_NO_SAMPLING",
    "-DTRACY_NO_SYSTEM_TRACING",
};

const cpp_flags = common_flags ++ [_][]const u8{
    "-std=c++17", "-fno-rtti",
};

const Target = struct { out: []const u8, query: std.Target.Query };
const targets = [_]Target{
    .{ .out = "windows", .query = .{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .msvc } },
    .{ .out = "linux", .query = .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu } },
    .{ .out = "macos", .query = .{ .cpu_arch = .x86_64, .os_tag = .macos } },
};

pub fn build(b: *std.Build) void {
    for (targets) |t| {
        const lib = b.addLibrary(.{
            .name = "tracy",
            .linkage = .static,
            .root_module = b.createModule(.{
                .target = b.resolveTargetQuery(t.query),
                .optimize = .ReleaseFast,
            }),
        });
        lib.root_module.addCSourceFile(.{
            .file = b.path("tracy/public/TracyClient.cpp"),
            .flags = &cpp_flags,
            .language = .cpp,
        });
        // Only the msvc target needs the hand-rolled libc++ symbols
        if (t.query.abi == .msvc) {
            lib.root_module.addCSourceFile(.{
                .file = b.path("shim/tracy_libcpp.cpp"),
                .flags = &cpp_flags,
                .language = .cpp,
            });
        }
        lib.root_module.addIncludePath(b.path("tracy/public"));
        lib.root_module.link_libcpp = true;
        lib.bundle_compiler_rt = true;
        const install = b.addInstallArtifact(lib, .{
            .dest_dir = .{ .override = .{ .custom = b.fmt("../.build/tracy/{s}", .{t.out}) } },
        });
        b.getInstallStep().dependOn(&install.step);
    }
}
