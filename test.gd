extends "res://addons/gut/test.gd"

func test_simple() -> void:
    var scene = load('res://Trello_Reporting_Tool.tscn').instance()
    var basepath = 'Trello_Reporting_Tool/VBoxContainer/HBoxContainer/'
    add_child_autofree(scene)

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
