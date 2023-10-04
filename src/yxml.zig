const std = @import("std");

pub const yxml_ret_t = enum(i8) {
    YXML_EEOF = -5, // Unexpected EOF
    YXML_EREF = -4, // Invalid character or entity reference (&whatever;)
    YXML_ECLOSE = -3, // Close tag does not match open tag (<Tag> .. </OtherTag>)
    YXML_ESTACK = -2, // Stack overflow (too deeply nested tags or too long element/attribute name)
    YXML_ESYN = -1, // Syntax error (unexpected byte)
    YXML_OK = 0, // Character consumed, no new token present
    YXML_ELEMSTART = 1, // Start of an element:   '<Tag ..'
    YXML_CONTENT = 2, // Element content
    YXML_ELEMEND = 3, // End of an element:     '.. />' or '</Tag>'
    YXML_ATTRSTART = 4, // Attribute:             'Name=..'
    YXML_ATTRVAL = 5, // Attribute value
    YXML_ATTREND = 6, // End of attribute       '.."'
    YXML_PISTART = 7, // Start of a processing instruction
    YXML_PICONTENT = 8, // Content of a PI
    YXML_PIEND = 9, // End of a processing instruction
};

pub const yxml_t = struct {
    elem: [*c]u8 = null,
    data: [8]u8 = .{ 0, 0, 0, 0, 0, 0, 0, 0 },
    attr: [*c]u8 = null,
    pi: [*c]u8 = null,
    byte: u64 = 0,
    total: u64 = 0,
    line: u32 = 0,

    // state: i32 = 0,
    state: yxml_state_t = undefined,
    stack: [*c]u8 = null,
    stacksize: usize = 0,
    stacklen: usize = 0,
    reflen: u32 = 0,
    quote: u8 = 0,
    nextstate: yxml_state_t = undefined,
    ignore: u32 = 0,
    string: [*c]u8 = null,
};

pub inline fn yxml_symlen(x: *yxml_t, s: [*c]const u8) usize {
    return (@intFromPtr(x.stack) + x.stacklen) - (@intFromPtr(s));
}

const yxml_state_t = enum {
    YXMLS_string,
    YXMLS_attr0,
    YXMLS_attr1,
    YXMLS_attr2,
    YXMLS_attr3,
    YXMLS_attr4,
    YXMLS_cd0,
    YXMLS_cd1,
    YXMLS_cd2,
    YXMLS_comment0,
    YXMLS_comment1,
    YXMLS_comment2,
    YXMLS_comment3,
    YXMLS_comment4,
    YXMLS_dt0,
    YXMLS_dt1,
    YXMLS_dt2,
    YXMLS_dt3,
    YXMLS_dt4,
    YXMLS_elem0,
    YXMLS_elem1,
    YXMLS_elem2,
    YXMLS_elem3,
    YXMLS_enc0,
    YXMLS_enc1,
    YXMLS_enc2,
    YXMLS_enc3,
    YXMLS_etag0,
    YXMLS_etag1,
    YXMLS_etag2,
    YXMLS_init,
    YXMLS_le0,
    YXMLS_le1,
    YXMLS_le2,
    YXMLS_le3,
    YXMLS_lee1,
    YXMLS_lee2,
    YXMLS_leq0,
    YXMLS_misc0,
    YXMLS_misc1,
    YXMLS_misc2,
    YXMLS_misc2a,
    YXMLS_misc3,
    YXMLS_pi0,
    YXMLS_pi1,
    YXMLS_pi2,
    YXMLS_pi3,
    YXMLS_pi4,
    YXMLS_std0,
    YXMLS_std1,
    YXMLS_std2,
    YXMLS_std3,
    YXMLS_ver0,
    YXMLS_ver1,
    YXMLS_ver2,
    YXMLS_ver3,
    YXMLS_xmldecl0,
    YXMLS_xmldecl1,
    YXMLS_xmldecl2,
    YXMLS_xmldecl3,
    YXMLS_xmldecl4,
    YXMLS_xmldecl5,
    YXMLS_xmldecl6,
    YXMLS_xmldecl7,
    YXMLS_xmldecl8,
    YXMLS_xmldecl9,
};

inline fn yxml_isChar(c: u8) bool {
    _ = c;
    return true;
}

inline fn yxml_isSP(c: u8) bool {
    return c == 0x20 or c == 0x09 or c == 0x0a;
}

inline fn yxml_isAlpha(c: u8) bool {
    const ov = @subWithOverflow((c | 32), 'a');
    return ov[0] < 26;
}

inline fn yxml_isNum(c: u8) bool {
    const ov = @subWithOverflow(c, '0');
    return ov[0] < 10;
}

inline fn yxml_isHex(c: u8) bool {
    const ov = @subWithOverflow((c | 32), 'a');
    return yxml_isNum(c) or ov[0] < 6;
}

