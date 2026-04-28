extends Node
class_name SteamManager

static var lobby_id : int = 0;
static var is_host = false;
static var host_steam_id : int = 0
static var is_steam_ready = false;
static var app_id = 480;
static var _instance : SteamManager
static var peer : SteamMultiplayerPeer;
static var player_scene : PackedScene = null;
static var initialized : bool = false;

static var spawner : MultiplayerSpawner;
static var lobby_list : Array = []  ## Stores the list of found lobbies
static var _pending_lobby_name : String = ""  ## Temporary storage for lobby name before creation

## Unique identifier for this game - uses the project name from ProjectSettings
static var game_id : String = ""

var _spawnable_scenes : Array[PackedScene] = []  ## Stores scenes for custom spawning
var _pending_lobby_setup : bool = false  ## Flag to delay lobby setup until we're in the tree
var _pending_client_setup : bool = false  ## Flag to delay client setup until we're in the tree
var _pending_host_id : int = 0  ## Stored host ID for pending client setup

## Skill system - defaults work out of the box, no setup needed
static var player_skill : float = 500.0  ## Player skill rating (1-5000), starts neutral at 500
static var use_skill_matchmaking : bool = false  ## Set to true to enable skill-based matching
static var save_path : String = "user://steam_skill.save"

## Skill falloff system - configure via these static variables, no code changes needed
static var skill_falloff_enabled : bool = false  ## Set to true to enable skill decay over time
static var skill_falloff_amount : float = 10.0  ## How much skill is lost per falloff tick
static var skill_falloff_interval_days : int = 7  ## Days between falloff ticks
static var skill_falloff_minimum : float = 100.0  ## Skill won't decay below this level
static var last_skill_update_path : String = "user://steam_skill_last_update.save"

signal lobby_created(type);
signal lobby_joined(type);
signal lobby_list_received  ## Signal to notify when lobby list is ready
signal lobby_chat_received(sender_name: String, message: String)  ## Chat message received
signal lobby_data_changed(key: String, value: String, member_id: int)  ## Custom lobby data changed
signal lobby_member_joined(member_id: int)  ## A member joined the lobby
signal lobby_member_left(member_id: int)  ## A member left the lobby
signal lobby_member_data_changed(member_id: int, key: String, value: String)  ## A member's data changed
signal player_connected(id: int)  ## A player connected to the multiplayer peer
signal player_disconnected(id: int)  ## A player disconnected from the multiplayer peer

#region Initialize the Steam Manager -----------------------------
static func initialize_steam(p_scene : PackedScene = null) -> void: ## Sets up Steam with the app ID. Player scene is optional.
	if not initialized:
		player_scene = p_scene
		
		game_id = ProjectSettings.get_setting("application/config/name", "UnknownGame")
		print("Game ID set to: ", game_id)
		
		print("Steam initialized", Steam.steamInit(app_id, true))
		Steam.initRelayNetworkAccess();
		_ensure_instance()
		Steam.lobby_created.connect(_instance._on_lobby_created)
		
		# Load saved skill and apply any falloff
		_instance.load_skill()
		_instance._apply_skill_falloff()
		
		initialized = true;
		is_steam_ready = true;

static func _ensure_instance() -> void: ## Creates the singleton SteamManager node and adds it to the scene tree if it doesn't exist
	if _instance == null:
		_instance = SteamManager.new()
		_instance.name = "SteamManager"
		
		var root = Engine.get_main_loop().root
		root.add_child(_instance)
		
		print("SteamManager added to root viewport")
		_instance._setup_callbacks()

static func get_instance() -> SteamManager: ## Returns the SteamManager instance for connecting signals
	_ensure_instance()
	return _instance

static func set_player_scene(p_scene: PackedScene) -> void: ## Sets the player scene after initialization
	player_scene = p_scene
	print("Player scene set")

func _ready() -> void: ## Called when node enters scene tree - handle any pending setups
	if _pending_lobby_setup:
		_pending_lobby_setup = false
		_finish_lobby_setup()
	if _pending_client_setup:
		_pending_client_setup = false
		_finish_client_setup(_pending_host_id)

func _process(_delta) -> void: ## Check for pending setups each frame as fallback
	if _pending_lobby_setup and is_inside_tree():
		_pending_lobby_setup = false
		_finish_lobby_setup()
	if _pending_client_setup and is_inside_tree():
		_pending_client_setup = false
		_finish_client_setup(_pending_host_id)

func _setup_callbacks() -> void: ## Connects all Steam lobby signals to their handler functions for both host and client
	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_joined.connect(_on_lobby_joined)
	Steam.lobby_match_list.connect(_on_lobby_match_list)
	Steam.lobby_data_update.connect(_on_lobby_data_update)
	Steam.lobby_message.connect(_on_lobby_chat_message)
	Steam.lobby_chat_update.connect(_on_lobby_chat_update)

