//! Installed-app launch screens, shared by the layouts (which link them) and
//! `routes/icons` (which renders them).
//!
//! iOS shows an `apple-touch-startup-image` while an installed web app starts, but only
//! one whose pixel size matches the screen exactly, so there is one per iPhone screen.
const std = @import("std");

/// An iPhone screen in CSS pixels (portrait) and its device pixel ratio.
const Screen = struct { width: u16, height: u16, ratio: u8 };

const screens = [_]Screen{
    .{ .width = 440, .height = 956, .ratio = 3 }, // 16/17 Pro Max
    .{ .width = 402, .height = 874, .ratio = 3 }, // 16/17 Pro, 17
    .{ .width = 420, .height = 912, .ratio = 3 }, // Air
    .{ .width = 430, .height = 932, .ratio = 3 }, // 14/15 Pro Max, 15/16 Plus
    .{ .width = 393, .height = 852, .ratio = 3 }, // 14/15 Pro, 15, 16
    .{ .width = 428, .height = 926, .ratio = 3 }, // 12/13 Pro Max, 14 Plus
    .{ .width = 390, .height = 844, .ratio = 3 }, // 12, 13, 14
    .{ .width = 375, .height = 812, .ratio = 3 }, // X, XS, 11 Pro, 12/13 mini
    .{ .width = 414, .height = 896, .ratio = 3 }, // XS Max, 11 Pro Max
    .{ .width = 414, .height = 896, .ratio = 2 }, // XR, 11
    .{ .width = 375, .height = 667, .ratio = 2 }, // SE, 8
};

pub const Theme = enum { light, dark };

pub const Splash = struct {
    /// File name under `/icons/`.
    name: []const u8,
    href: []const u8,
    /// The `media` query that selects it.
    media: []const u8,
    width: i32,
    height: i32,
    /// CSS-to-device pixels, to size the artwork the same on every screen.
    ratio: f32,
    theme: Theme,
};

pub const splashes: [screens.len * 2]Splash = blk: {
    var out: [screens.len * 2]Splash = undefined;
    for (screens, 0..) |s, i| {
        for ([_]Theme{ .light, .dark }, 0..) |theme, t| {
            const w = @as(u32, s.width) * s.ratio;
            const h = @as(u32, s.height) * s.ratio;
            const name = std.fmt.comptimePrint("splash-{d}x{d}-{t}.png", .{ w, h, theme });
            out[i * 2 + t] = .{
                .name = name,
                .href = "/icons/" ++ name,
                .media = std.fmt.comptimePrint(
                    "(device-width: {d}px) and (device-height: {d}px) and (-webkit-device-pixel-ratio: {d}) and (orientation: portrait) and (prefers-color-scheme: {t})",
                    .{ s.width, s.height, s.ratio, theme },
                ),
                .width = w,
                .height = h,
                .ratio = s.ratio,
                .theme = theme,
            };
        }
    }
    break :blk out;
};
