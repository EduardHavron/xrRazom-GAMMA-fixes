-- FX-QLIST (peer half): zz_xrrfix_taskboard_progress.script (specs/fixes/fx-qlist.md)
local H = ...

local MOD, FILE = "zz xrRazom Fix - Taskboard Refresh", "zz_xrrfix_taskboard_progress"
local MARKER = "[XRRFIX] taskboard: progressive refresh installed (redraw every 500 ms)"

-- xrr_patch_quests (xrRazom 1.4), peer side: one batch in flight; on_complete when all ids
-- answered (here: when the test calls finish()); an empty list completes at once.
local QUESTS_SRC = [==[
pending_cb = nil
requested = {}
function xrr_request_task_availability(ids, on_complete)
	if pending_cb then return false end
	requested[#requested + 1] = ids
	if #ids == 0 then on_complete(); return true end
	pending_cb = on_complete
	return true
end
function finish()
	local cb = pending_cb
	pending_cb = nil
	cb()
end
function OnQuestListResponse(npc, list)
	_G.xrr_quest_avail_full = _G.xrr_quest_avail_full or {}
	_G.xrr_quest_avail_full[npc] = list
end
_G.xrr_request_task_availability = xrr_request_task_availability
_G.OnQuestListResponse = OnQuestListResponse
]==]

-- xrr_patch_pda_taskboard: replaces the tab's refresh by table entry in on_game_start
-- (idempotent) and calls the global xrr_request_task_availability.
local XRR_TB_SRC = [==[
applied = 0
function on_game_start()
	if applied > 0 then return end
	if not (pda_taskboard and ui_pda_taskboard_tab and ui_pda_taskboard_tab.pda_taskboard_tab) then
		return
	end
	applied = applied + 1
	ui_pda_taskboard_tab.pda_taskboard_tab.OnBtnRefreshClicked = function(self)
		self.xrr_clicks = (self.xrr_clicks or 0) + 1
		xrr_request_task_availability(self.ids, function()
			pda_taskboard.refresh_tasks()
			self:DrawCategoryList()
		end)
	end
end
]==]

local function new_tab(G, ids)
	local tab = { ids = ids or { 10, 11 }, current_category = "cat", draws = 0, lists = {}, log = G.__uilog }
	tab.task_list = {
		pos = 0, max = 100,
		GetCurrentScrollPos = function(self) return self.pos end,
		GetMaxScrollPos = function(self) return self.max end,
		SetScrollPos = function(self, p) self.pos = p end,
	}
	function tab:DrawCategoryList() self.draws = self.draws + 1; G.__uilog[#G.__uilog + 1] = "cat" end
	function tab:RefreshTaskList(c)
		self.lists[#self.lists + 1] = c
		self.task_list.pos = 0 -- the real list rebuild resets scrolling
		G.__uilog[#G.__uilog + 1] = "list"
	end
	return tab
end

local function setup(opts)
	opts = opts or {}
	local G = H.env()
	G.__uilog = {}
	G.XrrIsClient = function() return opts.peer ~= false end
	G.xrr_quest_avail_full = { [10] = { "old10" }, [11] = { "old11" }, [99] = { "keep99" } }
	if not opts.no_board then
		local cls = { OnBtnRefreshClicked = function() error("board's own refresh must not run on a peer") end }
		G.ui_pda_taskboard_tab = { pda_taskboard_tab = cls }
		G.pda_taskboard = { calls = 0 }
		G.pda_taskboard.refresh_tasks = function()
			G.pda_taskboard.calls = G.pda_taskboard.calls + 1
			G.__uilog[#G.__uilog + 1] = "data"
			if opts.refresh_error then error("bad board", 0) end
		end
	end
	if not opts.no_quests then H.lazy(G, "xrr_patch_quests", QUESTS_SRC) end
	H.lazy(G, "xrr_patch_pda_taskboard", XRR_TB_SRC)
	local fix = H.load_fix(G, MOD, FILE)
	fix.on_game_start()
	return G, rawget(G, "xrr_patch_quests"), fix
end

local function click(G, tab) G.ui_pda_taskboard_tab.pda_taskboard_tab.OnBtnRefreshClicked(tab) end
local function at(G, ms) G.__now = ms; G.SendScriptCallback("actor_on_update") end

H.case("FX-QLIST-010 installs once around xrRazom's refresh, logs the marker", function()
	local G, q, fix = setup()
	H.log_has(G, MARKER)
	local xtb = rawget(G, "xrr_patch_pda_taskboard")
	H.eq(1, xtb.applied, "xrRazom's taskboard patch applied first")
	fix.on_game_start()
	H.eq(1, H.log_count(G, MARKER), "marker once")
	local tab = new_tab(G)
	click(G, tab)
	H.eq(1, tab.xrr_clicks, "xrRazom's refresh runs inside ours, once")
	H.eq(1, #q.requested, "one batch requested")
end)

H.case("FX-QLIST-010 without Taskboard or quest sync: skipped", function()
	local G = setup({ no_board = true })
	H.log_has(G, "[XRRFIX] taskboard: Taskboard or xrRazom quest sync not found, progressive refresh skipped")
	H.log_lacks(G, MARKER)
	G = setup({ no_quests = true })
	H.log_has(G, "progressive refresh skipped")
end)

H.case("FX-QLIST-011 refreshed NPCs' old lists cleared, others kept; nothing cleared when a batch is busy", function()
	local G, q = setup()
	click(G, new_tab(G))
	H.falsy(G.xrr_quest_avail_full[10], "10 cleared")
	H.falsy(G.xrr_quest_avail_full[11], "11 cleared")
	H.same({ "keep99" }, G.xrr_quest_avail_full[99], "unrelated NPC kept")
	G.OnQuestListResponse(10, { "t1" })
	local tab2 = new_tab(G, { 10, 99 })
	click(G, tab2) -- batch in flight: the stub refuses
	H.same({ "t1" }, G.xrr_quest_avail_full[10], "fresh answer kept")
	H.same({ "keep99" }, G.xrr_quest_avail_full[99], "not cleared by a refused batch")
end)

H.case("FX-QLIST-012 redraws at most every 500 ms while answers arrive, keeps the scroll", function()
	local G, q = setup()
	local tab = new_tab(G)
	at(G, 0)
	click(G, tab)
	at(G, 50)
	H.eq(0, G.pda_taskboard.calls, "no answers: no redraw")
	G.OnQuestListResponse(10, { "t1" })
	at(G, 100)
	G.OnQuestListResponse(11, { "t2" })
	at(G, 200); at(G, 499)
	H.eq(0, G.pda_taskboard.calls, "throttled before 500 ms")
	tab.task_list.pos = 40
	at(G, 500)
	H.eq(1, G.pda_taskboard.calls, "one redraw for both answers")
	H.same({ "data", "cat", "list" }, G.__uilog, "data, categories, task list in that order")
	H.same({ "cat" }, tab.lists, "current category redrawn")
	H.eq(40, tab.task_list.pos, "scroll restored")
	at(G, 1200)
	H.eq(1, G.pda_taskboard.calls, "no new answers: no redraw")
	G.OnQuestListResponse(11, { "t3" })
	tab.task_list.pos, tab.task_list.max = 300, 120
	at(G, 1300)
	H.eq(2, G.pda_taskboard.calls, "next answer redrawn")
	H.eq(120, tab.task_list.pos, "scroll clamped to the new maximum")
end)

H.case("FX-QLIST-013 final redraw after xrRazom's on_complete, then idle", function()
	local G, q = setup()
	local tab = new_tab(G)
	at(G, 0)
	click(G, tab)
	G.OnQuestListResponse(10, { "t1" })
	at(G, 600)
	q.finish()
	H.same({ "data", "cat", "list", "data", "cat", "data", "cat", "list" }, G.__uilog,
		"progressive redraw, xrRazom's own draw, then our full redraw")
	H.log_has(G, "[XRRFIX] taskboard: refresh done, 1 progressive redraws")
	G.OnQuestListResponse(11, { "late" })
	at(G, 2000)
	H.eq(3, G.pda_taskboard.calls, "after completion answers do not redraw")
end)

H.case("FX-QLIST-013 empty NPC list completes at once with a full redraw", function()
	local G = setup()
	local tab = new_tab(G, {})
	click(G, tab)
	H.same({ "data", "cat", "data", "cat", "list" }, G.__uilog, "xrRazom's draw, then ours")
	H.log_has(G, "[XRRFIX] taskboard: refresh done, 0 progressive redraws")
end)

H.case("FX-QLIST-014 host: wrappers pass through, nothing cleared or redrawn", function()
	local G, q = setup({ peer = false })
	local tab = new_tab(G)
	click(G, tab)
	H.eq(1, tab.xrr_clicks, "click passed through")
	H.same({ "old10" }, G.xrr_quest_avail_full[10], "nothing cleared")
	G.OnQuestListResponse(10, { "t1" })
	at(G, 1000)
	q.finish()
	H.same({ "data", "cat" }, G.__uilog, "only xrRazom's own draw")
	H.log_lacks(G, "refresh done")
end)

H.case("FX-QLIST-015 redraw errors logged once per refresh; destroyed tab is not redrawn", function()
	local G, q = setup({ refresh_error = true })
	local tab = new_tab(G)
	at(G, 0)
	click(G, tab)
	G.OnQuestListResponse(10, { "t1" }); at(G, 600)
	G.OnQuestListResponse(11, { "t2" }); at(G, 1200)
	H.eq(1, H.log_count(G, "[XRRFIX] taskboard: redraw error: bad board"), "logged once")

	G, q = setup()
	tab = new_tab(G)
	at(G, 0)
	click(G, tab)
	tab.destroyed = true
	G.OnQuestListResponse(10, { "t1" }); at(G, 600)
	H.eq(0, G.pda_taskboard.calls, "closed tab not redrawn")
end)
