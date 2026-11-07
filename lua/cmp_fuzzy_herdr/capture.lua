local M = {}
local cache, pending = {}, {}
local clock = function()
	return vim.uv.hrtime() / 1e6
end

function M.identity()
	return vim.json.encode({
		vim.env.HERDR_SOCKET_PATH or '',
		vim.env.HERDR_SESSION or '',
		vim.env.HERDR_CONFIG_PATH or '',
		vim.env.HERDR_PANE_ID or '',
	})
end

-- All callbacks run on the main loop, including spawn errors and timeouts.
function M.run(args, timeout, callback)
	local command = { 'herdr' }
	vim.list_extend(command, args)
	local ok = pcall(vim.system, command, { text = true, timeout = timeout }, function(result)
		vim.schedule(function()
			callback(result.code == 0 and result.stdout or nil)
		end)
	end)
	if not ok then
		vim.schedule(function()
			callback(nil)
		end)
	end
end

local function decode(raw)
	if not raw then
		return nil
	end
	local ok, data = pcall(vim.json.decode, raw)
	if ok and type(data) == 'table' and type(data.result) == 'table' then
		return data.result
	end
end

function M.select(panes, current, options)
	if type(panes) ~= 'table' or not vim.islist(panes) then
		return nil
	end
	local owner
	for _, pane in ipairs(panes) do
		if type(pane) ~= 'table' or type(pane.pane_id) ~= 'string' then
			return nil
		end
		if pane.pane_id == current then
			owner = pane
		end
	end
	if
		options.scope ~= 'panes'
		and (not owner or type(owner.tab_id) ~= 'string' or type(owner.workspace_id) ~= 'string')
	then
		return nil
	end
	local ids, seen = {}, {}
	for _, pane in ipairs(panes) do
		local included = (options.scope == 'tab' and pane.tab_id == owner.tab_id)
			or (options.scope == 'workspace' and pane.workspace_id == owner.workspace_id)
			or (options.scope == 'panes' and vim.tbl_contains(options.pane_ids, pane.pane_id))
		if included and not (options.exclude_current and pane.pane_id == current) and not seen[pane.pane_id] then
			seen[pane.pane_id] = true
			ids[#ids + 1] = pane.pane_id
		end
	end
	table.sort(ids)
	return { ids = ids, tab = owner and owner.tab_id or '', workspace = owner and owner.workspace_id or '' }
end

local function discover(options, callback)
	-- pane current resolves inherited caller IDs after Herdr moves a process.
	M.run({ 'pane', 'current', '--current' }, options.timeout_ms, function(raw)
		local data = decode(raw)
		local pane = data and data.pane
		local current = type(pane) == 'table' and pane.pane_id or vim.env.HERDR_PANE_ID
		M.run({ 'pane', 'list' }, options.timeout_ms, function(list)
			local result = decode(list)
			callback(M.select(result and result.panes, current, options), current)
		end)
	end)
end

local function context_key(identity, current, selection, options)
	return vim.json.encode({
		identity,
		current or '',
		selection.tab,
		selection.workspace,
		selection.ids,
		options.capture_source,
		options.max_lines,
		options.timeout_ms,
	})
end

local function store(key, lines)
	-- Bound retained contexts. Pending reads are independently bounded per capture.
	if vim.tbl_count(cache) >= 16 then
		local oldest
		for k, value in pairs(cache) do
			if not oldest or value.time < cache[oldest].time then
				oldest = k
			end
		end
		cache[oldest] = nil
	end
	cache[key] = { lines = lines, time = clock() }
end

function M.get(options, callback)
	local identity = M.identity()
	discover(options, function(selection, current)
		if identity ~= M.identity() or not selection then
			callback({})
			return
		end
		local key = context_key(identity, current, selection, options)
		local function deliver(lines)
			if identity ~= M.identity() then
				callback({})
				return
			end
			-- Revalidate topology even for cache hits; tabs can change without env changes.
			discover(options, function(latest, latest_current)
				if
					identity ~= M.identity()
					or not latest
					or context_key(identity, latest_current, latest, options) ~= key
				then
					callback({})
				else
					callback(lines)
				end
			end)
		end
		local cached = cache[key]
		if cached and clock() - cached.time < options.cache_ttl_ms then
			deliver(cached.lines)
			return
		end
		if pending[key] then
			table.insert(pending[key], deliver)
			return
		end
		pending[key] = { deliver }
		local next_index, active, finished = 1, 0, 0
		local outputs = {}
		local function done()
			local lines = {}
			for i = 1, #selection.ids do
				if outputs[i] then
					vim.list_extend(lines, vim.split(outputs[i], '\n', { plain = true }))
				end
			end
			store(key, lines)
			local listeners = pending[key]
			pending[key] = nil
			for _, listener in ipairs(listeners) do
				listener(lines)
			end
		end
		if #selection.ids == 0 then
			done()
			return
		end
		local pump
		pump = function()
			while active < 4 and next_index <= #selection.ids do
				local index = next_index
				next_index, active = next_index + 1, active + 1
				M.run(
					{
						'pane',
						'read',
						selection.ids[index],
						'--source',
						options.capture_source,
						'--lines',
						tostring(options.max_lines),
						'--format',
						'text',
					},
					options.timeout_ms,
					function(raw)
						outputs[index] = raw
						active, finished = active - 1, finished + 1
						if finished == #selection.ids then
							done()
						else
							pump()
						end
					end
				)
			end
		end
		pump()
	end)
end

function M.clear()
	cache = {}
end
return M
