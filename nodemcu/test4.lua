-- SPDX-License-Identifier: GPL-3.0
--
-- Copyright 2020, Matyukevich Sergey <geomatsi@gmail.com>
--

--
-- modules
--

local m = require("pwm_motors")
local u = require("hc_sr_04")

--
-- globals
--

local dist = 0
local ws = nil

--
-- settings
--

dofile("settings.lua")

--
-- WIFI
--

local function wifi_connect_event(conn)
  print("Connected to AP(" .. conn.SSID .. ")...")
end

local function wifi_ip_addr_event(conn)
  print("Obtained IP(" .. conn.IP .. ")...")
  ws:connect(WS_URL)
end

local function wifi_disconnect_event(conn)
  if conn.reason == wifi.eventmon.reason.ASSOC_LEAVE then
    print("disconnected...")
    return
  else
    print("Failed to connect to AP(" .. conn.SSID .. ")")
  end

  for key,val in pairs(wifi.eventmon.reason) do
    if val == conn.reason then
      print("Reason: " .. val .. "(" .. key .. ")")
      break
    end
  end
end

wifi.eventmon.register(wifi.eventmon.STA_CONNECTED, wifi_connect_event)
wifi.eventmon.register(wifi.eventmon.STA_GOT_IP, wifi_ip_addr_event)
wifi.eventmon.register(wifi.eventmon.STA_DISCONNECTED, wifi_disconnect_event)

--
-- WebSocket
--

local function ws_conn(ws)
  print('ws_conn: connected')
end

local function ws_recv(ws, msg, opcode)
	print('ws_recv: message: ', msg)
	print('ws_recv: opcode ', opcode)

	local ok, req = pcall(function() return sjson.decode(msg); end)
	if ok == false then
		print("invalid json: " .. msg)
		ws:send("err: invalid json")
	end

	-- process server command
	if req.Cmd == "stop" then
		print("stop")
		m.stop()
	elseif req.Cmd == "fwd" then
		print("forward")
		m.fwd()
	elseif req.Cmd == "rev" then
		print("backward")
		m.rev()
	elseif req.Cmd == "left" then
		print("rotate left")
		m.left()
	elseif req.Cmd == "right" then
		print("rotate right")
		m.right()
	elseif req.Cmd == "speed" then
		print("speed " .. req.Val)
		val = tonumber(req.Val)
		if val  == nil then
			val = 700
		elseif val < 500 then
			val = 500
		elseif val > 1000 then
			val = 1000
		end
		m.speed(val)
	elseif req.Cmd == "dist" then
		local resp = string.format("%d", dist)
		print("distance: ", resp)
		ws:send(resp)
	elseif req.Cmd == "stats" then
		local data = {}

		data.fs_free, data.fs_used, data.fs_total = file.fsinfo()
		data.mem_heap = node.heap()

		-- convert to kB
		data.mem_heap = bit.rshift(data.mem_heap, 10)
		data.fs_total = bit.rshift(data.fs_total, 10)
		data.fs_used = bit.rshift(data.fs_used, 10)
		data.fs_free = bit.rshift(data.fs_free, 10)

		ok, json = pcall(sjson.encode, data)
		if ok then
			print("send stats: ", json)
			ws:send(json)
		else
			print("failed to encode!")
			ws:send("err: failed to encode json")
		end
	else
		print('unknown command: ', msg)
		ws:send("err: unknown command")
	end
end

local function create_ws_reconnect(ws)
  return function()
    print("WS reconnect...")
    ws:connect(WS_URL)
  end
end

local function ws_close(ws, status)
  print('ws_close: status ', status)
  tmr.create():alarm(5 * 1000, tmr.ALARM_SINGLE, create_ws_reconnect(ws))
end

--
-- LED
--

local function led_toggle()
	local val = gpio.read(LED_PIN)
	if (val == 0) then
		gpio.write(LED_PIN, gpio.HIGH)
	else
		gpio.write(LED_PIN, gpio.LOW)
	end
end

--
-- ultrasonic sensor callback
--

local function usound_cb(distance)
	-- m-to-cm
	dist = distance * 100
	led_toggle()
end

--
-- MAIN
--

-- configure LED pin
gpio.mode(LED_PIN, gpio.OUTPUT)

-- configure motors
m.init(LFWD_PIN, LREV_PIN, RFWD_PIN, RREV_PIN)

-- configure ultrasonic sensor
u.HCSR04(TRIG_PIN, ECHO_PIN, 10, 3, true, usound_cb).measure()

-- setup websocket connection
ws = websocket.createClient()
ws:config({headers={['User-Agent']='SMARS'}})
ws:on('connection', ws_conn)
ws:on('receive', ws_recv)
ws:on('close', ws_close)

-- connect to WiFi AP
print("Connecting to WiFi access point...")
wifi.setmode(wifi.STATION)
wifi.sta.config({ssid=WIFI_SSID, pwd=WIFI_PASS})