func _setup_spawner(auto_spawn_scenes : Array[PackedScene] = []) -> void: ## Creates and configures the MultiplayerSpawner for automatic player spawning
	if spawner:
		return
	if player_scene == null:
		print("No player_scene set, skipping MultiplayerSpawner")
		return
	
	spawner = MultiplayerSpawner.new()
	spawner.name = "PlayerSpawner"
	spawner.spawn_path = NodePath("/root")
	spawner.spawn_function = _spawn_custom
	
	_spawnable_scenes = [player_scene]
	for scene in auto_spawn_scenes:
		if not _spawnable_scenes.has(scene):
			_spawnable_scenes.append(scene)
	
	add_child(spawner)
	print("MultiplayerSpawner setup complete")

func _spawn_custom(data) -> Node: ## Custom spawn function for MultiplayerSpawner
	if data is int and data < _spawnable_scenes.size():
		return _spawnable_scenes[data].instantiate()
	return null

func add_to_autospawn(scene: PackedScene) -> void: ## Adds additional scenes to the spawn list for network synchronization
	if not _spawnable_scenes.has(scene):
		_spawnable_scenes.append(scene)

#endregion --------------------------------------------------------

#region lobby creation --------------------------------------------

static func host_public_lobby(max_players:int = 4) -> void: ## Creates a public lobby visible to everyone on Steam
	_ensure_instance()
	host_lobby(Steam.LOBBY_TYPE_PUBLIC, max_players)

static func host_public_lobby_with_name(lobby_name: String, max_players:int = 4) -> void: ## Creates a public lobby with a custom name
	_ensure_instance()
	if not is_steam_ready:
		print("Steam is not ready yet!")
		return
	if lobby_id != 0:
		print("Already in a lobby!")
		return
	
	_instance._pending_lobby_name = lobby_name
	Steam.createLobby(Steam.LOBBY_TYPE_PUBLIC, max_players)
	is_host = true;

static func host_friends_only_lobby(max_players:int = 4) -> void: ## Creates a lobby only visible to your Steam friends
	_ensure_instance();
	host_lobby(Steam.LOBBY_TYPE_FRIENDS_ONLY, max_players)

static func host_invisible_lobby(max_players:int = 4) -> void: ## Creates a lobby that doesn't appear in searches but can be joined directly
	_ensure_instance();
	host_lobby(Steam.LOBBY_TYPE_INVISIBLE, max_players)

static func host_private_lobby(max_players:int = 4) -> void: ## Creates a private lobby that requires an invitation to join
	_ensure_instance();
	host_lobby(Steam.LOBBY_TYPE_PRIVATE, max_players)

static func host_unique_private_lobby(max_players:int = 4) -> void: ## Creates a private lobby with a unique ID, requires invitation
	_ensure_instance();
	host_lobby(Steam.LOBBY_TYPE_PRIVATE_UNIQUE, max_players)

static func host_lobby(lobby_type, max_players: int = 4) -> bool: ## Internal function that sends the lobby creation request to Steam
	_ensure_instance();
	if not is_steam_ready:
		print("Steam is not ready yet!")
		return false
	if lobby_id != 0:
		print("Already in a lobby!")
		return false
	
	Steam.createLobby(lobby_type, max_players)
	print("Lobby Created")
	is_host = true;
	return true

#endregion ---------------------------------------------------------


#region lobby joining ---------------------------------------------

static func join_lobby(lobby_id_to_join: int) -> void: ## Joins a specific lobby by its Steam lobby ID
	_ensure_instance()
	if not is_steam_ready:
		print("Steam is not ready yet!")
		return
	if lobby_id != 0:
		print("Already in a lobby!")
		return
	
	print("Attempting to join lobby: ", lobby_id_to_join)
	Steam.joinLobby(lobby_id_to_join)

static func get_lobby_list() -> void: ## Requests a list of all available lobbies from Steam's servers, filtered by game ID
	_ensure_instance()
	if not is_steam_ready:
		print("Steam is not ready yet!")
		return
	print("Requesting lobby list for game: ", game_id)
	
	Steam.addRequestLobbyListStringFilter("game", game_id, Steam.LOBBY_COMPARISON_EQUAL)
	Steam.addRequestLobbyListDistanceFilter(Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE)
	Steam.requestLobbyList()

static func leave_lobby() -> void: ## Leaves the current lobby and cleans up the multiplayer peer through the instance
	_ensure_instance()
	_instance._leave_lobby()

#endregion ---------------------------------------------------------


#region Lobby Chat ------------------------------------------------

