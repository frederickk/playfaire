-- Euclidean sequencer
--
-- (blatant copy of ash/playfair)
--
-- v2.0.1
--
-- E1 select
-- E2 density
-- E3 length
--
-- K1 + E1 bpm
-- K1 + E3 multiplier
--
-- K2 reset phase
-- K3 start/stop
--
-- add samples via param menu
--
--
-- llllllll.co/t/21349
--
-- @tehn
-- @dndrks
-- @pq
-- @simonvanderveldt
-- @okyeron
-- @justmat
-- @frederickk
--

er = require "er"
engine.name = "Ack"

local Ack = require "ack/lib/ack"
local Passthrough = include("lib/passthrough")
local BeatClock = require "beatclock"

local g = grid.connect()
-- TODO(frederickk): Update to nwe clock.
local clk = BeatClock.new()
local clk_midi = midi.connect()
clk_midi.event = function(data)
  clk:process_midi(data)
end
local clk_count = 0

local reset = false
local alt = false
local running = true
local track_edit = 1
local current_pattern = 0
local current_pset = 0
local keytimer = 0

local num_tracks = 8 -- 8 is max for Ack
local track = {}
for i = 1, num_tracks do
  track[i] = {
    density = 0,
    len = 16,
    mult = 1,
    pos = 1,
    s = {}
  }
end

local pattern = {}
for i = 1, 112 do
  pattern[i] = {
    data = 0,
    density = {},
    len = {}
  }
  for x = 1, num_tracks do
    pattern[i].density[x] = 0
    pattern[i].len[x] = 0
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
      engine.trig(i - 1)
    end
  end
end

function init()
  for i = 1, num_tracks do reer(i) end

  clk.on_step = step
  clk.on_select_internal = function() clk:start() end
  clk.on_select_external = reset_pattern

  params:add_separator()
  clk:add_clock_params()

  for channel = 1, num_tracks do
    params:add_separator()
    Ack.add_channel_params(channel)
  end
  
  params:add_separator()
  Ack.add_effects_params()

  params:default()

  playfaire_load()

  clk:start()

  Passthrough.init()

  screen.line_width(1)
  screen.aa(0)
  screen.ping()
end

local function reset_pattern()
  reset = true
  clk_count = 0
  clk:reset()
end

function step()
  if reset then
    for i = 1, num_tracks do
      track[i].pos = 1
    end
    reset = false
  else
    for i = 1, num_tracks do
      if (math.fmod(clk_count, track[i].mult) == 0) then
        track[i].pos = (track[i].pos % track[i].len) + 1
      end
    end
  end

  trig()
  redraw()
  
  clk_count = math.fmod(clk_count + 1, 16)
end

--- Event handler for Midi start.
function clock.transport.start()
  clk:start()
  running = true
end

--- Event handler for Midi stop.
function clock.transport.stop()
  clk:stop()
  running = false
end

function key(n, z)
  if n == 1 then
    alt = z
  elseif n == 2 and z == 1 then
    reset_pattern()
  elseif n == 3 and z == 1 then
    if running then
      clk:stop()
      running = false
    else
      clk:start()
      running = true
    end
  end

  redraw()
end

function enc(n, d)
  if n == 1 then
    if alt == 1 then
      params:delta("bpm", d)
    else
      track_edit = util.clamp(track_edit + d, 1, num_tracks)
    end
  elseif n == 2 then
    track[track_edit].density = util.clamp(track[track_edit].density + d, 0, track[track_edit].len)
  elseif n == 3 then
    if alt == 1 then
      track[track_edit].mult = util.clamp(track[track_edit].mult + d, 1, 16)
    else
      track[track_edit].len = util.clamp(track[track_edit].len + d, 1, 16)
      track[track_edit].density = util.clamp(track[track_edit].density, 0, track[track_edit].len)
    end
  elseif n == 4 then
    track[track_edit].mult = util.clamp(track[track_edit].mult + d, 1, 16)
  end

  reer(track_edit)
  redraw()
