extends CanvasLayer

var resource: DialogueResource
var temporary_game_states: Array = []
var is_dialogue_finished: bool = false

@onready var scroll_container: ScrollContainer = $Control/MainPanel/VBoxMain/ScrollContainer
@onready var chat_list: VBoxContainer = $Control/MainPanel/VBoxMain/ScrollContainer/ChatList
@onready var responses_menu: VBoxContainer = $Control/MainPanel/VBoxMain/ResponsesMenu

var dialogue_line: DialogueLine:
	set(next_dialogue_line):
		if not next_dialogue_line:
			finish_dialogue()
			return
			
		dialogue_line = next_dialogue_line
		add_message_to_chat(dialogue_line)

func _ready() -> void:
	responses_menu.hide()
	
	# ВАЖНО: Настраиваем фильтры мыши, чтобы клики по пустым местам 
	# проходили сквозь UI и достигали _unhandled_input
	$Control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$Control/MainPanel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$Control/MainPanel/VBoxMain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll_container.mouse_filter = Control.MOUSE_FILTER_PASS

# Заменяем _input на _unhandled_input
func _unhandled_input(event: InputEvent) -> void:
	# Проверяем ЛКМ или клавиши подтверждения/отмены
	var is_left_click = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	if is_left_click or event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
		
		# Если диалог завершен — закрываем чат
		if is_dialogue_finished:
			get_viewport().set_input_as_handled()
			close_chat()
		
		# Если диалог еще идет, но у текущей реплики НЕТ вариантов ответа — переходим к следующей
		elif dialogue_line and dialogue_line.responses.size() == 0:
			get_viewport().set_input_as_handled()
			next(dialogue_line.next_id)

# Добавление сообщения NPC или игрока в чат
func add_message_to_chat(line: DialogueLine) -> void:
	var row = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 12)
	
	var avatar = Panel.new()
	avatar.custom_minimum_size = Vector2(44, 44)
	avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var bubble = PanelContainer.new()
	bubble.custom_minimum_size = Vector2(480, 0)
	bubble.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN if line.character == "NPC" else Control.SIZE_SHRINK_END
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var label = RichTextLabel.new()
	label.text = line.text
	label.fit_content = true
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	bubble.add_child(label)
	
	if line.character == "NPC":
		row.add_child(avatar)
		row.add_child(bubble)
	else:
		row.add_child(bubble)
		row.add_child(avatar)
		
	chat_list.add_child(row)
	
	# Прокрутка вниз
	await get_tree().process_frame
	scroll_container.scroll_vertical = int(scroll_container.get_v_scroll_bar().max_value)

	# Очистка и создание кнопок
	for child in responses_menu.get_children():
		child.queue_free()
		
	if line.responses.size() > 0:
		for response in line.responses:
			var btn = Button.new()
			btn.text = response.text
			btn.custom_minimum_size = Vector2(0, 48)
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.mouse_filter = Control.MOUSE_FILTER_STOP # Кнопка ловит клики
			btn.pressed.connect(func(): 
				add_player_choice_to_chat(response.text)
				next(response.next_id)
			)
			responses_menu.add_child(btn)
		responses_menu.show()
	else:
		responses_menu.hide()

# Добавление ответа игрока в историю
func add_player_choice_to_chat(text: String) -> void:
	var row = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 12)
	
	var avatar = Panel.new()
	avatar.custom_minimum_size = Vector2(48, 48)
	avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var bubble = PanelContainer.new()
	bubble.custom_minimum_size = Vector2(350, 0)
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var label = RichTextLabel.new()
	label.text = text
	label.fit_content = true
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(330, 24)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	bubble.add_child(label)
	row.add_child(bubble)
	row.add_child(avatar)
	
	chat_list.add_child(row)

func next(next_id: String) -> void:
	self.dialogue_line = await DialogueManager.get_next_dialogue_line(resource, next_id, temporary_game_states)

# Завершение диалога — вывод кнопки «Закрыть»
# Завершение диалога — просто скрываем меню ответов
func finish_dialogue() -> void:
	is_dialogue_finished = true
	
	for child in responses_menu.get_children():
		child.queue_free()
		
	responses_menu.hide()

# Закрытие и удаление балуна
func close_chat() -> void:
	var player = get_tree().get_first_node_in_group("player")
	if player:
		player.can_move = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	queue_free()

func start(dialogue_resource: DialogueResource, title: String = "start", extra_game_states: Array = []) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE # Показываем курсор при старте диалога
	temporary_game_states = extra_game_states
	resource = dialogue_resource
	self.dialogue_line = await DialogueManager.get_next_dialogue_line(resource, title, temporary_game_states)
