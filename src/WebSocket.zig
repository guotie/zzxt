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
    };

    pub fn init(allocator: Allocator, io: Io, config: Config) !WebSocket {
        var client = try Client.init(io, allocator, .{
            .host = config.host,
            .port = config.port,
            .tls = config.tls,
            .max_size = config.max_size,
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
};
