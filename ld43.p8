pico-8 cartridge // http://www.pico-8.com
version 16
__lua__

local template_size = { width = 8, height = 8 }
local map_size = {
   width = 2 * template_size.width,
   height = 20 * template_size.height
}
local max_move_timer = 5
local max_player_length = 20
local max_collapse_timer = 50
local max_recent_score_timer = 20
local max_tile_collapse_timer = 40
local game_over_show_time = 20
local star_map = {
   tx = 24,
   ty = 0,
   width = 16,
   height = 16
}
local shooting_star_sprite = {
   start = 20,
   length = 5
}

local state = nil

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
   else
      return 0, 0
   end
end

function to_1d_idx(x, y, size)
   return ((x - 1) + size.width * (y - 1)) + 1
end

function to_2d_idx(i, size)
  return ((i - 1) % size.width) + 1, flr((i - 1) / size.width) % size.height + 1
end

function is_valid_idx(x, y, size)
   return x >= 1 and x <= size.width and y >= 1 and y <= size.height
end

if true then
   local size = { width = 2, height = 2 }
   local x, y = to_2d_idx(1, size)
   assert(x == 1)
   assert(y == 1)
   assert(to_1d_idx(x, y, size) == 1)

   local x, y = to_2d_idx(4, size)
   assert(x == 2)
   assert(y == 2)
   assert(to_1d_idx(x, y, size) == 4)
end

function tile_to_screen(tx, ty)
   return tx * 9 - 4 * ty, ty * 8
end

function screen_to_tile(sx, sy)
   local ty = sy / 8
   local tx = (sx + 4 * ty) / 9
   return tx, ty
end

function lerp(a, b, t)
   return a + (b - a) * t
end


local templates = {}
for tx = 0, 127, template_size.width do
   for ty = 0, 127, template_size.height do
      if mget(tx, ty) then

         local template = {}
         local is_empty = true

         for x = 0, template_size.width - 1 do
            for y = 0, template_size.height - 1 do
               local idx = to_1d_idx(x + 1, y + 1, template_size)
               local tile_type = mget(tx + x, ty + y)

               if tile_type == tile_types.floor then
                  is_empty = false
               end

               template[idx] = tile_type
            end
         end

         if not is_empty then
            add(templates, template)
         end
      end
   end
end

