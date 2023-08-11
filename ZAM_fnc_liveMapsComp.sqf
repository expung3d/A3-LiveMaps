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
			private _name = format ["MAZ_liveMap_%1",MAZ_liveMapCount];
			MAZ_liveMapCount = MAZ_liveMapCount + 1;
			publicVariable "MAZ_liveMapCount";
			private _texture = format ['#(rgb,1024,1024,1)ui("RscDisplayEmpty","%1")',_name];
			_object setObjectTextureGlobal [0,_texture];
			sleep 0.1;
			private _display = findDisplay _name;
			if(isNull _display) exitWith {systemChat "Failed to create display."};
			_object setVariable ["MAZ_map_name",_name,true];
			[_object,0,0.02,getPos player] call MAZ_fnc_setMapDisplayData;
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
			sleep 0.1;
			private _display = findDisplay _name;
			if(isNull _display) exitWith {systemChat "Failed to find display with that name."};
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
					_map setVariable ["MAZ_map_stopAnim",false,true];
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
							[_map,0,_scale * 1.75,_pos] spawn MAZ_fnc_setMapDisplayData;
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
	[_this] spawn MAZ_fnc_makeNewMapDisplay;
};