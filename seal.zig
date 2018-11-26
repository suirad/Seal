const std = @import("std");
const builtin = @import("builtin");
const assert = std.debug.assert;
const assertError = std.debug.assertError;
const mem = std.mem;
const Allocator = mem.Allocator;
const Error = Allocator.Error;

pub const Seal = struct {
    allocator: Allocator,
    wrapped_allocator: *Allocator,
    count: std.atomic.Int(u64),
    allowed_leaks: u64,


    pub fn init(allocator: *Allocator) Seal {
        var self_allocator: Allocator = undefined;
        if (builtin.mode == builtin.Mode.Debug or builtin.mode == builtin.Mode.ReleaseSafe){
            self_allocator = Allocator {
                .allocFn = alloc,
                .reallocFn = realloc,
                .freeFn = free,
            };
        } else {
            self_allocator = Allocator {
                .allocFn = allocator.allocFn,
                .reallocFn = allocator.reallocFn,
                .freeFn = allocator.freeFn,
            };
        }
        return Seal {
            .wrapped_allocator = allocator,
            .allocator = self_allocator,
            .count = std.atomic.Int(u64).init(0),
            .allowed_leaks = 0,
        };
    }

    fn alloc(allocself: *Allocator, byte_count: usize, alignment: u29) Error![]u8 {
        const self = @fieldParentPtr(Seal, "allocator", allocself);
        const ret = try self.wrapped_allocator.allocFn(self.wrapped_allocator, byte_count, alignment);
        _ = self.count.incr();
        return ret;
    }

    fn realloc(allocself: *Allocator, old_mem: []u8, new_mem_size: usize, alignment: u29) Error![]u8 {
        const self = @fieldParentPtr(Seal, "allocator", allocself);
        return try self.wrapped_allocator.reallocFn(
            self.wrapped_allocator,
            old_mem,
            new_mem_size,
            alignment
        );
    }

    fn free(allocself: *Allocator, old_mem: []u8) void {
        const self = @fieldParentPtr(Seal, "allocator", allocself);
        var ret = self.wrapped_allocator.freeFn(self.wrapped_allocator, old_mem);
        _ = self.count.decr();
        return ret;
    }

    pub fn deinit(self: *Seal) !void {
        if (builtin.mode != builtin.Mode.Debug and builtin.mode != builtin.Mode.ReleaseSafe){
            return;
        }

        if (self.count.get() > self.allowed_leaks) {
            return error.LeakDetected;
        }
    }

    pub fn allowLeaks(self: *Seal, num_of_leaks: u64) void {
        self.allowed_leaks = num_of_leaks;
    }
};

test "Wrapping another allocator" {
    var glob_alloc = std.debug.global_allocator;
    var seal = Seal.init(glob_alloc);
    defer seal.deinit() catch {@panic("Leaked memory");};

    var allocator = &seal.allocator;
    
    var one: []u32 = try allocator.alloc(u32, 1);
    one[0] = 1;
    assert(one[0] == 1);
    
    allocator.free(one);
}

test "Throw error on mem leakage" {
    var glob_alloc = std.debug.global_allocator;
    var seal = Seal.init(glob_alloc);

    var allocator = &seal.allocator;

    const num = try allocator.createOne(u32);

    assertError(seal.deinit(), error.LeakDetected);
}

test "Allow a value to be leaked" {
    var glob_alloc = std.debug.global_allocator;
    var seal = Seal.init(glob_alloc);
    defer seal.deinit() catch {@panic("Leaked memory");};

    seal.allowLeaks(1);

    var allocator = &seal.allocator;

    const num = try allocator.createOne(u32);
    defer allocator.destroy(num);
    const num2 = try allocator.createOne(u32);

}

