local root = vim.fn.getcwd()
vim.opt.rtp:prepend(root)
local siblings = vim.fn.fnamemodify(root, ':h')
for _, name in ipairs({ 'nvim-cmp', 'fuzzy.nvim', 'fzy-lua-native' }) do
	vim.opt.rtp:append(siblings .. '/' .. name)
end
local count = 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if not ok then
		error(name .. ': ' .. tostring(err))
	end
	count = count + 1
	print('ok ' .. count .. ' - ' .. name)
end
local eq = function(a, b)
	assert(vim.deep_equal(a, b), vim.inspect(a) .. ' != ' .. vim.inspect(b))
end
local config = require('cmp_fuzzy_herdr.config')
local capture = require('cmp_fuzzy_herdr.capture')
local Source = require('cmp_fuzzy_herdr')
local panes = {
	{ pane_id = 'self', tab_id = 'tab', workspace_id = 'workspace' },
	{ pane_id = 'neighbor', tab_id = 'tab', workspace_id = 'workspace' },
	{ pane_id = 'hidden', tab_id = 'tab', workspace_id = 'workspace', focused = false },
	{ pane_id = 'other-tab', tab_id = 'tab2', workspace_id = 'workspace' },
	{ pane_id = 'other-workspace', tab_id = 'tab3', workspace_id = 'workspace2' },
}
local options = config.resolve()
test('registration with real nvim-cmp', function()
	dofile(root .. '/after/plugin/cmp_fuzzy_herdr.lua')
	local found = false
	for _, s in pairs(require('cmp').get_registered_sources()) do
		if s.name == 'fuzzy_herdr' then
			found = true
		end
	end
	assert(found)
end)
test('layered options replace lists and do not mutate', function()
	config.setup({ scope = 'workspace', pane_ids = { 'one', 'two' }, max_lines = 77 })
	local input = { pane_ids = { 'three' }, scope = 'panes' }
	local a = config.resolve(input)
	eq(a.pane_ids, { 'three' })
	eq(a.max_lines, 77)
	a.pane_ids[1] = 'changed'
	eq(input.pane_ids, { 'three' })
	eq(config.resolve().pane_ids, { 'one', 'two' })
	assert(not pcall(config.setup, { max_lines = 0 }))
	eq(config.resolve().scope, 'workspace')
	config.setup({})
end)
test('recorded Herdr envelope selects only sibling panes', function()
	local data = vim.json.decode(table.concat(vim.fn.readfile(root .. '/tests/fixtures/panes.json'), '\n'))
	eq(capture.select(data.result.panes, 'self', options).ids, { 'neighbor' })
end)
test('tab selection includes hidden panes and excludes self and other tabs', function()
	eq(capture.select(panes, 'self', options).ids, { 'hidden', 'neighbor' })
	eq(capture.select(panes, 'missing', options), nil)
	eq(capture.select({}, 'self', options), nil)
	eq(capture.select({ false }, 'self', options), nil)
end)
test('workspace and explicit scope including current override', function()
	eq(
		capture.select(panes, 'self', config.resolve({ scope = 'workspace' })).ids,
		{ 'hidden', 'neighbor', 'other-tab' }
	)
	eq(
		capture.select(panes, 'self', config.resolve({ scope = 'panes', pane_ids = { 'self', 'neighbor' } })).ids,
		{ 'neighbor' }
	)
	eq(
		capture.select(
			panes,
			'self',
			config.resolve({ scope = 'panes', pane_ids = { 'self' }, exclude_current = false })
		).ids,
		{ 'self' }
	)
end)
test('real fuzzy backend, control cleanup, deduplication and limits', function()
	local items = Source.items(
		{ '\27[31mcompletionWord\27[0m completionWord', 'complementary', 'unrelated' },
		'cmpw',
		options,
		false
	)
	eq(#items, 1)
	eq(items[1].label, 'completionWord')
	eq(#Source.items({ 'same' }, 'same', options, false), 0)
	eq(#Source.items({ 'alpha alphabet alpine' }, 'al', config.resolve({ max_matches = 2 }), false), 2)
	local path = Source.items({ 'some/path?query' }, 'spq', options, true)
	eq(path[1].word, 'some\\/path\\?query')
end)
test('source-local comparator and tie ordering', function()
	local cmp = require('cmp_fuzzy_herdr.compare')
	local function entry(label, score, name)
		return {
			source = { name = name or 'fuzzy_herdr' },
			completion_item = { label = label, data = { score = score } },
		}
	end
	eq(cmp(entry('a', 2), entry('bb', 1)), true)
	eq(cmp(entry('a', 2), entry('bb', 2)), true)
	eq(cmp(entry('a', 2), entry('b', 1, 'fuzzy_buffer')), nil)
end)
local original_run = capture.run
local env = vim.env.HERDR_PANE_ID
vim.env.HERDR_PANE_ID = 'self'
local reads, list_calls, fail_neighbor, topology, commands = 0, 0, false, panes, {}
local function fake_run(args, timeout, cb)
	commands[#commands + 1] = args
	if args[2] == 'current' then
		cb(vim.json.encode({ result = { pane = { pane_id = 'self' } } }))
	elseif args[2] == 'list' then
		list_calls = list_calls + 1
		cb(vim.json.encode({ result = { panes = topology } }))
	else
		reads = reads + 1
		eq(args[4], '--source')
		eq(args[6], '--lines')
		eq(timeout, 1000)
		if args[3] == 'neighbor' and fail_neighbor then
			cb(nil)
		else
			cb('completionWord\nscrollbackToken')
		end
	end
end
capture.run = fake_run
local function get(opts)
	local result
	capture.get(config.resolve(opts), function(lines)
		result = lines
	end)
	assert(result ~= nil)
	return result
end
test('capture caches reads and isolates capture settings', function()
	capture.clear()
	reads = 0
	eq(#get(), 4)
	eq(reads, 2)
	eq(#get(), 4)
	eq(reads, 2)
	get({ capture_source = 'visible' })
	eq(reads, 4)
	get({ max_lines = 10 })
	eq(reads, 6)
	get({ cache_ttl_ms = 0 })
	eq(reads, 8)
end)
test('partial failures, malformed metadata and missing context', function()
	capture.clear()
	fail_neighbor = true
	eq(get(), { 'completionWord', 'scrollbackToken' })
	fail_neighbor = false
	topology = {}
	eq(get(), {})
	topology = panes
	capture.run = function(_, _, cb)
		cb('malformed')
	end
	eq(get(), {})
	capture.run = fake_run
end)
test('topology changes cannot reuse cached text', function()
	capture.clear()
	reads = 0
	get()
	topology = vim.deepcopy(panes)
	topology[1].tab_id = 'tab2'
	eq(#get(), 2)
	eq(reads, 3)
	topology = panes
end)
test('async capture deduplicates reads and revalidates context', function()
	capture.clear()
	local deferred, results = {}, {}
	capture.run = function(args, timeout, cb)
		if args[2] == 'read' then
			deferred[#deferred + 1] = cb
		else
			fake_run(args, timeout, cb)
		end
	end
	capture.get(options, function(lines)
		results[1] = lines
	end)
	capture.get(options, function(lines)
		results[2] = lines
	end)
	eq(#deferred, 2)
	topology = vim.deepcopy(panes)
	topology[1].tab_id = 'tab2'
	deferred[2]('second')
	deferred[1]('first')
	eq(results, { {}, {} })
	topology = panes
end)
test('pane reads use at most four concurrent processes', function()
	capture.clear()
	topology = { panes[1] }
	for i = 1, 10 do
		topology[#topology + 1] = { pane_id = tostring(i), tab_id = 'tab', workspace_id = 'workspace' }
	end
	local waiting, active, maximum, result = {}, 0, 0
	capture.run = function(args, timeout, cb)
		if args[2] ~= 'read' then
			fake_run(args, timeout, cb)
			return
		end
		active = active + 1
		maximum = math.max(maximum, active)
		waiting[#waiting + 1] = function()
			active = active - 1
			cb('word')
		end
	end
	capture.get(options, function(lines)
		result = lines
	end)
	eq(#waiting, 4)
	while #waiting > 0 do
		table.remove(waiting, 1)()
	end
	eq(maximum, 4)
	eq(#result, 10)
	topology = panes
end)
test('superseded source request settles empty while newest delivers', function()
	local original_get = capture.get
	local callbacks, results = {}, {}
	capture.get = function(_, cb)
		callbacks[#callbacks + 1] = cb
	end
	local s = Source.new()
	for i = 1, 2 do
		s:complete({ option = {}, offset = 1, context = { cursor_before_line = 'cmpw' } }, function(r)
			results[i] = r.items
		end)
	end
	callbacks[2]({ 'completionWord' })
	callbacks[1]({ 'completionWord' })
	eq(#results[2], 1)
	eq(results[1], {})
	capture.get = original_get
end)
test('connection identity change suppresses pending results', function()
	capture.clear()
	local deferred, result = {}, nil
	capture.run = function(args, timeout, cb)
		if args[2] == 'read' then
			deferred[#deferred + 1] = cb
		else
			fake_run(args, timeout, cb)
		end
	end
	capture.get(options, function(lines)
		result = lines
	end)
	vim.env.HERDR_PANE_ID = 'changed'
	for _, cb in ipairs(deferred) do
		cb('word')
	end
	eq(result, {})
	vim.env.HERDR_PANE_ID = 'self'
end)
test('outside Herdr and invalid source config settle with no candidates', function()
	vim.env.HERDR_PANE_ID = nil
	local s = Source.new()
	assert(not s:is_available())
	local result
	s:complete({ option = {}, offset = 1, context = { cursor_before_line = 'cmpw' } }, function(r)
		result = r.items
	end)
	eq(result, {})
	vim.env.HERDR_PANE_ID = 'self'
	s:complete({ option = { max_lines = 0 }, offset = 1, context = { cursor_before_line = 'cmpw' } }, function(r)
		result = r.items
	end)
	eq(result, {})
end)
capture.run = original_run
vim.env.HERDR_PANE_ID = env
test('transport handles spawn failure and timeout without exceptions', function()
	local system = vim.system
	local result, calls
	calls = 0
	vim.system = function()
		error('spawn failure')
	end
	capture.run({ 'pane', 'list' }, 1, function(raw)
		result = raw
		calls = calls + 1
	end)
	assert(vim.wait(1000, function()
		return calls == 1
	end))
	eq(result, nil)
	vim.system = function(cmd, opts, cb)
		eq(cmd, { 'herdr', 'pane', 'list' })
		eq(opts.timeout, 17)
		cb({ code = 124, stdout = '' })
	end
	capture.run({ 'pane', 'list' }, 17, function(raw)
		result = raw
		calls = calls + 1
	end)
	assert(vim.wait(1000, function()
		return calls == 2
	end))
	eq(result, nil)
	vim.system = system
end)
print('Passed ' .. count .. ' tests')
vim.cmd('qa!')
