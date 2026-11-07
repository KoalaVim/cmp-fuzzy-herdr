# cmp-fuzzy-herdr

Fuzzy [nvim-cmp](https://github.com/hrsh7th/nvim-cmp) completion from [Herdr](https://herdr.dev) terminal panes, powered by [KoalaVim/fuzzy.nvim](https://github.com/KoalaVim/fuzzy.nvim).

By default, reads **other panes in the caller's tab**, including panes hidden by zoom and recent output above the viewport. Retained history is bounded to 2,000 lines per pane; Herdr cannot recover discarded history or alternate-screen rows it never retained. No setup is needed. Outside Herdr the source is inactive.

Requires Neovim 0.10+, nvim-cmp, fuzzy.nvim with a working backend, and Herdr supporting `pane current --current`, `pane list`, and `pane read --source recent-unwrapped --lines N --format text` (tested with Herdr 0.8.2). Caller pane metadata must be resolvable; missing tab context produces no default candidates.

## Installation

```lua
{
  'KoalaVim/cmp-fuzzy-herdr',
  dependencies = {
    'hrsh7th/nvim-cmp',
    {
      'KoalaVim/fuzzy.nvim',
      dependencies = { { 'romgrk/fzy-lua-native', build = 'make' } },
    },
  },
}
```

Add the source and comparator to your existing cmp configuration:

```lua
local compare = require('cmp.config.compare')
require('cmp').setup({
  sources = {
    { name = 'fuzzy_buffer', priority = 150 }, -- if installed
    { name = 'fuzzy_herdr', priority = 100 },
  },
  sorting = {
    comparators = {
      require('cmp_fuzzy_herdr.compare'),
      compare.offset, compare.exact, compare.score,
      compare.recently_used, compare.length, compare.order,
    },
  },
})
```

## Configuration

All settings work both in optional plugin-wide setup and the cmp source's `option` table. Source options override plugin settings, which override built-in defaults. Lists are replaced as a whole. Unknown options or invalid values throw during setup; an invalid source configuration returns no candidates.

```lua
require('cmp_fuzzy_herdr').setup({
  scope = 'tab',                    -- 'tab', 'workspace', or 'panes'
  pane_ids = {},                    -- explicit IDs for scope = 'panes'
  exclude_current = true,
  capture_source = 'recent-unwrapped', -- or 'visible'
  max_lines = 2000,                 -- positive integer per pane
  cache_ttl_ms = 500,               -- 0 disables capture cache reuse
  timeout_ms = 1000,                -- positive integer per CLI request
  fuzzy_backend = 'fzy',            -- 'fzy', 'fzf', 'zf'; fuzzy.nvim fallback applies
  min_match_length = 1,
  max_match_length = 100,
  max_matches = 15,
})
```

For example, override only a specific source configuration to read visible text from explicit panes:

```lua
require('cmp').setup.filetype('markdown', {
  sources = {
    {
      name = 'fuzzy_herdr',
      max_item_count = 10,          -- normal cmp setting, independent of max_matches
      option = {
        scope = 'panes',
        pane_ids = { 'w1:p2', 'w1:p3' }, -- obtain IDs with herdr pane list
        capture_source = 'visible',
        max_lines = 100,
      },
    },
  },
})
```

To search the owning workspace instead, use `option = { scope = 'workspace' }`. To include the caller pane, set `exclude_current = false`. Scope uses live caller metadata rather than whichever tab another client has focused.

Search completion also works with `cmp.setup.cmdline('/', { sources = { { name = 'fuzzy_herdr' } } })`; inserted search delimiters are escaped.

## Behavior

Captures use asynchronous argument-vector CLI calls with four reads at a time, per-request timeouts, and up to 16 cached capture contexts. Metadata is revalidated before delivering results, even on cache hits. Identical in-flight reads are shared. Capture settings, target panes, tab/workspace context, and connection identity isolate cached text. New queries supersede old results. Closed panes, missing runtime metadata, and transport failures produce empty or partial results without repeated notifications.

Candidates are deduplicated words and punctuation-bearing tokens, ranked by fuzzy score with stable ties. Terminal presentation escapes are removed. The comparator handles Herdr results only; source priority controls ranking relative to other sources.

## Development

Clone nvim-cmp, KoalaVim/fuzzy.nvim, and a built fzy-lua-native alongside this repository, then run `make test` (or `make test NVIM=/path/to/nvim`). Tests use the real matcher and cmp registration, plus controlled transport fixtures for failure and race conditions. `tests/live.lua` exercises a running Herdr capture with `HERDR_PANE_ID` set to a known caller pane and `HERDR_TEST_WORD` naming an existing neighboring word.
