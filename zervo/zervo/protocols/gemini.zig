const std = @import("std");
const ssl = @import("ssl");
const SSLConnection = ssl.SSLConnection;
const Address = std.net.Address;
const Allocator = std.mem.Allocator;
const Url = @import("../url.zig").Url;

pub const GeminiResponse = struct {
    original: []const u8,
    content: []const u8,
    alloc: *Allocator,

    pub fn deinit(self: *GeminiResponse) void {
        self.alloc.free(self.original);
    }
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

pub fn request(allocator: *Allocator, address: Address, url: Url) !GeminiResponse {
    var out = std.io.getStdOut().outStream();
    var file = try syncTcpConnect(address);

    const conn = try SSLConnection.init(allocator, file, url.host, true);
    defer conn.deinit();
    const reader = conn.reader();
    const writer = conn.writer();

    const buf = try std.fmt.allocPrint(allocator, "{}\r\n", .{url});
    try writer.writeAll(buf); // send it all at once to avoid problems with bugged servers
    allocator.free(buf);

    var result: []u8 = try allocator.alloc(u8, 0);
    var bytes: []u8 = try allocator.alloc(u8, 4096);
    defer allocator.free(bytes);
    var read: usize = 0;
    var len: usize = 0;

    while (true) {
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