function create_state()
   -- generate map
   local map = {}
   local template_count = #templates
   for template_x = 0, map_size.width / template_size.width - 1 do
      for template_y = 0, map_size.height / template_size.height - 1 do

         local tx_min = template_x * template_size.width + 1
         local tx_max = (template_x + 1) * template_size.width
         local ty_min = template_y * template_size.height + 1
         local ty_max = (template_y + 1) * template_size.height

         local template = templates[flr(rnd(template_count)) + 1]

         for tx = tx_min, tx_max do
            for ty = ty_min, ty_max do
               local idx = to_1d_idx(tx, ty, map_size)
               local tidx = to_1d_idx(
                  ((tx - 1) % template_size.width) + 1,
                  ((ty - 1) % template_size.height) + 1,
                  template_size
               )

               local tile_type = template[tidx]
               if tile_type == tile_types.placeholder then
                  tile_type = rnd(1) < 0.7 and get_random_source_tile_type() or tile_types.destination
               end

               map[idx] = tile_type
            end
         end
      end
   end

   -- place player
   local player_ty = map_size.height - 5
   local player_tx = flr(rnd(map_size.width + 1))
   for tx = 1, map_size.width do
      player_tx = player_tx % map_size.width + 1

      if is_tile_empty(player_tx, player_ty, map) then
         break
      end
   end

   -- snap camera to player
   local sx, sy = tile_to_screen(player_tx, player_ty)
   camera_sx = sx - 64
   camera_sy = sy - 64

   return {
      time = 0,
      map = map,
      camera = { sx = camera_sx, sy = camera_sy },
      score = 0,
      recent_scores = {},
      collapsing_tiles = {},
      collapsing_ty = map_size.height,
      collapse_timer = max_collapse_timer,
      collapse_speed = 1,
      game_over_time = -1,
      player = {
         input_dir = -1,
         move_timer = max_move_timer,
         tail = {},
         positions = {
            { tx = player_tx, ty = player_ty, dir = -1 }
         }
      }
   }
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
         for i = max_player_length, 1, -1 do
            player.tail[i] =  player.tail[i - 1]
         end
         player.tail[1] = {
            tile_type = tile_type,
            source_tx = tx,
            source_ty = ty,
            is_emptying = false
         }

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
   if not state or (state.game_over_time >= 0 and btnp(5)) then
      state = create_state()
   end

   state.time += 1
   state.collapse_timer -= state.collapse_speed
   state.collapse_speed *= 1.0005
   state.collapse_speed = min(state.collapse_speed, 200)

   local cam = state.camera
   local player = state.player
   local map = state.map

   player.move_timer -= 1

   if state.collapse_timer < 0 then
      state.collapse_timer = max_collapse_timer

      local player_tx, player_ty = get_current_player_tile(player)
      local prev_ty = state.collapsing_ty
      local max_ty = player_ty + 20
      if state.collapsing_ty > max_ty then
         state.collapsing_ty = max_ty
      else
         state.collapsing_ty -= 1
      end

      -- random tile
      local tx = flr(rnd(map_size.width + 1))
      local ty = flr(rnd(map_size.height + 1))

      if is_tile_empty(tx, ty, map) then
         add(state.collapsing_tiles, { tx = tx, ty = ty, time = state.time })
      end

      -- bottom of map
      for tx = 1, map_size.width do
         for ty = state.collapsing_ty, prev_ty do
            if is_tile_empty(tx, ty, map) then
               add(state.collapsing_tiles, { tx = tx, ty = ty, time = state.time - flr(rnd(10)) })
            end
         end
      end

   end

   local collapsing_tiles = {}
   foreach(state.collapsing_tiles, function(collapsing_tile)
              if state.time - collapsing_tile.time < max_tile_collapse_timer then
                 add(collapsing_tiles, collapsing_tile)
              else
                 local player_tx, player_ty = get_current_player_tile(player)
                 if player_tx == collapsing_tile.tx and player_ty == collapsing_tile.ty and state.game_over_time < 0 then
                    state.game_over_time = state.time
                 end

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

   if state.game_over_time >= 0 then
      return
   end

   for dir = 0, 3 do
      if btnp(dir) then
         player.input_dir = dir
      end
   end

   if try_move(player, map, player.input_dir) or
   try_move(player, map, get_current_player_dir(player)) then end

   local padding = 80
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

   function draw_tile(tx, ty, tile_type)
      local x0, y0 = tile_to_screen(tx, ty)
      local x1, y1 = tile_to_screen(tx + 1, ty + 1)
      x1 -= 1
      y1 -= 1
      rectfill(x0, y0, x1, y1, tile_type)
   end

   function draw_tile_sprite(tx, ty, sprite, width, height, offset_x, offset_y)
      local x, y = tile_to_screen(tx, ty)
      x += (offset_x or 0)
      y += (offset_y or 0)

      width = width == nil and 8 or flr(width * 8)
      height = height == nil and 8 or flr(height * 8)
      sspr((sprite % 16) * 8, flr(sprite / 16) * 8, 8, 8, x + 4 - flr(width / 2), y + 4 - flr(height / 2), width, height)
   end

   function draw_tile_type_sprite(tx, ty, tile_type)
      if tile_type == tile_types.solid then
         return
      else
         -- offset to align tiles with objects above, since we don't have z
         local base_offset_x = -2
         local base_offset_y = 2
         draw_tile_sprite(tx, ty, 32, 1, 1, base_offset_x, base_offset_y)
         draw_tile_sprite(tx, ty, 33, 1, 1, base_offset_x + 8, base_offset_y + 0)
         draw_tile_sprite(tx, ty, 48, 1, 1, base_offset_x + 0, base_offset_y + 8)
         draw_tile_sprite(tx, ty, 49, 1, 1, base_offset_x + 8, base_offset_y + 8)

         if tile_type == tile_types.floor then
         elseif is_source_tile_type(tile_type) then
            draw_tile_sprite(tx, ty, 4)
         elseif tile_type == tile_types.destination then
            draw_tile_sprite(tx, ty, 2)
         else
            assert(false)
         end
      end
   end

   for tx = 1, 16 do
      for ty = 1, 16 do
         local star_sprite = mget(star_map.tx + (tx - 1) % star_map.width, star_map.ty + (ty - 1) % star_map.height)
         if star_sprite != 0 then
            spr(star_sprite, tx * 8, ty * 8)
         end
      end
   end

   local shooting_star_period = 100
   local slow_time = flr(state.time / 2)
   local shooting_star_frame = slow_time % shooting_star_period
   if shooting_star_frame < shooting_star_sprite.length then
      local fixed_start = slow_time - slow_time % shooting_star_period
      local tx = fixed_start % 16
      local ty = (fixed_start + 123) % 16
      draw_tile_sprite(tx, ty, shooting_star_sprite.start + shooting_star_frame)
   end

   camera(cam.sx, cam.sy)

   local start_x, start_y = screen_to_tile(cam.sx, cam.sy)
   local end_x, end_y = screen_to_tile(cam.sx + 128, cam.sy + 128)

   start_x = flr(min(max(1, start_x), map_size.width))
   end_x = ceil(min(max(1, end_x), map_size.width))
   start_y = flr(min(max(1, start_y), map_size.height))
   end_y = ceil(min(max(1, end_y), map_size.height))

   for x = start_x, end_x do
      for y = start_y, end_y do
         local idx = to_1d_idx(x, y, map_size)
         local tile_type = state.map[idx]
         draw_tile_type_sprite(x, y, tile_type)
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
              draw_tile_type_sprite(tx + d_tpos, ty + d_tpos, tile_type)
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
         local is_game_over = state.game_over_time >= 0

         local float_frac = 0.5 * (1 + sin(state.time / 30))

         local w, h = 1, 1
         if is_game_over then
            local fall_frac = max(0, 1 - (state.time - state.game_over_time) / 10)
            w = fall_frac
            h = fall_frac
         else
            -- draw shadow
            palt(7, true)
            palt(0, false)
            draw_tile_sprite(tx, ty, 34)
            palt()
         end

         draw_tile_sprite(tx, ty, 3, w, h, 0, -2 - float_frac * 4)

         if is_game_over then
            break
         end
      else
         local tail_item = player.tail[i - 1]
         if tail_item then
            local sprite = get_tail_sprite(tail_item, player.positions[1])
            draw_tile_sprite(tx, ty - 0.2 + 0.2 * sin(0.08 * i + state.time / 30), sprite)
         end
      end
   end

   camera(0, 0)
   color(7)

   function hcenter(s)
      return 64 - #s * 2
   end

   if state.game_over_time >= 0 and state.time - state.game_over_time > game_over_show_time then
      local msg = "you scored "..state.score.."!"
      print(msg, hcenter(msg), 60)

      msg = "❎ to restart"
      print(msg, hcenter(msg) - 2, 76)
   else
      print(state.score, 10, 10)
   end

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
0000000066666666bbbbbbbb00777700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000066666666bbbbbbbb07ccccc0009999000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0070070066666666bbbbbbbb0cc1111009999990000aa00000000000000000000000000000000000000000000000000000000000000000000000000000000000
0007700066666666bbbbbbbb0c1111100999999000aaaa0000077000000000000000000000000000000000000000000000000000000000000000000000000000
0007700066666666bbbbbbbbec11111e0999999000aaaa0000077000000000000000000000000000000000000000000000000000000000000000000000000000
0070070066666666bbbbbbbb2e22222209999990000aa00000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000066666666bbbbbbbb22222222009999000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000066666666bbbbbbbb02222220000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000070000000700000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000007000000070000000700000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000700000000000000000000000000000007000000070000000000000000000000000000000000000000000000000000000000000000000000000000
0003000000000000000000000000a000000000000000700000007000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000700000007000000000000000000000000000000000000000000000000000000000000000000
00000000000000000700000000000000000000000000000000000070000000700000007000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00055555555560007777777700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00055555555560007777777700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00555555555600007777777700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00555555555600007777777700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
05555555556000007777777700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
05555555556000007700007700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
55555555560000007000000700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
55555555560000007700007700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
ddddddddd00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__map__
0101000000000000000100000000000000000000000000000000001100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0101000201010000000100000000000000000000000000000000000000000000000000130000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0201000101010101010100000001010200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0001000000010000000100000001000000000000000000000012000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0101010201010001010101020101010100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0100000000010002010100000101000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0101010101010000000100000201000000000000000000000000000000000012000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0002000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000110000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000001200000000000000000011000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000130000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
