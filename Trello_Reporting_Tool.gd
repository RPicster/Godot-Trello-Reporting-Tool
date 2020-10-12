extends Panel

# Trello Reporting Tool - by Raffaele Picca: twitter.com/MV_Raffa

const PROXY_HOST = 'proxy.example'
const PROXY_PATH = '/proxy.php'

const POST_BOUNDARY: String = 'GodotFileUploadBoundaryZ29kb3RmaWxl'

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

onready var timer = Timer.new()
onready var http = HTTPClient.new()
onready var short_text = $VBoxContainer/HBoxContainer/ShortDescEdit
onready var long_text = $VBoxContainer/HBoxContainer/LongDescEdit
onready var send_button = $VBoxContainer/HBoxContainer/Custom/Send
onready var feedback = $VBoxContainer/HBoxContainer/Custom/feedback

func _ready():
	timer.set_wait_time(0.2)
	add_child(timer)
	if !trello_labels.empty():
		for i in range(trello_labels.size()):
			$VBoxContainer/HBoxContainer/Custom/Type.add_item(trello_labels[i].label_description, i)
		$VBoxContainer/HBoxContainer/Custom/Type.selected = 0
	else:
		$VBoxContainer/HBoxContainer/Custom/Type.hide()

func _on_Send_pressed():
	show_feedback()
	send_button.disabled = true
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
			'png':
				obj.mimetype = 'image/png'
			'jpg', 'jpeg':
				obj.mimetype = 'image/jpeg'
			'gif':
				obj.mimetype = 'image/gif'
			_:
				obj.mimetype = 'application/octet-stream'

		var file = File.new()
		if file.open(path, File.READ) != OK:
			return null
		obj.data = file.get_buffer(file.get_len())
		file.close()

		return obj

	static func from_image(img: Image, name: String) -> Attachment.Struct:
		var obj = Attachment.Struct.new()
		obj.filename = name + '.png'
		obj.mimetype = 'image/png'
		obj.data = img.save_png_to_buffer()
		return obj

func create_post_data(key: String, value) -> PoolByteArray:
	var body: PoolByteArray
	var extra: String = ''
	var bytes: PoolByteArray

	if value is Array:
		for idx in range(0, value.size()):
			var newkey = "%s[%d]" % [key, idx]
			body += create_post_data(newkey, value[idx])
		return body
	elif value is Attachment.Struct:
		extra = '; filename="' + value.filename + '"'
		if value.mimetype != 'application/octet-stream':
			extra += '\r\nContent-Type: ' + value.mimetype
		bytes = value.data
	elif value != null:
		bytes = value.to_ascii()

	var buf = 'Content-Disposition: form-data; name="' + key + '"' + extra
	body += ('--' + POST_BOUNDARY + '\r\n' + buf + '\r\n\r\n').to_ascii()
	body += bytes + '\r\n'.to_ascii()
	return body

func send_post(http: HTTPClient, path: String, data: Dictionary) -> int:
	var headers = [
		'Content-Type: multipart/form-data; boundary=' + POST_BOUNDARY,
	]

	var body: PoolByteArray
	for key in data:
		body += create_post_data(key, data[key])
	body += ('--' + POST_BOUNDARY + '--\r\n').to_ascii()

	return http.request_raw(HTTPClient.METHOD_POST, path, headers, body)

func create_card():
	var data = {
		'name': short_text.text,
		'desc': long_text.text + "\n\n**Operating System:** " + OS.get_name(),
	}

	if !trello_labels.empty():
		var type = $VBoxContainer/HBoxContainer/Custom/Type.selected
		data['label_id'] = trello_labels[type].label_trello_id

	data['cover'] = Attachment.from_path("res://icon.png")
	data['attachments'] = [
		Attachment.from_image(
			OpenSimplexNoise.new().get_image(200, 200), 'noise1'
		),
		Attachment.from_image(
			OpenSimplexNoise.new().get_image(200, 200), 'noise2'
		),
	]

	http.connect_to_host(PROXY_HOST, -1, true)

	var timeout = 30.0
	timer.start()
	while http.get_status() in [
		HTTPClient.STATUS_CONNECTING,
		HTTPClient.STATUS_RESOLVING
	]:
		http.poll()
		yield(timer, 'timeout')
		timeout -= timer.get_wait_time()
		if timeout < 0.0:
			feedback.text = "Timeout while waiting to connect to server :-("
			timer.stop()
			return
	timer.stop()

	if http.get_status() != HTTPClient.STATUS_CONNECTED:
		feedback.text = "Unable to connect to server :-("
		return

	if send_post(http, PROXY_PATH, data) != OK:
		feedback.text = "Unable to send feedback to server :-("
		return

	timeout = 30.0
	timer.start()
	while http.get_status() == HTTPClient.STATUS_REQUESTING:
		http.poll()
		yield(timer, 'timeout')
		timeout -= timer.get_wait_time()
		if timeout < 0.0:
			feedback.text = "Timeout waiting for server acknowledgement :-("
			timer.stop()
			return
	timer.stop()

	if not http.get_status() in [
		HTTPClient.STATUS_BODY,
		HTTPClient.STATUS_CONNECTED
	]:
		feedback.text = "Unable to connect to server :-("
		return

	if http.has_response() && http.get_response_code() != 200:
		timeout = 30.0
		timer.start()
		var response: PoolByteArray
		while http.get_status() == HTTPClient.STATUS_BODY:
			http.poll()
			var chunk = http.read_response_body_chunk()
			if chunk.size() == 0:
				yield(timer, 'timeout')
				timeout -= timer.get_wait_time()
				if timeout < 0.0:
					feedback.text = "Timeout waiting for server response :-("
					timer.stop()
					return
			else:
				response += chunk
		timer.stop()
		feedback.text = 'Error from server: ' + response.get_string_from_utf8()
		return

	feedback.text = "Feedback sent successfully, thank you!"

func show_feedback():
	#disable all input fields and show a short message about the current status
	send_button.hide()
	short_text.editable = false
	long_text.readonly = true
	$VBoxContainer/HBoxContainer/Custom/Type.hide()
	feedback.show()
	feedback.text = "Your feedback is being sent..."

func _on_ShortDescEdit_text_changed(_new_text):
	update_send_button()

func _on_LongDescEdit_text_changed():
	update_send_button()

func update_send_button():
	# check if text is entered, if not, disable the send button
	send_button.disabled = (long_text.text == "" or short_text.text == "")
