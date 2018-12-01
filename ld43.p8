pico-8 cartridge // http://www.pico-8.com
version 16
__lua__

local template_size = 8
local map_size_templates = 2
local map_size = map_size_templates * template_size
local max_move_timer = 5
local max_player_length = 20

local state = {
   map = {},
   camera = { sx = 0, sy = 0 },
   player = {
      input_dir = 0,
      move_timer = max_move_timer,
      tail = {},
      positions = {
         { tx = 1, ty = 1, dir = 0 }
      }
   }
}

local tile_types = {
   empty = 0,
   wall = 1,
   floor = 2,
   placeholder = 3,
   source_1 = 4,
   source_2 = 5,
   source_3 = 6,
   destination = 7,
   empty_cargo = 8
}

function is_empty_tile_type(tile_type)
   return tile_type >= tile_types.floor
end

function is_source_tile_type(tile_type)
   return tile_type and tile_type >= tile_types.source_1 and tile_type <= tile_types.source_3
end

function get_random_source_tile_type()
   return tile_types.source_1 + flr(rnd(tile_types.source_3 - tile_types.source_1 + 1))
end

function dir_to_dx_dy(dir)
   if dir == 0 then
      return -1, 0
   elseif dir == 1 then
      return 1, 0
   elseif dir == 2 then
      return 0, -1
   elseif dir == 3 then
      return 0, 1
   end
end

function to_1d_idx(x, y, size)
   return (x - 1) * size + y
end

function to_2d_idx(i, size)
  return flr((i - 1) / size) + 1, ((i - 1) % size) + 1
end

function is_valid_idx(x, y, size)
   return x >= 1 and x <= size and y >= 1 and y <= size
end

if true then
   local x, y = to_2d_idx(1, 2)
   assert(x == 1)
   assert(y == 1)
   assert(to_1d_idx(x, y, 2) == 1)

   local x, y = to_2d_idx(4, 2)
   assert(x == 2)
   assert(y == 2)
   assert(to_1d_idx(x, y, 2) == 4)
end

function tile_to_screen(tx, ty)
   return tx * 10, ty * 10
end

function lerp(a, b, t)
   return a + (b - a) * t
end

function is_tile_empty(tx, ty, map)
   if not is_valid_idx(tx, ty, map_size) then
      return false
   end

   return is_empty_tile_type(map[to_1d_idx(tx, ty, map_size)])
end

function get_current_player_tile(player)
   local pos = player.positions[1]
   return pos.tx, pos.ty
end

function get_current_player_dir(player)
   return player.positions[1].dir
end

local templates = {}
for tx = 0, 127, template_size do
   for ty = 0, 127, template_size do
      if mget(tx, ty) then

         local template = {}
         add(templates, template)

         for x = 0, template_size - 1 do
            for y = 0, template_size - 1 do
               local idx = to_1d_idx(x + 1, y + 1, template_size)
               template[idx] = mget(tx + x, ty + y)
            end
         end
      end
   end
end

for x = 1, map_size do
   for y = 1, map_size do
      local idx = to_1d_idx(x, y, map_size)
      local tidx = to_1d_idx(
         ((x - 1) % template_size) + 1,
         ((y - 1) % template_size) + 1,
         template_size
      )

      local tile_type = templates[1][tidx]
      if tile_type == tile_types.placeholder then
         tile_type = rnd(1) < 0.7 and get_random_source_tile_type() or tile_types.destination
      end

      state.map[idx] = tile_type
   end
end

