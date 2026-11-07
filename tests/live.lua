vim.opt.rtp:prepend(vim.fn.getcwd())
local parent = vim.fn.fnamemodify(vim.fn.getcwd(), ':h')
for _, name in ipairs({ 'nvim-cmp', 'fuzzy.nvim', 'fzy-lua-native' }) do
	vim.opt.rtp:append(parent .. '/' .. name)
end
local config = require('cmp_fuzzy_herdr.config')
local capture = require('cmp_fuzzy_herdr.capture')
local source = require('cmp_fuzzy_herdr')
local word = assert(vim.env.HERDR_TEST_WORD, 'set HERDR_TEST_WORD')
local function collect(options)
	local lines
	capture.get(config.resolve(options), function(result)
		lines = result
	end)
	assert(
		vim.wait(10000, function()
			return lines ~= nil
		end),
		'capture timed out'
	)
	return source.items(lines, word, config.resolve(), true)
end
assert(#collect() > 0, 'same-tab scrollback word missing')
assert(#collect({ capture_source = 'visible' }) == 0, 'word should be above viewport')
source.setup({ scope = 'panes', pane_ids = { assert(vim.env.HERDR_TEST_TARGET) } })
assert(#collect() > 0, 'global explicit-pane settings failed')
assert(#collect({ pane_ids = {} }) == 0, 'per-source pane override failed')
source.setup({})
print('Live capture: scrollback, visible-only, global setup and source overrides passed')
vim.cmd('qa!')
