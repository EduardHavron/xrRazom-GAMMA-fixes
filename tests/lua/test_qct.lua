-- MOD-QCT: qct_main.script (specs/fixes/mod-qct.md)
local H = ...

local MOD, FILE = "Quantity Craft and Transfer", "qct_main"

-------------------------------------------------------------------------------
-- World: objects with deferred client removal (alife_release is not instant)
-------------------------------------------------------------------------------
local Obj = {}
Obj.__index = Obj
function Obj:id() return self._id end
function Obj:section() return self._sec end
function Obj:condition() return self._cond or 1 end
function Obj:get_remaining_uses() return self._uses end
function Obj:set_remaining_uses(n) self._uses = n end
function Obj:ammo_get_count() return self._ammo end
function Obj:parent() return self._parent and self._w.objects[self._parent] end
function Obj:position() local x = self._x or 0; return { x = x, distance_to_sqr = function(_, o) return (x - o.x) ^ 2 end } end
function Obj:character_name() return self._nick end
function Obj:name() return self._sec .. self._id end

local AMMO = { ammo_x = 10, rnd = 10 }

local function world(G)
	local w = { objects = {}, se = {}, queue = {}, released = {}, creates = {}, next_id = 100, delay = 3 }
	function w.spawn(sec, t)
		w.next_id = w.next_id + 1
		local o = setmetatable({ _id = w.next_id, _sec = sec, _w = w, _parent = 0 }, Obj)
		for k, v in pairs(t or {}) do o[k] = v end
		w.objects[o._id] = o
		w.se[o._id] = { id = o._id, section_name = function() return sec end }
		return o
	end
	function w.count(sec)
		local n = 0
		for id, o in pairs(w.objects) do if o._sec == sec and not w.queue[id] then n = n + 1 end end
		return n
	end
	function w.tick()
		for id, left in pairs(w.queue) do
			if left <= 1 then w.objects[id] = nil; w.queue[id] = nil else w.queue[id] = left - 1 end
		end
	end
	function w.doubles()
		for _, n in pairs(w.released) do if n > 1 then return true end end
		return false
	end

	local actor = setmetatable({ _id = 0, _sec = "actor", _w = w }, Obj)
	w.objects[0] = actor
	function actor:iterate_inventory(fn)
		for _, o in pairs(w.objects) do if o._parent == 0 and o ~= actor then fn(actor, o) end end
	end
	function actor:iterate_belt() end
	w.actor = actor

	G.db = { actor = actor }
	G.AC_ID = 0
	G.level = { object_by_id = function(id) return w.objects[id] end }
	G.alife_object = function(id) return w.se[id] end
	G.alife_release = function(se)
		if not se then return nil end -- engine: nothing to release
		local id = se.id
		if type(id) == "function" then id = se:id() end
		w.se[id] = nil
		w.released[id] = (w.released[id] or 0) + 1
		w.queue[id] = w.delay
		return true
	end
	G.alife_release_id = function(id) return G.alife_release(G.alife_object(id)) end
	G.alife_create_item = function(sec, parent, t)
		w.creates[#w.creates + 1] = { sec = sec, ammo = t and t.ammo }
		return w.spawn(sec, { _ammo = t and t.ammo })
	end
	G.IsItem = function(typ, sec, obj)
		sec = obj and obj:section() or sec
		if typ == "multiuse" then return (sec == "kit") and 3 or nil end
		if typ == "ammo" then return AMMO[sec] end
	end
	G.IsAmmo = function(o) return o._ammo ~= nil end
	G.utils_item = {
		is_degradable = function() return false end,
		discharge = function(obj, num)
			local u = obj:get_remaining_uses() - (num or 1)
			if u >= 1 then obj:set_remaining_uses(u) else G.alife_release(obj) end
		end,
	}
	G.utils_obj = { play_sound = function() end }
	G.utils_xml = { get_color = function() return "" end }
	G.ui_item = { get_sec_name = function(s) return s end }
	G.game = { translate_string = function(s) return s end }
	G.game_statistics = { increment_statistic = function() end }
	G.size_table = function(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
	G.strformat = string.format
	G.printe = function(f, ...) G.__log[#G.__log + 1] = "printe: " .. string.format(f, ...) end
	G.clamp = function(v, a, b) return math.max(a, math.min(b, v)) end
	G.__clock = 0
	G.time_continual = function() return G.__clock end
	G.__keys = {}
	G.key_state = function(k) return G.__keys[k] and 1 or 0 end
	G.DIK_keys = { DIK_Y = 21, DIK_LCONTROL = 29, DIK_RCONTROL = 157, DIK_LSHIFT = 42, DIK_RSHIFT = 54, DIK_LMENU = 56, DIK_RMENU = 184 }
	G.ui_events = { WINDOW_KEY_PRESSED = 1 }
	G.actor_menu = { set_msg = function(_, s) w.hud = s end }
	G.qct_dialog = { open = function(p) w.dialog = p; return true end, is_open = function() return false end }
	return w
end

-------------------------------------------------------------------------------
-- ui_workshop stand-in: UpdateItem sees every live client object (like the stock
-- one); Craft mirrors zz_ui_workshop_keep_crafting_window_open (471- Craft From Stashes):
-- release, discharge, ammo = one box of craft_item_r[2], loop of craft_item_r[2]
-- results, lead box refund of (used - 1).
-------------------------------------------------------------------------------
local function workshop(G, w)
	local Craft = {}
	G.ui_workshop = { UIWorkshopCraft = Craft, workshop_toolkits = { "itm_basickit" } }
	w.craft_calls, w.chain_open = 0, {}

	function Craft:IsShown() return true end
	function Craft:UpdateItem(n, sec, amount, result)
		if result then
			local allow = true
			for i = 1, 4 do if self.craft_allow[i] == false then allow = false end end
			self.craft_allow_r = allow
			self.craft_item_r = { sec, AMMO[sec] or 1 }
			return
		end
		self.craft_item[n], self.craft_item_remain[n] = {}, {}
		local ids = {}
		for id, o in pairs(w.objects) do if o._sec == sec and o._parent == 0 then ids[#ids + 1] = id end end
		table.sort(ids)
		local multi = G.IsItem("multiuse", sec)
		local cnt = 0
		for _, id in ipairs(ids) do cnt = cnt + (multi and w.objects[id]._uses or 1) end
		self.craft_allow[n] = cnt >= amount
		local k = 0
		for _, id in ipairs(ids) do
			if k >= amount then break end
			self.craft_item[n][#self.craft_item[n] + 1] = id
			k = k + (multi and w.objects[id]._uses or 1)
		end
	end
	function Craft:On_CC_Mouse1(cont, idx)
		self.selected_index = self.CC.list.cell[idx].flags.info
		self.craft_item, self.craft_item_remain, self.craft_allow = {}, {}, {}
		self.complexCraft = {}
		local r = self.recipes[self.last_type][self.selected_index]
		for i = 1, 4 do if r[i] then self:UpdateItem(i, r[i][1], r[i][2], false) end end
		self:UpdateItem(nil, r.sec, 1, true)
	end
	function Craft:Craft()
		if not self.craft_allow_r then return end
		w.craft_calls = w.craft_calls + 1
		w.chain_open[#w.chain_open + 1] = w.peer_window
		local lead = 0
		for i = 1, #self.craft_item do
			for _, id in ipairs(self.craft_item[i]) do
				if w.objects[id] and w.objects[id]._sec == "lead_box" then lead = lead + 1 end
				G.alife_release_id(id)
			end
			local rem = self.craft_item_remain[i]
			if rem.id and w.objects[rem.id] then for _ = 1, rem.cnt do G.utils_item.discharge(w.objects[rem.id]) end end
		end
		if AMMO[self.craft_item_r[1]] then
			G.alife_create_item(self.craft_item_r[1], G.db.actor, { ammo = self.craft_item_r[2] })
		else
			for _ = 1, self.craft_item_r[2] do G.alife_create_item(self.craft_item_r[1], G.db.actor) end
		end
		if string.find(self.craft_item_r[1], "_lead_box") then
			for _ = 1, lead - 1 do G.alife_create_item("lead_box", G.db.actor) end
		end
	end
	function Craft:Update() end
	function Craft:Reset() end
	function Craft:OnKeyboard() return false end
	return Craft
end

local function new_wnd(Craft, recipe)
	local wnd = setmetatable({}, { __index = Craft })
	wnd.owner = { IsShown = function() return true end }
	wnd.btn_craft = { Show = function() end, Enable = function() end }
	wnd.info_text = { SetText = function(_, s) wnd.msg = s end }
	wnd.recipes = { [1] = { [1] = recipe } }
	wnd.recipes_items = { rec = true }
	wnd.toolkits_state = { true }
	wnd.last_type = 1
	wnd.CC = { list = { cell = { [7] = { flags = { info = 1 }, IsShown = function() return true end } }, hover = {} } }
	wnd:On_CC_Mouse1("list", 7)
	return wnd
end

local function setup(opts)
	local G = H.env()
	local w = world(G)
	local Craft = (not (opts and opts.no_workshop)) and workshop(G, w) or nil
	local m = H.load_fix(G, MOD, FILE)
	m.on_game_start()
	G.SendScriptCallback("actor_on_first_update")
	return G, w, m, Craft
end

local function ticks(G, w, Craft, wnd, n)
	for _ = 1, n do
		G.__clock = G.__clock + 16
		Craft.Update(wnd)
		w.tick()
	end
end

local RECIPE = { sec = "res", tool = 1, rsp = "rec", [1] = { "mat", 2 } }

-------------------------------------------------------------------------------
H.case("MOD-QCT-001 workshop patched once with the marker; no ui_inventory: logged and skipped", function()
	local G = setup()
	G.SendScriptCallback("actor_on_first_update")
	H.eq(1, H.log_count(G, "[QCT] workshop: batch crafting installed"), "marker once")
	H.log_has(G, "[QCT] inventory: UIInventory missing, skipped")
	local G2 = setup({ no_workshop = true })
	H.log_has(G2, "[QCT] workshop: UIWorkshopCraft missing, skipped")
end)

H.case("MOD-QCT-002 hotkey needs the exact modifier set; key <= 0 disables it", function()
	local G, w, m = setup()
	local K = G.DIK_keys
	local opts = { key = 21, mod_ctrl = true, mod_shift = true, mod_alt = false }
	G.ui_mcm = { get = function(path) return opts[string.match(path, "^qct/(.+)$")] end }
	G.__keys = { [K.DIK_LCONTROL] = true, [K.DIK_RSHIFT] = true }
	H.truthy(m.hotkey_match(21), "Ctrl+Shift+Y")
	H.falsy(m.hotkey_match(22), "other key")
	G.__keys = { [K.DIK_LCONTROL] = true }
	H.falsy(m.hotkey_match(21), "Ctrl+Y only")
	G.__keys = { [K.DIK_LCONTROL] = true, [K.DIK_LSHIFT] = true, [K.DIK_LMENU] = true }
	H.falsy(m.hotkey_match(21), "extra Alt")
	G.ui_mcm = nil -- defaults: Alt+Y
	G.__keys = {}
	H.falsy(m.hotkey_match(21), "plain Y with default Alt+Y")
	G.__keys = { [K.DIK_RMENU] = true }
	H.truthy(m.hotkey_match(21), "Alt+Y")
	opts = { key = -1 }
	G.ui_mcm = { get = function(path) return opts[string.match(path, "^qct/(.+)$")] end }
	H.falsy(m.hotkey_match(-1), "unbound")
end)

H.case("MOD-QCT-003 dialog max is the exact feasible N; the one-craft view is restored", function()
	local G, w, m, Craft = setup()
	for _ = 1, 11 do w.spawn("mat") end
	local wnd = new_wnd(Craft, RECIPE)
	m.open_craft_dialog(wnd)
	H.eq(5, w.dialog and w.dialog.max, "max")
	H.eq(2, #wnd.craft_item[1], "one-craft selection")
end)

H.case("MOD-QCT-004 OK with N: one Craft() call, N results, N sets consumed, nothing released twice", function()
	local G, w, m, Craft = setup()
	for _ = 1, 11 do w.spawn("mat") end
	local wnd = new_wnd(Craft, RECIPE)
	m.open_craft_dialog(wnd)
	w.dialog.on_ok(5)
	H.eq(1, w.craft_calls, "Craft calls")
	H.eq(5, #w.creates, "results")
	H.eq(1, w.count("mat"), "materials left")
	H.falsy(w.doubles(), "double release")
	ticks(G, w, Craft, wnd, 60)
	H.truthy(string.find(wnd.msg or "", "st_qct_craft_done", 1, true), "done message")
	H.log_has(G, "[QCT] craft res: asked 5, crafted 5 in one request")
end)

H.case("MOD-QCT-005 OK above what is left now is clamped by a fresh evaluation", function()
	local G, w, m, Craft = setup()
	for _ = 1, 7 do w.spawn("mat") end
	local wnd = new_wnd(Craft, RECIPE)
	m.open_craft_dialog(wnd)
	H.eq(3, w.dialog.max, "max at open")
	local gone = 0
	for id, o in pairs(w.objects) do
		if o._sec == "mat" and gone < 2 then w.objects[id] = nil; w.se[id] = nil; gone = gone + 1 end
	end
	w.dialog.on_ok(3)
	H.eq(2, #w.creates, "clamped")
	H.eq(1, w.count("mat"), "4 consumed")
end)

H.case("MOD-QCT-006 ammo result: N boxes of box size, dialog shows pieces", function()
	local G, w, m, Craft = setup()
	for _ = 1, 6 do w.spawn("mat") end
	local wnd = new_wnd(Craft, { sec = "ammo_x", tool = 1, rsp = "rec", [1] = { "mat", 2 } })
	m.open_craft_dialog(wnd)
	H.truthy(string.find(w.dialog.info_func(3), "st_qct_craft_info_units", 1, true), "pieces in info")
	w.dialog.on_ok(3)
	H.eq(3, #w.creates, "boxes")
	for i = 1, 3 do H.eq(10, w.creates[i].ammo, "box " .. i) end
end)

H.case("MOD-QCT-007 *_lead_box result: no lead box refund beyond per-craft", function()
	local G, w, m, Craft = setup()
	for _ = 1, 3 do w.spawn("lead_box"); w.spawn("af_x") end
	local wnd = new_wnd(Craft, { sec = "af_x_lead_box", tool = 1, rsp = "rec", [1] = { "lead_box", 1 }, [2] = { "af_x", 1 } })
	m.open_craft_dialog(wnd)
	w.dialog.on_ok(3)
	local res, refunds = 0, 0
	for _, c in ipairs(w.creates) do
		if c.sec == "af_x_lead_box" then res = res + 1 elseif c.sec == "lead_box" then refunds = refunds + 1 end
	end
	H.eq(3, res, "results")
	H.eq(0, refunds, "refunds")
end)

H.case("MOD-QCT-008 next batch refused while released objects linger; warning after the timeout", function()
	local G, w, m, Craft = setup()
	for _ = 1, 8 do w.spawn("mat") end
	w.delay = 1e9 -- removal never confirmed
	local wnd = new_wnd(Craft, RECIPE)
	m.open_craft_dialog(wnd)
	w.dialog.on_ok(2)
	H.eq(2, #w.creates, "first batch")
	w.dialog = nil
	m.open_craft_dialog(wnd)
	H.eq(nil, w.dialog, "second dialog")
	H.truthy(string.find(wnd.msg or "", "st_qct_wait", 1, true), "wait message")
	H.falsy(w.doubles(), "double release")
	ticks(G, w, Craft, wnd, 400)
	H.truthy(string.find(wnd.msg or "", "st_qct_warn_sync", 1, true), "sync warning")
end)

H.case("MOD-QCT-009 multi-use material: fewest uses first, exact consumption", function()
	local G, w, m, Craft = setup()
	local k1 = w.spawn("kit", { _uses = 1 })
	local k2 = w.spawn("kit", { _uses = 1 })
	w.spawn("kit", { _uses = 3 })
	local k4 = w.spawn("kit", { _uses = 2 })
	local wnd = new_wnd(Craft, { sec = "res", tool = 1, rsp = "rec", [1] = { "kit", 3 } })
	H.same({ k1._id, k2._id }, wnd.craft_item[1], "whole items")
	H.same({ id = k4._id, cnt = 1 }, wnd.craft_item_remain[1], "discharge")
	m.open_craft_dialog(wnd)
	H.eq(2, w.dialog.max, "max")
	w.dialog.on_ok(2)
	ticks(G, w, Craft, wnd, 60)
	local left = 0
	for _, o in pairs(w.objects) do if o._sec == "kit" then left = left + o._uses end end
	H.eq(2, #w.creates, "results")
	H.eq(1, left, "uses left")
end)

local function stack_gui(w, mode, items)
	local gui = { mode = mode, npc_id = 50, moved = {} }
	gui.IsShown = function() return true end
	gui.Cond_Move = function() return true end
	gui.Cond_Quest = function() return false end
	gui.Action_Move = function(self, id) self.moved[#self.moved + 1] = id; w.objects[id]._parent = 50; self.CC.actor_bag.indx_id[id] = nil end
	local cell = { ID = items[1]._id, childs = {} }
	local idx = {}
	for i, o in ipairs(items) do
		idx[o._id] = 1
		if i > 1 then cell.childs[o._id] = 1 end
	end
	gui.CC = { actor_bag = { indx_id = idx, GetCell_ID = function(self, id) return self.indx_id[id] and cell end } }
	return gui
end

H.case("MOD-QCT-010 move N: best first, re-validated at OK, packs counted in pieces", function()
	local G, w, m = setup()
	local box = setmetatable({ _id = 50, _sec = "box", _w = w }, Obj)
	w.objects[50] = box
	local a = w.spawn("rnd", { _ammo = 4 })
	local b = w.spawn("rnd", { _ammo = 10 })
	local c = w.spawn("rnd", { _ammo = 7 })
	local d = w.spawn("rnd", { _ammo = 10 })
	local gui = stack_gui(w, "loot", { a, b, c, d })
	m.open_move_dialog(gui, a._id, "actor_bag")
	H.eq(4, w.dialog.max, "packs")
	G.game.translate_string = function(s) return s == "st_qct_move_info_units" and "%s|%s" or s end
	H.eq("31|27", w.dialog.info_func(3), "pieces total / top 3")
	d._parent = 50 -- left the bag before OK
	w.dialog.on_ok(2)
	H.same({ b._id, c._id }, gui.moved, "moved")
end)

local function coop(G, w, x)
	local avatar = setmetatable({ _id = 77, _sec = "peer", _w = w, _x = x, _nick = "Friend" }, Obj)
	w.objects[77] = avatar
	w.sends = {}
	G.XrrIsHost = function() return true end
	G.XrrIsConnected = function() return true end
	G.XrrPlayers = function() return {
		GetPeerCount = function() return 1 end,
		GetPeerNetidAt = function() return "N1" end,
		GetPeerLocalIdAt = function() return 77 end,
		SendGiveItem = function(_, netid, id) w.sends[#w.sends + 1] = id; w.objects[id]._parent = 77 end,
	} end
	return avatar
end

H.case("MOD-QCT-011 give N: best still owned first, one SendGiveItem per id, stops when the player leaves", function()
	local G, w, m = setup()
	coop(G, w, 2)
	local p = { w.spawn("med", { _cond = 0.5 }), w.spawn("med", { _cond = 0.9 }), w.spawn("med", { _cond = 0.7 }), w.spawn("med", { _cond = 0.8 }) }
	local gui = stack_gui(w, "inventory", p)
	m.refresh_peers()
	m.open_give_dialog(gui, p[1]._id, "actor_bag", 1)
	H.eq(4, w.dialog.max, "stack")
	p[2]._parent = 50
	w.dialog.on_ok(3)
	for _ = 1, 20 do G.__clock = G.__clock + 60; m.give_tick() end
	H.same({ p[4]._id, p[3]._id, p[1]._id }, w.sends, "sent once each, best first")
	H.log_has(G, "[QCT] give med x3/3 to Friend done")

	local G2, w2, m2 = setup()
	local av = coop(G2, w2, 2)
	local q = {}
	for i = 1, 4 do q[i] = w2.spawn("med", { _cond = i / 10 }) end
	local gui2 = stack_gui(w2, "inventory", q)
	m2.refresh_peers()
	m2.open_give_dialog(gui2, q[1]._id, "actor_bag", 1)
	w2.dialog.on_ok(4)
	av._x = 10
	for _ = 1, 20 do G2.__clock = G2.__clock + 60; m2.give_tick() end
	H.eq(1, #w2.sends, "stopped after the player left")
end)

H.case("MOD-QCT-012 no xrRazom or nobody within 5 m: no give entries", function()
	local G, w, m = setup()
	local p = { w.spawn("med"), w.spawn("med") }
	local gui = stack_gui(w, "inventory", p)
	m.refresh_peers()
	m.open_give_dialog(gui, p[1]._id, "actor_bag", 1)
	H.eq(nil, w.dialog, "solo")
	coop(G, w, 9)
	m.refresh_peers()
	m.open_give_dialog(gui, p[1]._id, "actor_bag", 1)
	H.eq(nil, w.dialog, "player 9 m away")
end)

H.case("MOD-QCT-013 peer: Craft runs inside the xrRazom peer-chain window", function()
	local G, w, m, Craft = setup()
	G.XrrIsHost = function() return false end
	G.XrrNet = function() return { SetPeerChainWindow = function(_, v) w.peer_window = v end } end
	for _ = 1, 4 do w.spawn("mat") end
	local wnd = new_wnd(Craft, RECIPE)
	m.open_craft_dialog(wnd)
	w.dialog.on_ok(2)
	H.same({ true }, w.chain_open, "window open during Craft")
	H.eq(false, w.peer_window, "closed after")
end)
