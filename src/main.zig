// This can contain internal events as well as Vaxis events.
// Internal events can be posted into the same queue as vaxis events to allow
// for a single event loop with exhaustive switching. Booya
const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
    mouse: vaxis.Mouse,
};

const Vxim = vxim.Vxim(Event);

const Menu = enum {
    File,
};

const State = struct {
    mouse: ?vaxis.Mouse = null,
    clicks: usize = 0,
    open_menu: ?Menu = null,
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

    var vx: Vxim = .{};

    try vx.startLoop(gpa, update);
}

pub fn update(event: Event, ctx: Vxim.UpdateContext) anyerror!Vxim.UpdateResult {
    switch (event) {
        .key_press => |key| {
            if (key.matches('c', .{ .ctrl = true }))
                return .stop;
        },

        .winsize => {},

        .mouse => |mouse| state.mouse = mouse,
    }

    ctx.root_win.clear();

    // Menu Bar
    {
        const menu_bar = ctx.root_win.child(.{
            .width = ctx.root_win.width,
            .height = 1,
            .x_off = 0,
            .y_off = 0,
        });
        // menu_bar.fill(.{ .style = .{ .bg = .{ .index = 15 } } });

        const file_button = ctx.vxim.button(menu_bar, .{
            .mouse = state.mouse,
            .x = 0,
            .y = 0,
            .text = "File",
        });

        if (file_button == .pressed) {
            state.open_menu = .File;
        }
    }

    // File Menu
    if (state.open_menu == .File) {
        const file_menu = ctx.root_win.child(.{
            .width = 7,
            .height = 1,
            .x_off = 0,
            .y_off = 1,
        });

        const about_button = ctx.vxim.button(file_menu, .{
            .mouse = state.mouse,
            .x = 0,
            .y = 0,
            .text = "About",
        });

        _ = about_button;

        if (file_menu.hasMouse(state.mouse) == null) {
            if (state.mouse.?.type == .press) state.open_menu = null;
        }
    }

    // Main section of the app.
    {
        const modal_width = @min(40, ctx.root_win.width);
        const modal_height = @min(7, ctx.root_win.height);
        const modal = ctx.root_win.child(.{
            .width = modal_width,
            .height = modal_height,
            .x_off = ctx.root_win.width / 2 -| modal_width / 2,
            .y_off = ctx.root_win.height / 2 -| modal_height / 2,
            .border = .{ .where = .all },
        });
        const button_text = "Click Me!";

        const button_x: u16 =
            (modal_width / 2) -| ((@as(u16, @truncate(button_text.len)) + 2) / 2);
        const button_y: u16 = (modal_height / 2);

        const button_action =
            ctx.vxim.button(
                modal,
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
        const text_x: u16 = (modal_width / 2) -| (@as(u16, @truncate(text.len)) / 2);
        const text_y: u16 = (modal_height / 2) -| 2;

        ctx.vxim.text(modal, .{ .text = text, .x = text_x, .y = text_y });
    }

    return .keep_going;
}

const std = @import("std");
const builtin = @import("builtin");

const vaxis = @import("vaxis");
const vxim = @import("vxim");
