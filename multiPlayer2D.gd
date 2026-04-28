extends CharacterBody2D
class_name MultiplayerPlayer2D

var _super_called_enter_tree = false
var _super_called_physics_process = false
var _super_called_process = false

func _enter_tree() -> void:
	_super_called_enter_tree = true
	set_multiplayer_authority(name.to_int())

func _physics_process(delta: float) -> void:
	_super_called_physics_process = true
	if not is_multiplayer_authority():
		return

func _process(delta: float) -> void:
	_super_called_process = true
	if not is_multiplayer_authority():
		return

# Call this at the end of your child class's _ready() or in a debug build
func _ready() -> void:
	# Check if super was called (optional - call this manually or use assert)
	await get_tree().process_frame  # Wait one frame for callbacks to run
	
	assert(_super_called_enter_tree, "ERROR: You must call super() in enter_tree! This is required for multiplayer to work!")
	assert(_super_called_physics_process, "ERROR: You must call super(_delta) in physics process! This is required for multiplayer to work!")
	assert(_super_called_process, "ERROR: You must call super(_delta) in process! This is required for multiplayer to work!")
