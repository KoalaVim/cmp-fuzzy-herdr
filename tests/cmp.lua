-- Real cmp event loop: nvim --headless -u NONE -c 'luafile tests/cmp.lua'
vim.opt.rtp:prepend(vim.fn.getcwd())
local parent = vim.fn.fnamemodify(vim.fn.getcwd(), ':h')
for _, name in ipairs({ 'nvim-cmp', 'cmp-fuzzy-buffer', 'fuzzy.nvim', 'fzy-lua-native' }) do
	vim.opt.rtp:append(parent .. '/' .. name)
end
local cmp = require('cmp')
local capture = require('cmp_fuzzy_herdr.capture')
vim.env.HERDR_PANE_ID = 'self'
capture.run = function(args, _, cb)
	vim.schedule(function()
		if args[2] == 'current' then
			cb(vim.json.encode({ result = { pane = { pane_id = 'self' } } }))
		elseif args[2] == 'list' then
			cb(vim.json.encode({
				result = {
					panes = {
						{ pane_id = 'self', tab_id = 'tab', workspace_id = 'workspace' },
						{ pane_id = 'other', tab_id = 'tab', workspace_id = 'workspace' },
					},
				},
			}))
		else
			cb('completionWord some/path?query')
		end
	end)
end
cmp.register_source('fuzzy_herdr', require('cmp_fuzzy_herdr').new())
cmp.register_source('fuzzy_buffer', require('cmp_fuzzy_buffer').new())
local compare = require('cmp.config.compare')
cmp.setup({
	completion = { autocomplete = false },
	sources = {
		{ name = 'fuzzy_buffer', priority = 150, option = { fuzzy_backend = 'fzy' } },
		{ name = 'fuzzy_herdr', priority = 100 },
	},
	sorting = {
		comparators = {
			require('cmp_fuzzy_buffer.compare'),
			require('cmp_fuzzy_herdr.compare'),
			compare.score,
			compare.order,
		},
	},
})
cmp.setup.cmdline('/', { sources = { { name = 'fuzzy_herdr' } } })
vim.api.nvim_buf_set_lines(0, 0, -1, false, { '', 'completionBuffer' })
local function finish_error(err)
	io.stderr:write(tostring(err) .. '\n')
	vim.cmd('cq!')
end
local function later(fn)
	vim.defer_fn(function()
		local ok, err = pcall(fn)
		if not ok then
			finish_error(err)
		end
	end, 50)
end
local function await(predicate, next_step, attempts)
	attempts = attempts or 100
	later(function()
		if predicate() then
			next_step()
		else
			assert(attempts > 0, 'timed out waiting for cmp')
			await(predicate, next_step, attempts - 1)
		end
	end)
end
local function confirm_label(label)
	for _ = 1, #cmp.get_entries() do
		cmp.select_next_item()
		if cmp.get_selected_entry():get_word() == label then
			assert(cmp.confirm({ select = false }))
			return
		end
	end
	error('missing candidate ' .. label)
end
vim.api.nvim_input('icmp')
later(function()
	cmp.complete()
	await(function()
		return #cmp.get_entries() >= 2
	end, function()
		local sources = {}
		for _, entry in ipairs(cmp.get_entries()) do
			sources[entry.source.name] = true
		end
		assert(sources.fuzzy_buffer and sources.fuzzy_herdr, 'both sources must participate')
		assert(cmp.get_entries()[1].source.name == 'fuzzy_buffer', 'buffer priority')
		confirm_label('completionWord')
		await(function()
			return vim.api.nvim_get_current_line() == 'completionWord'
		end, function()
			vim.api.nvim_input(vim.keycode('<Esc>/spq'))
			later(function()
				cmp.complete()
				await(function()
					return cmp.visible() and #cmp.get_entries() > 0
				end, function()
					confirm_label('some\\/path\\?query')
					await(function()
						return vim.fn.getcmdline() == 'some\\/path\\?query'
					end, function()
						print('Real cmp: source priorities, insert confirmation and escaped search confirmation passed')
						vim.api.nvim_input(vim.keycode('<Esc>'))
						later(function()
							vim.cmd('qa!')
						end)
					end)
				end)
			end)
		end)
	end)
end)
