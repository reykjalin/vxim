// This can contain internal events as well as Vaxis events.
// Internal events can be posted into the same queue as vaxis events to allow
// for a single event loop with exhaustive switching. Booya
const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
    mouse: vaxis.Mouse,
    mouse_focus: vaxis.Mouse,
};

const Widget = enum(u32) {
    FileMenu,
    AboutButton,
    AboutWindow,
    QuitButton,
    CloseAboutButton,
    ClickMe,
    CounterModal,
    ScrollDemoWindow,
    ScrollDemoContent,
};

const Vxim = vxim.Vxim(Event, Widget);

const Menu = enum {
    File,
};

const Window = enum {
    About,
};

const State = struct {
    mouse: ?vaxis.Mouse = null,
    clicks: usize = 0,
    open_menu: ?Menu = null,
    open_window: ?Window = null,
    about_window_pos: struct { x: u16, y: u16 } = .{ .x = 0, .y = 1 },
    counter_window_pos: struct { x: u16, y: u16 } = .{ .x = 30, .y = 10 },
    scroll_window_pos: struct { x: u16, y: u16 } = .{ .x = 4, .y = 2 },
    v_scroll_offset: usize = 0,
    h_scroll_offset: usize = 0,
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

    var vx: Vxim = .init(gpa);
    defer vx.deinit(gpa);

    try vx.startLoop(gpa, update);
}

pub fn update(ctx: Vxim.UpdateContext) anyerror!Vxim.UpdateResult {
    switch (ctx.current_event) {
        .key_press => |key| {
            if (key.matches('c', .{ .ctrl = true }))
                return .stop;
        },
        .mouse => |mouse| state.mouse = mouse,

        .winsize => {},
        .mouse_focus => |_| {},
    }

    ctx.root_win.clear();

    // Counter window.
    {
        const modal_width = @min(25, ctx.root_win.width);
        const modal_height = @min(7, ctx.root_win.height);
        const modal = ctx.vxim.window(.CounterModal, ctx.root_win, .{
            .width = modal_width,
            .height = modal_height,
            .x = &state.counter_window_pos.x,
            .y = &state.counter_window_pos.y,
            .title = "Counter demo",
        });
        const button_text = "Click Me!";

        const button_x: u16 =
            (modal_width / 2) -| ((@as(u16, @truncate(button_text.len)) + 2) / 2) -| 1;
        const button_y: u16 = (modal_height / 2);

        const button_action =
            ctx.vxim.button(
                .ClickMe,
                modal,
                .{ .x = button_x, .y = button_y, .text = button_text },
            );

        if (button_action == .clicked) state.clicks +|= 1;

        const text = try std.fmt.allocPrint(ctx.vxim.arena(), "Clicks: {d}", .{state.clicks});
        const text_x: u16 = (modal_width / 2) -| (@as(u16, @truncate(text.len)) / 2) -| 1;
        const text_y: u16 = (modal_height / 2) -| 2;

        ctx.vxim.text(modal, .{ .text = text, .x = text_x, .y = text_y, .allow_selection = true });
    }

    // Scroll demo
    {
        const scroll_window = ctx.vxim.window(.ScrollDemoWindow, ctx.root_win, .{
            .x = &state.scroll_window_pos.x,
            .y = &state.scroll_window_pos.y,
            .height = 12,
            .width = 22,
            .title = "Scroll demo",
        });
        const content_height = 50;
        const scroll_body = ctx.vxim.scrollArea(.ScrollDemoContent, scroll_window, .{
            .content_height = content_height,
            .content_width = 30,
            .v_content_offset = &state.v_scroll_offset,
            .h_content_offset = &state.h_scroll_offset,
        });

        // It's sufficient to draw from the top of the scroll area.
        for (state.v_scroll_offset..content_height) |i| {
            // No need to draw outside the scroll area.
            if (i > state.v_scroll_offset + scroll_body.height) break;

            const text = try std.fmt.allocPrint(ctx.vxim.arena(), "line: {d}", .{i + 1});

            if (text.len <= state.h_scroll_offset) continue;

            ctx.vxim.text(scroll_body, .{
                .y = @as(u16, @intCast(i -| state.v_scroll_offset)),
                .text = text[state.h_scroll_offset..],
            });
        }
    }

    // About window
    if (state.open_window) |open_window| {
        if (open_window == .About) {
            const about_win = ctx.vxim.window(.AboutWindow, ctx.root_win, .{
                .width = @min(ctx.root_win.width, 35),
                .height = @min(ctx.root_win.height, 11),
                .x = &state.about_window_pos.x,
                .y = &state.about_window_pos.y,
                .title = "About this program",
            });

            const about_body = ctx.vxim.padding(about_win, .{ .all = 1 });

            const close = ctx.vxim.button(
                .CloseAboutButton,
                about_body,
                .{ .x = about_body.width / 2 -| 3, .y = about_body.height -| 1, .text = "Close" },
            );
            if (close == .clicked) {
                state.open_window = null;
            }

            ctx.vxim.text(
                about_body,
                // Extra space to center text in window.
                .{ .text = "          VXIM v0.0.0", .allow_selection = true },
            );
            ctx.vxim.text(
                about_body,
                .{
                    .text = "Experimental immediate mode renderer for libvaxis",
                    .y = 2,
                    .allow_selection = true,
                },
            );
        }
    }

    const menuAction = ctx.vxim.menuBar(ctx.root_win, &.{
        .{
            .name = "File",
            .id = .FileMenu,
            .items = &.{
                .{ .name = "About", .id = .AboutButton },
                .{ .name = "Quit", .id = .QuitButton },
            },
        },
    });

    if (menuAction) |action| {
        if (action.id == .AboutButton and action.action == .clicked) state.open_window = .About;
        if (action.id == .QuitButton and action.action == .clicked) return .stop;
    }

    return .keep_going;
}

const std = @import("std");
const builtin = @import("builtin");

const vaxis = @import("vaxis");
const vxim = @import("vxim");
