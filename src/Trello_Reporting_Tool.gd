extends Panel

# Trello Reporting Tool - by Raffaele Picca: twitter.com/MV_Raffa

# The URL pointing to the webserver location where "proxy.php" from this
# repository is served.
const PROXY_URL = "https://proxy.example/proxy.php"

# Internal constants, only change if you must ;-)
const POST_BOUNDARY: String = "GodotFileUploadBoundaryZ29kb3RmaWxl"
const URL_REGEX: String = \
	"^(?:(?<scheme>https?)://)?" + \
	"(?<host>\\[[a-fA-F0-9:.]+\\]|[^:/]+)" + \
	"(?::(?<port>[0-9]+))?(?<path>$|/.*)"

const CARD_DETAIL_TEXT:String = \
	"**Gameversion:** {game_version}\n" + \
	"**Level:** {game_level}\n" + \
	"**Graphics Adapter:** {graphics_adapter}\n" + \
	"**Window Resolution:** {window_resolution}\n" + \
	"**Screen Resolution:** {screen_resolution}\n" + \
	"**Operating System:** {os}\n"

# If you don't want to use labels, just leave this dictionary empty, you can
# add as many labels as you need by just expanding the library.
#
# To find out the label ids, use the same way as with the list ids. look for
# the label ids in the Trello json.
var trello_labels = {
	0 : {
		"label_trello_id"	: "LABEL ID FROM TRELLO",
		"label_description"	: "Label name for Option Button"
	},
	1 : {
		"label_trello_id"	: "LABEL ID FROM TRELLO",
		"label_description"	: "Label name for Option Button"
	}
}

var report_hash: String			= ""
var screenshot_data: Image		= Image.new()

onready var timer: Timer		= $TimeoutTimer
onready var http: HTTPClient	= HTTPClient.new()
onready var short_text:LineEdit	= $Content/Form/ShortDescEdit
onready var long_text:TextEdit	= $Content/Form/LongDescEdit
onready var send_button:Button	= $Content/Form/Custom/Send
onready var feedback:Label		= $Content/Feedback/feedback_label
onready var close_button:Button	= $Content/Feedback/close_button


func _ready():
	timer.set_wait_time(0.2)
	if !trello_labels.empty():
		for i in range(trello_labels.size()):
			$Content/Form/Custom/Type.add_item(trello_labels[i].label_description, i)
		$Content/Form/Custom/Type.selected = 0
	else:
		$Content/Form/Custom/Type.hide()
	
	# call this to show and reset the window
	show_window()


func show_window():
	# Create a hash that will make it easier to have a unique ID when handling tickets etc.
	report_hash = str( round(hash(str(OS.get_datetime()) + OS.get_unique_id() )*0.00001) )
	# Grab a screenshot before opening the report tool
	screenshot_data = get_viewport().get_texture().get_data()
	screenshot_data.flip_y()
	# Show the reporting tool, this should be done after taking the screenshot
	show()
	$Content/Form.show()
	$Content/Feedback.hide()
	short_text.grab_focus()
	short_text.text = ""
	long_text.text = ""
	$Content/Form/Custom/Type.selected = 0


func create_card():
	var card_title = short_text.text
	var card_message = long_text.text
	var card_details = CARD_DETAIL_TEXT.format({
		"game_version": "1.0", 
		"game_level": "Level 11", 
		"graphics_adapter": VisualServer.get_video_adapter_name() + " ( " + VisualServer.get_video_adapter_vendor() + " )",
		"window_resolution": str(OS.window_size),
		"screen_resolution": str(OS.get_screen_size()),
		"os": OS.get_name()
		})
	
	var data = {
		"name": card_title + " #" + report_hash,
		"desc": ("\n\n**--------- MESSAGE --------**\n\n" + card_message + "\n\n\n\n**---------- DETAILS ---------**\n\n" + card_details ),
	}
	
	if !trello_labels.empty():
		var type = $Content/Form/Custom/Type.selected
		data["label_id"] = trello_labels[type].label_trello_id
	
	# The cover attachment must be an image. If you don't want so sent further
	# attachments, just leave attachments empty.
	#
	# Use the function Attachment.from_path() to attach files from the filesystem or 
	# Attachment.from_image() to convert an Image instance to a png file.
	# Attachment.from_string() can be used to attach txt files.
	data["cover"] = Attachment.from_image(screenshot_data, report_hash+"_screenshot")
	data["attachments"] = [
		Attachment.from_path("res://icon.png"),
		Attachment.from_string("You can attach text files. Save games, further game details, etc.", "additional_info"),
	]
	
	var parsed_url = parse_url(PROXY_URL)
	if parsed_url.empty():
		change_feedback("Wrong proxy URL provided, can't send data :-(")
		return
	
	http.connect_to_host(
		parsed_url["host"],
		parsed_url["port"],
		parsed_url["scheme"] == "https"
	)
	
	var timeout = 30.0
	timer.start()
	while http.get_status() in [
		HTTPClient.STATUS_CONNECTING,
		HTTPClient.STATUS_RESOLVING
	]:
		http.poll()
		yield(timer, "timeout")
		timeout -= timer.get_wait_time()
		if timeout < 0.0:
			change_feedback("Timeout while waiting to connect to server :-(")
			timer.stop()
			return
	timer.stop()
	
	if http.get_status() != HTTPClient.STATUS_CONNECTED:
		change_feedback("Unable to connect to server :-(")
		return
	
	if send_post(http, parsed_url["path"], data) != OK:
		change_feedback("Unable to send feedback to server :-(")
		return
	
	timeout = 30.0
	timer.start()
	while http.get_status() == HTTPClient.STATUS_REQUESTING:
		http.poll()
		yield(timer, "timeout")
		timeout -= timer.get_wait_time()
		if timeout < 0.0:
			change_feedback("Timeout waiting for server acknowledgement :-(")
			timer.stop()
			return
	timer.stop()
	
	if not http.get_status() in [
		HTTPClient.STATUS_BODY,
		HTTPClient.STATUS_CONNECTED
	]:
		change_feedback("Unable to connect to server :-(")
		return
	
	if http.has_response() && http.get_response_code() != 200:
		timeout = 30.0
		timer.start()
		var response: PoolByteArray
		while http.get_status() == HTTPClient.STATUS_BODY:
			http.poll()
			var chunk = http.read_response_body_chunk()
			if chunk.size() == 0:
				yield(timer, "timeout")
				timeout -= timer.get_wait_time()
				if timeout < 0.0:
					change_feedback("Timeout waiting for server response :-(")
					timer.stop()
					return
			else:
				response += chunk
		timer.stop()
		feedback.text = "Error from server: " + response.get_string_from_utf8()
		return
	
	change_feedback("Feedback sent successfully, thank you!")


