const std = @import("std");
const ssl = @import("ssl");
const SSLConnection = ssl.SSLConnection;
const Address = std.net.Address;
const Allocator = std.mem.Allocator;

pub const GeminiResponse = struct {
    original: []const u8,
    content: []const u8,
    alloc: *Allocator,

    pub fn deinit(self: *GeminiResponse) void {
        self.alloc.free(self.original);
    }
};

pub const GeminiRequest = struct {
    host: []const u8,
    path: []const u8,
};

fn parseResponse(allocator: *Allocator, text: []u8) !GeminiResponse {
    var pos: usize = 0;
    while (true) : (pos += 1) {
        var char = text[pos];
        if (std.mem.eql(u8, text[pos..(pos+2)], "\r\n")) {
            pos += 2;
            break;
        }
    }

    var resp: GeminiResponse = .{
        .alloc = allocator,
        .content = text[pos..],
        .original = text
    };

    return resp;
}

fn syncTcpConnect(address: Address) !std.fs.File {
    const sock_flags = std.os.SOCK_STREAM | (if (@import("builtin").os.tag == .windows) 0 else std.os.SOCK_CLOEXEC);
    const sockfd = try std.os.socket(address.any.family, sock_flags, std.os.IPPROTO_TCP);
    errdefer std.os.close(sockfd);
    try std.os.connect(sockfd, &address.any, address.getOsSockLen());
    return std.fs.File{ .handle = sockfd };
}

pub fn request(allocator: *Allocator, address: Address, rst: GeminiRequest) !GeminiResponse {
    var out = std.io.getStdOut().outStream();
    var file = try syncTcpConnect(address);

    const conn = try SSLConnection.init(allocator, file, rst.host, true);
    defer conn.deinit();
    const reader = conn.reader();
    const writer = conn.writer();
    std.debug.warn("gemini://{}{}\r\n", .{rst.host, rst.path});
    try writer.print("gemini://{}{}\r\n", .{rst.host, rst.path});

    var result: []u8 = try allocator.alloc(u8, 0);
    var bytes: []u8 = try allocator.alloc(u8, 4096);
    defer allocator.free(bytes);
    var read: usize = 0;
    var len: usize = 0;

    while (true) {
        // if (std.event.Loop.instance) |loop| {
        //     loop.yield();
        // }
        var frame = async reader.read(bytes);
        read = try await frame;
        var start = len;
        len += read;
        result = try allocator.realloc(result, len);
        @memcpy(result[start..].ptr, bytes[0..read].ptr, read);
        if (read == 0) {
            break;
        }
    }
    std.debug.warn("response: {}", .{result});

    return parseResponse(allocator, result);
}
