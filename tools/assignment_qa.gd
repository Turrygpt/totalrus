extends SceneTree
var failures:=[]
func _initialize() -> void:call_deferred("run")
func check(ok:bool,message:String) -> void:
	print("PASS " if ok else "FAIL ",message)
	if not ok:failures.append(message)
func cost(slots:Array[Vector3],units:Array,result:PackedInt32Array) -> float:
	var value:=0.0
	for i in units.size():value+=units[i].position.distance_squared_to(slots[result[i]])
	return value
func run() -> void:
	change_scene_to_file("res://tools/front_qa_world.tscn")
	await create_timer(1).timeout
	var world=current_scene;var g=world.squad
	check(world.crowd_movement.native.has_method("assign_slots"),"native formation assignment loaded")
	var rng:=RandomNumberGenerator.new();rng.seed=871
	var native_us:=0;var gd_us:=0
	for n in [0,1,6,30,60]:
		var units:Array=g.soldiers.slice(0,n)
		for scenario in 3:
			var slots:Array[Vector3]=[]
			for i in n:slots.append(Vector3(rng.randf_range(-20,20),0,rng.randf_range(-25,15)))
			var t:=Time.get_ticks_usec();var fast:PackedInt32Array=g.assign_slots(slots,units);native_us+=Time.get_ticks_usec()-t
			t=Time.get_ticks_usec();var reference:PackedInt32Array=g.assign_slots_gd(slots,units);gd_us+=Time.get_ticks_usec()-t
			var unique:={}
			for slot in fast:unique[slot]=true
			check(fast.size()==n and unique.size()==n and absf(cost(slots,units,fast)-cost(slots,units,reference))<.02,"assignment matches optimal cost, N=%d case=%d"%[n,scenario])
	print("ASSIGNMENT_QA ",JSON.stringify({"failures":failures,"native_us":native_us,"gdscript_us":gd_us}))
	world.queue_free();await process_frame;await process_frame;quit(0 if failures.is_empty() else 1)
