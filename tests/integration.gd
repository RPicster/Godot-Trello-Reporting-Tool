extends "res://addons/gut/test.gd"

const BASEPATH = 'Trello_Reporting_Tool/Content/Form/'
const FEEDBACK_PATH = 'Trello_Reporting_Tool/Content/Feedback/feedback_label'

func get_trello_state() -> Dictionary:
    var req = HTTPRequest.new()
    add_child_autoqfree(req)

    var url = 'https://api.trello.com/__get_state'
    req.request(url, [], true, HTTPClient.METHOD_GET)

    var response = yield(req, 'request_completed')
    var json = JSON.parse(response[3].get_string_from_utf8())
    assert_eq(json.error, OK)
    return json.result

func assert_feedback(expected: String) -> void:
    assert_eq(get_node(FEEDBACK_PATH).text, expected)

func submit_report(title: String, body: String, label: int = -1) -> void:
    get_node(BASEPATH + 'ShortDescEdit').text = title
    get_node(BASEPATH + 'LongDescEdit').text = body
    if label != -1:
        get_node(BASEPATH + 'Custom/Type').selected = label
    get_node(BASEPATH + 'Custom/Send').emit_signal('pressed')

func wait_for_feedback(expected: String) -> void:
    for timeout in range(60):
        if get_node(FEEDBACK_PATH).text == expected:
            break
        yield(yield_for(1), YIELD)

    assert_feedback(expected)

func before_each() -> void:
    var scene = load('res://src/Trello_Reporting_Tool.tscn').instance()

    # XXX: Ideally the node would be properly parametrizable, so let's override
    #      the variables we need to be changed in the ugliest way possible:
    scene.trello_labels = {
        0: {'label_trello_id': '7f657925d36b4ec9a3406d3a',
            'label_description': 'Test label 1'},
        1: {'label_trello_id': '89daa2cc49014f0d9c3526d3',
            'label_description': 'Test label 2'},
    }

    add_child_autofree(scene)

func test_simple() -> void:
    submit_report('some report \u2b52', 'some report text')
    assert_feedback('Your feedback is being sent...')

    yield(wait_for_feedback('Feedback sent successfully, thank you!'),
          'completed')

    var state: Dictionary = yield(get_trello_state(), 'completed')
    var list_id: String = '44b3a1b2db65488e8ba5a9df'

    assert_has(state, 'lists')
    assert_has(state['lists'], list_id)

    assert_eq(state['lists'][list_id].size(), 1)
    var cards: Array = state['lists'][list_id]
    assert_eq(cards.size(), 1)
    var card: Dictionary = cards[0]

    assert_eq(card['name'], 'some report ⭒')
    assert_string_starts_with(card['desc'], 'some report text')
    assert_string_contains(card['desc'], 'Operating System:')
    assert_eq(card['pos'], 10.0)

    assert_has(state, 'attachments')
    assert_has(state['attachments'], card.id)
    assert_eq(state['attachments'][card.id].size(), 3)

    var names = []

    for attachment in state['attachments'][card.id]:
        names.push_back(attachment['name'])

        match attachment['name']:
            'icon.png':
                assert_eq(attachment['bytes'] as int, 11938)
                assert_eq(
                    attachment['chksum'],
                    # SHA-256 of icon.png:
                    '2cb95be3137bf3d77f6626ee5f3ac79b' +
                    '38eff5ac3142512191c0ba1dfae73f5d'
                )
                assert_eq(attachment['mimeType'], 'image/png')
            _:
                assert_gt(attachment['bytes'] as int, 0)
                assert_eq(attachment['mimeType'], 'image/png')

    names.sort()
    assert_eq(names, ['icon.png', 'noise1.png', 'noise2.png'])

func test_empty_title() -> void:
    submit_report('', 'non-empty')
    assert_feedback('Your feedback is being sent...')

    yield(wait_for_feedback('Error from server: insufficient data'),
          'completed')
