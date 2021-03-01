const std = @import("std");
const ssl = @import("ssl");
const SSLConnection = ssl.SSLConnection;
const Address = std.net.Address;
const Allocator = std.mem.Allocator;
const Url = @import("../url.zig").Url;

pub const GeminiResponse = struct {
    original: []const u8,
    content: []const u8,

    statusCode: u8,
    meta: []const u8,
    alloc: *Allocator,

    pub fn deinit(self: *GeminiResponse) void {
        self.alloc.free(self.original);
        self.alloc.free(self.meta);
    }
};

pub const TemporaryFailureEnum = enum {
    /// 40 TEMPORARY FAILURE
    Default,
    /// 41 SERVER UNAVAILABLE
    ServerUnavailable,
    /// 42 CGI ERROR
    CgiError,
    /// 43 PROXY ERROR
    ProxyError,
    /// 44 SLOW DOWN
    SlowDown
};

pub const PermanentFailureEnum = enum {
    /// 50 PERMANENT FAILURE
    Default,
    /// 51 NOT FOUND
    NotFound,
    /// 52 GONE
    Gone,
    /// 53 PROXY REQUEST REFUSED
    ProxyRequestRefused,
    /// 59 BAD REQUEST
    BadRequest
};

pub const ClientCertificateEnum = enum {
    /// 60 CLIENT CERTIFICATE REQUIRED
    Default,
    /// 61 CERTIFICATE NOT AUTHORISED
    NotAuthorised,
    /// 62 CERTIFICATE NOT VALID
    NotValid
};

pub const GeminiErrorDetails = union(enum) {
    /// 1x input
    Input: struct {
        sensitive: bool,
        meta: []const u8,
        allocator: *Allocator
    },
    /// 3x error
    Redirect: struct {
        temporary: bool,
        meta: []const u8,
        allocator: *Allocator
    },
    /// 4x error
    TemporaryFailure: struct {
        detail: TemporaryFailureEnum,
        meta: []const u8,
        allocator: *Allocator
    },
    /// 5x error
    PermanentFailure: struct {
        detail: PermanentFailureEnum,
        meta: []const u8,
        allocator: *Allocator
    },
    /// 6x error
    ClientCertificateRequired: struct {
        detail: ClientCertificateEnum,
        meta: []const u8,
        allocator: *Allocator
    },

    pub fn deinit(self: GeminiErrorDetails) void {
        const info = @typeInfo(GeminiErrorDetails).Union;
        const tag_type = info.tag_type.?;
        const active = std.meta.activeTag(self);
        inline for (info.fields) |field_info| {
            if (@field(tag_type, field_info.name) == active) {
                const child = @field(self, field_info.name);
                child.allocator.free(child.meta);
            }
        }
    }
};

pub const GeminiError = error {
    // invalid response
    MetaTooLong,
    MissingStatus,
    InvalidStatus,
    /// After receiving this error, the client should prompt the user to input a string
    /// and retry the request with the inputted string
    InputRequired,
    /// The error is a known protocol error and details are in the passed GeminiErrorDetails union.
    KnownError,
    /// The response from the server was malformed
    BadResponse,
};

