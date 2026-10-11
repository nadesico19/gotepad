class_name KataGoTerritoryAnalysisService
extends KataGoAnalysisService


func _ready() -> void:
	if OS.get_name() in ["Android", "iOS"]:
		set_transport(KataGoTerritoryTransport.new())
