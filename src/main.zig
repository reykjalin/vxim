// This can contain internal events as well as Vaxis events.
// Internal events can be posted into the same queue as vaxis events to allow
// for a single event loop with exhaustive switching. Booya
const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
    mouse: vaxis.Mouse,
};

const State = struct {
    mouse: ?vaxis.Mouse = null,
    clicks: usize = 0,
};

var state: State = .{};

var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

pub fn main() !void {
    const gpa, const is_debug = gpa: {
        break :gpa switch (builtin.mode) {
            .Debug, .ReleaseSafe => .{ debug_allocator.allocator(), true },
            .ReleaseFast, .ReleaseSmall => .{ std.heap.smp_allocator, false },
        };
    };
    defer if (is_debug) {
        _ = debug_allocator.deinit();
    };

    try vxim.startLoop(Event, gpa, update);
}

pub fn update(event: Event, ctx: vxim.UpdateContext) anyerror!vxim.UpdateResult {
    switch (event) {
        .key_press => |key| {
            if (key.matches('c', .{ .ctrl = true }))
                return .stop;
        },

        .winsize => {},

        .mouse => |mouse| state.mouse = mouse,
    }

    ctx.root_win.clear();

    const button_text = "Click Me!";

    const button_x: u16 =
        (ctx.root_win.width / 2) -| ((@as(u16, @truncate(button_text.len)) + 2) / 2);
    const button_y: u16 = (ctx.root_win.height / 2) +| 1;

    const button_action =
        vxim.button(
            ctx.root_win,
            .{ .x = button_x, .y = button_y, .text = button_text, .mouse = state.mouse },
        );

    if (button_action == .pressed) {
        state.clicks +|= 1;
    }

    if (button_action == .hovered or button_action == .pressed or button_action == .released)
        ctx.vx.setMouseShape(.pointer)
    else
        ctx.vx.setMouseShape(.default);

    const text = try std.fmt.allocPrint(ctx.arena, "Clicks: {d}", .{state.clicks});
    const text_x: u16 = (ctx.root_win.width / 2) -| (@as(u16, @truncate(text.len)) / 2);
    const text_y: u16 = (ctx.root_win.height / 2) -| 1;

    vxim.text(ctx.root_win, .{ .text = text, .x = text_x, .y = text_y });

    return .keep_going;
}

const std = @import("std");
const builtin = @import("builtin");

const vaxis = @import("vaxis");
const vxim = @import("vxim");
