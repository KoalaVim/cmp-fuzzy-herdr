NVIM ?= nvim

test:
	$(NVIM) --headless -u NONE -l tests/run.lua
	$(NVIM) --headless -u NONE -c 'luafile tests/cmp.lua'
