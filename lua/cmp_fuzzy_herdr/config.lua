local M = {}
local defaults = {
	scope = 'tab',
	pane_ids = {},
	exclude_current = true,
	capture_source = 'recent-unwrapped',
	max_lines = 2000,
	cache_ttl_ms = 500,
	timeout_ms = 1000,
	fuzzy_backend = 'fzy',
	min_match_length = 1,
	max_match_length = 100,
	max_matches = 15,
}
local configured = {}

function M.resolve(options)
	local result = vim.deepcopy(defaults)
	for _, layer in ipairs({ configured, options or {} }) do
		for key, value in pairs(layer) do
			if defaults[key] == nil then
				error('cmp-fuzzy-herdr: unknown option ' .. key)
			end
			result[key] = vim.deepcopy(value)
		end
	end
	assert(vim.tbl_contains({ 'tab', 'workspace', 'panes' }, result.scope), 'invalid scope')
	assert(vim.tbl_contains({ 'visible', 'recent-unwrapped' }, result.capture_source), 'invalid capture_source')
	assert(type(result.exclude_current) == 'boolean', 'exclude_current must be boolean')
	assert(type(result.pane_ids) == 'table' and vim.islist(result.pane_ids), 'pane_ids must be a list')
	for _, id in ipairs(result.pane_ids) do
		assert(type(id) == 'string' and id ~= '', 'invalid pane ID')
	end
	for _, key in ipairs({ 'max_lines', 'timeout_ms', 'min_match_length', 'max_match_length', 'max_matches' }) do
		assert(type(result[key]) == 'number' and result[key] >= 1 and result[key] % 1 == 0, 'invalid ' .. key)
	end
	assert(type(result.cache_ttl_ms) == 'number' and result.cache_ttl_ms >= 0, 'invalid cache_ttl_ms')
	assert(type(result.fuzzy_backend) == 'string', 'invalid fuzzy_backend')
	return result
end

function M.setup(options)
	local previous = configured
	configured = vim.deepcopy(options or {})
	local ok, err = pcall(M.resolve)
	if not ok then
		configured = previous
		error(err)
	end
end

return M
