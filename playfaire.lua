-- Playfaire
-- Euclidean sequencer
-- (blatant copy of ash/playfair)
--
-- Simple sequencer to
-- play up to 8
-- samples simultaneously.
--
-- v1.1.0
--
--
-- E1      Select page
-- K1 + E1 Select track
-- K2      Reset phase
-- K3      Start/Stop
--
-- E2      Density
-- E3      Length
-- K1 + E2 Change BPM
-- K1 + E3 Multiplier
--
-- See README for more
--
--
-- llllllll.co/t/xxx
--
-- Many thanks to those before me:
-- @tehn
-- @dndrks
-- @pq
-- @simonvanderveldt
-- @okyeron
-- @justmat


er = require "er"
engine.name = "Ack"

local VERSION = "1.1.0"

local Ack = require "ack/lib/ack"
local Fileselect = require "fileselect"
local Passthrough = include("lib/passthrough")
local ui = include("lib/core/ui")

local clock_counter = 0
local track_edit = 1

local reset = false
local alt = false
local running = true
local selecting_file = false

local grd = {
  device = grid.connect(),
  keytimer = 0,
  current_pset = 0,
  current_pattern = 0
}

local num_tracks = 8 -- 8 is max for Ack
-- TODO(frederickk): Store track data as params for pset recall.
local track = {}
for i = 1, num_tracks do
  track[i] = {
    density = 0,
    len = 16,
    mult = 1,
    pos = 1,
    triggered = false,
    s = {},
  }
end

local pattern = {}
for i = 1, 112 do
  pattern[i] = {
    data = 0,
    density = {},
    len = {},
    mult = {},
  }
  for x = 1, num_tracks do
    pattern[i].density[x] = 0
    pattern[i].len[x] = 0
    pattern[i].mult[x] = 0
  end
end

local function reer(i)
  if track[i].density == 0 then
    for n = 1, 16 do track[i].s[n] = false end
  else
    track[i].s = er.gen(track[i].density, track[i].len)
  end
end

local function trig()
  for i = 1, num_tracks do
    if track[i].s[track[i].pos] then
      if track[i].triggered == false then
        track[i].triggered = true
        engine.trig(i - 1)
      end
    end
  end
end

local function reset_pattern()
  reset = true
  clock_counter = 0

  if reset then
    for i = 1, num_tracks do
      track[i].pos = 0
    end
    reset = false
  end

  redraw()
end

local function step()
  while true do
    clock.sync(1 / 4)

    if running then
      for i = 1, num_tracks do
        if (math.fmod(clock_counter, track[i].mult) == 0) then
          track[i].triggered = false
          track[i].pos = (track[i].pos % track[i].len) + 1
        end
      end

      trig()

      if (selecting_file == false) then
        redraw()
      end
  
      clock_counter = math.fmod(clock_counter + 1, 16)
    end
  end
end

--- Event handler for Midi start.
function clock.transport.start()
  running = true
end

--- Event handler for Midi stop.
function clock.transport.stop()
  running = false
end

function init()
  print("Playfaire v" .. VERSION)
  
  screen.line_width(1)
  screen.aa(0)
  screen.ping()

  playfaire_load()

  Passthrough.init()

  -- params:add_separator()
  ui.add_page_params() 

  for i = 1, num_tracks do reer(i) end

  -- add params
  params:add_separator()
  Ack.add_effects_params()

  for channel = 1, num_tracks do
    params:add_separator()
    Ack.add_channel_params(channel)
  end
  params:default()

  params:read()
  params:bang()

  clock.run(step)
end

function key(index, z)
  if index == 1 then
    alt = z
  elseif index == 2 and z == 1 then
    if (ui.page_get() >= 2) then
      selecting_file = true
      Fileselect.enter(_path.dust .. "audio", function(file)
        selecting_file = false
        if file ~= "cancel" then
          params:set(track_edit .. "_sample", file)
          -- reset_pattern()
        end
      end)
    else
      reset_pattern()
    end
  elseif index == 3 and z == 1 then
    running = not running
  end
