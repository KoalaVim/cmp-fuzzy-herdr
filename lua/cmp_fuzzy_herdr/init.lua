local config = require('cmp_fuzzy_herdr.config')
local capture = require('cmp_fuzzy_herdr.capture')
local source = {}
source.__index = source

function source.new()
	return setmetatable({ generation = 0 }, source)
end

function source.setup(options)
	config.setup(options)
	capture.clear()
end

function source:is_available()
	return vim.env.HERDR_PANE_ID ~= nil and vim.env.HERDR_PANE_ID ~= '' and vim.fn.executable('herdr') == 1
end

function source:get_keyword_pattern()
	if vim.api.nvim_get_mode().mode == 'c' then
		return [[.\+]]
	end
	return [[\%(\k\|-\)\+]]
end

local function clean(text)
	return text:gsub('\27%][^\7\27]*\7', '')
		:gsub('\27%][^\27]*\27\\', '')
		:gsub('\27%[[0-?]*[ -/]*[@-~]', '')
		:gsub('\27[@-_]', '')
		:gsub('[%z\1-\8\11-\31\127]', '')
end

function source.items(lines, pattern, options, search)
	local words, seen = {}, {}
	-- Include punctuation suffixes like fuzzy-buffer, useful for paths in searches.
	local regex = vim.regex([[\%(\k\|-\)\+\S*]])
	for _, line in ipairs(lines) do
		line = clean(line)
		local offset = 0
		while offset < #line do
			local first, last = regex:match_str(line:sub(offset + 1))
			if not first then
				break
			end
			local token = line:sub(offset + first + 1, offset + last)
			local base = vim.fn.matchstr(token, [[^\%(\k\|-\)\+]])
			for _, word in ipairs({ base, token }) do
				if not seen[word] and #word >= options.min_match_length and #word <= options.max_match_length then
					seen[word] = true
					words[#words + 1] = word
				end
			end
			offset = offset + last
		end
	end
	local matcher = require('fuzzy_nvim.backends').get(options.fuzzy_backend)
	local matches = matcher:filter(pattern, words)
	local items = {}
	for _, match in ipairs(matches) do
		local word = type(match[1]) == 'table' and match[1][1] or match[1]
		if search or word ~= pattern then
			items[#items + 1] = {
				label = word,
				word = search and vim.fn.escape(word, [[\/?]]) or word,
				filterText = pattern,
				data = { score = match[3] },
				dup = 0,
			}
		end
	end
	table.sort(items, function(a, b)
		if a.data.score ~= b.data.score then
			return a.data.score > b.data.score
		end
		if #a.label ~= #b.label then
			return #a.label < #b.label
		end
		return a.label < b.label
	end)
	while #items > options.max_matches do
		table.remove(items)
	end
	return items
end

function source:complete(params, callback)
	self.generation = self.generation + 1
	local generation = self.generation
	local ok, options = pcall(config.resolve, params.option)
	local pattern = params.context.cursor_before_line:sub(params.offset)
	if not ok or not self:is_available() or #pattern < options.min_match_length then
		callback({ items = {}, isIncomplete = true })
		return
	end
	local identity = capture.identity()
	local search = vim.api.nvim_get_mode().mode == 'c' and vim.tbl_contains({ '/', '?' }, vim.fn.getcmdtype())
	capture.get(options, function(lines)
		local items = {}
		if generation == self.generation and identity == capture.identity() then
			local success, result = pcall(source.items, lines, pattern, options, search)
			if success then
				items = result
			end
		end
		callback({ items = items, isIncomplete = true })
	end)
end

return source