inline fn yxml_isEncName(c: u8) bool {
    return yxml_isAlpha(c) or yxml_isNum(c) or c == '.' or c == '_' or c == '-';
}

inline fn yxml_isNameStart(c: u8) bool {
    return yxml_isAlpha(c) or c == ':' or c == '_' or c >= 128;
}

inline fn yxml_isName(c: u8) bool {
    return yxml_isNameStart(c) or yxml_isNum(c) or c == '-' or c == '.';
}

inline fn yxml_isAttValue(c: u8, x: *yxml_t) bool {
    return yxml_isChar(c) and c != x.quote and c != '<' and c != '&';
}

inline fn yxml_isRef(c: u8) bool {
    return yxml_isNum(c) or yxml_isAlpha(c) or c == '#';
}

inline fn INTFROM5CHARS(a: u8, b: u8, c: u8, d: u8, e: u8) u64 {
    return (((@as(u64, @intCast(a))) << 32) | ((@as(u64, @intCast(b))) << 24) | ((@as(u64, @intCast(c))) << 16) | ((@as(u64, @intCast(d))) << 8) | (@as(u64, @intCast(e))));
}

inline fn yxml_setchar(dest: *u8, ch: u8) void {
    dest.* = ch;
}

fn yxml_setutf8(dest: [*]u8, ch: u32) void {
    var _dest: [*]u8 = dest;
    if (ch <= 0x007F) {
        yxml_setchar(@as(*u8, @ptrCast(&_dest[0])), @as(u8, @intCast(ch)));
        _dest += 1;
    } else if (ch <= 0x07FF) {
        yxml_setchar(@as(*u8, @ptrCast(&_dest[0])), 0xC0 | @as(u8, @intCast((ch >> 6))));
        _dest += 1;
        yxml_setchar(@as(*u8, @ptrCast(&_dest[0])), 0x80 | @as(u8, @intCast((ch & 0x3F))));
        _dest += 1;
    } else if (ch <= 0xFFFF) {
        yxml_setchar(@as(*u8, @ptrCast(&_dest[0])), 0xE0 | @as(u8, @intCast((ch >> 12))));
        _dest += 1;
        yxml_setchar(@as(*u8, @ptrCast(&_dest[0])), 0x80 | @as(u8, @intCast(((ch >> 6) & 0x3F))));
        _dest += 1;
        yxml_setchar(@as(*u8, @ptrCast(&_dest[0])), 0x80 | @as(u8, @intCast((ch & 0x3F))));
        _dest += 1;
    } else {
        yxml_setchar(@as(*u8, @ptrCast(&_dest[0])), 0xF0 | @as(u8, @intCast((ch >> 18))));
        _dest += 1;
        yxml_setchar(@as(*u8, @ptrCast(&_dest[0])), 0x80 | @as(u8, @intCast(((ch >> 12) & 0x3F))));
        _dest += 1;
        yxml_setchar(@as(*u8, @ptrCast(&_dest[0])), 0x80 | @as(u8, @intCast(((ch >> 6) & 0x3F))));
        _dest += 1;
        yxml_setchar(@as(*u8, @ptrCast(&_dest[0])), 0x80 | @as(u8, @intCast((ch & 0x3F))));
        _dest += 1;
    }
    _dest[0] = 0;
}

inline fn yxml_datacontent(x: *yxml_t, ch: u8) yxml_ret_t {
    yxml_setchar(&x.data[0], ch);
    x.data[1] = 0;
    return .YXML_CONTENT;
}

inline fn yxml_datapi1(x: *yxml_t, ch: u8) yxml_ret_t {
    yxml_setchar(&x.data[0], ch);
    x.data[1] = 0;
    return .YXML_PICONTENT;
}

inline fn yxml_datapi2(x: *yxml_t, ch: u8) yxml_ret_t {
    x.data[0] = '?';
    yxml_setchar(&x.data[1], ch);
    x.data[2] = 0;
    return .YXML_PICONTENT;
}

inline fn yxml_datacd1(x: *yxml_t, ch: u8) yxml_ret_t {
    x.data[0] = ']';
    yxml_setchar(&x.data[1], ch);
    x.data[2] = 0;
    return .YXML_CONTENT;
}

inline fn yxml_datacd2(x: *yxml_t, ch: u8) yxml_ret_t {
    x.data[0] = ']';
    x.data[1] = ']';
    yxml_setchar(&x.data[2], ch);
    x.data[3] = 0;
    return .YXML_CONTENT;
}

inline fn yxml_dataattr(x: *yxml_t, ch: u8) yxml_ret_t {
    var _ch = ch;
    if (ch == 0x9 or ch == 0xa) {
        _ch = 0x20;
    }
    yxml_setchar(&x.data[0], _ch);
    x.data[1] = 0;
    return .YXML_CONTENT;
}

