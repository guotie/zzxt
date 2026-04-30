const std = @import("std");
const Io = std.Io;

pub const HttpClient = struct {
    client: std.http.Client,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, io: Io) HttpClient {
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
        const uri = try std.Uri.parse(url);

        var req = try self.client.open(method, uri, .{
            .extra_headers = headers orelse &.{},
        }, .{});
        defer req.deinit();

        if (body) |b| {
            req.transfer_encoding = .{ .content_length = b.len };
        }

        try req.send(.{});
        if (body) |b| {
            try req.writeAll(b);
        }
        try req.finish();
        try req.wait();

        const response = req.response;
        if (response.status != .ok) {
            return error.NetworkError;
        }

        const data = try req.reader().readAllAlloc(self.allocator, 1024 * 1024);
        return data;
    }
};

test "HttpClient init/deinit" {
    const testing = std.testing;
    var client = HttpClient.init(testing.allocator, Io.failing);
    defer client.deinit();
}
