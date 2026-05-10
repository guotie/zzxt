const std = @import("std");

pub const HttpClient = struct {
    client: std.http.Client,
    allocator: std.mem.Allocator,
    proxy_arena: ?std.heap.ArenaAllocator = null,

    pub fn init(allocator: std.mem.Allocator, io: std.Io) HttpClient {
        return .{
            .client = std.http.Client{ .allocator = allocator, .io = io },
            .allocator = allocator,
        };
    }

    pub const Config = struct {
        /// HTTP(S) proxy URL, for example "http://127.0.0.1:7890".
        /// Userinfo in the URL is converted to Proxy-Authorization.
        proxy_url: ?[]const u8 = null,
    };

    pub fn initWithConfig(allocator: std.mem.Allocator, io: std.Io, config: Config) !HttpClient {
        var self = HttpClient.init(allocator, io);
        errdefer self.deinit();

        if (config.proxy_url) |url| {
            var proxy_arena = std.heap.ArenaAllocator.init(allocator);
            errdefer proxy_arena.deinit();

            const proxy = try parseProxyUrl(proxy_arena.allocator(), url);
            const http_proxy = try proxy_arena.allocator().create(std.http.Client.Proxy);
            http_proxy.* = proxy;
            const https_proxy = try proxy_arena.allocator().create(std.http.Client.Proxy);
            https_proxy.* = proxy;

            self.client.http_proxy = http_proxy;
            self.client.https_proxy = https_proxy;
            self.proxy_arena = proxy_arena;
        }

        return self;
    }

    pub fn deinit(self: *HttpClient) void {
        self.client.deinit();
        if (self.proxy_arena) |*proxy_arena| {
            proxy_arena.deinit();
            self.proxy_arena = null;
        }
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

    fn parseProxyUrl(arena: std.mem.Allocator, url: []const u8) !std.http.Client.Proxy {
        const uri = std.Uri.parse(url) catch try std.Uri.parseAfterScheme("http", url);
        const protocol = std.http.Client.Protocol.fromUri(uri) orelse return error.UnsupportedProxyScheme;
        const host = try uri.getHostAlloc(arena);

        const authorization: ?[]const u8 = if (uri.user != null or uri.password != null) auth: {
            const value = try arena.alloc(u8, std.http.Client.basic_authorization.valueLengthFromUri(uri));
            break :auth std.http.Client.basic_authorization.value(uri, value);
        } else null;

        return .{
            .protocol = protocol,
            .host = host,
            .authorization = authorization,
            .port = uri.port orelse switch (protocol) {
                .plain => 80,
                .tls => 443,
            },
            .supports_connect = true,
        };
    }
};

test "HttpClient init/deinit" {
    const testing = std.testing;
    var client = HttpClient.init(testing.allocator, std.Io.failing);
    defer client.deinit();
}

test "HttpClient proxy config parses URL" {
    const testing = std.testing;

    var client = try HttpClient.initWithConfig(testing.allocator, std.Io.failing, .{
        .proxy_url = "http://user:pass@127.0.0.1:7890",
    });
    defer client.deinit();

    try testing.expect(client.client.http_proxy != null);
    try testing.expect(client.client.https_proxy != null);
    try testing.expectEqualStrings("127.0.0.1", client.client.https_proxy.?.host.bytes);
    try testing.expectEqual(@as(u16, 7890), client.client.https_proxy.?.port);
    try testing.expect(client.client.https_proxy.?.authorization != null);
}