end

function enc(index, d)
  if index == 1 then
    if alt == 1 then
      track_edit = util.clamp(track_edit + d, 1, num_tracks)
    else
      ui.page_delta(d)
    end
  elseif index == 2 then
    if (ui.page_get() == 2) then
      params:delta(track_edit .. "_start_pos", d)
    elseif (ui.page_get() == 3) then
      params:delta(track_edit .. "_vol", d)
    elseif (ui.page_get() == 4) then
      params:delta(track_edit .. "_delay_send", d)
    else
      if alt == 1 then
        params:delta("clock_tempo", d)
      else
        track[track_edit].density = util.clamp(track[track_edit].density + d, 0, track[track_edit].len)
      end
    end
  elseif index == 3 then
    if (ui.page_get() == 2) then
      params:delta(track_edit .. "_end_pos", d)
    elseif (ui.page_get() == 3) then
      params:delta(track_edit .. "_speed", d)
    elseif (ui.page_get() == 4) then
      params:delta(track_edit .. "_reverb_send", d)
    else
      if alt == 1 then
        track[track_edit].mult = util.clamp(track[track_edit].mult + d, 1, 16)
      else
        track[track_edit].len = util.clamp(track[track_edit].len + d, 1, 16)
        track[track_edit].density = util.clamp(track[track_edit].density, 0, track[track_edit].len)
      end
    end
  elseif index == 4 then
    -- if (ui.page_get() == 4) then
    --   params:delta(track_edit .. "_dist", d)
    -- else
      track[track_edit].mult = util.clamp(track[track_edit].mult + d, 1, 16)
    -- end
  end

  reer(track_edit)
  redraw()
end

function redraw()
  screen.clear()
  screen.level(ui.OFF)

  if (ui.page_get() == 1) then
    for i = 1, num_tracks do
      local y = (track_edit > 5) and ((i * 10) + 10) - 10 * (track_edit - 5) or (i * 10) + 10

      if params:get(i .. "_sample") == "-" or params:get(i .. "_sample") == nil then    
        screen.level(ui.OFF)
      else 
        screen.level(ui.ON)
      end
      screen.move(0, y)
      screen.text(i .. ".")

      screen.level((i == track_edit) and ui.ON or ui.OFF)
      screen.move(14, y)
      screen.text(track[i].density)
      screen.move(24, y)
      screen.text(track[i].len)
      screen.move(36, y)
      screen.text(track[i].mult)

      for x = 1, track[i].len do
        screen.level((track[i].pos == x and not reset) and ui.ON or ui.OFF)
        screen.move(x * 5 + 45, y)
        if track[i].s[x] then
          screen.line_rel(0, -8)
        else
          screen.line_rel(0, -2)
        end
        screen.stroke()
      end
    end
  
  elseif (ui.page_get() >= 2) then
    if params:get(track_edit .. "_sample") == "-" or params:get(track_edit .. "_sample") == nil then    
      screen.level(ui.OFF)
    else 
      screen.level(ui.ON)
    end
    screen.move(0, 20)
    screen.text(track_edit .. ".")

    screen.level(ui.ON)
    screen.move(14, 20)
    screen.text(params:string(track_edit .. "_sample"))

    ui.draw_param(track_edit .. "_start_pos", 2, 14, 28, {
      label = "Start",
    })
    ui.draw_param(track_edit .. "_start_pos", 2, 14, 48, {
      label = "End",
    })

    ui.draw_param(track_edit .. "_vol", 3, ui.VIEWPORT.width / 3, 28, {
      label = "Volume",
    })
    ui.draw_param(track_edit .. "_speed", 3, ui.VIEWPORT.width / 3, 48, {
      label = "Speed",
    })

    ui.draw_param(track_edit .. "_delay_send", 4, ui.VIEWPORT.width / 3 * 2, 28, {
      label = "Delay",
    })
    ui.draw_param(track_edit .. "_reverb_send", 4, ui.VIEWPORT.width / 3 * 2, 48, {
      label = "Reverb",
    })
    -- TODO(frederickk): Add distortion as parameter?
    -- ui.draw_param(track_edit .. "_dist", 4, ui.VIEWPORT.width / 3 * 2, 58, {
    --   label = "Distort",
    -- })
  end

  screen.level(0)
  screen.rect(0, 0, 128, 10)
  screen.fill()

  screen.level(ui.OFF)
  screen.move(48, 7)
  screen.text(params:get("clock_tempo"))
  ui.signal(68, 4, (clock_counter % 4 == 0) and true or false)  
  screen.move(82, 7)
  screen.text(params:string("clock_source"))

  screen.update()
