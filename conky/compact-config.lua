-- Adapt only the known dashboard contract; custom host generators stay intact.
return function(screen_width, renderer)
    local config = conky.config
    local hook = config.lua_draw_hook_post or ''
    if not hook:match('^dashboard %d+ %d+ %d+ ') then return end
    local columns = screen_width >= 1600 and 6 or (screen_width >= 1000 and 3 or 2)
    local height = 132 * (6 / columns)
    -- Reuse the generator's DPI conversion instead of querying X a second time.
    local units_per_pixel = config.minimum_width / (screen_width - 32)
    config.minimum_height = math.floor(height * units_per_pixel + 0.5)
    config.lua_load = renderer
    config.lua_draw_hook_post = hook:gsub('^dashboard %d+ %d+ ',
        'compact_dashboard 14 ' .. columns .. ' ')
end
