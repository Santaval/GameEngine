for _, g in ipairs(lidx.gates) do
  if logic.is_locked(g, ws.has) then
    local r = g.rect
    draw_rect_world(r.x, r.y, r.w, r.h, 160, 110, 40, 160, true)
  end
end
