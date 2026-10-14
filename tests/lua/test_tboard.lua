-- FX-TBOARD: zz_xrrfix_taskboard.script (specs/fixes/fx-tboard.md)
local H = ...

local MOD, FILE = "zz xrRazom Fix - Taskboard Peer Details", "zz_xrrfix_taskboard"

-- pda_taskboard (PDA Taskboard Redesign v1.3): public get_task_card(task_info) builds
-- the card on demand; `build` stands in for pda_taskboard_cards.build_task_card(...).
local TB_SRC = [==[
function get_task_card(task_info)
	if not task_info then return nil end
	return build(task_info)
end
]==]

-- pda_taskboard_utils.split_legacy_details(value) -> subtitle, body (stubbed per test)
local TBU_SRC = [==[
calls = {}
function split_legacy_details(value)
	calls[#calls + 1] = value
	return split_impl(value)
end
]==]

local function setup(opts)
	local G = H.env()
	G.__connected = true
	G.XrrIsConnected = function() return G.__connected end
	G.xrr_task_offer_msgs = {}
	G.__preview_calls = 0
	-- xrr_patch_quests.xrr_peer_task_offer_preview as shipped (exported to _G); XrrNet absent.
	G.xrr_peer_task_offer_preview = function(task_id)
		G.__preview_calls = G.__preview_calls + 1
		local m = task_id and G._G.xrr_task_offer_msgs and G._G.xrr_task_offer_msgs[task_id]
		if not m then return nil end
		return { caption = m.caption, text = m.text, icon = m.icon, templ = m.templ }
	end
	local tb = H.load_module(G, "pda_taskboard", TB_SRC)
	local tbu = H.load_module(G, "pda_taskboard_utils", TBU_SRC)
	tbu.split_impl = function(v) return "Sub", "Body" end
	tb.build = function(task_info) return opts.card end
	local fix = H.load_fix(G, MOD, FILE)
	fix.on_game_start()
	H.log_has(G, "[XRRFIX] taskboard: get_task_card patched for peers", "install log")
	return G, tb, tbu
end

H.case("FX-TBOARD-002 card with local subtitle/body is left untouched", function()
	local card = { subtitle = "S", body = "" }
	local G, tb = setup({ card = card })
	G.xrr_task_offer_msgs.T1 = { caption = "C", text = "Host\\nText", icon = "ui\\y" }
	local got = tb.get_task_card({ task_id = "T1" })
	H.truthy(rawequal(card, got), "same card table returned")
	H.eq("S", got.subtitle, "subtitle")
	H.eq("", got.body, "body")
	H.eq(nil, got.icon, "icon")
	H.eq(0, G.__preview_calls, "xrr_peer_task_offer_preview not called")
end)

H.case("FX-TBOARD-003 empty card gets subtitle/body/icon from the host preview", function()
	local G, tb, tbu = setup({ card = { title = "T" } })
	G.xrr_task_offer_msgs.T1 = { caption = "C", text = "Sub\\nBody", icon = "ui\\x" }
	local got = tb.get_task_card({ task_id = "T1" })
	H.eq("Sub", got.subtitle, "subtitle")
	H.eq("Body", got.body, "body")
	H.eq("ui\\x", got.icon, "icon")
	H.eq("T", got.title, "title")
	H.same({ "Sub\\nBody" }, tbu.calls, "split_legacy_details(m.text)")
end)

H.case("FX-TBOARD-004 no change out of session / nil card / no preview / empty text", function()
	-- (a) not in a session
	local card = { title = "T" }
	local G, tb = setup({ card = card })
	G.__connected = false
	G.xrr_task_offer_msgs.T1 = { text = "Sub\\nBody", icon = "ui\\x" }
	local got = tb.get_task_card({ task_id = "T1" })
	H.truthy(rawequal(card, got), "(a) same card")
	H.same({ title = "T" }, got, "(a) unchanged")
	-- (b) orig returned nil
	G, tb = setup({ card = nil })
	G.xrr_task_offer_msgs.T1 = { text = "Sub\\nBody", icon = "ui\\x" }
	local ok, res = pcall(tb.get_task_card, { task_id = "T1" })
	H.truthy(ok, "(b) no error: " .. tostring(res))
	H.eq(nil, res, "(b) nil passes through")
	-- (c) no preview for the task
	card = { title = "T" }
	G, tb = setup({ card = card })
	got = tb.get_task_card({ task_id = "T2" })
	H.truthy(rawequal(card, got), "(c) same card")
	H.same({ title = "T" }, got, "(c) unchanged")
	-- (d) preview with empty text
	card = { title = "T" }
	G, tb = setup({ card = card })
	G.xrr_task_offer_msgs.T3 = { text = "", icon = "ui\\x" }
	got = tb.get_task_card({ task_id = "T3" })
	H.same({ title = "T" }, got, "(d) unchanged")
end)

H.case("FX-TBOARD-005 diagnostic line once per task_id per session", function()
	local G, tb = setup({ card = { title = "T" } })
	G.xrr_task_offer_msgs.T1 = { text = "Sub\\nBody" }
	for _ = 1, 3 do
		tb.build = function() return { title = "T" } end
		tb.get_task_card({ task_id = "T1" })
	end
	H.eq(1, H.log_count(G, "taskboard: task=T1 "), "lines for T1")
	H.log_has(G, "[XRRFIX] taskboard: task=T1 local_details=false host_msg=true preview_text=true")
	tb.get_task_card({ task_id = "T9" })
	H.eq(1, H.log_count(G, "taskboard: task=T9 "), "separate line for another task")
end)
