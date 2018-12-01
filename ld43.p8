pico-8 cartridge // http://www.pico-8.com
version 16
__lua__

local template_size = 8
local map_size_templates = 2
local map_size = map_size_templates * template_size
local max_move_timer = 5
local max_player_length = 20
local max_collapse_timer = 200
local max_recent_score_timer = 20
local max_tile_collapse_timer = 40


local state = {
   time = 0,
   map = {},
   camera = { sx = 0, sy = 0 },
   score = 0,
   recent_scores = {},
   collapsing_tiles = {},
   collapse_timer = max_collapse_timer,
   collapse_speed = 1,
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
   solid = 0,
   floor = 1,
   placeholder = 2,
   source_1 = 3,
   source_2 = 4,
   source_3 = 5,
   destination = 6
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
   return tx * 8, ty * 8
end

function screen_to_tile(sx, sy)
   return sx / 8, sy / 8
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

function get_tail_tile_type(tail_item)
   return tail_item.tile_type
end

function get_tail_value(tail_item, player_position)
   local dx = tail_item.source_tx - player_position.tx
   local dy = tail_item.source_ty - player_position.ty
   return flr(sqrt(dx * dx + dy * dy) + 0.5)
end

function get_tail_is_emptying(tail_item)
   return tail_item.is_emptying
end

function get_tail_sprite(tail_item, player_position)
   local value = get_tail_value(tail_item, player_position)
   if value < 10 then
      return 6
   elseif value < 20 then
      return 5
   else
      return 4
   end
end

function get_value_color(value)
   if value < 10 then
      return 7
   elseif value < 20 then
      return 10
   else
      return 9
   end
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
         add(player.tail, {
                tile_type = tile_type,
                source_tx = tx,
                source_ty = ty,
                is_emptying = false
         })

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
         if not get_tail_is_emptying(player.tail[i]) then
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

         local tail_item = player.tail[i - 1]
         if tile_type == tile_types.destination and tail_item and
         is_source_tile_type(get_tail_tile_type(tail_item)) then
            local value = get_tail_value(tail_item, player.positions[1])
            state.score += value

            add(state.recent_scores, {
                   value = value,
                   time = state.time,
                   tx = pos.tx,
                   ty = pos.ty
            })

            tail_item.is_emptying = true
            map[idx] = tile_types.floor
         end
      end

      return true
   end

   return false
end

function _update()
   state.time += 1
   state.collapse_timer -= state.collapse_speed
   state.collapse_speed *= 1.0001
   state.collapse_speed = min(state.collapse_speed, 200)

   local cam = state.camera
   local player = state.player
   local map = state.map

   player.move_timer -= 1

   if state.collapse_timer < 0 then
      state.collapse_timer = max_collapse_timer

      local tx = flr(rnd(map_size + 1))
      local ty = flr(rnd(map_size + 1))

      if is_tile_empty(tx, ty, map) then
         add(state.collapsing_tiles, { tx = tx, ty = ty, time = state.time })
      end
   end

   local collapsing_tiles = {}
   foreach(state.collapsing_tiles, function(collapsing_tile)
              if state.time - collapsing_tile.time < max_tile_collapse_timer then
                 add(collapsing_tiles, collapsing_tile)
              else
                 local idx = to_1d_idx(collapsing_tile.tx, collapsing_tile.ty, map_size)
                 map[idx] = tile_types.solid
              end
   end)
   state.collapsing_tiles = collapsing_tiles

   local recent_scores = {}
   foreach(state.recent_scores, function(recent_score)
              if state.time - recent_score.time < max_recent_score_timer then
                 add(recent_scores, recent_score)
              end
   end)
   state.recent_scores = recent_scores

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
   local player = state.player
   local cam = state.camera;

   cls(0)
   camera(cam.sx, cam.sy)

   function draw_tile(tx, ty, tile_type)
      local x0, y0 = tile_to_screen(tx, ty)
      local x1, y1 = tile_to_screen(tx + 1, ty + 1)
      x1 -= 1
      y1 -= 1
      rectfill(x0, y0, x1, y1, tile_type)
   end

   function draw_tile_sprite(tx, ty, sprite)
      local x, y = tile_to_screen(tx, ty)
      spr(sprite, x, y)
   end

   local start_x, start_y = screen_to_tile(cam.sx, cam.sy)
   local end_x, end_y = screen_to_tile(cam.sx + 128, cam.sy + 128)

   start_x = flr(min(max(1, start_x), map_size))
   end_x = ceil(min(max(1, end_x), map_size))
   start_y = flr(min(max(1, start_y), map_size))
   end_y = ceil(min(max(1, end_y), map_size))

   for x = start_x, end_x do
      for y = start_y, end_y do
         local idx = to_1d_idx(x, y, map_size)
         local tile_type = state.map[idx]
         draw_tile(x, y, tile_type)
      end
   end

   foreach(state.collapsing_tiles, function(collapsing_tile)
              local collapse_frac = max(0, 1 - (state.time - collapsing_tile.time) / max_tile_collapse_timer)
              assert(collapse_frac > 0)

              local tx = collapsing_tile.tx
              local ty = collapsing_tile.ty

              local d_tpos = (collapse_frac % 0.1 > 0.05 and 1 / 8 or 0)
              local idx = to_1d_idx(tx, ty, map_size)
              local tile_type = state.map[idx]
              draw_tile(tx, ty, 0)
              draw_tile(tx + d_tpos, ty + d_tpos, tile_type)
   end)

   local move_frac = 1 - max(0, player.move_timer / max_move_timer)

   for i = 1, #player.positions do
      local pos = player.positions[i]
      local dx, dy = dir_to_dx_dy(pos.dir)

      local tx0 = pos.tx - dx;
      local ty0 = pos.ty - dy;

      local tx = lerp(tx0, pos.tx, move_frac)
      local ty = lerp(ty0, pos.ty, move_frac)

      if i == 1 then
         draw_tile(tx, ty, 6)
      else
         local tail_item = player.tail[i - 1]
         if tail_item then
            local sprite = get_tail_sprite(tail_item, player.positions[1])
            draw_tile_sprite(tx, ty, sprite)
         end
      end
   end

   camera(0, 0)
   print(state.score, 10, 10)

   foreach(state.recent_scores, function(recent_score)
              local recent_score_frac = max(0, 1 - (state.time - recent_score.time) / max_recent_score_timer)
              assert(recent_score_frac > 0)

              local tx, ty = recent_score.tx, recent_score.ty
              local sx, sy = tile_to_screen(tx, ty)
              sx -= cam.sx
              sy -= cam.sy

              sy += recent_score_frac * 10 - 10
              color(get_value_color(recent_score.value))
              print("+"..recent_score.value, sx, sy)

              add(recent_scores, recent_score)
   end)
end

__gfx__
0000000066666666bbbbbbbb11111111555555555555555555555555000000000000000000000000000000000000000000000000000000000000000000000000
0000000066666666bbbbbbbb11111111599999955555555555555555000000000000000000000000000000000000000000000000000000000000000000000000
0070070066666666bbbbbbbb111111115999999555aaaa5555555555000000000000000000000000000000000000000000000000000000000000000000000000
0007700066666666bbbbbbbb111111115999999555aaaa5555577555000000000000000000000000000000000000000000000000000000000000000000000000
0007700066666666bbbbbbbb111111115999999555aaaa5555577555000000000000000000000000000000000000000000000000000000000000000000000000
0070070066666666bbbbbbbb555555555999999555aaaa5555555555000000000000000000000000000000000000000000000000000000000000000000000000
0000000066666666bbbbbbbb55555555599999955555555555555555000000000000000000000000000000000000000000000000000000000000000000000000
0000000066666666bbbbbbbb55555555555555555555555555555555000000000000000000000000000000000000000000000000000000000000000000000000
__map__
0101000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0101000201010000010101010101010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0201000101010101010002010200010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0001000000010000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0101010101010001010001010101010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0100000000010002010101020001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0101010101010000000100000001010100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0002000000000000000101010101000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0001010101010100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0001010101010100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000102000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0001020000010101000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0001010101010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