func _on_Send_pressed():
	show_feedback()
	create_card()


class Attachment:
	# XXX: This is to prevent reference cycles (and thus memleaks), see:
	# https://github.com/godotengine/godot/issues/27491
	class Struct:
		var filename: String
		var mimetype: String
		var data: PoolByteArray
	
	static func from_path(path: String) -> Attachment.Struct:
		var obj = Attachment.Struct.new()
		obj.filename = path.get_file()
		
		match path.get_extension():
			"png":
				obj.mimetype = "image/png"
			"jpg", "jpeg":
				obj.mimetype = "image/jpeg"
			"gif":
				obj.mimetype = "image/gif"
			_:
				obj.mimetype = "application/octet-stream"
		
		var file = File.new()
		if file.open(path, File.READ) != OK:
			return null
		obj.data = file.get_buffer(file.get_len())
		file.close()
		
		return obj
	
	static func from_image(img: Image, name: String) -> Attachment.Struct:
		var obj = Attachment.Struct.new()
		obj.filename = name + ".png"
		obj.mimetype = "image/png"
		obj.data = img.save_png_to_buffer()
		return obj
	
	static func from_string(string: String, name: String) -> Attachment.Struct:
		var obj = Attachment.Struct.new()
		obj.filename = name + ".txt"
		obj.mimetype = "text/plain"
		obj.data = string.to_utf8()
		return obj


func create_post_data(key: String, value) -> PoolByteArray:
	var body: PoolByteArray
	var extra: String = ""
	var bytes: PoolByteArray
	
	if value is Array:
		for idx in range(0, value.size()):
			var newkey = "%s[%d]" % [key, idx]
			body += create_post_data(newkey, value[idx])
		return body
	elif value is Attachment.Struct:
		extra = "; filename=\"" + value.filename + "\""
		if value.mimetype != "application/octet-stream":
			extra += "\r\nContent-Type: " + value.mimetype
		bytes = value.data
	elif value != null:
		bytes = value.to_utf8()
	
	var buf = "Content-Disposition: form-data; name=\"" + key + "\"" + extra
	body += ("--" + POST_BOUNDARY + "\r\n" + buf + "\r\n\r\n").to_ascii()
	body += bytes + "\r\n".to_ascii()
	return body


func send_post(http: HTTPClient, path: String, data: Dictionary) -> int:
	var headers = [
		"Content-Type: multipart/form-data; boundary=" + POST_BOUNDARY,
	]
	
	var body: PoolByteArray
	for key in data:
		body += create_post_data(key, data[key])
	body += ("--" + POST_BOUNDARY + "--\r\n").to_ascii()
	
	return http.request_raw(HTTPClient.METHOD_POST, path, headers, body)


func parse_url(url: String) -> Dictionary:
	var regex = RegEx.new()
	
	if regex.compile(URL_REGEX) != OK:
		return {}
	
	var re_match = regex.search(url)
	if re_match == null:
		return {}
	
	var scheme = re_match.get_string("scheme")
	if not scheme:
		scheme = "http"
	
	var port: int = 80 if scheme == "http" else 443
	if re_match.get_string("port"):
		port = int(re_match.get_string("port"))
	
	return {
		"scheme": scheme,
		"host": re_match.get_string("host"),
		"port": port,
		"path": re_match.get_string("path"),
	}


func show_feedback():
	#disable all input fields and show a short message about the current status
	$Content/Form.hide()
	$Content/Feedback.show()
	change_feedback("Your feedback is being sent...", true)


func change_feedback(new_message: String, close_button_disabled: bool = false) -> void:
	feedback.text = new_message
	close_button.disabled = close_button_disabled
	close_button.text = "Please wait" if close_button_disabled else "Close"
	close_button.grab_focus()


func _on_ShortDescEdit_text_changed(_new_text) -> void:
	update_send_button()


func _on_LongDescEdit_text_changed() -> void:
	update_send_button()


func update_send_button() -> void:
	# check if text is entered, if not, disable the send button
	send_button.disabled = (long_text.text == "" or short_text.text == "")


func _on_close_button_pressed():
	hide()
