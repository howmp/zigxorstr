const std = @import("std");
const builtin = @import("builtin");
const key = @import("option").key;
const string = []const u8;
fn xor(comptime str: string) [str.len]u8 {
    const enstr = init: {
        var initial_value: [str.len]u8 = undefined;
        for (&initial_value, 0..) |*c, i| {
            c.* = str[i] ^ key[i % key.len];
        }
        break :init initial_value;
    };
    return enstr;
}

inline fn x(comptime str: string) []u8 {
    // 先在编译时得到加密字符串
    const enstr = comptime xor(str);
    // 通过分块@memcpy，强制生成运行时的赋值指令(不需要rdata)
    var buf: [enstr.len]u8 = undefined;
    comptime var i = 0;
    const block = switch (builtin.cpu.arch) {
        .x86, .x86_64 => @sizeOf(usize) - 1,
        .arm, .aarch64 => @sizeOf(usize) - 1,
        .riscv64 => 4,
        else => @compileError("untested arch"),
    };
    inline while (i + block < enstr.len) : (i += block) {
        @memcpy(buf[i .. i + block], enstr[i .. i + block]);
    }
    @memcpy(buf[i..], enstr[i..]);

    // 运行时解密字符串
    var key_: [key.len]u8 = undefined;
    inline for (0..key.len) |pos| {
        key_[pos] = key[pos];
    }
    for (0..buf.len) |pos| {
        buf[pos] = buf[pos] ^ key_[pos % key.len];
    }
    return &buf;
}
pub fn main() void {
    const s1 = x("aaaabbbbccccddddaaaabbbbccccddddasdasdaaaabbbbccccddddaaaabbbbccccdddd1");
    _ = std.io.getStdOut().write(s1) catch unreachable;
}
