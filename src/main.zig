const zervo = @import("zervo");
const std = @import("std");
const ssl = @import("ssl");
const GraphicsBackend = @import("cairo.zig").CairoBackend;
const imr = zervo.markups.imr;
const os = std.os;
const net = std.net;
const warn = std.debug.warn;
const Allocator = std.mem.Allocator;

pub const io_mode = .evented;

fn testHttp(allocator: *Allocator, addr: net.Address, uri: zervo.Uri, path: []const u8) !imr.Document {
    var headers = zervo.protocols.http.HeaderMap.init(allocator);
    try headers.put("Connection", .{
        .value = "close"
    });
    try headers.put("User-Agent", .{
        .value = "Mozilla/5.0 (X11; Linux x86_64; rv:1.0) Gecko/20100101 Beenav/1.0"
    });
    defer headers.deinit();

    var response = try zervo.protocols.http.request(allocator, addr, .{
        .host = uri.host,
        .path = path,
        .headers = headers,
        .secure = true
    });
    defer response.deinit();

    const doc = try zervo.markups.html.parse_imr(allocator, response.content);
    return doc;
}

fn testGemini(allocator: *Allocator, addr: net.Address, uri: zervo.Uri, path: []const u8) !imr.Document {
    var request = async zervo.protocols.gemini.request(allocator, addr, .{
        .host = uri.host,
        .path = path
    });
    var response = try await request;
    defer response.deinit();

    const doc = try zervo.markups.gemini.parse(allocator, response.content);
    std.debug.warn("content: {}\n", .{response.content});
    return doc;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}) {};
    defer _ = gpa.deinit();
    const allocator = &gpa.allocator;

    try ssl.init();
    defer ssl.deinit();

    // gemini://gemini.circumlunar.space:1965/
    // gemini://drewdevault.com/2020/11/10/2020-Election-worker.gmi
    const uri = zervo.Uri {
        .scheme = "gemini",
        .host = "gemini.circumlunar.space",
        .port = null,
        .path = "/"
    };

    std.debug.warn("uri: {}\n", .{uri});

    const list = try net.getAddressList(allocator, uri.host, uri.port orelse 1965);
    defer list.deinit();

    if (list.addrs.len == 0) return error.UnknownHostName;

    var i: u32 = 0;
    var addr = list.addrs[0];
    while (addr.any.family == os.AF_INET6) {
        i += 1;
        addr = list.addrs[i];
    }
    std.debug.warn("address: {}\n", .{addr});

    //var loadFrame = async testHttp(allocator, addr, uri, "/");
    var loadFrame = async testGemini(allocator, addr, uri, "/");
    const doc = try await loadFrame;
    defer doc.deinit();

    // for (doc.tags.items) |tag| {
    //     std.debug.warn("{}\n", .{@tagName(tag.data)});
    // }

    var backend = try GraphicsBackend.init();

    var renderPtr: ?anyframe->void = null;
    while (true) {
        if (renderPtr) |frame| {
            await frame;
            if (!backend.update()) {
                break;
            }
        }
        var f = async zervo.renderer.render(GraphicsBackend, &backend, doc);
        renderPtr = &f;
    }

    backend.deinit();
}
