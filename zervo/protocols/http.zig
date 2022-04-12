const std = @import("std");
const ssl = @import("ssl");
const SSLConnection = ssl.SSLConnection;
const Address = std.net.Address;
const Allocator = std.mem.Allocator;
pub const HeaderMap = std.StringHashMap([]const u8);

pub const HttpResponse = struct {
    headers: HeaderMap,
    content: []const u8,
    all: []const u8,
    alloc: Allocator,

    pub fn deinit(self: *HttpResponse) void {
        self.alloc.free(self.all);
        self.headers.deinit();
    }
};

pub const HttpRequest = struct {
    headers: HeaderMap,
    host: []const u8,
    path: []const u8,
    /// Whether it uses TLS or SSL.
    secure: bool = false
};

fn parseResponse(allocator: Allocator, text: []u8) !HttpResponse {
    var map = HeaderMap.init(allocator);
    var pos: usize = 0;

    // 0 = HTTP status
    // 1 = header key
    // 2 = header value
    var parsing: u2 = 0;

    var keyStart: usize = 0;
    var keyEnd: usize = 0;

    var valueStart: usize = 0;
    var valueEnd: usize = 0;

    while (true) {
        var char = text[pos];
        if (std.mem.eql(u8, text[pos..(pos+2)], "\r\n")) {
            if (parsing == 1 and keyStart == 0) {
                pos = pos + 2;
                break;
            } else {
                if (parsing == 0) {
                    parsing = 1;
                }
                if (parsing == 2) {
                    const lower = try std.ascii.allocLowerString(allocator, text[keyStart..keyEnd]);
                    try map.put(lower, text[valueStart..valueEnd]);
                    keyStart = 0;
                    valueStart = 0;
                    parsing = 1;
                }
                pos = pos + 1;
            }
        } else if (parsing == 0) {
            // TODO
        } else if (parsing == 1) {
            if (keyStart == 0) {
                keyStart = pos;
            }
            if (char == ':') {
                pos = pos + 1; // skip : and whitespace
                parsing = 2;
            } else {
                keyEnd = pos+1;
            }
        } else if (parsing == 2) {
            if (valueStart == 0) {
                valueStart = pos;
            }
            valueEnd = pos+1;
        }
        pos = pos + 1;
    }

    var resp: HttpResponse = .{
        .headers = map,
        .alloc = allocator,
        .content = text[pos..],
        .all = text
    };

    return resp;
}

pub fn request(allocator: Allocator, address: Address, rst: HttpRequest) !HttpResponse {
    var file = try std.net.tcpConnectToAddress(address);

    const conn = try SSLConnection.init(allocator, file, rst.host, rst.secure);
    defer conn.deinit();
    const reader = conn.reader();
    const writer = conn.writer();

    try writer.print("GET {s} HTTP/1.1\r\n", .{ rst.path });
    try writer.print("Host: {s}\r\n", .{ rst.host });

    var it = rst.headers.iterator();
    while (it.next()) |entry| {
        try writer.print("{s}: {s}\r\n", .{entry.key_ptr.*, entry.value_ptr.*});
        std.log.debug("{s}: {s}\n", .{entry.key_ptr.*, entry.value_ptr.*});
    }
    try writer.writeAll("\r\n");
    std.log.info("sent", .{});

    var result: []u8 = try allocator.alloc(u8, 0);
    var bytes: []u8 = try allocator.alloc(u8, 4096);
    defer allocator.free(bytes);
    var read: usize = 0;
    var len: usize = 0;
    while (true) {
        read = try reader.read(bytes);
        var slice = bytes[0..read];
        var start = len;
        len += read;
        result = try allocator.realloc(result, len);
        @memcpy(result[start..].ptr, slice.ptr, read);
        std.log.info("{d}", .{read});
        if (read == 0) {
            break;
        }
    }
    std.log.info("sent", .{});

    return parseResponse(allocator, result);
}
