const std = @import("std");
const yxml = @import("yxml.zig");

pub fn main() !void {
    var stack: [8 * 1024]u8 = .{};

    var x: yxml.yxml_t = .{};
    var r: yxml.yxml_ret_t = .YXML_OK;
    // _ = r;
    yxml.yxml_init(&x, @ptrCast(*u8, &stack), @sizeOf(@TypeOf(stack)));

    for (xml_sample0) |v| {
        if (x.total == 92) {
            std.debug.print("break", .{});
        }
        r = yxml.yxml_parse(&x, v);
        y_printres(&x, r);
    }
}

pub fn y_printres(x: *yxml.yxml_t, r: yxml.yxml_ret_t) void {
    var indata: bool = false;
    var nextdata: bool = false;

    switch (r) {
        .YXML_OK => {
            if (verbose) {
                y_printtoken(x, "ok");
                nextdata = false;
            } else {
                nextdata = indata;
            }
        },
        .YXML_ELEMSTART => {
            y_printtoken(x, @constCast("elemstart "));
            y_printstring(x.elem);
            if (yxml.yxml_symlen(x, x.elem) != std.mem.len(x.elem)) {
                y_printtoken(x, @constCast("assertfail: elem lengths don't match"));
            }
        },
        .YXML_ELEMEND => {
            y_printtoken(x, @constCast("elemend"));
        },
        .YXML_ATTRSTART => {
            y_printtoken(x, @constCast("attrstart "));
            y_printstring(x.attr);
            if (yxml.yxml_symlen(x, x.attr) != std.mem.len(x.attr)) {
                y_printtoken(x, @constCast("assertfail: attr lengths don't match"));
            }
        },
        .YXML_ATTREND => {
            y_printtoken(x, @constCast("attrend"));
        },
        .YXML_PICONTENT, .YXML_CONTENT, .YXML_ATTRVAL => {
            if (!indata) {
                if (r == .YXML_CONTENT) {
                    y_printtoken(x, @constCast("content "));
                } else if (r == .YXML_PICONTENT) {
                    y_printtoken(x, @constCast("picontent "));
                } else {
                    y_printtoken(x, @constCast("attrval "));
                }
            }
            y_printstring(@ptrCast([*]u8, &x.data));
            nextdata = true;
        },
        .YXML_PISTART => {
            y_printtoken(x, @constCast("pistart "));
            y_printstring(x.pi);
            if (yxml.yxml_symlen(x, x.pi) != std.mem.len(x.pi)) {
                y_printtoken(x, @constCast("assertfail: pi lengths don't match"));
            }
        },
        .YXML_PIEND => {
            y_printtoken(x, @constCast("piend"));
        },
        else => {
            y_printtoken(x, @constCast("error\n"));
            std.os.exit(0);
        },
    }
    indata = nextdata;
}

pub fn y_printtoken(x: *yxml.yxml_t, str: []const u8) void {
    std.debug.print("\n", .{});
    if (verbose) {
        std.debug.print("t{d: >8}  l{d: >8}  b{d: >8}: ", .{ x.total, x.line, x.byte });
    }
    std.debug.print("{s}", .{str});
}

pub fn y_printstring(str: [*]u8) void {
    var i: usize = 0;
    while (str[i] != 0) {
        y_printchar(str[i]);
        i += 1;
    }
}

pub fn y_printchar(c: u8) void {
    if (c == 0x7F or (c >= 0x00 and c < 0x20)) {
        std.debug.print("\\x{x:0>2}", .{c});
    } else {
        std.debug.print("{c}", .{c});
    }
}

test "simple test" {}

const test_xml0 = "<test>hello</test>";

const xml_sample0 =
    \\<?xml version="1.0" encoding="ISO-8859-1"?>
    \\<!-- Edited by XMLSpy® -->
    \\<note>
    \\	<to>Tove</to>
    \\	<from>Jani</from>
    \\	<heading>Reminder</heading>
    \\	<body>Don't forget me this weekend!</body>
    \\</note>
;

const verbose = true;