func send_lobby_chat(message: String) -> bool: ## Sends a chat message to everyone in the lobby
	if lobby_id == 0:
		print("Error: Not in a lobby. Cannot send chat.")
		return false
	if message.is_empty():
		return false
	
	var was_sent: bool = Steam.sendLobbyChatMsg(lobby_id, message)
	
	if not was_sent:
		print("ERROR: Chat message failed to send.")
	
	return was_sent

#endregion ---------------------------------------------------------


#region Lobby Data (Key-Value Store) ------------------------------

func set_lobby_data(key: String, value: String) -> bool: ## Sets a custom key-value pair on the lobby that all members can read
	if lobby_id == 0:
		print("Error: Not in a lobby. Cannot set lobby data.")
		return false
	
	var success: bool = Steam.setLobbyData(lobby_id, key, value)
	if success:
		print("Set lobby data: ", key, " = ", value)
	return success

func get_lobby_data(key: String) -> String: ## Gets a custom key-value pair from the lobby
	if lobby_id == 0:
		return ""
	return Steam.getLobbyData(lobby_id, key)

func delete_lobby_data(key: String) -> bool: ## Deletes a custom key-value pair from the lobby
	if lobby_id == 0:
		return false
	var success: bool = Steam.deleteLobbyData(lobby_id, key)
	if success:
		print("Deleted lobby data: ", key)
	return success

func set_lobby_data_bool(key: String, value: bool) -> void: ## Convenience function for boolean lobby data
	set_lobby_data(key, "true" if value else "false")

func get_lobby_data_bool(key: String, default: bool = false) -> bool: ## Convenience function for reading boolean lobby data
	var val = get_lobby_data(key)
	if val == "":
		return default
	return val == "true"

func set_lobby_data_int(key: String, value: int) -> void: ## Convenience function for integer lobby data
	set_lobby_data(key, str(value))

func get_lobby_data_int(key: String, default: int = 0) -> int: ## Convenience function for reading integer lobby data
	var val = get_lobby_data(key)
	if val == "":
		return default
	return int(val)

func set_lobby_data_float(key: String, value: float) -> void: ## Convenience function for float lobby data
	set_lobby_data(key, str(value))

func get_lobby_data_float(key: String, default: float = 0.0) -> float: ## Convenience function for reading float lobby data
	var val = get_lobby_data(key)
	if val == "":
		return default
	return float(val)

#endregion ---------------------------------------------------------


#region Lobby Member Data (Per-Player Key-Value Store) ------------

func set_member_data(key: String, value: String) -> bool: ## Sets data specific to your own player in the lobby
	if lobby_id == 0:
		print("Error: Not in a lobby. Cannot set member data.")
		return false
	
	Steam.setLobbyMemberData(lobby_id, key, value)
	print("Set member data: ", key, " = ", value)
	return true

func get_member_data(member_id: int, key: String) -> String: ## Gets data for a specific lobby member
	if lobby_id == 0:
		return ""
	return Steam.getLobbyMemberData(lobby_id, member_id, key)

func get_my_member_data(key: String) -> String: ## Gets your own member data
	return get_member_data(Steam.getSteamID(), key)

#endregion ---------------------------------------------------------


#region Lobby Info ------------------------------------------------

func get_lobby_name() -> String: ## Returns the current lobby's name
	return get_lobby_data("name")

func get_lobby_member_count() -> int: ## Returns the number of members in the current lobby
	if lobby_id == 0:
		return 0
	return Steam.getNumLobbyMembers(lobby_id)

func get_lobby_max_members() -> int: ## Returns the maximum members allowed in the current lobby
	if lobby_id == 0:
		return 0
	return Steam.getLobbyMemberLimit(lobby_id)

func get_lobby_members() -> Array: ## Returns an array of Steam IDs for all members in the lobby
	if lobby_id == 0:
		return []
	
	var members: Array = []
	var count = Steam.getNumLobbyMembers(lobby_id)
	for i in range(count):
		var member_id = Steam.getLobbyMemberByIndex(lobby_id, i)
		members.append(member_id)
	return members

func get_lobby_member_names() -> Array: ## Returns an array of member names in the lobby
	var names: Array = []
	for member_id in get_lobby_members():
		var name = Steam.getFriendPersonaName(member_id)
		if name == "":
			name = "Unknown"
		names.append({"id": member_id, "name": name})
	return names

func is_lobby_owner() -> bool: ## Returns true if you are the lobby owner
	if lobby_id == 0:
		return false
	return Steam.getLobbyOwner(lobby_id) == Steam.getSteamID()

func get_lobby_owner_name() -> String: ## Returns the name of the lobby owner
	if lobby_id == 0:
		return ""
	var owner_id = Steam.getLobbyOwner(lobby_id)
	var name = Steam.getFriendPersonaName(owner_id)
	if name == "":
		name = "Unknown"
	return name