end

function redraw()
  screen.clear()
  screen.level(1)

  for i = 1, num_tracks do
    local y = (track_edit > 5) and ((i * 10) + 10) - 10 * (track_edit - 5) or (i * 10) + 10
    
    screen.level(1)
    screen.move(0, y)
    screen.text(i)

    screen.level((i == track_edit) and 15 or 1)
    screen.move(14, y)
    screen.text(track[i].density)
    screen.move(24, y)
    screen.text(track[i].len)
    screen.move(36, y)
    screen.text(track[i].mult)

    for x = 1, track[i].len do
      screen.level((track[i].pos == x and not reset) and 15 or 1)
      screen.move(x * 5 + 45, y)
      if track[i].s[x] then
        screen.line_rel(0, -8)
      else
        screen.line_rel(0, -2)
      end
      screen.stroke()
    end
  end

  screen.level(0)
  screen.rect(0, 0, 128, 10)
  screen.fill()

  screen.level(1)
  screen.move(0, 5)
  if params:get("clock") == 1 then
    -- screen.text(string.upper(string.sub(params:string("clock_source"), 1, 1)) .. params:get("clock_tempo") --[[.. " " .. params:get("bpm")--]])
    screen.text(params:get("clock_tempo") .. " " .. params:string("clock_source"))
  else
    for i = 1, clk.beat + 1 do
       screen.rect(i * 2, 1, 1, 2)
    end
    screen.fill()
  end

  screen.update()
end

function g.key(x, y, z)
  print(x, y, z)
  local id = x + (y - 1) * 16
  if z == 1 then
    if id > 16 then
      keytimer = util.time()
    elseif id < 17 then
      -- TODO(freederickk): Does this need to be user agnostic?
      params:read("tehn/playfaire-" .. string.format("%02d", id) .. ".pset")
      params:bang()
      current_pset = id
    end
  else
    if id > 16 then
      id = id - 16
      local elapsed = util.time() - keytimer
      if elapsed < 0.5 and pattern[id].data == 1 then
        -- recall pattern
        current_pattern = id
        for i = 1, num_tracks do
          track[i].len = pattern[id].len[i]
          track[i].density = pattern[id].density[i]
          reer(i)
        end
        --reset_pattern()
      elseif elapsed > 0.5 then
        -- store pattern
        current_pattern = id
        for i = 1, num_tracks do
          pattern[id].len[i] = track[i].len
          pattern[id].density[i] = track[i].density
          pattern[id].data = 1
        end
      end
    end
    grid_redraw()
  end
end

local function grid_redraw()
  g:all(0)
  if current_pset > 0 and current_pset < 17 then
    g:led(current_pset, 1, 9)
  end

  for x = 1, 16 do
    for y = 2, num_tracks do
      local id = x + (y - 2) * 16
      if pattern[id].data == 1 then
        g:led(x, y, id == current_pattern and 15 or 4)
      end
    end
  end
  g:refresh()
end

function playfaire_save()
  local fd = io.open(norns.state.data .. "playfaire.data", "w+")
  io.output(fd)

  for i = 1, 112 do
    io.write(pattern[i].data .. "\n")
    for x = 1, num_tracks do
      io.write(pattern[i].density[x] .. "\n")
      io.write(pattern[i].len[x] .. "\n")
    end
  end
  io.close(fd)

  -- save params
  params:write()
end

function playfaire_load()
  local fd = io.open(norns.state.data .. "playfaire.data", "r")

  if fd then
    print("found datafile")
    io.input(fd)
    for i = 1, 112 do
      pattern[i].data = tonumber(io.read())
      for x = 1, num_tracks do
        pattern[i].density[x] = tonumber(io.read())
        pattern[i].len[x] = tonumber(io.read())
      end
    end
    io.close(fd)
  end

  -- load saved params
  params:read()
end

cleanup = function()
  playfaire_save()
end


