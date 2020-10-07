extends Panel

# Trello Reporting Tool - by Raffaele Picca: twitter.com/MV_Raffa

# You need to get a key and generate a token by visiting this website (And you need to be logged in with the correct account):
# https://trello.com/app-key
var trello_key := "YOUR TRELLO API KEY"
var trello_token := "YOUR TRELLO API TOKEN"
var key_and_token = "?key=" + trello_key + "&token=" + trello_token

# to find the trello list id, the easiest way is to look up your Trello board, create the list you want to use, add a card, 
# click on the card and add ".json" to the url in the top
# you can then search for idList" - string behind that is the list_id below.
var list_id := "YOUR TRELLO LIST ID"

# if you don't want to use labels, just leave this dictionary empty, you can add as many labels as you need by just expanding the library
# to find out the label ids, use the same way as with the list ids. look for the label ids in the Trello json.
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

var current_card_hash := 0
var current_card_id := ""

onready var http = HTTPClient.new()
onready var http_req = $HTTPRequest
onready var short_text = $VBoxContainer/HBoxContainer/ShortDescEdit
onready var long_text = $VBoxContainer/HBoxContainer/LongDescEdit
onready var send_button = $VBoxContainer/HBoxContainer/Custom/Send

enum tasks {IDLE, CREATE_CARD, GET_CARD_ID, ADD_LABEL}
var task = tasks.IDLE

func _ready():
	if !trello_labels.empty():
		for i in range(trello_labels.size()):
			$VBoxContainer/HBoxContainer/Custom/Type.add_item(trello_labels[i].label_description, i)
		$VBoxContainer/HBoxContainer/Custom/Type.selected = 0
	else:
		$VBoxContainer/HBoxContainer/Custom/Type.hide()

func _on_HTTPRequest_request_completed(_result, response_code, _headers, body):
	if task == tasks.CREATE_CARD:
		print_debug("CREATE_CARD -> " + str(response_code))
		get_card_id()
		return
	
	elif task == tasks.GET_CARD_ID and current_card_id == "":
		print_debug("GET_CARD_ID -> " + str(response_code))
		var dict_result = parse_json(body.get_string_from_utf8())
		for i in dict_result:
			if str(current_card_hash) in i.name:
				current_card_id = i.id
				if !trello_labels.empty():
					add_label_to_card()
				add_attachment()
				return
	
	elif task == tasks.ADD_LABEL:
		print_debug("ADD_LABEL -> " + str(response_code))

func _on_Send_pressed():
	create_card()
	show_feedback()
	send_button.disabled = true

func get_card_id():
	task = tasks.GET_CARD_ID
	var query = "https://api.trello.com/1/lists/"+list_id+"/cards" + key_and_token
	http_req.request(query, [], true, HTTPClient.METHOD_GET)

func create_card():
	task = tasks.CREATE_CARD
	
	current_card_hash = str(str(OS.get_unique_id()) + str(OS.get_ticks_msec()) + str(OS.get_datetime()) ).hash()
	var current_card_title = str( short_text.text + " [" + str( current_card_hash ) + "]")
	var current_card_desc = long_text.text
	current_card_desc += "\n\n**Operating System:** " + OS.get_name()
	
	var query = "https://api.trello.com/1/cards" + key_and_token
	query += "&idList=" + list_id
	query += "&name=" + current_card_title.percent_encode()
	query += "&desc=" + current_card_desc.percent_encode()
	query += "&pos=top"
	
	http_req.request(query, [], true, HTTPClient.METHOD_POST)

func add_label_to_card():
	task = tasks.ADD_LABEL
	var type = $VBoxContainer/HBoxContainer/Custom/Type.selected
	var query = "https://api.trello.com/1/cards/"+current_card_id+"/idLabels" + key_and_token + "&value=" + trello_labels[type].label_trello_id
	http_req.request(query, [], true, HTTPClient.METHOD_POST)

func attachment_get_body():
	# The default icon.png is attached, you can attach any file, just change the Content-Type in the body part below to match the file type:
	# https://developer.mozilla.org/en-US/docs/Web/HTTP/Basics_of_HTTP/MIME_types/Common_types
	var file = File.new()
	file.open("res://icon.png", File.READ)
	var file_content = file.get_buffer(file.get_len())
	file.close()
	
	
	# create the body of the multipart/form-data , change the "Content-Type" if you want to send something else than an image.
	var boundary_start = "--GodotFileUploadBoundaryZ29kb3RmaWxl\r\n".to_ascii()
	var body = boundary_start
	body += ("Content-Disposition: form-data; name=\"key\"\r\n\r\n" + trello_key + "\r\n").to_ascii()
	body += boundary_start
	body += ("Content-Disposition: form-data; name=\"token\"\r\n\r\n" + trello_token + "\r\n").to_ascii()
	body += boundary_start
	body += ("Content-Disposition: form-data; name=\"name\"\r\n\r\nImage-"+str(current_card_hash)+"\r\n").to_ascii()
	body += boundary_start
	body += ("Content-Disposition: form-data; name=\"setCover\"\r\n\r\ntrue\r\n").to_ascii()
	body += boundary_start
	body += ("Content-Disposition: form-data; name=\"file\"; filename=\"Image_"+str(current_card_hash)+".png\"\r\nContent-Type: image/png\r\n\r\n").to_ascii()
	body += file_content
	body += ("\r\n--GodotFileUploadBoundaryZ29kb3RmaWxl--\r\n").to_ascii()
	
	return body

func add_attachment():
	# setup the header for sending attachments via multipart
	var headers = ["Content-Type: multipart/form-data; boundary=GodotFileUploadBoundaryZ29kb3RmaWxl"]
	var path = "/1/cards/"+ current_card_id +"/attachments"
	
	http.connect_to_host("https://api.trello.com", -1, true, false)

	while http.get_status() == HTTPClient.STATUS_CONNECTING or http.get_status() == HTTPClient.STATUS_RESOLVING:
		http.poll()
		OS.delay_msec(50)
	
	var err = http.request_raw(HTTPClient.METHOD_POST, path, headers, attachment_get_body())
	
	while http.get_status() == HTTPClient.STATUS_REQUESTING:
		http.poll()
		if not OS.has_feature("web"):
			OS.delay_msec(50)
		else:
			yield(Engine.get_main_loop(), "idle_frame")
	$VBoxContainer/HBoxContainer/Custom/feedback.text = "Feedback sent successfully, thank you!"

func show_feedback():
	#disable all input fields and show a short message about the current status
	send_button.hide()
	short_text.editable = false
	long_text.readonly = true
	$VBoxContainer/HBoxContainer/Custom/Type.hide()
	$VBoxContainer/HBoxContainer/Custom/feedback.show()
	$VBoxContainer/HBoxContainer/Custom/feedback.text = "Your feedback is being sent..."

func _on_ShortDescEdit_text_changed(_new_text):
	update_send_button()

func _on_LongDescEdit_text_changed():
	update_send_button()

func update_send_button():
	# check if text is entered, if not, disable the send button
	send_button.disabled = (long_text.text == "" or short_text.text == "")
