@tool
extends ScrollContainer

# Referencias a los nodos
@onready var picker_r: EditorResourcePicker = $VBox/Textures/R/VBoxContainer/HBoxContainer2/PanelContainer2/Picker
@onready var picker_g: EditorResourcePicker = $VBox/Textures/G/VBoxContainer/HBoxContainer2/PanelContainer2/Picker
@onready var picker_b: EditorResourcePicker = $VBox/Textures/B/VBoxContainer/HBoxContainer2/PanelContainer2/Picker
@onready var picker_a: EditorResourcePicker = $VBox/Textures/A/VBoxContainer/HBoxContainer2/PanelContainer2/Picker
@onready var invert_box_r: CheckBox = $VBox/Textures/R/VBoxContainer/HBoxContainer/PanelContainer/InvertBox
@onready var invert_box_g: CheckBox = $VBox/Textures/G/VBoxContainer/HBoxContainer/PanelContainer/InvertBox
@onready var invert_box_b: CheckBox = $VBox/Textures/B/VBoxContainer/HBoxContainer/PanelContainer/InvertBox
@onready var invert_box_a: CheckBox = $VBox/Textures/A/VBoxContainer/HBoxContainer/PanelContainer/InvertBox
@onready var channel_option_r: OptionButton = $VBox/Textures/R/VBoxContainer/HBoxContainer3/ChannelOption
@onready var channel_option_g: OptionButton = $VBox/Textures/G/VBoxContainer/HBoxContainer3/ChannelOption
@onready var channel_option_b: OptionButton = $VBox/Textures/B/VBoxContainer/HBoxContainer3/ChannelOption
@onready var channel_option_a: OptionButton = $VBox/Textures/A/VBoxContainer/HBoxContainer3/ChannelOption

@onready var preview_rect: TextureRect = $VBox/Preview/VBoxContainer/PreviewContainer/MarginContainer/TextureRect
@onready var save_button: Button = $VBox/SaveAction/SaveButton
@onready var pack_button: Button = $VBox/Actions/HBoxContainer2/PackButton
@onready var clean_preview: Button = $VBox/Actions/HBoxContainer2/CleanPreview
@onready var preview_channel: OptionButton = $VBox/Preview/VBoxContainer/PreviewChannel
@onready var size_selector: OptionButton = $VBox/Actions/HBoxContainer/SizeSelector
@onready var resampling_selector: OptionButton = $VBox/Actions/HBoxContainer3/ResamplingSelector

# Texturas seleccionadas
var texture_r: Texture2D = null
var texture_g: Texture2D = null
var texture_b: Texture2D = null
var texture_a: Texture2D = null

# Imagen resultante
var packed_image: Image = null


func _ready() -> void:
	_setup_picker(picker_r, "R")
	_setup_picker(picker_g, "G")
	_setup_picker(picker_b, "B")
	_setup_picker(picker_a, "A")
	pack_button.pressed.connect(_on_pack_textures)
	save_button.pressed.connect(_on_save_image)
	clean_preview.pressed.connect(_on_clean_preview)
	preview_channel.item_selected.connect(_on_preview_channel_changed)
	save_button.disabled = true


func _setup_picker(picker: EditorResourcePicker, channel: String) -> void:
	picker.base_type = "Texture2D"
	picker.editable = true
	picker.resource_changed.connect(
		func(res: Resource) -> void:
			_on_texture_changed(res, channel)
	)


func _on_texture_changed(resource: Resource, channel: String) -> void:
	var tex := resource as Texture2D
	if   channel == "R": texture_r = tex
	elif channel == "G": texture_g = tex
	elif channel == "B": texture_b = tex
	elif channel == "A": texture_a = tex


# Descomprime la imagen si está en un formato comprimido (DXT, ETC, BPTC, etc.)
func _decompress_image(img: Image) -> Image:
	if img.is_compressed():
		var copy := img.duplicate()
		var err: Error = copy.decompress()
		if err != OK:
			printerr("ARM Tool: can not pack image, format: ", img.get_format())
			return img
		return copy
	return img