fn parseResponse(allocator: *Allocator, text: []u8, errorDetails: *GeminiErrorDetails) !GeminiResponse {
    const headerEnd = std.mem.indexOf(u8, text, "\r\n") orelse {
        std.log.scoped(.gemini).err("Missing \\r\\n in server's response", .{});
        return GeminiError.BadResponse;
    };
    const header = text[0..headerEnd];

    var splitIterator = std.mem.split(header, " ");
    const status = splitIterator.next() orelse return GeminiError.MissingStatus;
    if (status.len != 2) {
        std.log.scoped(.gemini).err("Status code ({s}) has an invalid length: {} != 2", .{status, status.len});
        return GeminiError.InvalidStatus;
    }
    const statusCode = std.fmt.parseUnsigned(u8, status, 10) catch {
        std.log.scoped(.gemini).err("Invalid status code (not a number): {s}", .{status});
        return GeminiError.InvalidStatus;
    };

    const meta = try allocator.dupe(u8, splitIterator.rest());
    if (meta.len > 1024) {
        std.log.scoped(.gemini).warn("Meta string is too long: {} bytes > 1024 bytes", .{meta.len});
        //return GeminiError.MetaTooLong;
    }

    if (statusCode >= 10 and statusCode < 20) { // 1x (INPUT)
        errorDetails.* = .{
            .Input = .{
                .sensitive = statusCode == 11,
                .meta = meta,
                .allocator = allocator
            }
        };
        return GeminiError.InputRequired;
    } else if (statusCode >= 30 and statusCode < 40) { // 3x (REDIRECT)
        // TODO: redirect
        std.log.scoped(.gemini).crit("TODO status code: {}", .{statusCode});
        return GeminiError.KnownError;
    } else if (statusCode >= 40 and statusCode < 50) { // 4x (TEMPORARY FAILURE)
        errorDetails.* = .{
            .TemporaryFailure = .{
                .detail = switch (statusCode) {
                    41 => .ServerUnavailable,
                    42 => .CgiError,
                    43 => .ProxyError,
                    44 => .SlowDown,
                    else => .Default
                },
                .meta = meta,
                .allocator = allocator
            }
        };
        return GeminiError.KnownError;
    } else if (statusCode >= 50 and statusCode < 60) { // 5x (PERMANENT FAILURE)
        errorDetails.* = .{
            .PermanentFailure = .{
                .detail = switch (statusCode) {
                    51 => .NotFound,
                    52 => .Gone,
                    53 => .ProxyRequestRefused,
                    59 => .BadRequest,
                    else => .Default
                },
                .meta = meta,
                .allocator = allocator
            }
        };
        return GeminiError.KnownError;
    } else if (statusCode >= 60 and statusCode < 70) { // 6x (CLIENT CERTIFICATE REQUIRED)
        // TODO: client certificate
        std.log.scoped(.gemini).crit("TODO status code: {}", .{statusCode});
        return GeminiError.KnownError;
    } else if (statusCode < 20 or statusCode > 29) { // not 2x (SUCCESS)
        std.log.scoped(.gemini).err("{} is not a valid status code", .{statusCode});
        return GeminiError.InvalidStatus;
    }

    return GeminiResponse {
        .alloc = allocator,
        .content = text[std.math.min(text.len, headerEnd)..],
        .original = text,
        .statusCode = statusCode,
        .meta = meta
    };
}

fn syncTcpConnect(address: Address) !std.fs.File {
    const sock_flags = std.os.SOCK_STREAM | (if (@import("builtin").os.tag == .windows) 0 else std.os.SOCK_CLOEXEC);
    const sockfd = try std.os.socket(address.any.family, sock_flags, std.os.IPPROTO_TCP);
    errdefer std.os.close(sockfd);
    try std.os.connect(sockfd, &address.any, address.getOsSockLen());
    return std.fs.File{ .handle = sockfd };
}

pub fn request(allocator: *Allocator, address: Address, url: Url, errorDetails: *GeminiErrorDetails) !GeminiResponse {
    // TODO: move to Zig's new net I/O
    var file = try syncTcpConnect(address);

    const conn = try SSLConnection.init(allocator, file, url.host, true);
    defer conn.deinit();
    const reader = conn.reader();
    const writer = conn.writer();

    const buf = try std.fmt.allocPrint(allocator, "{}\r\n", .{url});
    try writer.writeAll(buf); // send it all at once to avoid problems with bugged servers
    allocator.free(buf);

    var result: []u8 = try allocator.alloc(u8, 0);
    errdefer allocator.free(result);
    var bytes: [1024]u8 = undefined;
    var read: usize = 0;
    var len: usize = 0;

    while (true) {
        var frame = async reader.read(&bytes);
        read = try await frame;
        var start = len;
        len += read;
        result = try allocator.realloc(result, len);
        @memcpy(result[start..].ptr, bytes[0..read].ptr, read);
        if (read == 0) {
            break;
        }
    }

    return parseResponse(allocator, result, errorDetails);
}
