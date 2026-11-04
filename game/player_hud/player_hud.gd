extends CanvasLayer

##Shows the locally-controlled player's health and inventory. Call bind_player() with that one
##player once it spawns (Game only calls this for spawner.local_player, never for remote players).

@onready var health_bar : ProgressBar = $HealthBar
@onready var slots_box : HBoxContainer = $InventorySlots

var _slot_panels : Array[PanelContainer] = []
var _slot_icons : Array[TextureRect] = []
var _normal_style : StyleBoxFlat
var _active_style : StyleBoxFlat
var _inventory : Inventory


func _ready() -> void:
	_normal_style = StyleBoxFlat.new()
	_normal_style.bg_color = Color(0, 0, 0, 0.4)
	_active_style = StyleBoxFlat.new()
	_active_style.bg_color = Color(1, 1, 1, 0.5)
	_active_style.border_color = Color.WHITE
	_active_style.set_border_width_all(2)

	for slot in slots_box.get_children():
		var panel : PanelContainer = slot as PanelContainer
		panel.add_theme_stylebox_override("panel", _normal_style)
		_slot_panels.append(panel)
		_slot_icons.append(panel.get_node("Icon"))


func bind_player(player : Player) -> void:
	health_bar.max_value = player.starting_health
	health_bar.value = player.health
	player.health_changed.connect(func(h : float) -> void: health_bar.value = h)
	call_deferred("_bind_inventory", player) #player hasn't entered the tree yet, so Inventory._ready() hasn't populated slots


func _bind_inventory(player : Player) -> void:
	_inventory = player.get_node("Inventory")
	_refresh_icons()
	_highlight_slot(_inventory.active_slot)
	_inventory.active_slot_changed.connect(_highlight_slot)


func _refresh_icons() -> void:
	for i in _slot_icons.size():
		var item : Item = _inventory.slots[i] if i < _inventory.slots.size() else null
		_slot_icons[i].texture = item.icon if item else null


func _highlight_slot(slot : int) -> void:
	_refresh_icons()
	for i in _slot_panels.size():
		_slot_panels[i].add_theme_stylebox_override("panel", _active_style if i == slot else _normal_style)
