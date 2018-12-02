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
local pop_sprite = {
   start = 11,
   length = 3
}

local state = nil

local tile_types = {
   solid = 0,
   floor = 1,
   placeholder = 2,
   source_1 = 3,
   source_2 = 4,
   source_3 = 5,
   destination = 6,
   destination_used = 7
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
                  tile_type = rnd(1) < 0.6 and get_random_source_tile_type() or tile_types.destination
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
      title_screen = false,
      time = 0,
      map = map,
      camera = { sx = camera_sx, sy = camera_sy },
      score = 0,
      recent_scores = {},
      pops = {},
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

function is_tile_type(tx, ty, map, tile_type)
   if not is_valid_idx(tx, ty, map_size) then
      return false
   end

   return map[to_1d_idx(tx, ty, map_size)] == tile_type
end

function is_tile_empty(tx, ty, map)
   if not is_valid_idx(tx, ty, map_size) then
      return false
   end

   return is_empty_tile_type(map[to_1d_idx(tx, ty, map_size)])
end

function get_player_tile(player, idx)
   local pos = player.positions[idx or 1]
   return pos.tx, pos.ty
end

function get_player_dir(player)
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

   local player_tx, player_ty = get_player_tile(player)

   local tx1 = player_tx + dx
   local ty1 = player_ty + dy

   local tx, ty = nil, nil
   if is_tile_empty(tx1, ty1, map) then
      if player.move_timer <= 0 then
         tx = tx1
         ty = ty1
      end
   elseif player.move_timer > max_move_timer * 0.3 and #player.positions > 2 then
      -- allow moving as if from previous tile, within a certain time after the last move

      local tx2, ty2 = get_player_tile(player, 2)
      local tx3, ty3 = get_player_tile(player, 3)

      tx2 += dx
      ty2 += dy

      if (tx2 != player_tx or ty2 != player_ty) and (tx2 != tx3 or ty2 != ty3) and is_tile_empty(tx2, ty2, map) then
         tx = tx2
         ty = ty2

         for i = 1, max_player_length do
            player.positions[i] = player.positions[i + 1]
         end
      end
   end

   if tx and ty then
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
            local tx, ty = get_player_tile(player, i + 1)
            add(state.pops, {
                   tx = tx,
                   ty = ty,
                   time = state.time
            })
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
            map[idx] = tile_types.destination_used
         end
      end

      return true
   end

   return false
end

function _update()
   local do_restart_game = state and state.game_over_time >= 0 and btnp(5)
   if not state or do_restart_game then
      music(0)
      state = create_state()
      state.title_screen = not do_restart_game
   end

   state.time += 1

   for i = 1, 6 do
      if btn(i - 1) then
         state.title_screen = false
      end
   end

   if state.title_screen then
      return
   end

   state.collapse_timer -= state.collapse_speed
   state.collapse_speed *= 1.0005
   state.collapse_speed = min(state.collapse_speed, 200)

   local cam = state.camera
   local player = state.player
   local map = state.map

   player.move_timer -= 1

   if state.collapse_timer < 0 then
      state.collapse_timer = max_collapse_timer

      local player_tx, player_ty = get_player_tile(player)
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
                 local player_tx, player_ty = get_player_tile(player)
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
   try_move(player, map, get_player_dir(player)) then end

   local padding = 80
   local tx, ty = get_player_tile(player)
   local sx_max, sy_max = tile_to_screen(tx + 1, ty + 1)
   local sx_min, sy_min = tile_to_screen(tx, ty)
   local xdiff = max(sx_max - (cam.sx + 128 - padding), 0) + min(sx_min - (cam.sx + padding), 0)
   local ydiff = max(sy_max - (cam.sy + 128 - padding), 0) + min(sy_min - (cam.sy + padding), 0)
   cam.sx += xdiff / 20
   cam.sy += ydiff / 20
end

function _draw()
   if not state then
      return
   end

   local player = state.player
   local cam = state.camera;
   local map = state.map

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

   function draw_destination_sprites(tx, ty, is_used)
      local slow_time = flr((state.time + ty) / 3)
      local blink = slow_time % 40 == 0

      if not is_used and blink then
         pal(11, 7)
         pal(3, 7)
         pal(6, 7)
      end

      for dir = 0, 3 do
         local dx, dy = dir_to_dx_dy(dir)
         local city_tx, city_ty = tx + dx, ty + dy
         if is_tile_type(city_tx, city_ty, map, tile_types.solid) then
            -- smoke
            if is_used then
               local sx, sy = tile_to_screen(city_tx, city_ty)
               local time1 = ((state.time + tx) / 4) % 4
               local time2 = ((state.time + ty) / 3) % 4
               circfill(4 + sx + time1, sy - time1, 0.5, 6)
               circfill(4 + sx + time2, sy - time2, 0.5, 6)
            end

            draw_tile_sprite(city_tx, city_ty, is_used and 10 or 9)

            break
         end
      end

      if not is_used then
         draw_tile_sprite(tx, ty, 8)
      end

      pal()
   end

   function draw_floor_sprite(tx, ty)
      -- offset to align tiles with objects above, since we don't have z
      local base_offset_x = -2
      local base_offset_y = 2
      draw_tile_sprite(tx, ty, 32, 1, 1, base_offset_x, base_offset_y)
      draw_tile_sprite(tx, ty, 33, 1, 1, base_offset_x + 8, base_offset_y + 0)
      draw_tile_sprite(tx, ty, 48, 1, 1, base_offset_x + 0, base_offset_y + 8)
      draw_tile_sprite(tx, ty, 49, 1, 1, base_offset_x + 8, base_offset_y + 8)
   end

   function draw_tile_type_sprite(tx, ty, tile_type)
      if tile_type == tile_types.solid then
         return
      else
         draw_floor_sprite(tx, ty)

         if tile_type == tile_types.floor then
         elseif is_source_tile_type(tile_type) then
            palt(7, true)
            palt(0, false)
            draw_tile_sprite(tx, ty, 7)
            palt()
         elseif tile_type == tile_types.destination or tile_type == tile_types.destination_used then
            draw_destination_sprites(tx, ty, tile_type == tile_types.destination_used)
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

   local shooting_star_period = 70
   local slow_time = flr(state.time / 2)
   local shooting_star_frame = slow_time % shooting_star_period
   if shooting_star_frame < shooting_star_sprite.length then
      local fixed_start = slow_time - slow_time % shooting_star_period
      local tx = fixed_start % 16
      local ty = (fixed_start + 123) % 16
      draw_tile_sprite(tx, ty, shooting_star_sprite.start + shooting_star_frame)
   end

   camera(cam.sx, cam.sy)

   local start_x, start_y = screen_to_tile(cam.sx - 1, cam.sy - 1)
   local end_x, end_y = screen_to_tile(cam.sx + 128, cam.sy + 128)

   start_x = flr(min(max(1, start_x), map_size.width))
   end_x = ceil(min(max(1, end_x), map_size.width))
   start_y = flr(min(max(1, start_y), map_size.height))
   end_y = ceil(min(max(1, end_y), map_size.height))

   for x = start_x, end_x do
      for y = start_y, end_y do
         local idx = to_1d_idx(x, y, map_size)
         local tile_type = map[idx]
         draw_tile_type_sprite(x, y, tile_type)
      end
   end

   function draw_collapsing_tiles(shake)
      foreach(state.collapsing_tiles, function(collapsing_tile)
                 local collapse_frac = max(0, 1 - (state.time - collapsing_tile.time) / max_tile_collapse_timer)
                 assert(collapse_frac > 0)

                 local tx = collapsing_tile.tx
                 local ty = collapsing_tile.ty

                 local d_tpos = (collapse_frac % 0.1 > 0.05 and 1 / 8 or 0)
                 if not shake then
                    d_tpos = 0
                 end

                 local idx = to_1d_idx(tx, ty, map_size)
                 local tile_type = state.map[idx]
                 draw_tile_type_sprite(tx + d_tpos, ty + d_tpos, tile_type)
      end)
   end

   -- blacken static tiles
   for c = 1, 15 do
      pal(c, 0)
   end
   draw_collapsing_tiles(false)
   pal()

   draw_collapsing_tiles(true)

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
         local fall_frac = 0

         if is_game_over then
            fall_frac = min(1, (state.time - state.game_over_time) / 100)
            float_frac = 0
         else
            -- draw shadow
            palt(7, true)
            palt(0, false)
            draw_tile_sprite(tx, ty, 34)
            palt()
         end

         local w = 1 - fall_frac
         local h = 1 - fall_frac
         draw_tile_sprite(tx, ty, 3, w, h, 0, -2 - float_frac * 4 + fall_frac * 40)

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

   local pops = {}
   foreach(state.pops, function(item)
              local slow_time = flr((state.time - item.time) / 2)
              if slow_time < pop_sprite.length then
                 draw_tile_sprite(item.tx, item.ty, pop_sprite.start + slow_time)
                 add(pops, item)
              end
   end)
   state.pops = pops

   camera(0, 0)
   color(7)

   function hcenter(s)
      return 64 - #s * 2
   end

   if state.title_screen then
      local lines = {
         "citizen.",
         "supply the colonies with",
         "vital energy resources.",
         "pay no attention to the world",
         "collapsing around you.",
         "",
         "",
         "",
         "life expectancy in this",
         "line of work is short,",
         "but trust that you are valued.",
         "",
         "press an arrow key to begin"
      }

      for i = 1, #lines do
         local msg = lines[i]
         print(msg, hcenter(msg), 7 + (i - 1) * 9)
      end
   elseif state.game_over_time >= 0 and state.time - state.game_over_time > game_over_show_time then
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
0000000066666666bbbbbbbb00777700000000000000000000000000749999470000000000000000000000000000000000000000000000000000000000000000
0000000066666666bbbbbbbb07ccccc0009999000000000000000000499994470000000000060000000600000000000007000070070000700000000000000000
0070070066666666bbbbbbbb0cc1111009999990000aa00000000000444444470000000000050600000506000070070000700700000000000000000000000000
0007700066666666bbbbbbbb0c1111100999999000aaaa0000077000494444470000000000055500000555000007700000000000000000000000000000000000
0007700066666666bbbbbbbbec11111e0999999000aaaa000007700044944447003333000055d500005575000007700000000000000000000000000000000000
0070070066666666bbbbbbbb2e22222209999990000aa0000000000044494447030bb03001555510035555300070070000700700000000000000000000000000
0000000066666666bbbbbbbb22222222009999000000000000000000444444000300003011515511335155330000000007000070070000700000000000000000
0000000066666666bbbbbbbb02222220000000000000000000000000700000070033330001111110033333300000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000070000000700000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000007000000070000000700000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000700000000000000000000000000000007000000070000000000000000000000000000000000000000000000000000000000000000000000000000
0003000000000000000000000000a000000000000000700000007000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000700000007000000000000000000000000000000000000000000000000000000000000000000
00000000000000000700000000000000000000000000000000000070000000700000007000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000555555555d0007777777700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000555555555d0007777777700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00555555555d00007777777700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00555555555d00007777777700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0555555555d000007777777700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0555555555d000007700007700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
555555555d0000007000000700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
555555555d0000007700007700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
11111111100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__map__
0101000000000000000100000000000000000000000000000000001100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0101000201010000000100000000000000000000000000000000000000000000000000130000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0201000101010101010100000001010200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0001000000010000000100000001000000000000000000000012000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0101010201010001010101020101010100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0100000000010002010100000101000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0101010101010000000100000201000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0002000000000000000100000000000000000000000000000000000000001200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000110000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000001200000000000000000011000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000130000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__sfx__
001f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
002000001500018100150001000015000181001c10000000000000000000000000000000000000000000000000000000000000000000000000000000000000001825418242182321822217252172121724123241
0020000009244092410923109221092110921109212092120524411241112311122111211112111121211212022440e2410e2310e2210e2110e2110e2120e2121324407241072310722107221072210722207222
00200000042441024110231102211021110211102121021209244092410923109221092110921109212092121324407241072310722107211072110721207212022440e2410e2310e2210e2210e2210e2220e222
001000201160011600116000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001135324645113530c35300000
0022000009244092410923109221092110921109212092120524411241112311122111211112111121211212022440e2410e2310e2210e2110e2110e2120e212022440e2410e2310e2210e2000e2000e2000e200
002200000424410241102311022110211102111021210212092440924109231092210921109211092120921213244072410723107221072110721107212072121324407241072310722107200072000720007200
00110020101700010010170001000010010170001001017000100101700010010170131701017013170101700e171001000e17000100001000e170001000c170001000c170001000c170111700c170111700c171
0022001015216182161c2161521615216182161c2161521613216172161a216132161121615216182161121601106171001510615106181061c10615106111061510618106011060210602106021060210600000
001100200535300000106450535300000053531064511300053530000023625053530000005353236251130005353000001064505353000000535310645113000535300000236250535300000053532362505353
0022000009244092410923109221092110921109212092120524411241112311122111211112111121211212022440e2410e2310e2210e2110e2110e2120e2120524411241112311122111211112111121211212
001100001517000000151701017115170000001717018170000001a17018170000001717000000131700000013170151700000015170000001520000000152001324415244000001524400000000000000000000
001100001c170000001a170181711a170000001c17018170000000000017170000001517013170000001517000000000000000000000000000000000000000001324415244000001524400000000000000000000
001100001117011160111501317013160131501517015160181701816018150131300000000000151300000013170131601315015170151601515017170171601a1701a1601a1501135324645113530c35300000
00220000112261522618226112261122615226182261122613236172361a2361323613236172361a2361323600000000000000000000000000000000000000000000000000000000000000000000000000000000
002000000524405241052310522105211052110521205212072440724107231072210721107211072120721200000000000000000000000000000000000000000000000000000000000000000000000000000000
__music__
00 42020344
00 01050604
01 0708090a
00 0708090a
00 0b08090a
00 0c08090a
00 0b08090a
02 0d0e090f

