const std = @import("std");

pub const HttpClient = struct {
    client: std.http.Client,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, io: std.Io) HttpClient {
        return .{
            .client = std.http.Client{ .allocator = allocator, .io = io },
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *HttpClient) void {
        self.client.deinit();
    }

    pub fn get(self: *HttpClient, url: []const u8, headers: ?[]const std.http.Header) ![]u8 {
        return self.request(.GET, url, null, headers);
    }

    pub fn post(self: *HttpClient, url: []const u8, body: []const u8, headers: ?[]const std.http.Header) ![]u8 {
        return self.request(.POST, url, body, headers);
    }

    pub fn delete(self: *HttpClient, url: []const u8, headers: ?[]const std.http.Header) ![]u8 {
        return self.request(.DELETE, url, null, headers);
    }

    fn request(self: *HttpClient, method: std.http.Method, url: []const u8, body: ?[]const u8, headers: ?[]const std.http.Header) ![]u8 {
        var allocating = std.Io.Writer.Allocating.init(self.allocator);

        const result = try self.client.fetch(.{
            .location = .{ .url = url },
            .method = method,
            .payload = body,
            .extra_headers = headers orelse &.{},
            .response_writer = &allocating.writer,
        });

        if (result.status != .ok) {
            return error.NetworkError;
        }

        // The Allocating writer owns the memory, return it
        return allocating.toOwnedSlice() catch return error.OutOfMemory;
    }
};

test "HttpClient init/deinit" {
    const testing = std.testing;
    var client = HttpClient.init(testing.allocator, std.Io.failing);
    defer client.deinit();
}
