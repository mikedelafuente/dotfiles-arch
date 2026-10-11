"""Load Lua specs with mocked plugin/runtime facts; no plugins or network."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which("nvim"), "Neovim Lua interpreter unavailable")
class Compatibility(unittest.TestCase):
    def test_branches_pins_and_lockfiles(self):
        with tempfile.TemporaryDirectory() as tmp:
            driver = Path(tmp) / "check.lua"
            driver.write_text(r'''
local root = os.getenv("DFA_TEST_SOURCE")
local seen
package.loaded.lazy = { setup = function(_, opts) seen = opts.lockfile end }
vim.loop.fs_stat = function() return {} end
vim.opt.rtp = { prepend = function() end }
vim.fn.stdpath = function(_) return "/fixture" end
for _, modern in ipairs({false, true}) do
  vim.fn.has = function(_) return modern and 1 or 0 end
  local plugins = assert(loadfile(root .. "/config/nvim/lua/plugins/treesitter.lua"))()
  for _, plugin in ipairs(plugins) do
    assert(plugin.branch == (modern and "main" or "master"))
    assert(modern or #plugin.commit == 40)
  end
  assert(loadfile(root .. "/config/nvim/lua/config/lazy.lua"))()
  assert(seen == (modern and "/fixture/lazy-lock.json" or "/fixture/lazy-lock-0.11.json"))
end
''')
            env = dict(os.environ, DFA_TEST_SOURCE=str(ROOT),
                       XDG_CONFIG_HOME=tmp, XDG_DATA_HOME=tmp,
                       XDG_STATE_HOME=tmp, XDG_CACHE_HOME=tmp)
            result = subprocess.run(["nvim", "--headless", "-u", "NONE", "-i", "NONE", "-n", "-l", str(driver)],
                                    env=env, cwd=tmp, capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
