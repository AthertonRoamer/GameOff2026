extends CanvasLayer

##Shows the locally-controlled player's health and inventory. Call bind_player() with that one
##player once it spawns (Game only calls this for spawner.local_player, never for remote players).

@onready var sound_cue : SoundCue = $SoundCue #the arcs at the edge of the screen that point to where a sound came from
@onready var health_bar : ProgressBar = $HealthBar
@onready var slots_box : HBoxContainer = $InventorySlots
@onready var interact_prompt : Label = $InteractPrompt #"E   use the ..." while a console is in reach
@onready var inventory_full_label : Label = $InventoryFullLabel #while an item in reach can't be taken for lack of room
@onready var target_label : Label = $TargetLabel #attackers only: which artifact they are after
@onready var clock_label : Label = $ClockLabel #hidden until bind_clock(): the playground has no clock
@onready var score_label : Label = $ScoreLabel #hidden until bind_deathmatch()

@onready var stamina_bar : ProgressBar = $StaminaBar
@onready var ammo_label : Label = $AmmoLabel #the gun in the hands: rounds in the magazine / the supply
@onready var minimap : Minimap = $Minimap
@onready var map_screen : MapScreen = $MapScreen #the full map, on the map key

var _player : Player
var _slot_panels : Array[PanelContainer] = []
var _slot_counts : Array[Label] = [] #the supply on the ammo's slot
var _slot_icons : Array[TextureRect] = []
var _normal_style : StyleBoxFlat
var _active_style : StyleBoxFlat
var _fill_style : StyleBoxFlat #the health bar's fill: the accent, alarm red when low
var _stamina_fill : StyleBoxFlat #the stamina bar's: pale, alarm red while winded
var _inventory : Inventory


func _ready() -> void:
	_normal_style = StyleBoxFlat.new() #a slot is a dark panel, and the selected one has the accent's border
	_normal_style.bg_color = Color(Palette.SHADOW, 0.8)
	_normal_style.border_color = Palette.PANEL_LINE
	_normal_style.set_border_width_all(2)
	_active_style = StyleBoxFlat.new()
	_active_style.bg_color = Palette.DEEP
	_active_style.border_color = Palette.BACKUP
	_active_style.set_border_width_all(2)
	_fill_style = health_bar.get_theme_stylebox("fill").duplicate()
	health_bar.add_theme_stylebox_override("fill", _fill_style)

	for slot in slots_box.get_children():
		var panel : PanelContainer = slot as PanelContainer
		panel.add_theme_stylebox_override("panel", _normal_style)
		_slot_panels.append(panel)
		_slot_icons.append(panel.get_node("Icon"))
		_slot_counts.append(panel.get_node("Count"))
	_stamina_fill = stamina_bar.get_theme_stylebox("fill").duplicate()
	stamina_bar.add_theme_stylebox_override("fill", _stamina_fill)


## A hit marker over the mouse whenever one of this player's instant shots hits (the lobby says so).
func bind_hitscan(hitscan : HitscanManager) -> void:
	var marker : HitMarker = HitMarker.new()
	add_child(marker)
	hitscan.hit_confirmed.connect(func(_damage : float) -> void: marker.flash())


## The maps show this facility (the minimap and the full map on the map key).
func bind_map(facility : FacilityMap) -> void:
	minimap.facility = facility
	map_screen.facility = facility


func bind_player(player : Player) -> void:
	_player = player
	minimap.track(player)
	map_screen.player = player
	stamina_bar.max_value = player.stamina_max
	health_bar.max_value = player.starting_health
	_show_health(player.health)
	player.health_changed.connect(_show_health)
	var interactor : PlayerInteractor = player.get_node("Interactor") #by node: the player is not in the tree yet, so its @onready vars are unset
	interactor.prompt_changed.connect(_show_prompt)
	interactor.inventory_full_changed.connect(inventory_full_label.set_visible)
	call_deferred("_bind_inventory", player) #player hasn't entered the tree yet, so Inventory._ready() hasn't populated slots


func _process(_delta : float) -> void:
	if not is_instance_valid(_player) or _inventory == null:
		return
	stamina_bar.value = _player.stamina
	_stamina_fill.bg_color = Palette.ALARM if _player.winded else Palette.MUTED
	var gun : Gun = _inventory.active_item as Gun
	ammo_label.visible = gun != null
	if gun != null:
		ammo_label.text = "RELOADING" if _inventory.is_reloading() else "%d / %d" % [_inventory.magazine, _inventory.reserve_now()]
		ammo_label.add_theme_color_override("font_color", Palette.ALARM if _inventory.magazine <= 0 else Palette.BACKUP)
	for i in _slot_counts.size():
		_slot_counts[i].text = str(_inventory.reserve_now()) if i < _inventory.slots.size() and _inventory.slots[i] is AmmoItem else ""


func _show_health(health : float) -> void:
	health_bar.value = health
	_fill_style.bg_color = Palette.ALARM if health < health_bar.max_value * 0.3 else Palette.BACKUP


## A deathmatch has a countdown in the clock's place, and the kills under it.
func bind_deathmatch(mode : DeathmatchMode) -> void:
	var local_id : int = multiplayer.get_unique_id()
	clock_label.text = DeathmatchMode.format_time(mode.duration_seconds)
	clock_label.visible = true
	score_label.text = mode.scoreboard_text(local_id)
	score_label.visible = true
	mode.time_changed.connect(func(left : float) -> void: clock_label.text = DeathmatchMode.format_time(left))
	mode.scores_changed.connect(func() -> void: score_label.text = mode.scoreboard_text(local_id))


func bind_clock(clock : GameClock) -> void:
	clock_label.text = clock.get_time_text()
	clock_label.visible = true
	clock.time_changed.connect(clock_label.set_text)


func show_target(artifact : Artifact) -> void:
	target_label.visible = artifact != null
	if artifact != null:
		target_label.text = "Target: %s" % artifact.item_name


func _bind_inventory(player : Player) -> void:
	_inventory = player.get_node("Inventory")
	_refresh_icons()
	_highlight_slot(_inventory.active_slot)
	_inventory.active_slot_changed.connect(_highlight_slot)
	_inventory.items_changed.connect(_refresh_icons)


func _show_prompt(text : String) -> void:
	interact_prompt.text = text
	interact_prompt.visible = text != ""


func _refresh_icons() -> void:
	for i in _slot_icons.size():
		var item : Item = _inventory.slots[i] if i < _inventory.slots.size() else null
		_slot_icons[i].texture = item.icon if item else null


func _highlight_slot(slot : int) -> void:
	_refresh_icons()
	for i in _slot_panels.size():
		_slot_panels[i].add_theme_stylebox_override("panel", _active_style if i == slot else _normal_style)