fn yxml_pushstack(x: *yxml_t, res: *[*c]u8, ch: u8) yxml_ret_t {
    if (x.stacklen + 2 >= x.stacksize)
        return .YXML_ESTACK;
    x.stacklen += 1;
    res.* = x.stack + x.stacklen;
    x.stack[x.stacklen] = ch;
    x.stacklen += 1;
    x.stack[x.stacklen] = 0;
    return .YXML_OK;
}

fn yxml_pushstackc(x: *yxml_t, ch: u8) yxml_ret_t {
    if (x.stacklen + 1 >= x.stacksize)
        return .YXML_ESTACK;
    x.stack[x.stacklen] = ch;
    x.stacklen += 1;
    x.stack[x.stacklen] = 0;
    return .YXML_OK;
}

fn yxml_popstack(x: *yxml_t) void {
    x.stacklen -= 1;
    while (x.stack[x.stacklen] != 0) : (x.stacklen -= 1) { //TODO Check Behavior
    }
}

inline fn yxml_elemstart(x: *yxml_t, ch: u8) yxml_ret_t {
    return yxml_pushstack(x, &x.elem, ch);
}

inline fn yxml_elemname(x: *yxml_t, ch: u8) yxml_ret_t {
    return yxml_pushstackc(x, ch);
}

inline fn yxml_elemnameend(x: *yxml_t, ch: u8) yxml_ret_t {
    _ = ch;
    _ = x;
    return .YXML_ELEMSTART;
}

fn yxml_selfclose(x: *yxml_t, ch: u8) yxml_ret_t {
    _ = ch;
    yxml_popstack(x);
    if (x.stacklen != 0) {
        x.elem = x.stack + x.stacklen - 1;
        var tmp = x.elem - 1;
        while (tmp[0] != 0) : (tmp = x.elem - 1) {
            x.elem -= 1;
        }
        return .YXML_ELEMEND;
    }
    x.elem = x.stack;
    x.state = .YXMLS_misc3;
    return .YXML_ELEMEND;
}

inline fn yxml_elemclose(x: *yxml_t, ch: u8) yxml_ret_t {
    if (x.elem.* != ch)
        return .YXML_ECLOSE;
    x.elem += 1;
    return .YXML_OK;
}

inline fn yxml_elemcloseend(x: *yxml_t, ch: u8) yxml_ret_t {
    if (x.elem.* != 0)
        return .YXML_ECLOSE;
    return yxml_selfclose(x, ch);
}

inline fn yxml_attrstart(x: *yxml_t, ch: u8) yxml_ret_t {
    return yxml_pushstack(x, &x.attr, ch);
}

inline fn yxml_attrname(x: *yxml_t, ch: u8) yxml_ret_t {
    return yxml_pushstackc(x, ch);
}

inline fn yxml_attrnameend(x: *yxml_t, ch: u8) yxml_ret_t {
    _ = ch;
    _ = x;
    return .YXML_ATTRSTART;
}

inline fn yxml_attrvalend(x: *yxml_t, ch: u8) yxml_ret_t {
    _ = ch;
    yxml_popstack(x);
    return .YXML_ATTREND;
}

inline fn yxml_pistart(x: *yxml_t, ch: u8) yxml_ret_t {
    return yxml_pushstack(x, &x.pi, ch);
}

inline fn yxml_piname(x: *yxml_t, ch: u8) yxml_ret_t {
    return yxml_pushstackc(x, ch);
}

inline fn yxml_piabort(x: *yxml_t, ch: u8) yxml_ret_t {
    _ = ch;
    yxml_popstack(x);
    return .YXML_OK;
}

inline fn yxml_pinameend(x: *yxml_t, ch: u8) yxml_ret_t {
    _ = ch;
    return if ((x.pi[0] | 32) == 'x' and (x.pi[1] | 32) == 'm' and (x.pi[2] | 32) == 'l' and (x.pi[3] == 0))
        return .YXML_ESYN
    else
        return .YXML_PISTART;
}

inline fn yxml_pivalend(x: *yxml_t, ch: u8) yxml_ret_t {
    _ = ch;
    yxml_popstack(x);
    x.pi = x.stack;
    return .YXML_PIEND;
}

inline fn yxml_refstart(x: *yxml_t, ch: u32) yxml_ret_t {
    _ = ch;
    // @memset(x.data, 0);
    for (0..x.data.len) |v| {
        x.data[v] = 0;
    }
    // x.data = null; //TODO Check Behavior
    // @memset(x.data, 0);
    // for (x.data[0..x.data]) |*b| b.* = 0;
    x.reflen = 0;
    return .YXML_OK;
}

