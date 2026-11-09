"""Settings window builds, reflects the saved values and applies changes."""
from pathlib import Path
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


def test_config_window():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(f'dofile("{ROOT}/tests/wow_stub.lua")')
    lua.execute(f'STUB.load("{ROOT}")')
    lua.execute('''
STUB.units.player = {name="Zabbu", class="MAGE", hp=1000, max=1000}
STUB.fire("VARIABLES_LOADED")
zDPS.Config.Toggle()
assert(zDPSConfig:IsShown())
local lock
for _, f in ipairs(STUB.frames) do if f.kind == "CheckButton" and f.text and f.text:GetText() == "Locked" then lock = f end end
assert(lock and lock:GetChecked() == false)
this = lock.hit; lock.hit.scripts.OnClick()
assert(zDPS.db.locked == true and lock:GetChecked() == true)
local cyc
for _, f in ipairs(STUB.frames) do if f.kind == "Button" and f.text and f.text:GetText() == "Reset total" then cyc = f end end
this = cyc; cyc.scripts.OnClick()
assert(zDPS.db.resetTotal == "group" and cyc.value:GetText() == "Joining a group")
local sl
for _, f in ipairs(STUB.frames) do if f.kind == "Slider" and f.text and f.text:GetText() == "Row height" then sl = f end end
sl:SetValue(16); this = sl; sl.scripts.OnValueChanged()
assert(zDPS.db.rowHeight == 16, zDPS.db.rowHeight)
zDPS.Config.Toggle(); assert(not zDPSConfig:IsShown())
''')
