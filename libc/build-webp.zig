const std = @import("std");

const c_flags = [_][]const u8{
    "-std=c11",
    "-O3",
    "-fvisibility=default",
};

// Only the decode side of libwebp: no encoder, no sharpyuv, no tools.
const dec_sources = [_][]const u8{
    "dec/alpha_dec.c",          "dec/buffer_dec.c",          "dec/frame_dec.c",
    "dec/idec_dec.c",           "dec/io_dec.c",              "dec/quant_dec.c",
    "dec/tree_dec.c",           "dec/vp8_dec.c",             "dec/vp8l_dec.c",
    "dec/webp_dec.c",           "demux/anim_decode.c",       "demux/demux.c",
    "utils/bit_reader_utils.c", "utils/color_cache_utils.c", "utils/filters_utils.c",
    "utils/huffman_utils.c",    "utils/palette.c",           "utils/quant_levels_dec_utils.c",
    "utils/rescaler_utils.c",   "utils/random_utils.c",      "utils/thread_utils.c",
    "utils/utils.c",            "dsp/alpha_processing.c",    "dsp/cpu.c",
    "dsp/dec.c",                "dsp/dec_clip_tables.c",     "dsp/filters.c",
    "dsp/lossless.c",           "dsp/rescaler.c",            "dsp/upsampling.c",
    "dsp/yuv.c",
};

const sse2_sources = [_][]const u8{
    "dsp/alpha_processing_sse2.c", "dsp/dec_sse2.c",      "dsp/filters_sse2.c",
    "dsp/lossless_sse2.c",         "dsp/rescaler_sse2.c", "dsp/upsampling_sse2.c",
    "dsp/yuv_sse2.c",
};

const sse41_sources = [_][]const u8{
    "dsp/alpha_processing_sse41.c", "dsp/dec_sse41.c", "dsp/lossless_sse41.c",
    "dsp/upsampling_sse41.c",       "dsp/yuv_sse41.c",
};

const avx2_sources = [_][]const u8{"dsp/lossless_avx2.c"};
const x86_flags = c_flags ++ [_][]const u8{ "-DWEBP_HAVE_SSE41", "-DWEBP_HAVE_AVX2" };

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

fn addSimdObjects(
    b: *std.Build,
    lib: *std.Build.Step.Compile,
    base: std.Target.Query,
    features: []const std.Target.x86.Feature,
    files: []const []const u8,
) void {
    var query = base;
    query.cpu_features_add = std.Target.x86.featureSet(features);
    const target = b.resolveTargetQuery(query);
    for (files) |file| {
        const obj = b.addObject(.{
            .name = std.fs.path.stem(file),
            .root_module = b.createModule(.{
                .target = target,
                .optimize = .ReleaseFast,
            }),
        });
        obj.root_module.addCSourceFile(.{ .file = b.path(b.fmt("libwebp/src/{s}", .{file})), .flags = &x86_flags });
        obj.root_module.addIncludePath(b.path("libwebp"));
        obj.root_module.addIncludePath(b.path("libwebp/src"));
        obj.root_module.link_libc = true;
        lib.root_module.addObject(obj);
    }
}

pub fn build(b: *std.Build) void {
    for (targets) |t| {
        const lib = b.addLibrary(.{
            .name = "webp",
            .linkage = .static,
            .root_module = b.createModule(.{
                .target = b.resolveTargetQuery(t.query),
                .optimize = .ReleaseFast,
            }),
        });

        const x86 = t.query.cpu_arch == .x86_64;
        const flags: []const []const u8 = if (x86) &x86_flags else &c_flags;

        lib.root_module.addCSourceFiles(.{ .root = b.path("libwebp/src"), .files = &dec_sources, .flags = flags });
        lib.root_module.addCSourceFiles(.{ .root = b.path("webp"), .files = &.{"webp.c"}, .flags = flags });
        if (x86) {
            lib.root_module.addCSourceFiles(.{ .root = b.path("libwebp/src"), .files = &sse2_sources, .flags = flags });
            addSimdObjects(b, lib, t.query, &.{.sse4_1}, &sse41_sources);
            addSimdObjects(b, lib, t.query, &.{ .sse4_1, .avx2 }, &avx2_sources);
        }
        lib.root_module.addIncludePath(b.path("libwebp"));
        lib.root_module.addIncludePath(b.path("libwebp/src"));
        lib.root_module.link_libc = true;

        const install = b.addInstallArtifact(lib, .{
            .dest_dir = .{ .override = .{ .custom = b.fmt("../.build/webp/{s}", .{t.out}) } },
        });
        b.getInstallStep().dependOn(&install.step);
    }
}