fn yxml_ref(x: *yxml_t, ch: u8) yxml_ret_t {
    if (x.reflen >= @sizeOf([8]u8) - 1)
        return .YXML_EREF;
    yxml_setchar(&x.data[x.reflen], ch);
    x.reflen += 1;
    return .YXML_OK;
}

fn yxml_refend(x: *yxml_t, ret: yxml_ret_t) yxml_ret_t {
    var r: [*]u8 = &x.data;
    var ch: u32 = 0;
    if (r[0] == '#') {
        if (r[1] == 'x') {
            r += 2;
            while (yxml_isHex(r[0])) {
                ch = (ch << 4);
                if (r[0] <= '9') {
                    ch += r[0] - '0';
                } else {
                    ch += (r[0] | 32) - 'a' + 10;
                }
                r += 1;
            }
        } else {
            r += 1;
            while (yxml_isNum(r[0])) {
                ch = ch * 10 + (r[0] - '0');
                r += 1;
            }
        }

        if (r[0] != 0) {
            ch = 0;
        }
    } else {
        var i: u64 = INTFROM5CHARS(r[0], r[1], r[2], r[3], r[4]);
        ch = if (i == INTFROM5CHARS('l', 't', 0, 0, 0))
            '<'
        else if (i == INTFROM5CHARS('g', 't', 0, 0, 0))
            '>'
        else if (i == INTFROM5CHARS('a', 'm', 'p', 0, 0))
            '&'
        else if (i == INTFROM5CHARS('a', 'p', 'o', 's', 0))
            '\''
        else if (i == INTFROM5CHARS('q', 'u', 'o', 't', 0))
            '"'
        else
            0;
    }

    // Codepoints not allowed in the XML 1.1 definition of a Char
    if (ch == 0 or ch > 0x10FFFF or ch == 0xFFFE or ch == 0xFFFF or (ch - 0xDFFF) < 0x7FF)
        return .YXML_EREF;
    yxml_setutf8(&x.data, ch);
    return ret;
}

inline fn yxml_refcontent(x: *yxml_t, ch: u8) yxml_ret_t {
    _ = ch;
    return yxml_refend(x, .YXML_CONTENT);
}

inline fn yxml_refattrval(x: *yxml_t, ch: u8) yxml_ret_t {
    _ = ch;
    return yxml_refend(x, .YXML_ATTRVAL);
}

pub fn yxml_init(x: *yxml_t, stack: *u8, stacksize: usize) void {
    x.* = .{
        .line = 1,
        .stack = stack,
        .stacksize = stacksize,
        .attr = x.stack,
        .pi = x.attr,
        .elem = x.pi,
        .state = yxml_state_t.YXMLS_init,
    };
    x.stack.* = 0;
}

