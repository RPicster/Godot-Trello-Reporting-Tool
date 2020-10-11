extends Panel

# Trello Reporting Tool - by Raffaele Picca: twitter.com/MV_Raffa

const PROXY_HOST = 'proxy.example'
const PROXY_PATH = '/proxy.php'

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

func send_post(http: HTTPClient, path: String, data: Dictionary) -> int:
	var boundary: String = 'GodotFileUploadBoundaryZ29kb3RmaWxl'
	var headers = ['Content-Type: multipart/form-data; boundary=' + boundary]

	var body: PoolByteArray
	for key in data:
		var value = data[key]
		var extra: String = ''
		var bytes: PoolByteArray

		if value is File:
			var fname = value.get_path().get_file()
			var mimetype: String
			match value.get_path().get_extension():
				'png':
					mimetype = 'image/png'
				'jpg', 'jpeg':
					mimetype = 'image/jpeg'
				'gif':
					mimetype = 'image/gif'
				_:
					continue
			extra = '; filename="' + fname + '"\r\nContent-Type: ' + mimetype
			bytes = value.get_buffer(value.get_len())
		else:
			bytes = value.to_ascii()

		var buf = 'Content-Disposition: form-data; name="' + key + '"' + extra
		body += ('--' + boundary + '\r\n' + buf + '\r\n\r\n').to_ascii()
		body += bytes + '\r\n'.to_ascii()

	body += ('--' + boundary + '--\r\n').to_ascii()

	return http.request_raw(HTTPClient.METHOD_POST, path, headers, body)

func create_card():
	var data = {
		'name': short_text.text,
		'desc': long_text.text + "\n\n**Operating System:** " + OS.get_name(),
	}

	if !trello_labels.empty():
		var type = $VBoxContainer/HBoxContainer/Custom/Type.selected
		data['label_id'] = trello_labels[type].label_trello_id

	var attachment = File.new()
	attachment.open("res://icon.png", File.READ)
	data['attachment'] = attachment
	data['cover_file'] = 'attachment'

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
