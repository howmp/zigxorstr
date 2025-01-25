# zigxorstr

编译时对字符串常量加密,在产物中敏感字符串不以明文存储，所以在特征免杀中有较好的效果。

## 其他常见的方案

### 使用LLVM pass实现字符串加密

通常思路都是在pass中对字符串常量加密并添加解密函数，在初始化或者引用时解密字符串。

从稳定性上看，需要实现临界区或增加标志位，防止多线程竞争同时解密。

从免杀效果上看，由于字符串仍在原地解密，无法绕过内存查杀。

参考链接:

* <https://github.com/Breathleas/notes-2/blob/master/llvm/ollvm/3_string_encrypt.md>
* <https://github.com/tsarpaul/llvm-string-obfuscator>
* <https://obfuscator.re/omvll/passes/strings-encoding/>
* <https://github.com/61bcdefg/Hikari-LLVM15>

### C++17 constexpr

<https://github.com/JustasMasiulis/xorstr> 是通过C++17 constexpr特性实现的字符串常量加密。

来看一个xorstr的例子

```c
int main() {
    std::puts(xorstr_("an extra long hello_world"));
}
```

```asm
movabs rax, -4762152789334367252
push rbp
mov rbp, rsp
and rsp, -32
sub rsp, 64
mov QWORD PTR [rsp], rax
mov rdi, rsp
movabs rax, -6534519754492314190
mov QWORD PTR [rsp+8], rax
......
vpxor ymm0, ymm1, YMMWORD PTR [rsp+32]
vmovdqa YMMWORD PTR [rsp], ymm0
vzeroupper
call puts
xor eax, eax
leave
ret
```

相对于llvm的方案而言优势在于将字符串常量解密在栈上

1. 完成就没有线程安全问题了
1. 栈上内存可能很快就被覆盖，一定程度上也解决了内存查杀问题

另外就是支持x86,arm下通过AVX、SSE、NEON等指令进行加速解密。

最大问题也非常突出: ~~C++狗都不学~~ C++从学习难度，产物体积等完全没有优势

## 用zig实现编译时字符串常量加密

本文使用zig 0.13.0

zig也有类似于C++17 constexpr的特性，使用 `comptime` 关键字 

官方文档在此: <https://ziglang.org/documentation/0.13.0/#comptime>

通过很简单的代码即可实现编译时字符串常量加密，如下:

```zig
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
```

```asm
  movabs rax, 8245869312136934253
  movabs rsi, 3778634648996296306
  movabs rdx, 8014000979142798644
  mov word ptr [rsp - 75], 4364
  mov byte ptr [rsp - 73], 85
  xor ecx, ecx
  mov qword ptr [rsp - 69], rax
  mov dword ptr [rsp - 72], 1832153197
  mov qword ptr [rsp - 62], rsi
  movabs rsi, 8460066280462250607
  mov qword ptr [rsp - 55], rdx
  movabs rdx, 3780067325533697141
  mov qword ptr [rsp - 48], rsi
  movabs rsi, 7941943385054539060
  mov qword ptr [rsp - 41], rdx
  movabs rdx, 8460066267577348718
  mov qword ptr [rsp - 34], rsi
  movabs rsi, 3995657366399693173
  mov qword ptr [rsp - 27], rdx
  movabs rdx, 7509315250667351607
  mov qword ptr [rsp - 20], rsi
  movabs rsi, 3
  mov qword ptr [rsp - 13], rdx
  mov dword ptr [rsp - 6], 1748071784
  mov byte ptr [rsp - 2], 32
.LBB5_1:
  mov rax, rcx
  xor edx, edx
  div rsi
  cmp rcx, 71
  je .LBB5_3
  imul rax, rax, -3
  lea rax, [rsp + rax - 75]
  mov al, byte ptr [rax + rcx]
  xor byte ptr [rsp + rcx - 72], al
  inc rcx
  jmp .LBB5_1
.LBB5_3:
  movabs rdi, 1
  lea rsi, [rsp - 72]
  movabs rdx, 71
  xor r8d, r8d
.LBB5_4:
  mov rax, rdi
  syscall
  mov ecx, eax
  neg ecx
  cmp rax, -4095
  cmovb ecx, r8d
  cmp cx, 4
  je .LBB5_4
  ret
```

可以点击此链接体验: <https://zig.godbolt.org/z/dTzbe8arY>

### 实现动态密钥

上面的例子的key是固定的，如果在zig使用中每次编译生成不通的key?

参考: <https://ziggit.dev/t/how-to-implement-conditional-compilation-in-zig/379/3>

在build.zig中添加,相当于定义了一个 `option` 模块，并添加了 `key` 的定义

```zig
var options = b.addOptions();
var key: [3]u8 = undefined;
std.crypto.random.bytes(&key);
options.addOption([3]u8, "key", key);
exe.root_module.addOptions("option", options);
```

并修改main.zig中key的定义

```zig
const key = @import("option").key;
```

### 更新历史

#### 2025年1月25日

1. 更新到zig 0.13.0
1. 通过负优化不需要引用常量(没有只读数据段rdata/rodata)