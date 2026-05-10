const std = @import("std");
const websocket = @import("websocket");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const Client = websocket.Client;
const Message = websocket.Message;

pub const WebSocket = struct {
    client: Client,
    allocator: Allocator,

    pub const Config = struct {
        host: []const u8,
        port: u16 = 443,
        tls: bool = true,
        path: []const u8 = "/",
        max_size: usize = 65536,
        /// HTTP proxy URL used to create a CONNECT tunnel.
        /// Example: "http://127.0.0.1:7890".
        proxy_url: ?[]const u8 = null,
    };

    pub fn init(allocator: Allocator, io: Io, config: Config) !WebSocket {
        var proxy_arena = std.heap.ArenaAllocator.init(allocator);
        defer proxy_arena.deinit();

        const proxy = if (config.proxy_url) |url|
            try parseProxyUrl(proxy_arena.allocator(), url)
        else
            null;

        var client = try Client.init(io, allocator, .{
            .host = config.host,
            .port = config.port,
            .tls = config.tls,
            .max_size = config.max_size,
            .proxy = proxy,
        });
        errdefer client.deinit();

        try client.handshake(config.path, .{});

        return .{
            .client = client,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *WebSocket) void {
        self.client.close(.{}) catch {};
        self.client.deinit();
    }

    pub fn writeText(self: *WebSocket, data: []u8) !void {
        try self.client.write(data);
    }

    pub fn read(self: *WebSocket) !?[]const u8 {
        const msg = try self.client.read() orelse return null;
        return msg.data;
    }

    pub fn close(self: *WebSocket) !void {
        try self.client.close(.{});
    }

    fn parseProxyUrl(arena: Allocator, url: []const u8) !Client.Proxy {
        const uri = std.Uri.parse(url) catch try std.Uri.parseAfterScheme("http", url);
        const protocol = std.http.Client.Protocol.fromUri(uri) orelse return error.UnsupportedProxyScheme;
        if (protocol != .plain) return error.UnsupportedProxyScheme;

        const host = try uri.getHostAlloc(arena);
        const authorization: ?[]const u8 = if (uri.user != null or uri.password != null) auth: {
            const value = try arena.alloc(u8, std.http.Client.basic_authorization.valueLengthFromUri(uri));
            break :auth std.http.Client.basic_authorization.value(uri, value);
        } else null;

        return .{
            .host = host.bytes,
            .port = uri.port orelse 80,
            .authorization = authorization,
        };
    }
};

test "WebSocket proxy config parses URL" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const proxy = try WebSocket.parseProxyUrl(arena.allocator(), "http://user:pass@127.0.0.1:7890");
    try testing.expectEqualStrings("127.0.0.1", proxy.host);
    try testing.expectEqual(@as(u16, 7890), proxy.port);
    try testing.expect(proxy.authorization != null);
}
