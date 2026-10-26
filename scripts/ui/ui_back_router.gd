## ui_back_router.gd
## W0：安卓系统返回键统一入口。新屏里 add_child(UiBackRouter.new()) 即可，
## 回退目标由 UiNav.register_back_target 注册（未注册则什么也不做）。
class_name UiBackRouter
extends Node


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		UiNav.go_back(get_tree())