pub fn yxml_parse(x: *yxml_t, _ch: u8) yxml_ret_t {
    var ch = _ch;
    if (ch == 0)
        return .YXML_ESYN;
    x.total += 1;

    if (x.ignore == ch) {
        x.ignore = 0;
        return .YXML_OK;
    }

    if (ch == 0xd) {
        x.ignore = 0xa;
    } else {
        x.ignore = 0;
    }

    if (ch == 0xa or ch == 0xd) {
        ch = 0xa;
        x.line += 1;
        x.byte = 0;
    }
    x.byte += 1;
    switch (x.state) {
        .YXMLS_string => {
            if (ch == x.string.*) {
                x.string += 1;
                if (x.string.* == 0)
                    x.state = x.nextstate;
                return .YXML_OK;
            }
        },
        .YXMLS_attr0 => {
            if (yxml_isName(ch))
                return yxml_attrname(x, ch);
            if (yxml_isSP(ch)) {
                x.state = .YXMLS_attr1;
                return yxml_attrnameend(x, ch);
            }
            if (ch == '=') {
                x.state = .YXMLS_attr2;
                return yxml_attrnameend(x, ch);
            }
        },
        .YXMLS_attr1 => {
            if (yxml_isSP(ch))
                return .YXML_OK;
            if (ch == '=') {
                x.state = .YXMLS_attr2;
                return .YXML_OK;
            }
        },
        .YXMLS_attr2 => {
            if (yxml_isSP(ch))
                return yxml_ret_t.YXML_OK;
            if (ch == '"' or ch == '\'') {
                x.state = .YXMLS_attr3;
                x.string = ch;
                return .YXML_OK;
            }
        },
        .YXMLS_attr3 => {
            if (yxml_isAttValue(ch, x)) {
                return yxml_dataattr(x, ch);
            }
            if (ch == '&') {
                x.state = .YXMLS_attr4;
                return yxml_refstart(x, ch);
            }
            if (x.quote == ch) {
                x.state = .YXMLS_elem2;
                return yxml_attrvalend(x, ch);
            }
        },
        .YXMLS_attr4 => {
            if (yxml_isRef(ch))
                return yxml_ref(x, ch);
            if (ch == '\x3b') {
                x.state = .YXMLS_attr3;
                return yxml_refattrval(x, ch);
            }
        },
        .YXMLS_cd0 => {
            if (ch == ']') {
                x.state = .YXMLS_cd1;
                return .YXML_OK;
            }
            if (yxml_isChar(ch))
                return yxml_datacontent(x, ch);
        },
        .YXMLS_cd1 => {
            if (ch == ']') {
                x.state = .YXMLS_cd2;
                return .YXML_OK;
            }
            if (yxml_isChar(ch)) {
                x.state = .YXMLS_cd0;
                return yxml_datacontent(x, ch);
            }
        },
        .YXMLS_cd2 => {
            if (ch == ']') {
                return yxml_datacontent(x, ch);
            }
            if (ch == '>') {
                x.state = .YXMLS_misc2;
                return .YXML_OK;
            }
            if (yxml_isChar(ch)) {
                x.state = .YXMLS_cd0;
                return yxml_datacd2(x, ch);
            }
        },
        .YXMLS_comment0 => {
            if (ch == '-') {
                x.state = .YXMLS_comment1;
                return .YXML_OK;
            }
        },
        .YXMLS_comment1 => {
            if (ch == '-') {
                x.state = .YXMLS_comment2;
                return .YXML_OK;
            }
        },
        .YXMLS_comment2 => {
            if (ch == '-') {
                x.state = .YXMLS_comment3;
                return .YXML_OK;
            }
            if (yxml_isChar(ch))
                return .YXML_OK;
        },
        .YXMLS_comment3 => {
            if (ch == '-') {
                x.state = .YXMLS_comment4;
                return .YXML_OK;
            }
            if (yxml_isChar(ch)) {
                x.state = .YXMLS_comment2;
                return .YXML_OK;
            }
        },
        .YXMLS_comment4 => {
            if (ch == '>') {
                x.state = x.nextstate;
                return .YXML_OK;
            }
        },
        .YXMLS_dt0 => {
            if (ch == '>') {
                x.state = .YXMLS_misc1;
                return .YXML_OK;
            }
            if (ch == '\'' or ch == '"') {
                x.state = .YXMLS_dt1;
                x.quote = ch;
                x.nextstate = .YXMLS_dt0;
                return .YXML_OK;
            }
            if (ch == '<') {
                x.state = .YXMLS_dt2;
                return .YXML_OK;
            }
            if (yxml_isChar(ch))
                return .YXML_OK;
        },
        .YXMLS_dt1 => {
            if (ch == x.quote) {
                x.state = x.nextstate;
                return .YXML_OK;
            }
            if (yxml_isChar(ch))
                return .YXML_OK;
        },
        .YXMLS_dt2 => {
            if (ch == '?') {
                x.state = .YXMLS_pi0;
                x.nextstate = .YXMLS_dt0;
                return .YXML_OK;
            }
            if (ch == '!') {
                x.state = .YXMLS_dt3;
                return .YXML_OK;
            }
        },
        .YXMLS_dt3 => {
            if (ch == '-') {
                x.state = .YXMLS_comment1;
                x.nextstate = .YXMLS_dt0;
                return .YXML_OK;
            }
            if (yxml_isChar(ch)) {
                x.state = .YXMLS_dt4;
                return .YXML_OK;
            }
        },
        .YXMLS_dt4 => {
            if (ch == '\'' or ch == '"') {
                x.state = .YXMLS_dt1;
                x.quote = ch;
                x.nextstate = .YXMLS_dt4;
                return .YXML_OK;
            }
            if (ch == '>') {
                x.state = .YXMLS_dt0;
                return .YXML_OK;
            }
            if (yxml_isChar(ch)) {
                return .YXML_OK;
            }
        },
        .YXMLS_elem0 => {
            if (yxml_isName(ch))
                return yxml_elemname(x, ch);
            if (yxml_isSP(ch)) {
                x.state = .YXMLS_elem1;
                return yxml_elemnameend(x, ch);
            }
            if (ch == '/') {
                x.state = .YXMLS_elem3;
                return yxml_elemnameend(x, ch);
            }
            if (ch == '>') {
                x.state = .YXMLS_misc2;
                return yxml_elemnameend(x, ch);
            }
        },
        .YXMLS_elem1 => {
            if (yxml_isSP(ch))
                return .YXML_OK;
            if (ch == '/') {
                x.state = .YXMLS_elem3;
                return .YXML_OK;
            }
            if (ch == '>') {
                x.state = .YXMLS_misc2;
                return .YXML_OK;
            }
            if (yxml_isNameStart(ch)) {
                x.state = .YXMLS_attr0;
                return yxml_attrstart(x, ch);
            }
        },
        .YXMLS_elem2 => {
            if (yxml_isSP(ch)) {
                x.state = .YXMLS_elem1;
                return .YXML_OK;
            }
            if (ch == '/') {
                x.state = .YXMLS_elem3;
                return .YXML_OK;
            }
            if (ch == '>') {
                x.state = .YXMLS_misc2;
                return .YXML_OK;
            }
        },
        .YXMLS_elem3 => {
            if (ch == '>') {
                x.state = .YXMLS_misc2;
                return yxml_selfclose(x, ch);
            }
        },
        .YXMLS_enc0 => {
            if (yxml_isSP(ch))
                return .YXML_OK;
            if (ch == '=') {
                x.state = .YXMLS_enc1;
                return .YXML_OK;
            }
        },
        .YXMLS_enc1 => {
            if (yxml_isSP(ch))
                return .YXML_OK;
            if (ch == '\'' or ch == '"') {
                x.state = .YXMLS_enc2;
                x.quote = ch;
                return .YXML_OK;
            }
        },
        .YXMLS_enc2 => {
            if (yxml_isAlpha(ch)) {
                x.state = .YXMLS_enc3;
                return .YXML_OK;
            }
        },
        .YXMLS_enc3 => {
            if (yxml_isEncName(ch))
                return .YXML_OK;
            if (x.quote == ch) {
                x.state = .YXMLS_xmldecl6;
                return .YXML_OK;
            }
        },
        .YXMLS_etag0 => {
            if (yxml_isNameStart(ch)) {
                x.state = .YXMLS_etag1;
                return yxml_elemclose(x, ch);
            }
        },
        .YXMLS_etag1 => {
            if (yxml_isName(ch))
                return yxml_elemclose(x, ch);
            if (yxml_isSP(ch)) {
                x.state = .YXMLS_etag2;
                return yxml_elemcloseend(x, ch);
            }
            if (ch == '>') {
                x.state = .YXMLS_misc2;
                return yxml_elemcloseend(x, ch);
            }
        },
        .YXMLS_etag2 => {
            if (yxml_isSP(ch))
                return .YXML_OK;
            if (ch == '>') {
                x.state = .YXMLS_misc2;
                return .YXML_OK;
            }
        },
        .YXMLS_init => {
            if (ch == '\xef') {
                x.state = .YXMLS_string;
                x.nextstate = .YXMLS_misc0;
                x.string = @constCast("\xbb\xbf"); //TODO Check Behavior
                return .YXML_OK;
            }
            if (yxml_isSP(ch)) {
                x.state = .YXMLS_misc0;
                return .YXML_OK;
            }
            if (ch == '<') {
                x.state = .YXMLS_le0;
                return .YXML_OK;
            }
        },
        .YXMLS_le0 => {
            if (ch == '!') {
                x.state = .YXMLS_lee1;
                return .YXML_OK;
            }
            if (ch == '?') {
                x.state = .YXMLS_leq0;
                return .YXML_OK;
            }
            if (yxml_isNameStart(ch)) {
                x.state = .YXMLS_elem0;
                return yxml_elemstart(x, ch);
            }
        },
        .YXMLS_le1 => {
            if (ch == '!') {
                x.state = .YXMLS_lee1;
                return .YXML_OK;
            }
            if (ch == '?') {
                x.state = .YXMLS_pi0;
                x.nextstate = .YXMLS_misc1;
                return .YXML_OK;
            }
            if (yxml_isNameStart(ch)) {
                x.state = .YXMLS_elem0;
                return yxml_elemstart(x, ch);
            }
        },
        .YXMLS_le2 => {
            if (ch == '!') {
                x.state = .YXMLS_lee2;
                return .YXML_OK;
            }
            if (ch == '?') {
                x.state = .YXMLS_pi0;
                x.nextstate = .YXMLS_misc2;
                return .YXML_OK;
            }
            if (ch == '/') {
                x.state = .YXMLS_etag0;
                return .YXML_OK;
            }
            if (yxml_isNameStart(ch)) {
                x.state = .YXMLS_elem0;
                return yxml_elemstart(x, ch);
            }
        },
        .YXMLS_le3 => {
            if (ch == '!') {
                x.state = .YXMLS_comment0;
                x.nextstate = .YXMLS_misc3;
                return .YXML_OK;
            }
            if (ch == '?') {
                x.state = .YXMLS_pi0;
                x.nextstate = .YXMLS_misc3;
                return .YXML_OK;
            }
        },
        .YXMLS_lee1 => {
            if (ch == '-') {
                x.state = .YXMLS_comment1;
                x.nextstate = .YXMLS_misc1;
                return .YXML_OK;
            }
            if (ch == 'D') {
                x.state = .YXMLS_string;
                x.nextstate = .YXMLS_dt0;
                x.string = @constCast("OCTYPE");
                return .YXML_OK;
            }
        },
        .YXMLS_lee2 => {
            if (ch == '-') {
                x.state = .YXMLS_comment1;
                x.nextstate = .YXMLS_misc2;
                return .YXML_OK;
            }
            if (ch == '[') {
                x.state = .YXMLS_string;
                x.nextstate = .YXMLS_cd0;
                x.string = @constCast("CDATA[");
                return .YXML_OK;
            }
        },
        .YXMLS_leq0 => {
            if (ch == 'x') {
                x.state = .YXMLS_xmldecl0;
                x.nextstate = .YXMLS_misc1;
                return yxml_pistart(x, ch);
            }
            if (yxml_isNameStart(ch)) {
                x.state = .YXMLS_pi1;
                x.nextstate = .YXMLS_misc1;
                return yxml_pistart(x, ch);
            }
        },
        .YXMLS_misc0 => {
            if (yxml_isSP(ch))
                return .YXML_OK;
            if (ch == '<') {
                x.state = .YXMLS_le0;
                return .YXML_OK;
            }
        },
        .YXMLS_misc1 => {
            if (yxml_isSP(ch))
                return .YXML_OK;
            if (ch == '<') {
                x.state = .YXMLS_le1;
                return .YXML_OK;
            }
        },
        .YXMLS_misc2 => {
            if (ch == '<') {
                x.state = .YXMLS_le2;
                return .YXML_OK;
            }
            if (ch == '&') {
                x.state = .YXMLS_misc2a;
                return yxml_refstart(x, ch);
            }
            if (yxml_isChar(ch))
                return yxml_datacontent(x, ch);
        },
        .YXMLS_misc2a => {
            if (yxml_isRef(ch))
                return yxml_ref(x, ch);
            if (ch == '\x3b') {
                x.state = .YXMLS_misc2;
                return yxml_refcontent(x, ch);
            }
        },
        .YXMLS_misc3 => {
            if (yxml_isSP(ch))
                return .YXML_OK;
            if (ch == '<') {
                x.state = .YXMLS_le3;
                return .YXML_OK;
            }
        },
        .YXMLS_pi0 => {
            if (yxml_isNameStart(ch)) {
                x.state = .YXMLS_pi1;
                return yxml_pistart(x, ch);
            }
        },
        .YXMLS_pi1 => {
            if (yxml_isName(ch))
                return yxml_piname(x, ch);
            if (ch == '?') {
                x.state = .YXMLS_pi4;
                return yxml_pinameend(x, ch);
            }
            if (yxml_isSP(ch)) {
                x.state = .YXMLS_pi2;
                return yxml_pinameend(x, ch);
            }
        },
        .YXMLS_pi2 => {
            if (ch == '?') {
                x.state = .YXMLS_pi3;
                return .YXML_OK;
            }
            if (yxml_isChar(ch))
                return yxml_datapi1(x, ch);
        },
        .YXMLS_pi3 => {
            if (ch == '>') {
                x.state = x.nextstate;
                return yxml_pivalend(x, ch);
            }
            if (yxml_isChar(ch)) {
                x.state = .YXMLS_pi2;
                return yxml_datapi2(x, ch);
            }
        },
        .YXMLS_pi4 => {
            if (ch == '>') {
                x.state = x.nextstate;
                return yxml_pivalend(x, ch);
            }
        },
        .YXMLS_std0 => {
            if (yxml_isSP(ch))
                return .YXML_OK;
            if (ch == '=') {
                x.state = .YXMLS_std1;
                return .YXML_OK;
            }
        },
        .YXMLS_std1 => {
            if (yxml_isSP(ch))
                return .YXML_OK;
            if (ch == '\'' or ch == '"') {
                x.state = .YXMLS_std2;
                x.quote = ch;
                return .YXML_OK;
            }
        },
        .YXMLS_std2 => {
            if (ch == 'y') {
                x.state = .YXMLS_string;
                x.nextstate = .YXMLS_std3;
                x.string = @constCast("es");
                return .YXML_OK;
            }
            if (ch == 'n') {
                x.state = .YXMLS_string;
                x.nextstate = .YXMLS_std3;
                x.string = @constCast("o");
                return .YXML_OK;
            }
        },
        .YXMLS_std3 => {
            if (x.quote == ch) {
                x.state = .YXMLS_xmldecl8;
                return .YXML_OK;
            }
        },
        .YXMLS_ver0 => {
            if (yxml_isSP(ch))
                return .YXML_OK;
            if (ch == '=') {
                x.state = .YXMLS_ver1;
                return .YXML_OK;
            }
        },
        .YXMLS_ver1 => {
            if (yxml_isSP(ch))
                return .YXML_OK;
            if (ch == '\'' or ch == '"') {
                x.state = .YXMLS_string;
                x.quote = ch;
                x.nextstate = .YXMLS_ver2;
                x.string = @constCast("1.");
                return .YXML_OK;
            }
        },
        .YXMLS_ver2 => {
            if (yxml_isNum(ch)) {
                x.state = .YXMLS_ver3;
                return .YXML_OK;
            }
        },
        .YXMLS_ver3 => {
            if (yxml_isNum(ch))
                return .YXML_OK;
            if (x.quote == ch) {
                x.state = .YXMLS_xmldecl4;
                return .YXML_OK;
            }
        },
        .YXMLS_xmldecl0 => {
            if (ch == 'm') {
                x.state = .YXMLS_xmldecl1;
                return yxml_piname(x, ch);
            }
            if (yxml_isName(ch)) {
                x.state = .YXMLS_pi1;
                return yxml_piname(x, ch);
            }
            if (ch == '?') {
                x.state = .YXMLS_pi4;
                return yxml_pinameend(x, ch);
            }
            if (yxml_isSP(ch)) {
                x.state = .YXMLS_pi2;
                return yxml_pinameend(x, ch);
            }
        },
        .YXMLS_xmldecl1 => {
            if (ch == 'l') {
                x.state = .YXMLS_xmldecl2;
                return yxml_piname(x, ch);
            }
            if (yxml_isName(ch)) {
                x.state = .YXMLS_pi1;
                return yxml_piname(x, ch);
            }
            if (ch == '?') {
                x.state = .YXMLS_pi4;
                return yxml_pinameend(x, ch);
            }
            if (yxml_isSP(ch)) {
                x.state = .YXMLS_pi2;
                return yxml_pinameend(x, ch);
            }
        },
        .YXMLS_xmldecl2 => {
            if (yxml_isSP(ch)) {
                x.state = .YXMLS_xmldecl3;
                return yxml_piabort(x, ch);
            }
            if (yxml_isName(ch)) {
                x.state = .YXMLS_pi1;
                return yxml_piname(x, ch);
            }
        },
        .YXMLS_xmldecl3 => {
            if (yxml_isSP(ch))
                return .YXML_OK;
            if (ch == 'v') {
                x.state = .YXMLS_string;
                x.nextstate = .YXMLS_ver0;
                x.string = @constCast("ersion");
                return .YXML_OK;
            }
        },
        .YXMLS_xmldecl4 => {
            if (yxml_isSP(ch)) {
                x.state = .YXMLS_xmldecl5;
                return .YXML_OK;
            }
            if (ch == '?') {
                x.state = .YXMLS_xmldecl9;
                return .YXML_OK;
            }
        },
        .YXMLS_xmldecl5 => {
            if (yxml_isSP(ch))
                return .YXML_OK;
            if (ch == '?') {
                x.state = .YXMLS_xmldecl9;
                return .YXML_OK;
            }
            if (ch == 'e') {
                x.state = .YXMLS_string;
                x.nextstate = .YXMLS_enc0;
                x.string = @constCast("ncoding");
                return .YXML_OK;
            }
            if (ch == 's') {
                x.state = .YXMLS_string;
                x.nextstate = .YXMLS_std0;
                x.string = @constCast("tandalone");
                return .YXML_OK;
            }
        },
        .YXMLS_xmldecl6 => {
            if (yxml_isSP(ch)) {
                x.state = .YXMLS_xmldecl7;
                return .YXML_OK;
            }
            if (ch == '?') {
                x.state = .YXMLS_xmldecl9;
                return .YXML_OK;
            }
        },
        .YXMLS_xmldecl7 => {
            if (yxml_isSP(ch))
                return .YXML_OK;
            if (ch == '?') {
                x.state = .YXMLS_xmldecl9;
                return .YXML_OK;
            }
            if (ch == 's') {
                x.state = .YXMLS_string;
                x.nextstate = .YXMLS_std0;
                x.string = @constCast("tandalone");
                return .YXML_OK;
            }
        },
        .YXMLS_xmldecl8 => {
            if (yxml_isSP(ch))
                return .YXML_OK;
            if (ch == '?') {
                x.state = .YXMLS_xmldecl9;
                return .YXML_OK;
            }
        },
        .YXMLS_xmldecl9 => {
            if (ch == '>') {
                x.state = .YXMLS_misc1;
                return .YXML_OK;
            }
        },
    }
    return .YXML_ESYN;
}

pub fn yxml_eof(x: *yxml_t) yxml_ret_t {
    if (x.state != .YXMLS_misc3)
        return .YXML_EEOF;
    return .YXML_OK;
}
