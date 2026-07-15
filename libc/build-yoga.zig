const std = @import("std");

const cpp_flags = [_][]const u8{
    "-std=c++20",
    "-fno-omit-frame-pointer",
    "-fno-exceptions",
    "-fno-rtti",
    "-fno-threadsafe-statics",
    "-fvisibility=hidden",
    "-O2",
    "-Wall",
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
    const yoga_root = "yoga";
    const sources = collectSources(b, yoga_root ++ "/yoga") catch |err| {
        std.debug.print("failed to scan yoga sources: {}\n", .{err});
        std.process.exit(1);
    };

    for (targets) |t| {
        const resolved = b.resolveTargetQuery(t.query);

        const lib = b.addLibrary(.{
            .name = "yogacore",
            .linkage = .static,
            .root_module = b.createModule(.{
                .target = resolved,
                .optimize = optimize,
            }),
        });

        lib.root_module.addCSourceFiles(.{
            .root = b.path(yoga_root),
            .files = sources,
            .flags = &cpp_flags,
            .language = .cpp,
        });
        lib.root_module.addCSourceFiles(.{
            .root = b.path("shim"),
            .files = &.{"cxx_shim.cpp"},
            .flags = &cpp_flags,
            .language = .cpp,
        });
        lib.root_module.addIncludePath(b.path(yoga_root));
        lib.root_module.link_libcpp = true;
        lib.bundle_compiler_rt = true;

        const install = b.addInstallArtifact(lib, .{
            .dest_dir = .{ .override = .{ .custom = b.fmt("../yoga/build/{s}", .{t.out}) } },
        });
        b.getInstallStep().dependOn(&install.step);
    }
}

fn collectSources(b: *std.Build, dir: []const u8) ![]const []const u8 {
    var list: std.ArrayList([]const u8) = .empty;
    var d = try b.build_root.handle.openDir(dir, .{ .iterate = true });
    defer d.close();

    var walker = try d.walk(b.allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.path, ".cpp")) continue;
        const rel = b.fmt("yoga/{s}", .{entry.path});
        const norm = try b.allocator.dupe(u8, rel);
        for (norm) |*c| {
            if (c.* == '\\') c.* = '/';
        }
        try list.append(b.allocator, norm);
    }

    return list.toOwnedSlice(b.allocator);
}
