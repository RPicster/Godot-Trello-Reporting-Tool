extends "res://addons/gut/test.gd"

func get_trello_state() -> Dictionary:
    var req = HTTPRequest.new()
    add_child_autoqfree(req)

    var url = 'https://api.trello.com/__get_state'
    req.request(url, [], true, HTTPClient.METHOD_GET)

    var response = yield(req, 'request_completed')
    var json = JSON.parse(response[3].get_string_from_utf8())
    assert_eq(json.error, OK)
    return json.result

func test_simple() -> void:
    var scene = load('res://Trello_Reporting_Tool.tscn').instance()
    var basepath = 'Trello_Reporting_Tool/VBoxContainer/HBoxContainer/'
    add_child_autofree(scene)

    # XXX: Ideally the node would be properly parametrizable, so let's override
    #      the variables we need to be changed in the ugliest way possible:
    scene.trello_labels = {
        0: {'label_trello_id': '7f657925d36b4ec9a3406d3a2979b338',
            'label_description': 'Test label 1'},
        1: {'label_trello_id': '89daa2cc49014f0d9c3526d32511c155',
            'label_description': 'Test label 2'},
    }

    get_node(basepath + 'ShortDescEdit').text = 'some report'
    get_node(basepath + 'LongDescEdit').text = 'some report text'
    get_node(basepath + 'Custom/Send').emit_signal('pressed')

    var feedback_node = get_node(basepath + 'Custom/feedback')

    assert_eq(feedback_node.text, 'Your feedback is being sent...')

    var expected = 'Feedback sent successfully, thank you!'
    for timeout in range(60):
        if feedback_node.text == expected:
            break
        yield(yield_for(1), YIELD)

    assert_eq(feedback_node.text, expected)

    var state: Dictionary = yield(get_trello_state(), 'completed')
    var list_id: String = '44b3a1b2db65488e8ba5a9dfba1dd9aa'

    assert_has(state, 'lists')
    assert_has(state['lists'], list_id)

    assert_eq(state['lists'][list_id].size(), 1)
    var cards: Array = state['lists'][list_id]
    assert_eq(cards.size(), 1)
    var card: Dictionary = cards[0]

    var regex = RegEx.new()
    assert_eq(regex.compile('^some report \\[([^]]+)\\]$'), OK)
    var re_match = regex.search(card['name'])
    assert_not_null(re_match)
    var identifier: String = re_match.get_string(1)

    assert_string_starts_with(card['desc'], 'some report text')
    assert_string_contains(card['desc'], 'Operating System:')
    assert_eq(card['pos'], 10.0)

    assert_has(state, 'attachments')
    assert_has(state['attachments'], card.id)
    assert_eq(state['attachments'][card.id].size(), 1)
    var attachment: Dictionary = state['attachments'][card.id][0]

    assert_eq(
        attachment.bytes,
        # SHA-256 of icon.png:
        '2c160bfdb8d0423b958083202dc7b58d499cbef22f28d2a58626884378ce9b7f'
    )

    assert_eq(attachment.name, 'Image-' + identifier)
    assert_eq(attachment.mimeType, 'image/png')
