const std = @import("std");

const cpp_flags = [_][]const u8{
    "-std=c++17", "-fno-omit-frame-pointer", "-fno-exceptions", "-fno-rtti",
    "-fno-threadsafe-statics", "-fvisibility=hidden", "-O2",
    "-DMSDFGEN_USE_CPP11", "-DMSDFGEN_PUBLIC=",
};

const sources = [_][]const u8{
    "core/contour-combiners.cpp", "core/Contour.cpp", "core/convergent-curve-ordering.cpp",
    "core/DistanceMapping.cpp", "core/edge-coloring.cpp", "core/edge-segments.cpp",
    "core/edge-selectors.cpp", "core/EdgeHolder.cpp", "core/equation-solver.cpp",
    "core/export-svg.cpp", "core/msdf-error-correction.cpp", "core/MSDFErrorCorrection.cpp",
    "core/msdfgen.cpp", "core/Projection.cpp", "core/rasterization.cpp", "core/render-sdf.cpp",
    "core/save-bmp.cpp", "core/save-fl32.cpp", "core/save-rgba.cpp", "core/save-tiff.cpp",
    "core/Scanline.cpp", "core/sdf-error-estimation.cpp", "core/shape-description.cpp", "core/Shape.cpp",
};

const Target = struct { out: []const u8, query: std.Target.Query };
const targets = [_]Target{
    .{ .out = "windows", .query = .{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .msvc } },
    .{ .out = "linux", .query = .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu } },
    .{ .out = "macos", .query = .{ .cpu_arch = .x86_64, .os_tag = .macos } },
    .{ .out = "wasm", .query = .{ .cpu_arch = .wasm32, .os_tag = .wasi } },
};

pub fn build(b: *std.Build) void {
    for (targets) |t| {
        const lib = b.addLibrary(.{
            .name = "msdfgen", .linkage = .static,
            .root_module = b.createModule(.{ .target = b.resolveTargetQuery(t.query), .optimize = .ReleaseFast }),
        });
        lib.root_module.addCSourceFiles(.{ .root = b.path("msdfgen"), .files = &sources, .flags = &cpp_flags, .language = .cpp });
        lib.root_module.addCSourceFiles(.{ .root = b.path("shim"), .files = &.{ "msdfgen_shim.cpp", "cxx_shim.cpp" }, .flags = &cpp_flags, .language = .cpp });
        lib.root_module.addIncludePath(b.path("msdfgen"));
        lib.root_module.link_libcpp = true;
        lib.bundle_compiler_rt = true;
        const install = b.addInstallArtifact(lib, .{ .dest_dir = .{ .override = .{ .custom = b.fmt("../msdfgen/build/{s}", .{t.out}) } } });
        b.getInstallStep().dependOn(&install.step);
    }
}
