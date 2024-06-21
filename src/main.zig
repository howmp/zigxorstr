const std = @import("std");
const key = @import("option").key;
const string = []const u8;

fn encrypt(comptime str: string) *[str.len]u8 {
    comptime var enstr: [str.len]u8 = undefined;
    @setEvalBranchQuota(1024 * 1024);
    for (0..str.len) |i| {
        enstr[i] = str[i] ^ key[i % key.len];
    }

    return enstr[0..str.len];
}

inline fn x(comptime str: string) []u8 {
    comptime var e = encrypt(str);
    var buf = e.*;
    for (0..buf.len) |i| {
        buf[i] ^= key[i % key.len];
    }
    return buf[0..str.len];
}

pub fn main() void {
    var s1 = x("aaaabbbbccccddddaaaabbbbccccdddd123123123123123");
    _ = std.io.getStdOut().write(s1) catch unreachable;
}
