class_name ImGuiConfig extends Resource

@export_category("Font Settings")
@export var Fonts: Array[ImGuiFont]
@export var AddDefaultFont: bool = true

@export_category("Other")
@export_range(0.25, 4.0, 0.001, "or_greater") var Scale: float = 1.0
@export var IniFilename: String = "user://imgui.ini"
@export_enum("RenderingDevice", "Canvas", "Dummy") var Renderer: String = "RenderingDevice"
@export_range(-128, 128) var Layer: int = 128
