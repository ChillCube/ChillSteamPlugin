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

signal lobby_created(type);
signal lobby_joined(type);
signal lobby_list_received  ## Signal to notify when lobby list is ready
signal lobby_chat_received(sender_name: String, message: String)  ## Chat message received
signal lobby_data_changed(key: String, value: String, member_id: int)  ## Custom lobby data changed
signal lobby_member_joined(member_id: int)  ## A member joined the lobby
signal lobby_member_left(member_id: int)  ## A member left the lobby
signal lobby_member_data_changed(member_id: int, key: String, value: String)  ## A member's data changed

#region Initialize the Steam Manager -----------------------------
static func initialize_steam(p_scene : PackedScene) -> void: ## Sets up Steam with the app ID and stores the player scene reference
	if not initialized:
		player_scene = p_scene
		
		# Get the project name to use as game identifier
		game_id = ProjectSettings.get_setting("application/config/name", "UnknownGame")
		print("Game ID set to: ", game_id)
		
		print("Steam initialized", Steam.steamInit(app_id, true))
		Steam.initRelayNetworkAccess();
		_ensure_instance()
		Steam.lobby_created.connect(_instance._on_lobby_created)
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
		if player_scene == null:
			assert(false, "You must either run 'initialize_steam(player_scene) or set SteamManager.player_scene to the player scene'");
		else:
			initialize_steam(player_scene)

static func get_instance() -> SteamManager: ## Returns the SteamManager instance for connecting signals
	_ensure_instance()
	return _instance

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
	
	spawner = MultiplayerSpawner.new()
	spawner.name = "PlayerSpawner"
	spawner.spawn_path = NodePath("/root")
	spawner.spawn_function = _spawn_custom
	
	# Store player scene and any additional scenes
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
	
	# Filter to only show lobbies from this specific game
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


#region Quick Matchmaking Helpers --------------------------------

func find_any_lobby() -> void: ## Finds the first available lobby and joins it
	_ensure_instance()
	if not is_steam_ready:
		print("Steam is not ready yet!")
		return
	
	print("Quick match: finding any lobby...")
	Steam.addRequestLobbyListStringFilter("game", game_id, Steam.LOBBY_COMPARISON_EQUAL)
	Steam.addRequestLobbyListDistanceFilter(Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE)
	Steam.addRequestLobbyListResultCountFilter(1)
	Steam.requestLobbyList()
	
	if not _instance.lobby_list_received.is_connected(_on_quick_match_list):
		_instance.lobby_list_received.connect(_on_quick_match_list, CONNECT_ONE_SHOT)

func _on_quick_match_list() -> void: ## Auto-joins the first lobby in the list for quick match
	if lobby_list.size() > 0:
		print("Quick match: joining lobby ", lobby_list[0]["id"])
		join_lobby(lobby_list[0]["id"])
	else:
		print("Quick match: no lobbies found. Creating one...")
		host_public_lobby()

#endregion ---------------------------------------------------------


#region Steam Callbacks --------------------------------------------

func _on_lobby_created(result : int, lobby_created_id : int) -> void: ## Host callback: Sets up the host peer and tags lobby with game ID
	_ensure_instance()
	if result == Steam.Result.RESULT_OK:
		self.lobby_id = lobby_created_id;
		
		# Tag this lobby as belonging to our game
		Steam.setLobbyData(lobby_created_id, "game", game_id)
		print("Tagged lobby with game ID: ", game_id)
		
		# Set the lobby name if we have a pending one, otherwise use default
		if _pending_lobby_name != "":
			Steam.setLobbyData(lobby_created_id, "name", _pending_lobby_name)
			print("Set lobby name to: ", _pending_lobby_name)
			_pending_lobby_name = ""
		else:
			Steam.setLobbyData(lobby_created_id, "name", "Lobby " + str(lobby_created_id))
		
		# Check if we're in the tree, if not set flag for later
		if is_inside_tree():
			_finish_lobby_setup()
		else:
			_pending_lobby_setup = true
	else:
		print("Failed to create lobby: ", result)

func _on_lobby_joined(lobby_id_joined: int, permissions: int, locked: bool, response: int) -> void: ## Client callback: Handles lobby join response and queues client peer setup
	print("Joined lobby: ", lobby_id_joined)
	
	# Verify this lobby belongs to our game before fully joining
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
		
		# Get host ID and queue client setup
		var host_id = Steam.getLobbyOwner(lobby_id_joined)
		if host_id != 0:
			print("Host Steam ID: ", host_id)
			_pending_host_id = host_id
			_pending_client_setup = true
		else:
			print("Error: Could not get lobby owner")
		
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

func _on_lobby_match_list(lobbies: Array) -> void: ## Receives, stores, and emits signal with the list of lobbies found from search
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

func _on_lobby_data_update(success: bool, lobby_id_updated: int, member_id: int) -> void: ## Callback: Triggers when any lobby member updates lobby data or metadata
	if success:
		print("Lobby data updated for lobby: ", lobby_id_updated)

func _on_lobby_chat_message(lobby_id_chat: int, user: int, message: String, chat_type: int) -> void: ## Callback: Processes incoming lobby chat messages
	if message.is_empty():
		return
	
	var sender_name: String = Steam.getFriendPersonaName(user)
	if sender_name == "":
		sender_name = "Player " + str(user)
	
	print("Chat from ", sender_name, ": ", message)
	lobby_chat_received.emit(sender_name, message)

func _on_lobby_chat_update(lobby_id_chat: int, user_joined: int, user_left: int, user_made_change: int, member_state: int) -> void: ## Callback: Tracks member joins, leaves, and changes
	if user_joined != 0:
		print("Member joined: ", Steam.getFriendPersonaName(user_joined))
		lobby_member_joined.emit(user_joined)
	if user_left != 0:
		print("Member left: ", Steam.getFriendPersonaName(user_left))
		lobby_member_left.emit(user_left)
	if user_made_change != 0:
		print("Member changed state: ", Steam.getFriendPersonaName(user_made_change), " state: ", member_state)
		lobby_member_data_changed.emit(user_made_change, "state", str(member_state))

#endregion ---------------------------------------------------------


#region Game Connection Setup --------------------------------------

func _add_player(id : int = 1) -> void: ## Host function: Spawns a player scene for a connected peer, called when a player joins the game
	_ensure_instance()
	var player = player_scene.instantiate();
	player.name = str(id);
	call_deferred("add_child", player)
	print("Player added with ID: ", id)

func _remove_player(id : int) -> void: ## Host function: Removes a player's scene when they disconnect from the game
	_ensure_instance()
	if !self.has_node(str(id)):
		return
	
	self.get_node(str(id)).queue_free();
	print("Player removed with ID: ", id)

func _finish_lobby_setup() -> void: ## Sets up the game as Host using SteamMultiplayerPeer
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
		lobby_created.emit("created")
	else:
		print("Error: Failed to get tree for host setup")

func _finish_client_setup(host_id: int) -> void: ## Creates the client peer when we're safely in the tree
	print("Finishing client setup for host: ", host_id)
	
	peer = SteamMultiplayerPeer.new()
	peer.create_client(host_id, 0)

	var tree = get_tree()
	if tree:
		tree.multiplayer.multiplayer_peer = peer
		print("Client peer setup complete, connected to host ", host_id)
	else:
		print("Error: Could not get scene tree for client setup")

func _leave_lobby() -> void: ## Instance method that handles the actual lobby leaving and multiplayer cleanup
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