end

-- Grid
function grd.redraw()
  grd.device:all(0)
  if grd.current_pset > 0 and grd.current_pset < 17 then
    grd.device:led(grd.current_pset, 1, 9)
  end

  for x = 1, 16 do
    for y = 2, num_tracks do
      local id = x + (y - 2) * 16
      if pattern[id].data == 1 then
        grd.device:led(x, y, id == grd.current_pattern and 15 or 4)
      end
    end
  end

  grd.device:refresh()
end

function grd.device.key(x, y, z)
  print(x, y, z)
  local id = x + (y - 1) * 16
  if z == 1 then
    if id > 16 then
      grd.keytimer = util.time()
    elseif id < 17 then
      -- TODO(freederickk): Does this need to be user agnostic?
      params:read("tehn/playfaire-" .. string.format("%02d", id) .. ".pset")
      params:bang()
      grd.current_pset = id
    end
  else
    if id > 16 then
      id = id - 16
      local elapsed = util.time() - grd.keytimer
      if elapsed < 0.5 and pattern[id].data == 1 then
        -- recall pattern
        grd.current_pattern = id
        for i = 1, num_tracks do
          track[i].len = pattern[id].len[i]
          track[i].density = pattern[id].density[i]
          reer(i)
        end
        --reset_pattern()
      elseif elapsed > 0.5 then
        -- store pattern
        grd.current_pattern = id
        for i = 1, num_tracks do
          pattern[id].len[i] = track[i].len
          pattern[id].density[i] = track[i].density
          pattern[id].data = 1
        end
      end
    end

    grd.redraw()
  end
end

function playfaire_save()
  local fd = io.open(norns.state.data .. "playfaire.data", "w+")
  for i = 1, 112 do
    fd:write(pattern[i].data .. "\n")
    for x = 1, num_tracks do
      fd:write(pattern[i].density[x] .. "\n")
      fd:write(pattern[i].len[x] .. "\n")
      fd:write(pattern[i].mult[x] .. "\n")
    end
  end
  fd:close(fd)

  fd = io.open(norns.state.data .. "playfaire.track.data", "w+")
  for i = 1, num_tracks do
    fd:write(track[i].density .. "\n")
    fd:write(track[i].len .. "\n")
    fd:write(track[i].mult .. "\n")
    -- fd:write(track[i].s .. "\n")
  end
  fd:close(fd)

  -- save params
  params:write()
end

function playfaire_load()
  local fd = io.open(norns.state.data .. "playfaire.data", "r")

  if fd then
    print("found playfaire.data")
    for i = 1, 112 do
      pattern[i].data = tonumber(fd:read())
      for x = 1, num_tracks do
        pattern[i].density[x] = tonumber(fd:read())
        pattern[i].len[x] = tonumber(fd:read())
        pattern[i].mult[x] = tonumber(fd:read())
      end
    end
    fd:close(fd)
  end

  fd = io.open(norns.state.data .. "playfaire.track.data", "r")
  if fd then
    print("found playfaire.track.data")
    for i = 1, num_tracks do
      track[i].density = tonumber(fd:read())
      track[i].len = tonumber(fd:read())
      track[i].mult = tonumber(fd:read())
      -- track[i].s = tonumber(fd:read())
    end
    fd:close(fd)
  end

  -- load saved params
  params:read()
end

function cleanup()
  playfaire_save()
end
