extends Node
class_name MultiplayerNode

var _super_called_enter_tree = false
var _super_called_physics_process = false
var _super_called_process = false

func _enter_tree() -> void: ## Sets multiplayer authority to the peer whose ID matches this node's name; must call super() in subclasses
	_super_called_enter_tree = true
	set_multiplayer_authority(name.to_int())

func _physics_process(delta: float) -> void: ## Early-outs if this peer is not the authority; must call super(delta) in subclasses
	_super_called_physics_process = true
	if not is_multiplayer_authority():
		return

func _process(delta: float) -> void: ## Early-outs if this peer is not the authority; must call super(delta) in subclasses
	_super_called_process = true
	if not is_multiplayer_authority():
		return

# Call this at the end of your child class's _ready() or in a debug build
func _ready() -> void: ## Asserts that all three super() calls were made in subclass overrides; crashes with a clear message if any are missing
	# Check if super was called (optional - call this manually or use assert)
	await get_tree().process_frame  # Wait one frame for callbacks to run
	
	assert(_super_called_enter_tree, "ERROR: You must call super() in enter_tree! This is required for multiplayer to work!")
	assert(_super_called_physics_process, "ERROR: You must call super(_delta) in physics process! This is required for multiplayer to work!")
	assert(_super_called_process, "ERROR: You must call super(_delta) in process! This is required for multiplayer to work!")
