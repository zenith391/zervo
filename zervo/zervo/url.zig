const std = @import("std");
const Allocator = std.mem.Allocator;

pub const UrlError = error {
    EmptyString,
    MissingScheme,
    InvalidPort,
    TooLong
};

pub const Url = struct {
    scheme: []const u8,
    host: []const u8,
    port: ?u16,
    path: []const u8,
    query: ?[]const u8,
    allocator: ?*Allocator = null,

    const MAX_LENGTH = 1024;

    pub fn parse(text: []const u8) !Url {
        const schemePos = std.mem.indexOf(u8, text, "://") orelse return UrlError.MissingScheme;
        if (schemePos == 0) return UrlError.MissingScheme;
        const scheme = text[0..schemePos];
        const portPos = std.mem.indexOfPos(u8, text, schemePos+3, ":");
        const pathPos = std.mem.indexOfPos(u8, text, schemePos+3, "/") orelse text.len;
        var port: ?u16 = null;
        if (portPos) |pos| {
            port = std.fmt.parseUnsigned(u16, text[pos+1..pathPos], 10) catch |err| return UrlError.InvalidPort;
        }
        const host = text[schemePos+3..(portPos orelse pathPos)];
        var path = text[pathPos..];
        if (path.len == 0) path = "/";
        return Url {
            .scheme = scheme,
            .host = host,
            .port = port,
            .path = path,
            .query = null
        };
    }

    pub fn combine(self: *const Url, allocator: *Allocator, part: []const u8) !Url {
        if (part.len == 0) return UrlError.EmptyString;
        if (part[0] == '/') {
            return Url {
                .scheme = try allocator.dupe(u8, self.scheme),
                .host = try allocator.dupe(u8, self.host),
                .port = self.port,
                .path = try allocator.dupe(u8, part),
                .query = null
            };
        } else if (part[0] == '?') {
            return Url {
                .scheme = self.scheme,
                .host = self.host,
                .port = self.port,
                .path = self.path,
                .query = try allocator.dupe(u8, part[1..])
            };
        } else {
            if (std.mem.indexOf(u8, part, "://")) |schemePos| {
                if (schemePos != 0) {
                    // todo, handle urls like "://example.com/test"
                    return try (try Url.parse(part)).dupe(allocator);
                } else {
                    // TODO
                    unreachable;
                }
            } else {
                if (part.len + 1 > Url.MAX_LENGTH) return UrlError.TooLong;
                const path = try std.fmt.allocPrint(allocator, "/{}", .{part});
                return Url {
                    .scheme = try allocator.dupe(u8, self.scheme),
                    .host = try allocator.dupe(u8, self.host), .port = self.port,
                    .path = path, .query = null,
                    .allocator = allocator
                };
            }
        }
    }

    pub fn dupe(self: *const Url, allocator: *Allocator) !Url {
        return Url {
            .scheme = try allocator.dupe(u8, self.scheme),
            .host = try allocator.dupe(u8, self.host),
            .port = self.port,
            .path = try allocator.dupe(u8, self.path),
            .query = null, // TODO
            .allocator = allocator
        };
    }

    pub fn deinit(self: *const Url) void {
        if (self.allocator) |allocator| {
            allocator.free(self.path);
            allocator.free(self.host);
            allocator.free(self.scheme);
        }
    }

    pub fn format(self: *const Url, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("{}://{}", .{self.scheme, self.host});
        if (self.port) |port| {
            try writer.print(":{}", .{port});
        }
        try writer.writeAll(self.path);
        if (self.query) |query| {
            try writer.print("?{}", .{query});
        }
    }
};