func set_lobby_joinable(joinable: bool) -> bool: ## Sets whether the lobby can be joined by new players
	if lobby_id == 0:
		return false
	return Steam.setLobbyJoinable(lobby_id, joinable)

func set_lobby_max_members(max_players: int) -> bool: ## Changes the maximum number of players allowed in the lobby
	if lobby_id == 0:
		return false
	return Steam.setLobbyMemberLimit(lobby_id, max_players)

#endregion ---------------------------------------------------------


#region Friends ------------------------------------------------

func get_friend_count() -> int: ## Returns the number of friends
	return Steam.getFriendCount(Steam.FRIEND_FLAG_IMMEDIATE)

func get_friend_list() -> Array: ## Returns an array of friend dictionaries with id and name
	var friends: Array = []
	var count = get_friend_count()
	for i in range(count):
		var friend_id = Steam.getFriendByIndex(i, Steam.FRIEND_FLAG_IMMEDIATE)
		var name = Steam.getFriendPersonaName(friend_id)
		var state = Steam.getFriendPersonaState(friend_id)
		var game = Steam.getFriendGamePlayed(friend_id)
		friends.append({
			"id": friend_id,
			"name": name,
			"state": state,
			"in_game": game != 0,
			"game_id": game
		})
	return friends

func is_friend_in_same_game(friend_id: int) -> bool: ## Checks if a friend is playing this game
	var game = Steam.getFriendGamePlayed(friend_id)
	return game == app_id

func invite_friend_to_lobby(friend_id: int) -> bool: ## Invites a friend to the current lobby
	if lobby_id == 0:
		print("Error: Not in a lobby. Cannot invite.")
		return false
	return Steam.inviteUserToLobby(lobby_id, friend_id)

func get_my_steam_id() -> int: ## Returns your own Steam ID
	return Steam.getSteamID()

func get_my_steam_name() -> String: ## Returns your own Steam display name
	return Steam.getFriendPersonaName(Steam.getSteamID())

func get_steam_name(steam_id: int) -> String: ## Returns the display name for any Steam ID
	var name = Steam.getFriendPersonaName(steam_id)
	if name == "":
		name = "Unknown"
	return name

func get_steam_avatar(steam_id: int, size: int = Steam.AVATAR_MEDIUM) -> ImageTexture: ## Returns the avatar for a Steam ID as a Godot texture
	var handle: int = 0
	if size == Steam.AVATAR_SMALL:
		handle = Steam.getSmallFriendAvatar(steam_id)
	elif size == Steam.AVATAR_LARGE:
		handle = Steam.getLargeFriendAvatar(steam_id)
	else:
		handle = Steam.getMediumFriendAvatar(steam_id)
	
	if handle == 0:
		return null
	
	var image_size: Dictionary = Steam.getImageSize(handle)
	if not image_size["success"]:
		return null
	
	var width: int = image_size["width"]
	var height: int = image_size["height"]
	
	var image_data: Dictionary = Steam.getImageRGBA(handle)
	if not image_data["success"]:
		return null
	
	var image = Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, image_data["data"])
	var texture = ImageTexture.create_from_image(image)
	return texture

#endregion ---------------------------------------------------------


#region Game Settings & Rich Presence --------------------------

func set_rich_presence(key: String, value: String) -> bool: ## Sets rich presence data (shown on friends list)
	return Steam.setRichPresence(key, value)

func clear_rich_presence() -> void: ## Clears all rich presence data
	Steam.clearRichPresence()

func set_lobby_game_server() -> void: ## Associates a game server with the lobby (for server browsing)
	if lobby_id == 0:
		return
	Steam.setLobbyGameServer(lobby_id, "0", 0, Steam.getSteamID())

func get_lobby_game_server() -> Dictionary: ## Gets the game server info for the lobby
	if lobby_id == 0:
		return {}
	return Steam.getLobbyGameServer(lobby_id)

#endregion ---------------------------------------------------------


#region Skill System ----------------------------------------------

func get_player_skill() -> float: ## Returns the current player skill rating
	return player_skill

func increase_skill(amount: float = 25.0) -> void: ## Increases player skill and saves
	player_skill = min(player_skill + amount, 5000.0)
	print("Skill increased by ", amount, " -> New skill: ", player_skill)
	_save_last_skill_update()
	save_skill()
	if lobby_id != 0:
		set_member_data("skill", str(player_skill))
		update_lobby_skill()

func decrease_skill(amount: float = 25.0) -> void: ## Decreases player skill and saves
	player_skill = max(player_skill - amount, 1.0)
	print("Skill decreased by ", amount, " -> New skill: ", player_skill)
	_save_last_skill_update()
	save_skill()
	if lobby_id != 0:
		set_member_data("skill", str(player_skill))
		update_lobby_skill()

