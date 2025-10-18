pub fn Vxim(comptime Event: type) type {
    return struct {
        const Self = @This();

        pub const UpdateContext = struct {
            arena: std.mem.Allocator,
            root_win: vaxis.Window,
            vx: *vaxis.Vaxis,
            vxim: *Self,
        };

        pub const UpdateResult = enum {
            keep_going,
            stop,
        };

        pub const TextOptions = struct {
            x: u16 = 0,
            y: u16 = 0,
            text: []const u8 = "",
            style: vaxis.Style = .{},
        };

        const ButtonAction = enum {
            pressed,
            released,
            hovered,
            none,
        };

        pub const Style = struct {
            pub const Button = struct {
                default: vaxis.Style = .{ .bg = .{ .index = 12 } },
                hovered: vaxis.Style = .{ .bg = .{ .index = 12 } },
                pressed: vaxis.Style = .{ .bg = .{ .index = 4 } },

                text: Text = .{
                    .default = .{ .fg = .{ .index = 12 }, .reverse = true },
                    .hovered = .{ .fg = .{ .index = 12 }, .reverse = true },
                    .pressed = .{ .fg = .{ .index = 4 }, .reverse = true },
                },
            };

            pub const Text = struct {
                default: vaxis.Style = .{},
                hovered: vaxis.Style = .{},
                pressed: vaxis.Style = .{},
            };
        };

        const ButtonOptions = struct {
            x: u16,
            y: u16,
            text: []const u8,
            mouse: ?vaxis.Mouse,
            style: Style.Button = .{},
        };

        pub fn button(_: *Self, win: vaxis.Window, opts: ButtonOptions) ButtonAction {
            const child = win.child(.{
                .x_off = opts.x,
                .y_off = opts.y,
                .width = @min(
                    @as(u16, @truncate(opts.text.len)) + 2,
                    win.width,
                ),
                .height = 1,
            });

            const button_has_mouse = child.hasMouse(opts.mouse) != null;
            const button_pressed = if (opts.mouse) |mouse| button_has_mouse and mouse.button == .left and mouse.type == .press else false;

            if (button_pressed) {
                child.fill(.{ .style = opts.style.pressed });
            } else if (button_has_mouse) {
                child.fill(.{ .style = opts.style.hovered });
            } else {
                child.fill(.{ .style = opts.style.default });
            }

            const text_style: vaxis.Style = if (button_pressed)
                opts.style.text.pressed
            else if (button_has_mouse)
                opts.style.text.hovered
            else
                opts.style.text.default;

            _ = child.printSegment(
                .{ .text = opts.text, .style = text_style },
                .{ .row_offset = 0, .col_offset = 1 },
            );

            const button_released = if (opts.mouse) |mouse|
                button_has_mouse and mouse.button == .left and mouse.type == .release
            else
                false;

            if (button_pressed) return .pressed;
            if (button_released) return .released;
            if (button_has_mouse) return .hovered;
            return .none;
        }

        pub fn text(_: *Self, win: vaxis.Window, opts: TextOptions) void {
            _ = win.printSegment(
                .{ .text = opts.text, .style = opts.style },
                .{ .col_offset = opts.x, .row_offset = opts.y },
            );
        }

        pub fn startLoop(
            self: *Self,
            gpa: std.mem.Allocator,
            updateFn: fn (evt: Event, ctx: UpdateContext) anyerror!UpdateResult,
        ) !void {
            var arena_state: std.heap.ArenaAllocator = .init(gpa);
            defer arena_state.deinit();

            const arena = arena_state.allocator();

            // Initialize a tty
            var buffer: [1024]u8 = undefined;
            var tty = try vaxis.Tty.init(&buffer);
            defer tty.deinit();

            // Initialize Vaxis
            var vx = try vaxis.init(gpa, .{});
            // deinit takes an optional allocator. If your program is exiting, you can
            // choose to pass a null allocator to save some exit time.
            defer vx.deinit(gpa, tty.writer());

            // The event loop requires an intrusive init. We create an instance with
            // stable pointers to Vaxis and our TTY, then init the instance. Doing so
            // installs a signal handler for SIGWINCH on posix TTYs
            //
            // This event loop is thread safe. It reads the tty in a separate thread
            var loop: vaxis.Loop(Event) = .{
                .tty = &tty,
                .vaxis = &vx,
            };
            try loop.init();

            // Start the read loop. This puts the terminal in raw mode and begins
            // reading user input
            try loop.start();
            defer loop.stop();

            // Optionally enter the alternate screen
            try vx.enterAltScreen(tty.writer());

            // Sends queries to terminal to detect certain features. This should always
            // be called after entering the alt screen, if you are using the alt screen
            try vx.queryTerminal(tty.writer(), 1 * std.time.ns_per_s);

            // enable mouse events.
            try vx.setMouseMode(tty.writer(), true);

            while (true) {
                // nextEvent blocks until an event is in the queue
                const event = loop.nextEvent();

                // Handle window resize automatically.
                switch (event) {
                    .winsize => |ws| try vx.resize(gpa, tty.writer(), ws),
                    else => {},
                }

                // vx.window() returns the root window. This window is the size of the
                // terminal and can spawn child windows as logical areas. Child windows
                // cannot draw outside of their bounds
                const win = vx.window();

                const update_result = try updateFn(event, .{
                    .root_win = win,
                    .arena = arena,
                    .vx = &vx,
                    .vxim = self,
                });

                // Render the screen. Using a buffered writer will offer much better
                // performance, but is not required
                try vx.render(tty.writer());

                _ = arena_state.reset(.retain_capacity);

                if (update_result == .stop) break;
            }
        }
    };
}

const std = @import("std");
const vaxis = @import("vaxis");
