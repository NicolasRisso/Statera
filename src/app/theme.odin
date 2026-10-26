package app

import im "../../vendor/imgui"
import sdl "vendor:sdl3"

FONT_UI :: #load("../../assets/fonts/Inter.ttf")
FONT_MONO :: #load("../../assets/fonts/JetBrainsMono.ttf")
FONT_SIZE :: 16

Theme :: enum u8 {
	Dark,
	Light,
}

// What the user picked; .System follows the OS setting and updates when it changes.
Theme_Mode :: enum u8 {
	System,
	Light,
	Dark,
}

resolve_theme :: proc(mode: Theme_Mode) -> Theme {
	switch mode {
	case .Dark:   return .Dark
	case .Light:  return .Light
	case .System: return .Light if sdl.GetSystemTheme() == .LIGHT else .Dark
	}
	return .Dark
}

// Semantic colors used by our own widgets (ImGui's style covers the rest).
Palette :: struct {
	bg, panel, frame, hover, active, border:   im.Vec4,
	text, dim, accent, accent_soft, header:    im.Vec4,
	missing, sysmis, ok, error:                im.Vec4,
}

palette: Palette

@(private = "file")
hex :: proc "contextless" (rgb: u32, a: f32 = 1) -> im.Vec4 {
	return {f32((rgb >> 16) & 0xff) / 255, f32((rgb >> 8) & 0xff) / 255, f32(rgb & 0xff) / 255, a}
}

@(private = "file")
DARK := Palette {
	bg          = hex(0x0F1115),
	panel       = hex(0x151821),
	frame       = hex(0x1D212C),
	hover       = hex(0x262B39),
	active      = hex(0x30364A),
	border      = hex(0x252A36),
	text        = hex(0xE6E8EF),
	dim         = hex(0x8A90A2),
	accent      = hex(0x7C8CFF),
	accent_soft = hex(0x7C8CFF, 0.22),
	header      = hex(0x1A1E29),
	missing     = hex(0xE0A458),
	sysmis      = hex(0x5C6275),
	ok          = hex(0x5FD3A1),
	error       = hex(0xFF6B7A),
}

@(private = "file")
LIGHT := Palette {
	bg          = hex(0xF4F5F9),
	panel       = hex(0xFFFFFF),
	frame       = hex(0xEDEFF5),
	hover       = hex(0xE2E5EF),
	active      = hex(0xD6DAE8),
	border      = hex(0xE0E3EB),
	text        = hex(0x1D2130),
	dim         = hex(0x6B7185),
	accent      = hex(0x4F5BD5),
	accent_soft = hex(0x4F5BD5, 0.14),
	header      = hex(0xF0F2F7),
	missing     = hex(0xB86E12),
	sysmis      = hex(0xA0A6B6),
	ok          = hex(0x1F9D6B),
	error       = hex(0xD63B4E),
}

apply_theme :: proc(theme: Theme) {
	palette = DARK if theme == .Dark else LIGHT
	p := palette
	s := im.GetStyle()

	s.WindowRounding = 8
	s.ChildRounding = 6
	s.FrameRounding = 6
	s.PopupRounding = 8
	s.GrabRounding = 6
	s.TabRounding = 6
	s.ScrollbarRounding = 8
	s.WindowPadding = {12, 10}
	s.FramePadding = {10, 6}
	s.ItemSpacing = {8, 7}
	s.ItemInnerSpacing = {6, 4}
	s.CellPadding = {9, 5}
	s.ScrollbarSize = 12
	s.WindowBorderSize = 1
	s.FrameBorderSize = 0
	s.PopupBorderSize = 1
	s.TabBorderSize = 0
	s.DockingSeparatorSize = 2
	s.WindowMenuButtonPosition = .None

	c := &s.Colors
	c[im.Col.Text] = p.text
	c[im.Col.TextDisabled] = p.dim
	c[im.Col.WindowBg] = p.panel
	c[im.Col.ChildBg] = {0, 0, 0, 0}
	c[im.Col.PopupBg] = p.panel
	c[im.Col.Border] = p.border
	c[im.Col.BorderShadow] = {0, 0, 0, 0}
	c[im.Col.FrameBg] = p.frame
	c[im.Col.FrameBgHovered] = p.hover
	c[im.Col.FrameBgActive] = p.active
	c[im.Col.TitleBg] = p.bg
	c[im.Col.TitleBgActive] = p.bg
	c[im.Col.TitleBgCollapsed] = p.bg
	c[im.Col.MenuBarBg] = p.bg
	c[im.Col.ScrollbarBg] = {0, 0, 0, 0}
	c[im.Col.ScrollbarGrab] = p.active
	c[im.Col.ScrollbarGrabHovered] = p.dim
	c[im.Col.ScrollbarGrabActive] = p.accent
	c[im.Col.CheckMark] = p.accent
	c[im.Col.SliderGrab] = p.accent
	c[im.Col.SliderGrabActive] = p.accent
	c[im.Col.Button] = p.frame
	c[im.Col.ButtonHovered] = p.hover
	c[im.Col.ButtonActive] = p.active
	c[im.Col.Header] = p.accent_soft
	c[im.Col.HeaderHovered] = p.hover
	c[im.Col.HeaderActive] = p.active
	c[im.Col.Separator] = p.border
	c[im.Col.SeparatorHovered] = p.accent
	c[im.Col.SeparatorActive] = p.accent
	c[im.Col.ResizeGrip] = {0, 0, 0, 0}
	c[im.Col.ResizeGripHovered] = p.accent
	c[im.Col.ResizeGripActive] = p.accent
	c[im.Col.Tab] = p.bg
	c[im.Col.TabHovered] = p.hover
	c[im.Col.TabSelected] = p.panel
	c[im.Col.TabSelectedOverline] = p.accent
	c[im.Col.TabDimmed] = p.bg
	c[im.Col.TabDimmedSelected] = p.panel
	c[im.Col.TabDimmedSelectedOverline] = p.border
	c[im.Col.DockingPreview] = p.accent_soft
	c[im.Col.DockingEmptyBg] = p.bg
	c[im.Col.TableHeaderBg] = p.header
	c[im.Col.TableBorderStrong] = p.border
	c[im.Col.TableBorderLight] = p.border
	c[im.Col.TableRowBg] = {0, 0, 0, 0}
	c[im.Col.TableRowBgAlt] = {p.text.x, p.text.y, p.text.z, 0.025}
	c[im.Col.TextSelectedBg] = p.accent_soft
	c[im.Col.NavCursor] = p.accent
	c[im.Col.ModalWindowDimBg] = {0, 0, 0, 0.45}
}

Fonts :: struct {
	ui:   ^im.Font,
	mono: ^im.Font,
}

load_fonts :: proc() -> Fonts {
	atlas := im.GetIO().Fonts
	// The atlas frees font data with ImGui's allocator, so hand it a copy of the embedded bytes.
	own :: proc(data: []u8) -> rawptr {
		p := im.MemAlloc(uint(len(data)))
		copy(([^]u8)(p)[:len(data)], data)
		return p
	}
	return {
		ui   = im.FontAtlas_AddFontFromMemoryTTF(atlas, own(FONT_UI), i32(len(FONT_UI)), FONT_SIZE),
		mono = im.FontAtlas_AddFontFromMemoryTTF(atlas, own(FONT_MONO), i32(len(FONT_MONO)), FONT_SIZE),
	}
}