func set_skill(new_skill: float) -> void: ## Sets player skill to a specific value and saves
	player_skill = clamp(new_skill, 1.0, 5000.0)
	print("Skill set to: ", player_skill)
	_save_last_skill_update()
	save_skill()
	if lobby_id != 0:
		set_member_data("skill", str(player_skill))
		update_lobby_skill()

func enable_skill_matchmaking(enabled: bool) -> void: ## Toggle skill-based matchmaking on/off
	use_skill_matchmaking = enabled
	print("Skill matchmaking: ", "ON" if enabled else "OFF")

func save_skill() -> void: ## Saves the player skill to disk
	var file = FileAccess.open(save_path, FileAccess.WRITE)
	if file:
		file.store_var(player_skill)
		file.close()
	else:
		print("Note: Could not save skill")

func load_skill() -> void: ## Loads the player skill from disk, defaults to 500
	if FileAccess.file_exists(save_path):
		var file = FileAccess.open(save_path, FileAccess.READ)
		if file:
			player_skill = file.get_var()
			file.close()
			print("Skill loaded: ", player_skill)
		else:
			player_skill = 500.0
	else:
		player_skill = 500.0

#endregion ---------------------------------------------------------


#region Skill Falloff System --------------------------------------

## Configure falloff by changing these static variables (no code changes needed):
##   SteamManager.skill_falloff_enabled = true           -- Enable falloff
##   SteamManager.skill_falloff_amount = 10.0             -- Skill lost per tick
##   SteamManager.skill_falloff_interval_days = 7         -- Days between ticks
##   SteamManager.skill_falloff_minimum = 100.0           -- Skill won't go below this

func _save_last_skill_update() -> void: ## Saves the timestamp of the last skill update
	var file = FileAccess.open(last_skill_update_path, FileAccess.WRITE)
	if file:
		file.store_var(Time.get_unix_time_from_system())
		file.close()

func _get_last_skill_update() -> float: ## Returns the timestamp of the last skill update, or 0 if never
	if FileAccess.file_exists(last_skill_update_path):
		var file = FileAccess.open(last_skill_update_path, FileAccess.READ)
		if file:
			var timestamp = file.get_var()
			file.close()
			return timestamp
	return 0.0

func _apply_skill_falloff() -> void: ## Checks for and applies skill decay based on inactivity
	if not skill_falloff_enabled:
		return
	
	var last_update = _get_last_skill_update()
	if last_update <= 0:
		# First time playing, no falloff to apply
		_save_last_skill_update()
		return
	
	var current_time = Time.get_unix_time_from_system()
	var seconds_since_update = current_time - last_update
	var days_since_update = seconds_since_update / 86400.0  # 86400 seconds = 1 day
	
	if days_since_update < skill_falloff_interval_days:
		return  # Not enough time has passed
	
	# Calculate how many falloff ticks to apply
	var ticks = floor(days_since_update / skill_falloff_interval_days)
	var total_falloff = ticks * skill_falloff_amount
	var old_skill = player_skill
	
	player_skill = max(player_skill - total_falloff, skill_falloff_minimum)
	
	if player_skill < old_skill:
		print("Skill decay applied: ", old_skill, " -> ", player_skill, " (", ticks, " ticks of ", skill_falloff_amount, " after ", days_since_update, " days)")
		save_skill()
		_save_last_skill_update()

func get_skill_falloff_info() -> Dictionary: ## Returns information about the falloff state
	var last_update = _get_last_skill_update()
	var days_since = 0.0
	var next_tick_days = 0.0
	
	if last_update > 0:
		var current_time = Time.get_unix_time_from_system()
		var seconds_since = current_time - last_update
		days_since = seconds_since / 86400.0
		next_tick_days = skill_falloff_interval_days - fmod(days_since, skill_falloff_interval_days)
	
	return {
		"falloff_enabled": skill_falloff_enabled,
		"falloff_amount": skill_falloff_amount,
		"falloff_interval_days": skill_falloff_interval_days,
		"falloff_minimum": skill_falloff_minimum,
		"days_since_update": days_since,
		"days_until_next_tick": next_tick_days,
		"current_skill": player_skill
	}

#endregion ---------------------------------------------------------


#region Lobby Skill Average ---------------------------------------

func get_lobby_average_skill() -> float: ## Calculates the average skill of all lobby members
	if lobby_id == 0:
		return player_skill
	
	var total_skill: float = 0.0
	var member_count: int = 0
	var members = get_lobby_members()
	
	for member_id in members:
		var skill_str = get_member_data(member_id, "skill")
		if skill_str != "":
			total_skill += float(skill_str)
			member_count += 1
	
	if member_count == 0:
		return 500.0
	
	return total_skill / float(member_count)

