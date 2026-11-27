extends SceneTree
func _initialize() -> void:
	if not ClassDB.class_exists("CrowdNative"):
		print("NO_NATIVE"); quit(1); return
	var solver=ClassDB.instantiate("CrowdNative")
	var state:=PackedFloat32Array([0,0,0,0,10,0,0,0,3.6,1,1,0,2,0,0,0,-10,0,0,0,3.6,1,1,0])
	var original:=state.duplicate()
	for i in 200:
		state=solver.call("step",state,.05)
		assert(Vector2(state[2],state[3]).length()<=3.601,"speed cap")
		assert(Vector2(state[12]-state[0],state[13]-state[1]).length()>=.50,"body separation")
	assert(state[0]>2 and state[12]<0,"head-on walkers pass instead of jamming")
	assert(original[0]==0 and original[12]==2,"input array unchanged")
	assert(solver.call("step",PackedFloat32Array(),.05).is_empty(),"empty input")
	state=original.duplicate()
	for i in 70:
		state=solver.call("step",state,.2)
		assert(Vector2(state[12]-state[0],state[13]-state[1]).length()>=.50,"accelerated simulation keeps body separation")
	assert(state[0]>2 and state[12]<0,"accelerated simulation passes head-on")
	var far_state := PackedFloat32Array([350,600,0,0,375,620,0,0,3.6,1,1,0])
	for i in 40: far_state = solver.call("step_bounded",far_state,.05,419.4,644.4)
	assert(far_state[0]>352 and far_state[1]>602,"movement reaches the expanded back corner")
	far_state[0]=419.2;far_state[1]=644.2;far_state[4]=440.0;far_state[5]=660.0
	for i in 40: far_state = solver.call("step_bounded",far_state,.05,419.4,644.4)
	assert(absf(far_state[0]-419.4)<.001 and absf(far_state[1]-644.4)<.001,"movement stops at the expanded boundary")
	var base:=PackedFloat32Array();base.resize(40);base[12]=.3;base[16]=17
	var old:=PackedFloat32Array([0,0,0,0,0,0,0,0,0,1,1,0])
	var now:=old.duplicate();now[0]=2;now[1]=4;now[6]=PI
	var buffer:PackedFloat32Array=solver.call("render_buffer",base,PackedFloat32Array([0,-1]),now,old,.5)
	assert(absf(buffer[3]-1)<.0001 and absf(buffer[11]-2)<.0001,"interpolated translation")
	assert(absf(buffer[12]-.3)<.0001 and buffer[16]==17,"instance color and animation preserved")
	for i in range(20,32): assert(buffer[i]==0,"released instance hidden")
	base[23] = 42.0
	buffer = solver.call("render_grounded_buffer",base,PackedFloat32Array([0,-2]),now,old,.5,PackedFloat32Array([5,8]))
	assert(is_equal_approx(buffer[7],6.5),"terrain height is interpolated with planar motion")
	assert(buffer[23] == 42.0,"static transforms survive the packed upload")
	var ground := PackedFloat32Array([0,2,4,12])
	var ground_config := PackedFloat32Array([2,2,1,1,2,2])
	var terrain_points := PackedFloat32Array([
		-.5,-.5,0,0,0,0,0,0,0,1,1,0,
		.5,.5,0,0,0,0,0,0,0,1,1,0,
	])
	var projected: PackedFloat32Array = solver.call("project_terrain",terrain_points,ground,ground_config)
	assert(is_equal_approx(projected[1],1.5) and is_equal_approx(projected[4],7.5),"both heightfield triangles")
	terrain_points[0] = 0
	terrain_points[1] = 0
	ground_config.append_array(PackedFloat32Array([0,0,.6]))
	projected = solver.call("project_terrain",terrain_points,ground,ground_config)
	assert(is_equal_approx(projected[0],.6) and is_equal_approx(projected[1],5.4) and projected[2] == 0.0,"obstacle edge projected onto the heightfield")
	projected = solver.call("project_terrain",terrain_points,ground,PackedFloat32Array())
	assert(projected.is_empty(),"rejects a missing grid configuration")
	var visibility := PackedFloat32Array()
	visibility.resize(60)
	visibility[0] = 1.0
	visibility[3] = 50.0
	visibility[20] = 1.0
	visibility[23] = 2.0
	visibility[39] = .5
	buffer = solver.call("compact_render_buffer",visibility,PackedFloat32Array([1,0,0,10]),3,4.0)
	assert(solver.call("visible_render_count") == 1,"render culling removes off-screen and unused slots")
	assert(buffer[3] == 2.0 and buffer[19] == .5 and visibility[3] == 50.0,"render culling preserves the visible transform and animation data")
	var empty := PackedFloat32Array()
	var planes := PackedFloat32Array([1,0,0,10])
	var height_samples := PackedFloat32Array([5,8])
	assert(solver.call("prepare_render_frame",now,old,height_samples,empty,empty,planes,.5)==1,"one cached actor pose")
	buffer = solver.call("assemble_render_batch",base,PackedFloat32Array([-1,0]),2,4.0)
	assert(solver.call("visible_render_count")==1,"cached batches compact a released slot")
	assert(is_equal_approx(buffer[3],1.0) and is_equal_approx(buffer[7],6.5) and is_equal_approx(buffer[11],2.0),"cached pose matches grounded interpolation")
	buffer = solver.call("assemble_render_batch",visibility,PackedFloat32Array([-2,-2,-1]),3,4.0)
	assert(solver.call("visible_render_count")==1 and buffer[3]==2.0 and buffer[19]==.5,"static slots retain their transforms and animation")
	var mounted := old.duplicate()
	mounted[11] = 8
	var slope := PackedFloat32Array([0,0,1,1])
	var slope_config := PackedFloat32Array([2,2,4,4,8,8])
	solver.call("prepare_render_frame",mounted,mounted,PackedFloat32Array([.5,.5]),slope,slope_config,empty,1.0)
	buffer = solver.call("assemble_render_batch",base,PackedFloat32Array([0,-1]),1,-1.0)
	assert(is_equal_approx(buffer[6],sin(atan(.125))) and is_equal_approx(buffer[7],.5),"mounted cached pose pitches with the terrain")
	print("NATIVE ",state)
	for gap_test in [[19,23,1.39],[27,31,2.35]]:
		state=PackedFloat32Array([0,0,0,0,0,-5,0,0,3.6,1,1,gap_test[0],0,-5,0,0,0,0,PI,PI,3.6,1,1,gap_test[1]])
		for i in 120:state=solver.call("step",state,.05)
		assert(Vector2(state[12]-state[0],state[13]-state[1]).length()>=gap_test[2],"weapon space / mounted footprint")
	print("NATIVE_QA PASS")
	quit()
