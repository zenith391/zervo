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

//pub const io_mode = .evented;

const DISABLE_IPV4 = true;

var gpa = std.heap.GeneralPurposeAllocator(.{}) {};
const allocator = &gpa.allocator;
var currentUrl: ?zervo.Url = null;

const LoadResult = union(enum) {
    Document: imr.Document,
    Download: []const u8
};

fn loadHttp(addr: net.Address, url: zervo.Url) !imr.Document {
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

fn loadGemini(addr: net.Address, url: zervo.Url) !LoadResult {
    var request = async zervo.protocols.gemini.request(allocator, addr, url);
    var response = try await request;
    defer response.deinit();

    if (response.statusCode != 20) {
        std.log.err("Request error:\nStatus code: {} {s}", .{response.statusCode, response.meta});
        return zervo.protocols.gemini.GeminiError.InvalidStatus;
    }

    const mime = response.meta;
    if (try zervo.markups.from_mime(allocator, url, mime, response.content)) |doc| {
        std.log.info("content: {s}", .{response.content});
        return LoadResult {
            .Document = doc
        };
    } else {
        return LoadResult {
            .Download = try allocator.dupe(u8, response.content)
        };
    }
}

fn loadPage(url: zervo.Url) !LoadResult {
    std.log.info("Loading web page at {} host = {s}", .{url, url.host});

    var defaultPort: u16 = 80;
    if (std.mem.eql(u8, url.scheme, "gemini")) defaultPort = 1965;
    if (std.mem.eql(u8, url.scheme, "https")) defaultPort = 443;

    const list = try net.getAddressList(allocator, url.host, url.port orelse defaultPort);
    defer list.deinit();
    if (list.addrs.len == 0) return error.UnknownHostName;
    var addr = list.addrs[0];
    if (DISABLE_IPV4) {
        var i: u32 = 1;
        while (addr.any.family == os.AF_INET6) : (i += 1) {
            addr = list.addrs[i];
        }
    }
    std.log.info("Resolved address of {s}: {}", .{url.host, addr});

    if (std.mem.eql(u8, url.scheme, "gemini")) {
        var loadFrame = async loadGemini(addr, url);
        return try await loadFrame;
    } else {
        std.log.err("cannot load URL with scheme {s}", .{url.scheme});
        return error.UnknownHostName;
    }
}

fn loadPageChecked(url: zervo.Url) ?LoadResult {
    const doc = loadPage(url) catch |err| switch (err) {
        else => {
            std.log.err("TODO: return an error page for error {s}", .{@errorName(err)});
            if (@errorReturnTrace()) |trace| {
                std.debug.dumpStackTrace(trace.*);
            }
            return null;
        }
    };
    return doc;
}

// Handlers
fn loadLink(ctx: *RenderContext, url: zervo.Url) !void {
    if (loadPageChecked(url)) |result| {
        switch (result) {
            .Document => |doc| {
                if (currentUrl) |u| {
                    u.deinit();
                }
                currentUrl = try url.dupe(allocator);
                ctx.document.deinit();
                ctx.document = doc;
                ctx.layout();
                ctx.offsetY = 0;
                ctx.offsetYTarget = 0;
            },
            .Download => |content| {
                defer allocator.free(content);

                const lastSlash = std.mem.lastIndexOfScalar(u8, url.path, '/').?;
                const name = url.path[lastSlash+1..];
                const file = try std.fs.cwd().createFile(name, .{});
                try file.writeAll(content);
                file.close();
                std.log.info("Saved to {s}", .{name});

                var xdg = try std.ChildProcess.init(&[_][]const u8 {"xdg-open", name}, allocator);
                defer xdg.deinit();
                _ = try xdg.spawnAndWait();
            }
        }
    }
}

// Main function
pub fn main() !void {
    defer _ = gpa.deinit();

    try ssl.init();
    defer ssl.deinit();

    // Example URLs:
    //  gemini://gemini.circumlunar.space:1965/
    //  gemini://drewdevault.com/
    //  gemini://skyjake.fi:1965/lagrange/
    const url = try zervo.Url.parse("gemini://drewdevault.com/");

    const doc: imr.Document = (try loadPage(url)).Document;
    currentUrl = url;
    defer currentUrl.?.deinit();

    var backend = try GraphicsBackend.init();

    var renderCtx = RenderContext { .graphics = &backend, .document = doc, .linkCallback = loadLink };
    var renderPtr: ?anyframe->void = null;
    defer renderCtx.document.deinit();

    renderCtx.setup();
    renderCtx.layout();
    renderCtx.y = 50;
    var addressBarBuf: [1024]u8 = undefined;
    var addressBarFocused: bool = false;
    while (true) {
        if (backend.frame_requested) {
            const g = &backend;
            g.clear();
            renderCtx.layout(); // TODO: only layout on resize and page changes
            renderCtx.render();

            g.moveTo(0, 0);
            g.setSourceRGB(0.5, 0.5, 0.5);
            g.rectangle(0, 0, g.getWidth(), 50);
            g.fill();
            g.setSourceRGB(0.1, 0.1, 0.1);
            g.rectangle(80, 10, g.getWidth() - 90, 30);
            g.fill();

            if (currentUrl) |u| {
                g.moveTo(90, 14);
                g.setFontFace("Nunito");
                g.setFontSize(10);
                g.setTextWrap(null);
                g.setSourceRGB(1, 1, 1);
                g.text(try std.fmt.bufPrintZ(&addressBarBuf, "{}", .{currentUrl}));
                g.stroke();
            }
        }
        if (!backend.update()) {
            break;
        }
    }

    backend.deinit();
}
