-- Compact dashboard: physical-pixel typography, ring gauges and a shortcut column.
require('cairo')
if not conky_surface then require('cairo_xlib') end

local palette = {
    text = {0.737, 0.757, 0.792}, value = {0.957, 0.945, 0.918},
    accent = {0.941, 0.659, 0.408}, teal = {0.40, 0.79, 0.77},
    blue = {0.57, 0.69, 0.92}, track = {0.22, 0.24, 0.28},
}

local function parsed(expression)
    return (conky_parse(expression) or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

local function number(expression)
    return tonumber((parsed(expression):gsub(',', '.'))) or 0
end

local function readable(expression)
    return parsed(expression):gsub('(%d)([KMGT]iB)', '%1 %2'):gsub('(%d)%.(%d)', '%1,%2')
end

local function color(cr, name)
    local rgb = palette[name]
    cairo_set_source_rgb(cr, rgb[1], rgb[2], rgb[3])
end

local function text(cr, extents, x, y, value, width, size, tone, centered)
    cairo_select_font_face(cr, 'DejaVu Sans Mono', CAIRO_FONT_SLANT_NORMAL,
        CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, size)
    value = tostring(value):gsub('[\r\n\t]', ' ')
    local function measure(s)
        cairo_text_extents(cr, s, extents)
        return math.max(extents.x_advance, extents.width + extents.x_bearing)
    end
    if measure(value) > width then
        local characters = {}
        for c in value:gmatch('[%z\1-\127\194-\244][\128-\191]*') do
            characters[#characters + 1] = c
        end
        repeat
            characters[#characters] = nil
            value = table.concat(characters) .. '…'
        until #characters == 0 or measure(value) <= width
    end
    if measure(value) > width then return end
    if centered then x = x + (width - measure(value)) / 2 end
    color(cr, tone or 'text')
    cairo_move_to(cr, x, y)
    cairo_show_text(cr, value)
end

local function line(cr, x, y, x2, y2, tone)
    color(cr, tone or 'track')
    cairo_set_line_width(cr, 1)
    cairo_move_to(cr, x, y)
    cairo_line_to(cr, x2, y2)
    cairo_stroke(cr)
end

local function ring(cr, extents, x, y, percent, tone)
    percent = math.max(0, math.min(100, percent))
    cairo_set_line_width(cr, 5)
    color(cr, 'track')
    cairo_new_sub_path(cr)
    cairo_arc(cr, x, y, 31, 0, 2 * math.pi)
    cairo_stroke(cr)
    color(cr, tone)
    cairo_new_sub_path(cr)
    cairo_arc(cr, x, y, 31, -math.pi / 2, -math.pi / 2 + percent / 50 * math.pi)
    cairo_stroke(cr)
    text(cr, extents, x - 28, y + 5, string.format('%.0f%%', percent), 56, 16, 'value', true)
end

local function rate(value)
    if value < 0.05 then return '0 B/s' end
    local unit = 'KiB/s'
    if value >= 1024 then value, unit = value / 1024, 'MiB/s' end
    if value >= 1024 then value, unit = value / 1024, 'GiB/s' end
    return string.format('%.1f %s', value, unit):gsub('%.', ',')
end

function conky_compact_dashboard(size, columns, cpu_count, interface, network_kind, battery, ...)
    if not conky_window or number('${updates}') < 2 then return end
    size, columns, cpu_count = tonumber(size), tonumber(columns), tonumber(cpu_count)
    local owned = not conky_surface
    local surface
    if owned then
        surface = cairo_xlib_surface_create(conky_window.display, conky_window.drawable,
            conky_window.visual, conky_window.width, conky_window.height)
    else
        surface = conky_surface()
    end
    if not surface then return end
    local cr, extents = cairo_create(surface), cairo_text_extents_t:create()
    local width, height = conky_window.width, conky_window.height
    if not owned and conky_window.pixel_size then
        width, height = conky_window.pixel_size.x, conky_window.pixel_size.y
        local scale = conky_window.scale or 1
        cairo_scale(cr, 1 / scale, 1 / scale)
    end
    -- Reserve the rightmost column for shortcuts, also on wrapped layouts.
    local cell = width / (columns + 1)
    local row_height = height / (6 / columns)
    local titles = {'SYSTEM', 'CPU', 'SPEICHER', 'LAUFWERK', 'NETZWERK', 'PROZESSE'}
    line(cr, 0, 1, width, 1, 'accent')
    for i, title in ipairs(titles) do
        local left, top = (i - 1) % columns * cell, math.floor((i - 1) / columns) * row_height
        local x, w = left + 16, cell - 32
        if i > 1 then line(cr, left, top + 12, left, top + row_height - 12) end
        cairo_save(cr)
        cairo_rectangle(cr, x, top + 4, w, row_height - 8)
        cairo_clip(cr)
        local function label(dx, y, value, tone, font_size)
            text(cr, extents, x + dx, top + y, value, w - dx, font_size or size, tone)
        end
        label(0, 25, title, 'accent')
        if title == 'SYSTEM' then
            label(0, 52, parsed('${nodename}'), 'value', 19)
            label(0, 77, 'Uptime  ' .. parsed('${uptime_short}'))
            if battery ~= '-' then
                label(0, 103, 'Akku ' .. parsed('${battery_percent ' .. battery .. '}') .. '%  ' ..
                    parsed('${battery_short ' .. battery .. '}'))
            else
                label(0, 103, parsed('${processes}') .. ' Prozesse')
            end
        elseif title == 'CPU' then
            ring(cr, extents, x + 34, top + 74, number('${cpu}'), 'accent')
            label(84, 58, parsed(table.concat({...}, ' ')), 'value', 17)
            label(84, 81, cpu_count .. ' Threads')
            local slot = (w - 84) / cpu_count
            for core = 1, cpu_count do
                local bx = x + 84 + (core - 1) * slot
                color(cr, 'track')
                cairo_rectangle(cr, bx, top + 94, math.max(1, slot - 2), 16)
                cairo_fill(cr)
                local load = math.min(100, math.max(0, number('${cpu cpu' .. core .. '}')))
                color(cr, 'accent')
                cairo_rectangle(cr, bx, top + 110 - load * 0.16, math.max(1, slot - 2), load * 0.16)
                cairo_fill(cr)
            end
        elseif title == 'SPEICHER' then
            ring(cr, extents, x + 34, top + 74, number('${memperc}'), 'teal')
            label(84, 56, readable('${mem}'), 'value', 17)
            label(84, 80, 'von ' .. readable('${memmax}'))
            label(84, 104, 'Swap ' .. readable('${swap}'))
        elseif title == 'LAUFWERK' then
            ring(cr, extents, x + 34, top + 74, number('${fs_used_perc /}'), 'blue')
            label(84, 54, readable('${fs_free /}') .. ' frei', 'value')
            label(84, 79, 'R ' .. readable('${diskio_read}') .. '/s')
            label(84, 104, 'W ' .. readable('${diskio_write}') .. '/s')
        elseif title == 'NETZWERK' then
            label(0, 54, '↓ ' .. rate(number('${downspeedf ' .. interface .. '}')), 'teal', 17)
            label(0, 80, '↑ ' .. rate(number('${upspeedf ' .. interface .. '}')), 'blue', 17)
            label(0, 106, network_kind == 'wireless' and
                ('WLAN ' .. parsed('${wireless_link_qual_perc ' .. interface .. '}') .. '% · ' .. interface) or interface)
        elseif title == 'PROZESSE' then
            for rank = 1, 2 do
                label(0, 49 + (rank - 1) * 20, 'C ' .. readable('${top cpu ' .. rank .. '}') .. '% ' ..
                    parsed('${top name ' .. rank .. '}'))
                label(0, 91 + (rank - 1) * 20, 'M ' .. readable('${top_mem mem ' .. rank .. '}') .. '% ' ..
                    parsed('${top_mem name ' .. rank .. '}'))
            end
        end
        cairo_restore(cr)
    end
    local shortcut_left = columns * cell
    line(cr, shortcut_left, 12, shortcut_left, height - 12)
    local shortcuts = {'s  Cheats', 't  Übersetzen', 'c  Clipboard', 'm  Monitor', 'u  USB'}
    text(cr, extents, shortcut_left + 16, 25, 'Mod + Ctrl +', cell - 32, size, 'accent')
    for i, shortcut in ipairs(shortcuts) do
        text(cr, extents, shortcut_left + 16, 44 + (i - 1) * 17,
            shortcut, cell - 32, size, 'text')
    end
    cairo_text_extents_t:destroy(extents)
    cairo_destroy(cr)
    if owned then cairo_surface_destroy(surface) end
end