function try_move(player, map, dir)
   local dx, dy = dir_to_dx_dy(dir)
   local tx0, ty0 = get_current_player_tile(player)
   local tx = tx0 + dx
   local ty = ty0 + dy

   if player.move_timer <= 0 and is_tile_empty(tx, ty, map) then
      player.move_timer = max_move_timer

      -- destroy tail on collision
      local destroy_tail_idx = nil
      for i = 2, #player.positions do
         local pos = player.positions[i]
         if pos.tx == tx and pos.ty == ty then
            destroy_tail_idx = i - 1
            break
         end
      end

      if destroy_tail_idx then
         for i = destroy_tail_idx, #player.tail do
            player.tail[i] = nil
         end
      end

      -- collect source
      local idx = to_1d_idx(tx, ty, map_size)
      local tile_type = map[idx]

      if is_source_tile_type(tile_type) then
         add(player.tail, tile_type)
         if #player.tail > max_player_length then
            for i = 1, #player.tail do
               player.positions[i] = player.positions[i + 1]
            end
         end

         map[idx] = tile_types.floor
      end

      -- clean up empty cargo from previous move
      local new_tail = {}
      for i = 1, #player.tail do
         if player.tail[i] != tile_types.empty_cargo then
            add(new_tail, player.tail[i])
         end
      end
      player.tail = new_tail

      -- shift positions forward by one
      for i = max_player_length, 1, -1 do
         player.positions[i] =  player.positions[i - 1]
      end
      player.positions[1] = { tx = tx, ty = ty, dir = dir }

      -- check for destination
      for i = 2, #player.positions do
         local pos = player.positions[i]

         local idx = to_1d_idx(pos.tx, pos.ty, map_size)
         local tile_type = map[idx]

         if tile_type == tile_types.destination and is_source_tile_type(player.tail[i - 1]) then
            player.tail[i - 1] = tile_types.empty_cargo
            map[idx] = tile_types.floor
         end
      end

      return true
   end

   return false
end

function _update()
   local cam = state.camera
   local player = state.player
   local map = state.map

   player.move_timer -= 1

   for dir = 0, 3 do
      if btnp(dir) then
         player.input_dir = dir
      end
   end

   if try_move(player, map, player.input_dir) or
   try_move(player, map, get_current_player_dir(player)) then end

   local padding = 40
   local tx, ty = get_current_player_tile(player)
   local sx_max, sy_max = tile_to_screen(tx + 1, ty + 1)
   local sx_min, sy_min = tile_to_screen(tx, ty)

   local xdiff = max(sx_max - (cam.sx + 128 - padding), 0) + min(sx_min - (cam.sx + padding), 0)
   local ydiff = max(sy_max - (cam.sy + 128 - padding), 0) + min(sy_min - (cam.sy + padding), 0)
   cam.sx += xdiff / 20
   cam.sy += ydiff / 20
end

function _draw()
   cls(0)
   camera(state.camera.sx, state.camera.sy)

   function draw_tile(tx, ty, tile_type)
      local x0, y0 = tile_to_screen(tx, ty)
      local x1, y1 = tile_to_screen(tx + 1, ty + 1)
      x1 -= 1
      y1 -= 1
      rectfill(x0, y0, x1, y1, tile_type)
   end

   for x = 1, map_size do
      for y = 1, map_size do
         local idx = to_1d_idx(x, y, map_size)
         local tile_type = state.map[idx]
         draw_tile(x, y, tile_type)
      end
   end

   local player = state.player
   local move_frac = 1 - max(0, player.move_timer / max_move_timer)

   for i = 1, #player.positions do
      local clr

      if i == 1 then
         clr = 6
      else
         local tile_type = player.tail[i - 1]
         if tile_type then
            clr = tile_type
         end
      end

      if clr then
         local pos = player.positions[i]
         local dx, dy = dir_to_dx_dy(pos.dir)

         local tx0 = pos.tx - dx;
         local ty0 = pos.ty - dy;

         local tx = lerp(tx0, pos.tx, move_frac)
         local ty = lerp(ty0, pos.ty, move_frac)

         draw_tile(tx, ty, clr)
      end
   end
end

__gfx__
00000000111111116666666688888888000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000111111116666666688888888000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00700700111111116666666688888888000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00077000111111116666666688888888000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00077000111111116666666688888888000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00700700111111116666666688888888000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000111111116666666688888888000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000111111116666666688888888000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__map__
0202000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0202000302020000020202020202020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0302000202020202020003020300020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0002000000020000000000000000020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0202020202020002020002020202020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0200000000020003020202030002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0202020202020000000200000002020200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0003000000000000000202020202000200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0002020202020200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0002020202020200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000203000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0002030000020202000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0002020202020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