func _get_image_for_channel(tex: Texture2D, w: int, h: int, white_fill: bool, selected: int, interp: int = Image.INTERPOLATE_LANCZOS) -> PackedByteArray:
	if tex == null:
		var blank := PackedByteArray()
		blank.resize(w * h)
		blank.fill(255 if white_fill else 0)
		return blank

	var img: Image = tex.get_image().duplicate()

	# Descomprimir si es necesario antes de cualquier conversión
	img = _decompress_image(img)

	# Redimensionar ANTES de convertir para evitar padding inesperado
	if img.get_width() != w or img.get_height() != h:
		img.resize(w, h, interp)

	# Convertir a RGBA8 para tener siempre 4 bytes por píxel bien definidos
	img.convert(Image.FORMAT_RGBA8)

	return _extract_channel(img, selected)

func _on_pack_textures() -> void:
	if texture_r == null and texture_g == null and texture_b == null and texture_a == null:
		printerr("ARM Tool: select at least one texture.")
		return

	# Tamaño de referencia
	var ref: Texture2D = texture_r if texture_r else \
						  texture_g if texture_g else \
						  texture_b if texture_b else texture_a
	var ref_img: Image = _decompress_image(ref.get_image().duplicate())
	
	# Resolución de salida: 0=Original, 1=512, 2=1024, 3=2048, 4=4096
	const SIZES: Array = [0, 512, 1024, 2048, 4096]
	var chosen: int = SIZES[size_selector.selected]
	var w: int = chosen if chosen > 0 else ref_img.get_width()
	var h: int = chosen if chosen > 0 else ref_img.get_height()
	
	# Modo de resampleo: 0=Nearest, 1=Bilinear, 2=Lanczos
	const INTERP: Array = [Image.INTERPOLATE_NEAREST, Image.INTERPOLATE_BILINEAR, Image.INTERPOLATE_LANCZOS]
	var interp: int = INTERP[resampling_selector.selected]
	
	# Obtener los bytes de cada canal
	var ch_r: PackedByteArray = _get_image_for_channel(texture_r, w, h, false, channel_option_r.selected, interp)
	var ch_g: PackedByteArray = _get_image_for_channel(texture_g, w, h, false, channel_option_g.selected, interp)
	var ch_b: PackedByteArray = _get_image_for_channel(texture_b, w, h, false, channel_option_b.selected, interp)
	var ch_a: PackedByteArray = _get_image_for_channel(texture_a, w, h, true, channel_option_a.selected, interp)

	# Aplicar inversión si el checkbox está marcado
	if invert_box_r.button_pressed: ch_r = _invert_channel(ch_r)
	if invert_box_g.button_pressed: ch_g = _invert_channel(ch_g)
	if invert_box_b.button_pressed: ch_b = _invert_channel(ch_b)
	if invert_box_a.button_pressed: ch_a = _invert_channel(ch_a)
	
	# Validar que todos los canales tienen el tamaño correcto
	var expected: int = w * h
	if ch_r.size() != expected or ch_g.size() != expected or ch_b.size() != expected or ch_a.size() != expected:
		printerr("ARM Tool: wrong channel size. R=%d G=%d B=%d A=%d (esperado %d)" % [
			ch_r.size(), ch_g.size(), ch_b.size(), ch_a.size(), expected
		])
		return

	# Construir el buffer RGBA final
	var dst := PackedByteArray()
	dst.resize(expected * 4)
	for i in expected:
		dst[i * 4 + 0] = ch_r[i]
		dst[i * 4 + 1] = ch_g[i]
		dst[i * 4 + 2] = ch_b[i]
		dst[i * 4 + 3] = ch_a[i]

	packed_image = Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, dst)

	save_button.disabled = false
	_update_preview()
	print("ARM Tool: packed OK — %dx%d" % [w, h])


func _on_save_image() -> void:
	if packed_image == null:
		printerr("ARM Tool: first pack textures.")
		return

	var file_dialog := EditorFileDialog.new()
	file_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	file_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	file_dialog.add_filter("*.png", "PNG Image")
	file_dialog.file_selected.connect(_save_packed_image)
	EditorInterface.get_base_control().add_child(file_dialog)
	file_dialog.popup_centered_ratio(0.6)


func _save_packed_image(path: String) -> void:
	if not path.ends_with(".png"):
		path += ".png"
	var err: Error = packed_image.save_png(path)
	if err == OK:
		print("ARM Tool: imagen guardada en ", path)
		EditorInterface.get_resource_filesystem().scan()
	else:
		printerr("ARM Tool: error al guardar — código ", err)

