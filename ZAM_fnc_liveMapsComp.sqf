comment '
	Function: MAZ_fnc_makeNewMapDisplay
	Author: Expung3d
	Description: Creates a new live map display on an object that can take a texture screen.
	Example: [cursorObject] spawn MAZ_fnc_makeNewMapDisplay;
	Params:
		0: Map object that displays the map.
';

comment '
	Function: MAZ_fnc_makeMapDisplayCtrl
	Author: Expung3d
	Description: This function should not be manually ran. The system will call this when necessary. 
				 !! Excess calls can reduce performance !!
	Params: 
		0: Name of the map display. Automatically made and handled by the system.
		1: Map object that displays the map.
';

comment "
	Function: MAZ_fnc_setMapDisplayData
	Author: Expung3d
	Description: Directly and immediately changes the position of the map display. Removes the queue of animations.
	Example: [cursorObject,0,0.02,getPos player] call MAZ_fnc_setMapDisplayData;
	Example 2: [cursorObject,0,1,[worldSize/2,worldSize/2]] call MAZ_fnc_setMapDisplayData;
	Params:
		0: Map object that displays the map.
		1: Time to commit. A number in seconds.
		2: Scale for the map, between 0.001 and 1.
		3: Position for the map to center on.
";

if(isNil "MAZ_fnc_makeNewMapDisplay") then {
	MAZ_liveMapCount = 0;
	publicVariable "MAZ_liveMapCount";

	private _varName = "MAZ_System_LiveMaps";
	private _myJIPCode = "MAZ_LiveMaps_JIP";

	private _value = (str {
		MAZ_fnc_makeNewMapDisplay = {
			params ["_object"];
			[[_object],MAZ_fnc_makeNewMapDisplayExec] call MAZ_EP_fnc_addToExecQueue;
		};

		MAZ_fnc_makeNewMapDisplayExec = {
			params ["_object"];
			private _name = format ["MAZ_liveMap_%1",MAZ_liveMapCount];
			MAZ_liveMapCount = MAZ_liveMapCount + 1;
			publicVariable "MAZ_liveMapCount";
			_object setVariable ["MAZ_map_name",_name,true];
			[_object,0,0.02,getPos _object] call MAZ_fnc_setMapDisplayData;
			[[_name,_object], {
				params ["_name","_object"];
				if(isNull _object) exitWith {};
				waitUntil {!isNull (findDisplay 46) && alive player};
				waitUntil {!isNil "MAZ_fnc_addMapActions"};
				[_name,_object] spawn MAZ_fnc_makeMapDisplayCtrl;
				[_object] call MAZ_fnc_addMapActions;
			}] remoteExec ['spawn',0,_object];
		};

		MAZ_fnc_makeMapDisplayCtrl = {
			params ["_name","_object"];
			waitUntil {uiSleep 0.1; player distance _object < 300 && !visibleMap};
			private _texture = format ["#(rgb,1024,1024,1)ui('RscDisplayEmpty','%1')",_name];
			private _textureIndex = [_object] call MAZ_fnc_getMapTextureIndex;
			_object setObjectTexture [_textureIndex,""];
			sleep 0.1;
			_object setObjectTexture [_textureIndex,_texture];
			sleep 0.1;
			private _display = findDisplay _name;
			if(isNull _display) exitWith {
				private _counter = _object getVariable ["MAZ_map_tryCount",0];
				if(_counter >= 3) then {
					systemChat "Failed to create display.";
				} else {
					if(!isMultiplayer) then {
						systemChat "Failed to create display... trying again.";
						systemChat format ["Distance to object: %1. View Distance: %2",(getPos player) distance _object, viewDistance];
					};
					_object setVariable ["MAZ_map_tryCount",_counter + 1, true];
					[_name,_object] spawn MAZ_fnc_makeMapDisplayCtrl;
				};
			};
			sleep 0.1;
			_display setVariable ["MAZ_map_mapObject",_object];
			private _waitingToLoad = _display ctrlCreate ["RscStructuredText",11];
			_waitingToLoad ctrlSetStructuredText parseText "<t align='center'>Loading map...</t>";
			_waitingToLoad ctrlSetTextColor [1,1,1,1];
			private _ctrlTextWidth = ctrlTextWidth _waitingToLoad;
			_waitingToLoad ctrlSetPosition [0,0.5,1,0.1];
			_waitingToLoad ctrlCommit 0;
			displayUpdate _display;

			if(isNull _object) exitWith {};
			sleep 0.5;
			private _mapCtrl = _display ctrlCreate ["RscMapControl",10];
			_mapCtrl ctrlSetPosition [0,0,1,1];
			_mapCtrl ctrlMapSetPosition [0,0,1,1];
			_mapCtrl ctrlCommit 0;
			
			private _event = _mapCtrl ctrlAddEventHandler ["Draw", {
				params ["_mapCtrl"];
				private _display = ctrlParent _mapCtrl;

				private _map = _display getVariable ["MAZ_map_mapObject",objNull];
				if(isNull _map) exitWith {
					systemChat "Removing event";
					private _event = _mapCtrl getVariable ["MAZ_map_mapEvent",-1];
					_mapCtrl ctrlRemoveEventHandler ["Draw",_event];
				};

				if !(_map getVariable ["MAZ_map_doDrawUnits",false]) exitWith {};

				private _enemyGroups = (allGroups - _groups) select {
					private _enemyGroup = _x;
					private _known = false;
					{
						if(_x knowsAbout (leader _enemyGroup) > 1.1) then {
							_known = true;
						};
					}forEach _groups;
					_known;
				};

				private _groups = allGroups select {isPlayer (leader _x) && (count (units _x) > 0) && side _x == side group player};

				if(_map getVariable ["MAZ_map_drawAIUnits",false]) then {
					_groups = allGroups select {side _x == side group player};
				};

				private _enemyGroups = [];
				{
					private _group = _x;
					private _groupTargets = [];
					{
						_groupTargets = _groupTargets + (_x call BIS_fnc_enemyTargets);
					}forEach (units _group);
					{
						if(side group _x == side _group) then {continue};
						_enemyGroups pushBackUnique _x;
					}forEach _groupTargets;
				}forEach _groups;
				

				private _fn_isUnitCopilot = {
					if(vehicle _this == _this) exitWith {false};

					private ["_veh", "_cfg", "_trts", "_return", "_trt"];
					_veh = (vehicle _this);
					_cfg = configFile >> "CfgVehicles" >> typeOf(_veh);
					_trts = _cfg >> "turrets";
					_return = false;

					for "_i" from 0 to (count _trts - 1) do {
						_trt = _trts select _i;

						if(getNumber(_trt >> "iscopilot") == 1) exitWith {
							_return = (_veh turretUnit [_i] == _this);
						};
					};

					_return
				};

				private _fnc_getGroupIconString = {
					params ["_leader"];
					private _veh = vehicle _leader;
					if(_veh == _leader) exitWith {"inf"};

					if(!(_leader call _fn_isUnitCopilot) || driver _veh != _leader || commander _veh != _leader || gunner _veh != _leader) exitWith {"inf"};

					if((count (getArray (configFile >> "CfgVehicles" >> (typeOf _veh) >> "availableForSupportTypes")) > 0) && {(getArray (configFile >> "CfgVehicles" >> (typeOf _veh) >> "availableForSupportTypes")) # 0 == "Artillery"}) exitWith {
						private _out = "art";
						if(_veh isKindOf "Mortar_01_base_F") then {_out = "mortar"};
						_out
					};
					if(_veh isKindOf "Wheeled_APC_F") exitWith {"mech_inf"};
					if(_veh isKindOf "Tank") exitWith {"armor"};
					if(_veh isKindOf "Helicopter") exitWith {"air"};
					if(_veh isKindOf "Plane") exitWith {"plane"};
					if(_veh isKindOf "Ship") exitWith {"naval"};
					if(_veh isKindOf "LandVehicle") exitWith {"motor_inf"};
					"unknown"
				};

				private _vehicleList = [];
				{
					if(count ((units _x) select {alive _x}) <= 0) then {continue};
					if((side _x) isEqualTo (side group player)) then {
						_leader = leader _x;
						_pos = (leader _x) modelToWorldVisual [0,0,0];
						_text = (groupId _x);
						
						_alpha = 1;
						_type = [_leader] call _fnc_getGroupIconString;
						_icon = switch (side _x) do {
							case west: {format ["a3\ui_f\data\map\markers\nato\b_%1.paa",_type]};
							case east: {format ["a3\ui_f\data\map\markers\nato\o_%1.paa",_type]};
							case independent: {format ["a3\ui_f\data\map\markers\nato\n_%1.paa",_type]};
							default {"a3\ui_f\data\map\markers\nato\o_unknown.paa"};
						};
						_color = [side _x] call BIS_fnc_sideColor;
						
						if((group player) isEqualTo _x) then {
							_color = [0.1,0.5,0.5,_alpha];
						};
						
						_pos2D = _mapCtrl ctrlMapWorldToScreen _pos;
						_posCursor2D = getMousePosition;
						_dist = _pos2D distance2D _posCursor2D;
						_scale = ctrlMapScale _mapCtrl;
			
						_mapCtrl drawIcon
						[
							_icon,
							_color,
							_pos,
							25,
							25,
							0,
							_text,
							2,
							0.05,
							"RobotoCondensedBold",
							"left"
						];
		
						_mapCtrl drawIcon
						[
							_icon,
							_color,
							_pos,
							25,
							25,
							0,
							_text,
							1,
							0.05,
							"RobotoCondensedBold",
							"left"
						];

						comment '{
							if !((vehicle _x) in _vehicleList) then {
								_vehicleList pushback vehicle _x;
			
								_dir = getDir vehicle _x;
			
								_className = (typeOf vehicle _x);
								_file = getText (configfile >> "CfgVehicles" >> _className >> "icon");
			
								_driver = driver vehicle _x;
			
								_vehName = getText (configfile >> "CfgVehicles" >> _className >> "displayName");
								_text = _vehName;
			
								_text2 = "";
								_count = count crew vehicle _x;
								if(_count > 1) then {
									_text2 = ((name _driver) + " + " + (str (_count-1)) + " more");
								} else {
									_text2 = (name _driver);
								};
								if((_scale > 0.0045) && (_dist > 0.02)) then {_text = ""; _text2 = "";};
								
								_mapCtrl drawIcon
								[
									_file,
									_color,
									_pos,
									20,
									20,
									_dir,
									_text,
									2,
									0.05,
									"RobotoCondensedBold",
									"left"
								];
			
								_mapCtrl drawIcon
								[
									_file,
									_color,
									_pos,
									20,
									20,
									_dir,
									_text2,
									2,
									0.05,
									"RobotoCondensedBold",
									"right"
								];
			
								_mapCtrl drawIcon
								[
									_file,
									_color,
									_pos,
									20,
									20,
									_dir,
									_text,
									1,
									0.05,
									"RobotoCondensedBold",
									"left"
								];
							};
						}';
					};
				} foreach _groups + _enemyGroups;
			}];
			_mapCtrl setVariable ["MAZ_map_mapEvent",_event];

			waitUntil {uiSleep 0.1; !((_object getVariable ["MAZ_map_data",-420]) isEqualType -420)};
			(_object getVariable "MAZ_map_data") params ["_time","_scale","_pos"];
			_mapCtrl ctrlMapAnimAdd [0, 0.02, getPos _object];
			ctrlMapAnimCommit _mapCtrl;
			displayUpdate _display;
			ctrlDelete _waitingToLoad;
			while{!isNull _object} do {
				if(count (_object getVariable ["MAZ_map_data",[]]) > 0) then {
					((_object getVariable "MAZ_map_data") select 0) params ["_time","_scale","_pos","_delay"];
					_mapCtrl ctrlMapAnimAdd [_time, _scale, _pos];
					ctrlMapAnimCommit _mapCtrl;
					private _tempTimer = 0;
					waitUntil {
						uiSleep 0.1;
						displayUpdate _display;
						_tempTimer = _tempTimer + 0.1;
						if(_tempTimer >= _time) then {
							private _tempData = _object getVariable ["MAZ_map_data",[]];
							_tempData deleteAt 0;
							_object setVariable ["MAZ_map_data",_tempData,true];
						};
						_tempTimer >= _time || (_object getVariable ["MAZ_map_stopAnim",false])
					};
					_object setVariable ["MAZ_map_stopAnim",false,true];
					sleep _delay;
				} else {
					displayUpdate _display;
					sleep 0.1;
				};
			};
		};

		MAZ_fnc_getLiveMapData = {
			params ["_map"];
			private _dispName = _map getVariable "MAZ_map_name";
			private _mapDisplay = findDisplay _dispName;
			if(isNull _mapDisplay) exitWith {systemChat "Failed to find display with that name.";};
			_mapControl = _mapDisplay displayCtrl 10;
			_mapScale = ctrlMapScale _mapControl;
			_mapPos = _mapControl ctrlMapScreenToWorld [0.5,0.5];
			[_mapScale, _mapPos]
		};

		MAZ_fnc_setMapDisplayData = {
			params ["_map","_time","_scale","_pos"];
			_scale = [_scale, 0.001,1] call BIS_fnc_clamp;
			private _name = _map getVariable ["MAZ_map_name",""];
			if(_name == "") exitWith {false};
			private _display = findDisplay _name;
			private _mapCtrl = _display displayCtrl 10;
			_map setVariable ["MAZ_map_data",[],true];
			_map setVariable ["MAZ_map_stopAnim",true,true];
			sleep 0.1;
			_mapCtrl ctrlMapAnimAdd [_time, _scale, _pos];
			ctrlMapAnimCommit _mapCtrl;
			displayUpdate _display;
			true
		};

		MAZ_fnc_addMapDisplayAnimation = {
			params ["_map","_time","_scale","_pos",["_delay",0.1]];
			_scale = [_scale, 0.001,1] call BIS_fnc_clamp;
			private _currentData = _map getVariable ["MAZ_map_data",[]];
			_currentData pushBack [_time,_scale,_pos,_delay];
			_map setVariable ["MAZ_map_data",_currentData,true];
		};

		MAZ_fnc_canMoveMap = {
			params ["_map","_player"];
			if(_map distance _player > 3) exitWith {false};
			if(_map getVariable ["MAZ_LM_moving",false]) exitWith {false};
			true;
		};

		MAZ_fnc_addMapActions = {
			params ["_object"];
			[
				_object,
				"Change Map Location",
				"\a3\ui_f_oldman\data\IGUI\Cfg\holdactions\map_ca.paa",
				"\a3\ui_f_oldman\data\IGUI\Cfg\holdactions\map_ca.paa",
				"[_target,_this] call MAZ_fnc_canMoveMap",
				"true",
				{},
				{},
				{
					params ["_target", "_caller", "_actionId", "_arguments"];
					_target setVariable ["MAZ_LM_moving",true,true];
					([_target] call MAZ_fnc_getLiveMapData) params ["_scale","_pos"];
					openMap [true,false];
					(findDisplay 12 displayCtrl 51) ctrlMapAnimAdd [0, _scale, _pos];
					ctrlMapAnimCommit (findDisplay 12 displayCtrl 51);
					systemChat "Move to where the map should be shown.";
					addMissionEventHandler ["Map", {
						params ["_mapIsOpened", "_mapIsForced"];
						_thisArgs params ["_map"];
						if(!_mapIsOpened) then {
							private _scale = ctrlMapScale (findDisplay 12 displayCtrl 51);
							private _pos = (findDisplay 12 displayCtrl 51) ctrlMapScreenToWorld [0.4,0.5];
							[_map,0,_scale * 1.75,_pos] spawn MAZ_fnc_addMapDisplayAnimation;
							_map setVariable ["MAZ_LM_moving",false,true];
							removeMissionEventHandler ["Map",_thisEventHandler];
						};
					},[_target]];
				},
				{},
				[],
				0.5,
				1000,
				false
			] call BIS_fnc_holdActionAdd;

			[
				_object,
				"Toggle Drawing Groups",
				"\a3\ui_f_oldman\data\IGUI\Cfg\holdactions\map_ca.paa",
				"\a3\ui_f_oldman\data\IGUI\Cfg\holdactions\map_ca.paa",
				"_target distance _this < 3",
				"true",
				{},
				{},
				{
					params ["_target", "_caller", "_actionId", "_arguments"];
					if(_target getVariable ["MAZ_map_doDrawUnits",false]) then {
						_target setVariable ["MAZ_map_doDrawUnits",false,true];
					} else {
						_target setVariable ["MAZ_map_doDrawUnits",true,true];
					};
				},
				{},
				[],
				0.25,
				999,
				false
			] call BIS_fnc_holdActionAdd;

			[
				_object,
				"Toggle Drawing AI Groups",
				"\a3\ui_f_oldman\data\IGUI\Cfg\holdactions\map_ca.paa",
				"\a3\ui_f_oldman\data\IGUI\Cfg\holdactions\map_ca.paa",
				"_target distance _this < 3 && _target getVariable ['MAZ_map_doDrawUnits',false]",
				"true",
				{},
				{},
				{
					params ["_target", "_caller", "_actionId", "_arguments"];
					if(_target getVariable ["MAZ_map_drawAIUnits",false]) then {
						_target setVariable ["MAZ_map_drawAIUnits",false,true];
					} else {
						_target setVariable ["MAZ_map_drawAIUnits",true,true];
					};
				},
				{},
				[],
				0.25,
				998,
				false
			] call BIS_fnc_holdActionAdd;
		};

		MAZ_fnc_getMapTextureIndex = {
			params ["_object"];
			private _out = 0;
			{
				_x params ["_type","_index"];
				if((typeOf _object) isKindOf _type) exitWith {_out = _index;};
			}forEach [
				["Land_Laptop_03_base_F",1],
				["Land_MapBoard_F",0],
				["Land_Billboard_F",0],
				["UserTexture1m_F",0],
				["Land_WallSign_01_base_F",1],
				["Canvas_01_base_F",0],
				["Land_BriefingRoomDesk_01_F",0],
				["Land_BriefingRoomScreen_01_F",0],
				["Land_Laptop_unfolded_F",0],
				["Land_PCSet_01_screen_F",0],
				["Land_TripodScreen_01_large_F",0]
			];
			_out
		};

		MAZ_EP_fnc_addToExecQueue = {
			params ["_parameters","_function"];
			if(isNil "MAZ_EP_ExecQueueStarted") then {
				MAZ_EP_ExecQueueStarted = false;
			};
			if(isNil "MAZ_EP_ExecQueue") then {
				MAZ_EP_ExecQueue = [];
			};
			
			MAZ_EP_ExecQueue pushBack [_parameters,_function];
			if(!MAZ_EP_ExecQueueStarted) then {
				MAZ_EP_ExecQueueStarted = true;
				[] spawn MAZ_EP_fnc_startExecQueue;
			};
		};

		MAZ_EP_fnc_startExecQueue = {
			while {count MAZ_EP_ExecQueue > 0} do {
				(MAZ_EP_ExecQueue select 0) params ["_parameters","_function"];
				private _scriptHandle = _parameters spawn _function;
				waitUntil {scriptDone _scriptHandle};
				MAZ_EP_ExecQueue deleteAt 0;
			};
			MAZ_EP_ExecQueueStarted = false;
		};
	}) splitString "";

	_value deleteAt (count _value - 1);
	_value deleteAt 0;

	_value = _value joinString "";
	_value = _value + "removeMissionEventhandler ['EachFrame',_thisEventHandler];";
	_value = _value splitString "";

	missionNamespace setVariable [_varName,_value,true];

	[[_varName], {
		params ["_ding"];
		private _data = missionNamespace getVariable [_ding,[]];
		_data = _data joinString "";
		private _id = addMissionEventhandler ["EachFrame", _data];
	}] remoteExec ['spawn',0,_myJIPCode];
};

this spawn {
	waitUntil {!isNil "MAZ_fnc_addMapActions"};
	sleep 0.5;
	private _name = _this getVariable "MAZ_map_name";
	if(!isNil "_name") exitWith {};
	[_this] spawn MAZ_fnc_makeNewMapDisplay;
};
