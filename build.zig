const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("zzxt", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    const lib = b.addLibrary(.{
        .name = "zzxt",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(lib);

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&run_mod_tests.step);

    // Integration tests
    const integration_test_files = [_][]const u8{
        "tests/json_utils_test.zig",
        "tests/signing_test.zig",
        "tests/binance_parsing_test.zig",
        "tests/exchange_vtable_test.zig",
        "tests/errors_test.zig",
        "tests/types_test.zig",
        "tests/rate_limiter_test.zig",
    };

    for (integration_test_files) |test_file| {
        const int_test = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(test_file),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "zzxt", .module = mod },
                },
            }),
        });
        const run_int_test = b.addRunArtifact(int_test);
        test_step.dependOn(&run_int_test.step);
    }

    const exe = b.addExecutable(.{
        .name = "fetch_ticker",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/fetch_ticker.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zzxt", .module = mod },
            },
        }),
    });
    b.installArtifact(exe);

    const run_step = b.step("run", "Run fetch_ticker example");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
}
