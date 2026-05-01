const std = @import("std");

pub const RateLimiter = struct {
    interval_ms: u32,
    last_request: i64,

    pub fn init(rate_limit_ms: u32) RateLimiter {
        return .{
            .interval_ms = rate_limit_ms,
            .last_request = 0,
        };
    }

    pub fn acquire(self: *RateLimiter) void {
        _ = self;
        // Rate limiting requires Io for sleep, which complicates the API.
        // For now, this is a no-op. Real rate limiting will be added
        // when the Io dependency is properly threaded through.
    }
};

test "RateLimiter basic" {
    const testing = std.testing;
    var limiter = RateLimiter.init(100);
    limiter.acquire();
    try testing.expect(true);
}