func update_lobby_skill() -> void: ## Updates the lobby's skill data
	if lobby_id == 0:
		return
	
	set_member_data("skill", str(player_skill))
	var avg_skill = get_lobby_average_skill()
	set_lobby_data_float("avg_skill", avg_skill)

#endregion ---------------------------------------------------------


#region Smart Matchmaking -----------------------------------------

func join_random_lobby() -> void: ## Joins a random lobby with smart or skill-based matching
	if use_skill_matchmaking:
		join_lobby_by_skill(200.0)
	else:
		_join_random_lobby_no_skill()

func _join_random_lobby_no_skill() -> void: ## Standard smart matching without skill
	_ensure_instance()
	if not is_steam_ready or lobby_id != 0:
		return
	
	print("Smart matchmaking: fetching lobby list...")
	Steam.addRequestLobbyListStringFilter("game", game_id, Steam.LOBBY_COMPARISON_EQUAL)
	Steam.addRequestLobbyListDistanceFilter(Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE)
	Steam.requestLobbyList()
	
	if not _instance.lobby_list_received.is_connected(_on_smart_match_list):
		_instance.lobby_list_received.connect(_on_smart_match_list, CONNECT_ONE_SHOT)

func _on_smart_match_list() -> void:
	if lobby_list.is_empty():
		print("Smart matchmaking: no lobbies found. Creating one...")
		host_public_lobby()
		return
	
	var scored_lobbies: Array = []
	for lobby in lobby_list:
		var score: float = _calculate_lobby_score(lobby)
		scored_lobbies.append({
			"id": lobby["id"], "name": lobby["name"],
			"players": lobby["players"], "max_players": lobby["max_players"],
			"score": score
		})
	
	scored_lobbies.sort_custom(func(a, b): return a["score"] > b["score"])
	
	print("\n=== Smart Matchmaking Results ===")
	for i in range(min(5, scored_lobbies.size())):
		var lobby = scored_lobbies[i]
		print("%d. %s | Players: %d/%d | Score: %.1f" % [i+1, lobby["name"], lobby["players"], lobby["max_players"], lobby["score"]])
	print("==================================\n")
	
	join_lobby(scored_lobbies[0]["id"])

func _calculate_lobby_score(lobby: Dictionary) -> float:
	var score: float = 0.0
	var players: int = lobby["players"]
	var max_players: int = lobby["max_players"]
	var fill_ratio: float = float(players) / float(max_players) if max_players > 0 else 0.0
	
	if fill_ratio >= 0.3 and fill_ratio < 0.9:
		score += 30.0
	elif fill_ratio >= 0.1 and fill_ratio < 0.3:
		score += 15.0
	elif fill_ratio >= 0.9:
		score -= 10.0
	
	score += players * 5.0
	
	if players <= 1:
		score -= 20.0
	
	var slots_left = max_players - players
	if slots_left >= 2:
		score += 10.0
	elif slots_left == 1:
		score += 5.0
	else:
		score -= 50.0
	
	var lobby_age = Steam.getLobbyData(lobby["id"], "created_at").to_int()
	if lobby_age > 0:
		var current_time = Time.get_unix_time_from_system()
		var age_seconds = current_time - lobby_age
		if age_seconds < 300:
			score += 20.0
		elif age_seconds < 600:
			score += 10.0
	
	return score

#endregion ---------------------------------------------------------


#region Skill-Based Matchmaking -----------------------------------

func join_lobby_by_skill(skill_range: float = 200.0) -> void:
	_ensure_instance()
	if not is_steam_ready or lobby_id != 0:
		return
	
	print("Skill-based matchmaking: fetching lobbies for skill ", player_skill)
	Steam.addRequestLobbyListStringFilter("game", game_id, Steam.LOBBY_COMPARISON_EQUAL)
	Steam.addRequestLobbyListDistanceFilter(Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE)
	Steam.requestLobbyList()
	
	if not _instance.lobby_list_received.is_connected(_on_skill_match_list):
		_instance.lobby_list_received.connect(_on_skill_match_list.bind(skill_range), CONNECT_ONE_SHOT)

