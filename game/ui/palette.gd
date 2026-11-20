class_name Palette
extends RefCounted

## The game's colours ("Palette A, Backup Power"): navy guards, warm amber emergency light, near-black rooms. Everything drawn in code uses these names, and the
## theme (night_shift_theme.tres, the look of every button, panel and bar) holds the same values, so a new screen is made from these and nothing else.
## Amber is the interface's accent: what can be used, what is selected, what is on. Red is alarm and danger, green is open or safe, cyan is an item or a screen.

# darkness: the rooms and the backs of panels
const VOID : Color = Color("#07090c")
const SHADOW : Color = Color("#0c0e12")
const DEEP : Color = Color("#151920")
# the facility: lines and borders
const FLOOR : Color = Color("#1a1f27")
const LINE : Color = Color("#222833")
const WALL : Color = Color("#2a313d")
const WALL_TOP : Color = Color("#3a4352")
const METAL : Color = Color("#5a6475")
# light and power
const FLASH : Color = Color("#fff3c4")
const BACKUP : Color = Color("#f2b544") # the accent
const WARM : Color = Color("#e07b2a")
# signals
const ALARM : Color = Color("#e5484d")
const OK : Color = Color("#4be38a")
const ITEM : Color = Color("#6fd3e8")
# text
const TEXT : Color = Color("#e7e3d8")
const MUTED : Color = Color("#a9a495")
const ACCENT_BLUE : Color = Color("#8fb3e0")
# a screen's panel, a shade lighter than DEEP
const PANEL : Color = Color("#10131a")
const PANEL_LINE : Color = Color("#262c36")
