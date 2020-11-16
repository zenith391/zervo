const zervo = @import("zervo");
const std = @import("std");
const ssl = @import("ssl");
const GraphicsBackend = @import("cairo.zig").CairoBackend;
const RenderContext = zervo.renderer.RenderContext(GraphicsBackend);
const imr = zervo.markups.imr;
const os = std.os;
const net = std.net;
const warn = std.debug.warn;
const Allocator = std.mem.Allocator;

pub const io_mode = .evented;

var gpa = std.heap.GeneralPurposeAllocator(.{}) {};
const allocator = &gpa.allocator;

fn testHttp(addr: net.Address, url: zervo.Url) !imr.Document {
    var headers = zervo.protocols.http.HeaderMap.init(allocator);
    try headers.put("Connection", .{
        .value = "close"
    });
    try headers.put("User-Agent", .{
        .value = "Mozilla/5.0 (X11; Linux x86_64; rv:1.0) Gecko/20100101 TestAmabob/1.0"
    });
    defer headers.deinit();

    var response = try zervo.protocols.http.request(allocator, addr, .{
        .host = url.host,
        .path = url.path,
        .headers = headers,
        .secure = true
    });
    defer response.deinit();

    const doc = try zervo.markups.html.parse_imr(allocator, response.content);
    return doc;
}

fn testGemini(addr: net.Address, url: zervo.Url) !imr.Document {
    var request = async zervo.protocols.gemini.request(allocator, addr, url);
    var response = try await request;
    defer response.deinit();

    const doc = try zervo.markups.gemini.parse(allocator, url, response.content);
    std.debug.warn("content: {}\n", .{response.content});
    return doc;
}

fn loadLink(ctx: *RenderContext, url: zervo.Url) !void {
    if (std.mem.eql(u8, url.scheme, "gemini")) {
        std.debug.warn("load gemini {}\n", .{url});
        const list = try net.getAddressList(allocator, url.host, url.port orelse 1965);
        defer list.deinit();
        if (list.addrs.len == 0) return error.UnknownHostName;
        var i: u32 = 0;
        var addr = list.addrs[0];
        while (addr.any.family == os.AF_INET6) {
            i += 1;
            addr = list.addrs[i];
        }
        std.debug.warn("address: {}\n", .{addr});
        var loadFrame = async testGemini(addr, url);
        var doc = try nosuspend await loadFrame;
        //ctx.document.deinit();
        ctx.document = doc;
    } else {
        unreachable;
    }
}

pub fn main() !void {
    defer _ = gpa.deinit();

    try ssl.init();
    defer ssl.deinit();

    // Example URLs:
    // gemini://gemini.circumlunar.space:1965/
    // gemini://drewdevault.com/2020/11/10/2020-Election-worker.gmi
    const url = try zervo.Url.parse("gemini://gemini.circumlunar.space");

    std.debug.warn("url: {}\n", .{url});

    const list = try net.getAddressList(allocator, url.host, url.port orelse 1965);
    defer list.deinit();

    if (list.addrs.len == 0) return error.UnknownHostName;

    var i: u32 = 0;
    var addr = list.addrs[0];
    while (addr.any.family == os.AF_INET6) {
        i += 1;
        addr = list.addrs[i];
    }
    std.debug.warn("address: {}\n", .{addr});

    //var loadFrame = async testHttp(addr, url);
    var loadFrame = async testGemini(addr, url);
    var doc = try await loadFrame;

    var backend = try GraphicsBackend.init();

    var renderCtx = RenderContext { .graphics = &backend, .document = doc, .linkCallback = loadLink };
    var renderPtr: ?anyframe->void = null;
    defer renderCtx.document.deinit();

    renderCtx.setup();
    while (true) {
        if (renderPtr) |frame| {
            await frame;
            if (!backend.update()) {
                break;
            }
        }
        var f = async renderCtx.render();
        renderPtr = &f;
    }

    backend.deinit();
}
