# ChillSteamPlugin API Reference
Generated: 2026-04-28

A custom version of the GodotSteam plugin, made to be comptaible with ChillCube's developer tools and made with specific features for ChillCube

## Class: SteamManager
**Inherits:** [Node](https://docs.godotengine.org/en/stable/classes/class_node.html)


### 💾 Class Variables (Standard)
| Property | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| **lobby_list** | `Array` | `[]` | Stores the list of found lobbies |
| **_pending_lobby_name** | `String` | `""` | Temporary storage for lobby name before creation |
| **_spawnable_scenes** | `Array[PackedScene]` | `[]` | Stores scenes for custom spawning |
| **_pending_lobby_setup** | `bool` | `false` | Flag to delay lobby setup until we're in the tree |
| **_pending_client_setup** | `bool` | `false` | Flag to delay client setup until we're in the tree |
| **_pending_host_id** | `int` | `0` | Stored host ID for pending client setup |
| **player_skill** | `float` | `500.0` | Player skill rating (1-5000), starts neutral at 500 |
| **use_skill_matchmaking** | `bool` | `false` | Set to true to enable skill-based matching |
| **skill_falloff_enabled** | `bool` | `false` | Set to true to enable skill decay over time |
| **skill_falloff_amount** | `float` | `10.0` | How much skill is lost per falloff tick |
| **skill_falloff_interval_days** | `int` | `7` | Days between falloff ticks |
| **skill_falloff_minimum** | `float` | `100.0` | Skill won't decay below this level |

### 🔔 Signals
| Signal | Arguments | Description |
| :--- | :--- | :--- |
| **lobby_list_received** | - |  Signal to notify when lobby list is ready |
| **lobby_chat_received** | `sender_name: String`<br>`message: String` |  Chat message received |
| **lobby_data_changed** | `key: String`<br>`value: String`<br>`member_id: int` |  Custom lobby data changed |
| **lobby_member_joined** | `member_id: int` |  A member joined the lobby |
| **lobby_member_left** | `member_id: int` |  A member left the lobby |
| **lobby_member_data_changed** | `member_id: int`<br>`key: String`<br>`value: String` |  A member's data changed |
| **player_connected** | `id: int` |  A player connected to the multiplayer peer |
| **player_disconnected** | `id: int` |  A player disconnected from the multiplayer peer |
| **static func get_instance** | `` |  Returns the SteamManager instance for connecting signals |
| **func _setup_callbacks** | `` |  Connects all Steam lobby signals to their handler functions for both host and client |

### 🛠️ Methods
| Method | Arguments | Returns | Description |
| :--- | :--- | :--- | :--- |
| **static func initialize_steam()** | `p_scene : PackedScene = null` | `void` |  Sets up Steam with the app ID. Player scene is optional. |
| **static func _ensure_instance()** | - | `void` |  Creates the singleton SteamManager node and adds it to the scene tree if it doesn't exist |
| **static func get_instance()** | - | `SteamManager` |  Returns the SteamManager instance for connecting signals |
| **static func set_player_scene()** | `p_scene: PackedScene` | `void` |  Sets the player scene after initialization |
| **add_to_autospawn()** | `scene: PackedScene` | `void` |  Adds additional scenes to the spawn list for network synchronization |
| **static func host_public_lobby()** | `max_players:int = 4` | `void` |  Creates a public lobby visible to everyone on Steam |
| **static func host_public_lobby_with_name()** | `lobby_name: String`<br>`max_players:int = 4` | `void` |  Creates a public lobby with a custom name |
| **static func host_friends_only_lobby()** | `max_players:int = 4` | `void` |  Creates a lobby only visible to your Steam friends |
| **static func host_invisible_lobby()** | `max_players:int = 4` | `void` |  Creates a lobby that doesn't appear in searches but can be joined directly |
| **static func host_private_lobby()** | `max_players:int = 4` | `void` |  Creates a private lobby that requires an invitation to join |
| **static func host_unique_private_lobby()** | `max_players:int = 4` | `void` |  Creates a private lobby with a unique ID, requires invitation |
| **static func host_lobby()** | `lobby_type`<br>`max_players: int = 4` | `bool` |  Internal function that sends the lobby creation request to Steam |
| **static func join_lobby()** | `lobby_id_to_join: int` | `void` |  Joins a specific lobby by its Steam lobby ID |
| **static func get_lobby_list()** | - | `void` |  Requests a list of all available lobbies from Steam's servers, filtered by game ID |
| **static func leave_lobby()** | - | `void` |  Leaves the current lobby and cleans up the multiplayer peer through the instance |
| **send_lobby_chat()** | `message: String` | `bool` |  Sends a chat message to everyone in the lobby |
| **set_lobby_data()** | `key: String`<br>`value: String` | `bool` |  Sets a custom key-value pair on the lobby that all members can read |
| **get_lobby_data()** | `key: String` | `String` |  Gets a custom key-value pair from the lobby |
| **delete_lobby_data()** | `key: String` | `bool` |  Deletes a custom key-value pair from the lobby |
| **set_lobby_data_bool()** | `key: String`<br>`value: bool` | `void` |  Convenience function for boolean lobby data |
| **get_lobby_data_bool()** | `key: String`<br>`default: bool = false` | `bool` |  Convenience function for reading boolean lobby data |
| **set_lobby_data_int()** | `key: String`<br>`value: int` | `void` |  Convenience function for integer lobby data |
| **get_lobby_data_int()** | `key: String`<br>`default: int = 0` | `int` |  Convenience function for reading integer lobby data |
| **set_lobby_data_float()** | `key: String`<br>`value: float` | `void` |  Convenience function for float lobby data |
| **get_lobby_data_float()** | `key: String`<br>`default: float = 0.0` | `float` |  Convenience function for reading float lobby data |
| **set_member_data()** | `key: String`<br>`value: String` | `bool` |  Sets data specific to your own player in the lobby |
| **get_member_data()** | `member_id: int`<br>`key: String` | `String` |  Gets data for a specific lobby member |
| **get_my_member_data()** | `key: String` | `String` |  Gets your own member data |
| **get_lobby_name()** | - | `String` |  Returns the current lobby's name |
| **get_lobby_member_count()** | - | `int` |  Returns the number of members in the current lobby |
| **get_lobby_max_members()** | - | `int` |  Returns the maximum members allowed in the current lobby |
| **get_lobby_members()** | - | `Array` |  Returns an array of Steam IDs for all members in the lobby |
| **get_lobby_member_names()** | - | `Array` |  Returns an array of member names in the lobby |
| **is_lobby_owner()** | - | `bool` |  Returns true if you are the lobby owner |
| **get_lobby_owner_name()** | - | `String` |  Returns the name of the lobby owner |
| **set_lobby_joinable()** | `joinable: bool` | `bool` |  Sets whether the lobby can be joined by new players |
| **set_lobby_max_members()** | `max_players: int` | `bool` |  Changes the maximum number of players allowed in the lobby |
| **get_friend_count()** | - | `int` |  Returns the number of friends |
| **get_friend_list()** | - | `Array` |  Returns an array of friend dictionaries with id and name |
| **is_friend_in_same_game()** | `friend_id: int` | `bool` |  Checks if a friend is playing this game |
| **invite_friend_to_lobby()** | `friend_id: int` | `bool` |  Invites a friend to the current lobby |
| **get_my_steam_id()** | - | `int` |  Returns your own Steam ID |
| **get_my_steam_name()** | - | `String` |  Returns your own Steam display name |
| **get_steam_name()** | `steam_id: int` | `String` |  Returns the display name for any Steam ID |
| **get_steam_avatar()** | `steam_id: int`<br>`size: int = Steam.AVATAR_MEDIUM` | `ImageTexture` |  Returns the avatar for a Steam ID as a Godot texture |
| **set_rich_presence()** | `key: String`<br>`value: String` | `bool` |  Sets rich presence data (shown on friends list) |
| **clear_rich_presence()** | - | `void` |  Clears all rich presence data |
| **set_lobby_game_server()** | - | `void` |  Associates a game server with the lobby (for server browsing) |
| **get_lobby_game_server()** | - | `Dictionary` |  Gets the game server info for the lobby |
| **get_player_skill()** | - | `float` |  Returns the current player skill rating |
| **increase_skill()** | `amount: float = 25.0` | `void` |  Increases player skill and saves |
| **decrease_skill()** | `amount: float = 25.0` | `void` |  Decreases player skill and saves |
| **set_skill()** | `new_skill: float` | `void` |  Sets player skill to a specific value and saves |
| **enable_skill_matchmaking()** | `enabled: bool` | `void` |  Toggle skill-based matchmaking on/off |
| **save_skill()** | - | `void` |  Saves the player skill to disk |
| **load_skill()** | - | `void` |  Loads the player skill from disk, defaults to 500 |
| **get_skill_falloff_info()** | - | `Dictionary` |  Returns information about the falloff state |
| **get_lobby_average_skill()** | - | `float` |  Calculates the average skill of all lobby members |
| **update_lobby_skill()** | - | `void` |  Updates the lobby's skill data |
| **join_random_lobby()** | - | `void` |  Joins a random lobby with smart or skill-based matching |

---

## Class: MultiplayerNode
**Inherits:** [Node](https://docs.godotengine.org/en/stable/classes/class_node.html)


---

## Class: MultiplayerPlayer2D
**Inherits:** [CharacterBody2D](https://docs.godotengine.org/en/stable/classes/class_characterbody2d.html)


---

## Class: MultiplayerNode2D
**Inherits:** [Node2D](https://docs.godotengine.org/en/stable/classes/class_node2d.html)


---

## Class: updates
**Inherits:** [MarginContainer](https://docs.godotengine.org/en/stable/classes/class_margincontainer.html)


---

## Class: steamworks_panel
**Inherits:** [Control](https://docs.godotengine.org/en/stable/classes/class_control.html)


---

## Class: GodotSteamPlugin
**Inherits:** [EditorPlugin](https://docs.godotengine.org/en/stable/classes/class_editorplugin.html)


---

## Class: MultiplayerNode3D
**Inherits:** [Node3D](https://docs.godotengine.org/en/stable/classes/class_node3d.html)


---