func _on_skill_match_list(skill_range: float):
	if lobby_list.is_empty():
		print("Skill matchmaking: no lobbies found. Creating one...")
		host_public_lobby()
		return
	
	var scored_lobbies: Array = []
	for lobby in lobby_list:
		var lobby_avg_skill = Steam.getLobbyData(lobby["id"], "avg_skill").to_float()
		if lobby_avg_skill <= 0:
			lobby_avg_skill = 500.0
		
		var skill_diff = abs(player_skill - lobby_avg_skill)
		var score: float = _calculate_skill_lobby_score(lobby, skill_diff, skill_range)
		scored_lobbies.append({
			"id": lobby["id"], "name": lobby["name"],
			"players": lobby["players"], "max_players": lobby["max_players"],
			"avg_skill": lobby_avg_skill, "skill_diff": skill_diff,
			"score": score
		})
	
	scored_lobbies.sort_custom(func(a, b): return a["score"] > b["score"])
	
	print("\n=== Skill Matchmaking Results ===")
	print("Your skill: ", player_skill)
	for i in range(min(5, scored_lobbies.size())):
		var lobby = scored_lobbies[i]
		print("%d. %s | Skill: %.0f (diff: %.0f) | Players: %d/%d | Score: %.1f" % [
			i+1, lobby["name"], lobby["avg_skill"], lobby["skill_diff"],
			lobby["players"], lobby["max_players"], lobby["score"]
		])
	print("==================================\n")
	
	join_lobby(scored_lobbies[0]["id"])

func _calculate_skill_lobby_score(lobby: Dictionary, skill_diff: float, skill_range: float) -> float:
	var score: float = 0.0
	var players: int = lobby["players"]
	var max_players: int = lobby["max_players"]
	var fill_ratio: float = float(players) / float(max_players) if max_players > 0 else 0.0
	
	if skill_diff <= skill_range * 0.25:
		score += 50.0
	elif skill_diff <= skill_range * 0.5:
		score += 35.0
	elif skill_diff <= skill_range:
		score += 20.0
	else:
		score -= 30.0
	
	if fill_ratio >= 0.3 and fill_ratio < 0.9:
		score += 15.0
	elif fill_ratio >= 0.1:
		score += 8.0
	
	score += players * 3.0
	
	if players <= 1:
		score -= 15.0
	
	var slots_left = max_players - players
	if slots_left >= 2:
		score += 10.0
	elif slots_left == 1:
		score += 5.0
	else:
		score -= 100.0
	
	var lobby_age = Steam.getLobbyData(lobby["id"], "created_at").to_int()
	if lobby_age > 0:
		var current_time = Time.get_unix_time_from_system()
		var age_seconds = current_time - lobby_age
		if age_seconds < 300:
			score += 15.0
		elif age_seconds < 600:
			score += 8.0
	
	return score

#endregion ---------------------------------------------------------


#region Steam Callbacks --------------------------------------------

func _on_lobby_created(result : int, lobby_created_id : int) -> void:
	_ensure_instance()
	if result == Steam.Result.RESULT_OK:
		self.lobby_id = lobby_created_id;
		
		Steam.setLobbyData(lobby_created_id, "game", game_id)
		print("Tagged lobby with game ID: ", game_id)
		
		Steam.setLobbyData(lobby_created_id, "created_at", str(Time.get_unix_time_from_system()))
		print("Set lobby creation timestamp")
		
		if _pending_lobby_name != "":
			Steam.setLobbyData(lobby_created_id, "name", _pending_lobby_name)
			print("Set lobby name to: ", _pending_lobby_name)
			_pending_lobby_name = ""
		else:
			Steam.setLobbyData(lobby_created_id, "name", "Lobby " + str(lobby_created_id))
		
		if is_inside_tree():
			_finish_lobby_setup()
		else:
			_pending_lobby_setup = true
	else:
		print("Failed to create lobby: ", result)

func _on_lobby_joined(lobby_id_joined: int, permissions: int, locked: bool, response: int) -> void:
	print("Joined lobby: ", lobby_id_joined)
	
	var lobby_game_id = Steam.getLobbyData(lobby_id_joined, "game")
	if lobby_game_id != game_id:
		print("Warning: Joining lobby from different game: ", lobby_game_id, " (expected: ", game_id, ")")
	
	self.lobby_id = lobby_id_joined
	is_host = false
	
	if response == Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		print("Successfully entered lobby chat room")
		
		var lobby_name = Steam.getLobbyData(lobby_id_joined, "name")
		var member_count = Steam.getNumLobbyMembers(lobby_id_joined)
		print("Lobby: ", lobby_name, " | Members: ", member_count)
		
		var host_id = Steam.getLobbyOwner(lobby_id_joined)
		if host_id != 0:
			print("Host Steam ID: ", host_id)
			_pending_host_id = host_id
			_pending_client_setup = true
		else:
			print("Error: Could not get lobby owner")
		
		update_lobby_skill()
		lobby_joined.emit("joined")
	else:
		var fail_reason: String
		match response:
			Steam.CHAT_ROOM_ENTER_RESPONSE_DOESNT_EXIST:
				fail_reason = "This lobby no longer exists."
			Steam.CHAT_ROOM_ENTER_RESPONSE_NOT_ALLOWED:
				fail_reason = "You don't have permission to join this lobby."
			Steam.CHAT_ROOM_ENTER_RESPONSE_FULL:
				fail_reason = "The lobby is now full."
			Steam.CHAT_ROOM_ENTER_RESPONSE_ERROR:
				fail_reason = "Uh... something unexpected happened!"
			Steam.CHAT_ROOM_ENTER_RESPONSE_BANNED:
				fail_reason = "You are banned from this lobby."
			_:
				fail_reason = "No reason given for failure"
		print("Failed to join lobby: ", fail_reason)
		self.lobby_id = 0

