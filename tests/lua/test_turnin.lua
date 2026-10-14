-- FX-TURNIN: zz_xrrfix_task_sync.script (specs/fixes/fx-turnin.md)
local H = ...

local MOD, FILE = "zz xrRazom Fix - Turned-in Task Sync", "zz_xrrfix_task_sync"

-- xrr_net_client (xrRazom 1.4) defines the handlers as module functions and exports them
-- to _G at file end. Loaded lazily: the fix must force-load it before wrapping.
local NC_SRC = [==[
calls = {}
function OnPlayerTask(...)
	calls[#calls + 1] = { name = "OnPlayerTask", n = select("#", ...), args = { ... } }
	return "ret1", "ret2"
end
function OnJoinTask(...)
	calls[#calls + 1] = { name = "OnJoinTask", n = select("#", ...), args = { ... } }
end
function OnTaskSyncWith(...)
	calls[#calls + 1] = { name = "OnTaskSyncWith", n = select("#", ...), args = { ... } }
end
_G.OnPlayerTask   = OnPlayerTask
_G.OnTaskSyncWith = OnTaskSyncWith
_G.OnJoinTask     = OnJoinTask
]==]

local function setup(is_host, task_info)
	local G = H.env()
	G.XrrIsHost = function() return is_host end
	local tm = { task_info = task_info or {} }
	G.task_manager = { get_task_manager = function() return tm end }
	H.lazy(G, "xrr_net_client", NC_SRC)
	local fix = H.load_fix(G, MOD, FILE)
	fix.on_game_start()
	H.log_has(G, "[XRRFIX] tasksync: stage-255 guard installed", "install log")
	H.log_lacks(G, "missing, skipped", "all three handlers wrapped")
	return G, rawget(G, "xrr_net_client")
end

H.case("FX-TURNIN-001 peer drops stage-255 syncs for tasks it does not have", function()
	local G, nc = setup(false, {})
	H.truthy(nc, "xrr_net_client force-loaded by the fix")
	G.OnPlayerTask(1, "T", 5, 0, 0, 255)
	G.OnJoinTask("T", 5, 255, 0)
	G.OnTaskSyncWith(1, "T", 5, 255)
	H.eq(0, #nc.calls, "no original called")
	H.eq(3, H.log_count(G, "ignored turned-in task T (stage 255)"), "three log lines")
	H.log_has(G, "[XRRFIX] tasksync: OnPlayerTask ignored turned-in task T (stage 255)")
	H.log_has(G, "[XRRFIX] tasksync: OnJoinTask ignored turned-in task T (stage 255)")
	H.log_has(G, "[XRRFIX] tasksync: OnTaskSyncWith ignored turned-in task T (stage 255)")
end)

H.case("FX-TURNIN-002 active task (task_info[id].t) still gets stage 255", function()
	local G, nc = setup(false, { T = { t = {} } })
	G.OnTaskSyncWith(1, "T", 5, 255)
	H.eq(1, #nc.calls, "original called")
	H.eq("OnTaskSyncWith", nc.calls[1].name)
	H.eq(4, nc.calls[1].n, "arg count")
	H.same({ 1, "T", 5, 255 }, nc.calls[1].args, "same args")
	-- entry without .t is not "active"
	G, nc = setup(false, { T = {} })
	G.OnTaskSyncWith(1, "T", 5, 255)
	H.eq(0, #nc.calls, "task_info entry without t is dropped")
end)

H.case("FX-TURNIN-003 other stages pass through with all args and return values", function()
	local G, nc = setup(false, {})
	local r1, r2 = G.OnPlayerTask(1, "T", 5, 0, 0, 1, "x", nil, "z")
	H.eq(1, #nc.calls, "original called")
	H.eq(9, nc.calls[1].n, "trailing args (incl. nil hole) forwarded")
	H.same({ 1, "T", 5, 0, 0, 1, "x", nil, "z" }, nc.calls[1].args, "args")
	H.eq("ret1", r1, "first return value")
	H.eq("ret2", r2, "second return value")
	G.OnJoinTask("T", 5, 3, 0)
	G.OnTaskSyncWith(1, "T", 5, 0)
	H.eq(3, #nc.calls, "non-255 stages of the other handlers pass")
end)

H.case("FX-TURNIN-004 host never filters", function()
	local G, nc = setup(true, {})
	G.OnPlayerTask(1, "T", 5, 0, 0, 255)
	G.OnJoinTask("T", 5, 255, 0)
	G.OnTaskSyncWith(1, "T", 5, 255)
	H.eq(3, #nc.calls, "all originals called")
	H.log_lacks(G, "ignored turned-in task")
end)
