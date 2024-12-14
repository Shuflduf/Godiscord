class_name DiscordBot
extends Node

@export var token: String = OS.get_environment("DISCORD_BOT_TOKEN")

signal message_recieved(message: DiscordMessage)
signal bot_ready()

var websocket: WebSocketPeer
var user: DiscordUser

func _ready():
	websocket = WebSocketPeer.new()
	websocket.connect_to_url("wss://gateway.discord.gg/?v=9&encoding=json")

func _process(_delta):
	websocket.poll()
	var state = websocket.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		while websocket.get_available_packet_count():
			var data = websocket.get_packet().get_string_from_utf8()
			#print("Packet: ", data)
			var json = JSON.parse_string(data)
			if json["op"] == 10:  # Hello
				var heartbeat_interval = json["d"]["heartbeat_interval"] / 1000.0
				send_identify()
				start_heartbeat(heartbeat_interval)
			elif json["op"] == 0 and json["t"] == "READY":
				user = DiscordUser.new()
				user.id = int(json["d"]["user"]["id"])
				user.name = json["d"]["user"]["username"]
				bot_ready.emit()
			elif json["op"] == 0 and json["t"] == "MESSAGE_CREATE":
				var message = DiscordMessage.new()
				message.token = token
				message.content = json["d"]["content"]
				message.author = DiscordUser.new()
				message.author.id = int(json["d"]["author"]["id"])
				message.channel = DiscordChannel.new()
				message.channel.token = token
				message.channel.id = int(json["d"]["channel_id"])
				message.id = int(json["d"]["id"])

				message_recieved.emit(message)
			elif json["op"] == 0 and json["t"] == "INTERACTION_CREATE":
				handle_interaction(json["d"])
	elif state == WebSocketPeer.STATE_CLOSING:
		pass
	elif state == WebSocketPeer.STATE_CLOSED:
		var code = websocket.get_close_code()
		var reason = websocket.get_close_reason()
		print("WebSocket closed with code: %d, reason %s. Clean: %s" % [code, reason, code != -1])
		set_process(false)

func send_identify():
	var payload = {
		"op": 2,
		"d": {
			"token": token,
			"intents": 513,
			"properties": {
				"$os": OS.get_name(),
				"$browser": "godot",
				"$device": "godot"
			}
		}
	}
	websocket.put_packet(JSON.stringify(payload).to_utf8_buffer())

func start_heartbeat(interval: float):
	await get_tree().create_timer(interval).timeout
	websocket.put_packet(JSON.stringify({"op": 1, "d": null}).to_utf8_buffer())
	start_heartbeat(interval)

func handle_interaction(interaction):
	var url = "https://discord.com/api/v9/interactions/%s/%s/callback" % [interaction["id"], interaction["token"]]
	var headers = [
		"Authorization: Bot %s" % token,
		"Content-Type: application/json"
	]
	var payload = {
		"type": 4,
		"data": {
			"content": "Hello! This is a response from your slash command."
		}
	}
	var http_req = HTTPRequest.new()
	DiscordRequestHandler.add_child(http_req)
	http_req.request_completed.connect(func(_r, _c, _h, _b): http_req.queue_free())
	http_req.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))

func _on_request_completed(result, response_code, headers, body):
	if response_code == 201:
		print("Global slash command registered successfully")
	else:
		print("Failed to register global slash command: %s" % body)
func register_slash_command():
	var url = "https://discord.com/api/v9/applications/%s/commands" % user.id
	var headers = [
		"Authorization: Bot %s" % token,
		"Content-Type: application/json"
	]
	var payload = {
		"name": "hello",
		"description": "Says hello",
		"options": []
	}
	var http_req = HTTPRequest.new()
	DiscordRequestHandler.add_child(http_req)
	http_req.request_completed.connect(func(_r, _c, _h, _b): http_req.queue_free())
	http_req.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))