func _on_lobby_match_list(lobbies: Array) -> void:
	print("Found ", lobbies.size(), " lobbies for game: ", game_id)
	
	lobby_list.clear()
	
	for found_lobby_id in lobbies:
		var lobby_game_id = Steam.getLobbyData(found_lobby_id, "game")
		var lobby_name = Steam.getLobbyData(found_lobby_id, "name")
		var num_players = Steam.getNumLobbyMembers(found_lobby_id)
		var max_players = Steam.getLobbyMemberLimit(found_lobby_id)
		
		lobby_list.append({
			"id": found_lobby_id,
			"name": lobby_name,
			"game": lobby_game_id,
			"players": num_players,
			"max_players": max_players
		})
		
		print("Lobby: ", lobby_name, " | Game: ", lobby_game_id, " | Players: ", num_players, "/", max_players)
	
	lobby_list_received.emit()

func _on_lobby_data_update(success: bool, lobby_id_updated: int, member_id: int) -> void:
	if success:
		print("Lobby data updated for lobby: ", lobby_id_updated)

func _on_lobby_chat_message(lobby_id_chat: int, user: int, message: String, chat_type: int) -> void:
	if message.is_empty():
		return
	
	var sender_name: String = Steam.getFriendPersonaName(user)
	if sender_name == "":
		sender_name = "Player " + str(user)
	
	print("Chat from ", sender_name, ": ", message)
	lobby_chat_received.emit(sender_name, message)

func _on_lobby_chat_update(lobby_id_chat: int, user_joined: int, user_left: int, user_made_change: int, member_state: int) -> void:
	if user_joined != 0:
		print("Member joined: ", Steam.getFriendPersonaName(user_joined))
		lobby_member_joined.emit(user_joined)
		update_lobby_skill()
	if user_left != 0:
		print("Member left: ", Steam.getFriendPersonaName(user_left))
		lobby_member_left.emit(user_left)
		update_lobby_skill()
	if user_made_change != 0:
		print("Member changed state: ", Steam.getFriendPersonaName(user_made_change), " state: ", member_state)
		lobby_member_data_changed.emit(user_made_change, "state", str(member_state))

#endregion ---------------------------------------------------------


#region Game Connection Setup --------------------------------------

func _add_player(id : int = 1) -> void:
	_ensure_instance()
	if player_scene == null:
		print("Player ", id, " connected - no player_scene set, emitting signal only")
		player_connected.emit(id)
		return
	var player = player_scene.instantiate();
	player.name = str(id);
	call_deferred("add_child", player)
	print("Player added with ID: ", id)
	player_connected.emit(id)

func _remove_player(id : int) -> void:
	_ensure_instance()
	player_disconnected.emit(id)
	if !self.has_node(str(id)):
		return
	self.get_node(str(id)).queue_free();
	print("Player removed with ID: ", id)

func _finish_lobby_setup() -> void:
	if player_scene != null:
		_setup_spawner()

	peer = SteamMultiplayerPeer.new()
	peer.create_host(0)

	host_steam_id = Steam.getSteamID()

	var tree = get_tree()
	if tree:
		tree.multiplayer.multiplayer_peer = peer
		tree.multiplayer.peer_connected.connect(_add_player)
		tree.multiplayer.peer_disconnected.connect(_remove_player)
		_add_player()
		update_lobby_skill()
		lobby_created.emit("created")
	else:
		print("Error: Failed to get tree for host setup")

func _finish_client_setup(host_id: int) -> void:
	print("Finishing client setup for host: ", host_id)
	
	peer = SteamMultiplayerPeer.new()
	peer.create_client(host_id, 0)

	var tree = get_tree()
	if tree:
		tree.multiplayer.multiplayer_peer = peer
		print("Client peer setup complete, connected to host ", host_id)
	else:
		print("Error: Could not get scene tree for client setup")

func _leave_lobby() -> void:
	if lobby_id != 0:
		Steam.leaveLobby(lobby_id)
		print("Left lobby: ", lobby_id)
		lobby_id = 0
		is_host = false
		
		var tree = get_tree()
		if tree and tree.multiplayer.multiplayer_peer:
			tree.multiplayer.multiplayer_peer.close()
			tree.multiplayer.multiplayer_peer = null
		peer = null

#endregion ---------------------------------------------------------