func _invert_channel(data: PackedByteArray) -> PackedByteArray:
	var result := data.duplicate()
	for i in result.size():
		result[i] = 255 - result[i]
	return result

# Extrae el canal seleccionado en el OptionButton (0=R, 1=G, 2=B, 3=A, 4=Luminance)
func _extract_channel(img: Image, selected: int) -> PackedByteArray:
	var w: int = img.get_width()
	var h: int = img.get_height()
	var pixel_count: int = w * h
	var result := PackedByteArray()
	result.resize(pixel_count)

	if selected == 4:
		# Luminance: brillo perceptual (0.299R + 0.587G + 0.114B)
		var rgba := img.get_data()  # FORMAT_RGBA8 garantizado antes de llamar esto
		for i in pixel_count:
			var r: float = rgba[i * 4 + 0] / 255.0
			var g: float = rgba[i * 4 + 1] / 255.0
			var b: float = rgba[i * 4 + 2] / 255.0
			result[i] = int((0.299 * r + 0.587 * g + 0.114 * b) * 255.0)
	else:
		# R=0, G=1, B=2, A=3 — coincide con el offset en RGBA8
		var rgba := img.get_data()
		for i in pixel_count:
			result[i] = rgba[i * 4 + selected]
	
	return result

func _on_preview_channel_changed(_index: int) -> void:
	_update_preview()

func _update_preview() -> void:
	if packed_image == null:
		return

	var selected: int = preview_channel.selected
	var w: int = packed_image.get_width()
	var h: int = packed_image.get_height()
	var src := packed_image.get_data()
	var pixel_count: int = w * h

	# Standard: mostrar la imagen RGBA tal cual
	if selected == 0:
		preview_rect.texture = ImageTexture.create_from_image(packed_image)
		return
	
	# Alpha: componer el canal A sobre un fondo checker
	if selected == 4:
		preview_rect.texture = ImageTexture.create_from_image(_make_alpha_checker(src, w, h, pixel_count))
		return
	
	# Canal aislado en escala de grises (1=R, 2=G, 3=B, 4=A)
	var channel_index: int = selected - 1  # 0=R, 1=G, 2=B, 3=A en RGBA8
	var dst := PackedByteArray()
	dst.resize(pixel_count * 4)
	for i in pixel_count:
		var value: int = src[i * 4 + channel_index]
		dst[i * 4 + 0] = value
		dst[i * 4 + 1] = value
		dst[i * 4 + 2] = value
		dst[i * 4 + 3] = 255

	var isolated := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, dst)
	preview_rect.texture = ImageTexture.create_from_image(isolated)

func _make_alpha_checker(src: PackedByteArray, w: int, h: int, pixel_count: int) -> Image:
	const TILE: int = 16        # tamaño de cada cuadro del checker en píxeles
	const LIGHT: int = 204      # gris claro  (#CCCCCC)
	const DARK: int  = 128      # gris oscuro (#808080)

	var dst := PackedByteArray()
	dst.resize(pixel_count * 4)

	for i in pixel_count:
		var x: int = i % w
		var y: int = i / w
		var alpha: float = src[i * 4 + 3] / 255.0

		# Color del checker en este píxel
		var checker: int = LIGHT if ((x / TILE + y / TILE) % 2 == 0) else DARK

		# Mezclar el checker con el alpha del píxel
		var out: int = int(checker * (1.0 - alpha) + 255.0 * alpha)
		dst[i * 4 + 0] = out
		dst[i * 4 + 1] = out
		dst[i * 4 + 2] = out
		dst[i * 4 + 3] = 255

	return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, dst)

func _on_clean_preview():
	picker_r.set_edited_resource(null)
	picker_g.set_edited_resource(null)
	picker_b.set_edited_resource(null)
	picker_a.set_edited_resource(null)
	invert_box_r.button_pressed = false
	invert_box_g.button_pressed = false
	invert_box_b.button_pressed = false
	invert_box_a.button_pressed = false
	texture_r = null
	texture_g = null
	texture_b = null
	texture_a = null
	preview_rect.texture = null
	packed_image = null
	save_button.disabled = true
