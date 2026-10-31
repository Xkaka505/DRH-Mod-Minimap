package mods.minimap;

import mods.api.Context;
import openfl.display.Sprite;
import openfl.events.Event;
import openfl.geom.Vector3D;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.Lib;
import distributedObjects.DistributedDungeonFloor;

class Minimap extends Sprite {
	static inline var MAP_W = 180.;
	static inline var MAP_H = 180.;
	static inline var HEADER_H = 28.;
	static inline var FOOTER_H = 28.;
	static inline var PAD = 6.;
	static inline var PANEL_W = MAP_W + PAD * 2;
	static inline var PANEL_H = MAP_H + HEADER_H + FOOTER_H + PAD * 2;
	static inline var TILE_SIZE = 900.;

	var ctx:Context;
	var refs:Refs;
	var startTime:Int;

	var map:Sprite = new Sprite();
	var playerMarker:Sprite = new Sprite();
	var markersByHero:Map<Int, Sprite> = new Map();

	var timerLabel:TextField;
	var floorLabel:TextField;
	var goldLabel:TextField;
	var goldEarned = 0;

	/** Library tile id -> "PLATE" / "KILLS" / "PLATE_KILLS" / "OTHER" / "NONE", generated from the level JSON files. */
	var exitModes:Map<String, String> = new Map();

	/** Open mode of each exit tile of the current floor, by position. */
	var exitModeByKey:Map<String, String> = new Map();

    function isGateSuffix(s:Int):Bool
        return s == 101 || s == 201;

    // Exit gate states
    static inline var GATE_UNKNOWN = 0; // no gate object found
    static inline var GATE_CLOSED = 1;
    static inline var GATE_OPEN = 2;
	static inline var GATE_BREAK = 3; 
    var exitState = "";

	// Drawing state
	var ready = false;
	var minX = 0.;
	var minY = 0.;
	var scale = 1.;
	var offX = 0.;
	var offY = 0.;

	// Redraw triggers
	var drawnFloor:Dynamic = null;
	var tileCount = -1;
	var exitCount = -1;
	var checkFrames = 0;

	/** Positions ("x,y") of the exit tiles of the current floor. */
	var exitKeys:Map<String, Bool> = new Map();

	public function new(ctx:Context, refs:Refs, startTime:Int) {
		super();
		this.ctx = ctx;
		this.refs = refs;
		this.startTime = startTime;
		mouseEnabled = false;
		mouseChildren = false;

		// Panel background and separators
		graphics.beginFill(0x101820, 0.88);
		graphics.lineStyle(2, 0xA8B8C8, 0.9);
		graphics.drawRoundRect(0, 0, PANEL_W, PANEL_H, 10, 10);
		graphics.endFill();
		graphics.lineStyle(1, 0xA8B8C8, 0.8);
		graphics.moveTo(6, HEADER_H);
		graphics.lineTo(PANEL_W - 6, HEADER_H);
		graphics.moveTo(6, HEADER_H + MAP_H + PAD);
		graphics.lineTo(PANEL_W - 6, HEADER_H + MAP_H + PAD);

		map.x = PAD;
		map.y = HEADER_H + PAD;
		addChild(map);

		addChild(monsterLayer); // above the map, below the player marker

		playerMarker.graphics.beginFill(0xFFDF4D);
		playerMarker.graphics.lineStyle(1, 0xFFFFFF, 1);
		playerMarker.graphics.drawCircle(0, 0, 3.5);
		playerMarker.graphics.endFill();
		addChild(playerMarker);

		timerLabel = label(new TextFormat("Arial", 11, 0xFFFFFF, true), PAD, 6, 80);
		floorLabel = label(new TextFormat("Arial", 11, 0xFFFFFF, true), PANEL_W - PAD - 75, 6, 75);
		goldLabel = label(new TextFormat("Arial", 12, 0xFFD700, true), PAD, HEADER_H + MAP_H + PAD, PANEL_W - PAD * 2);
		goldLabel.text = "Gold : --";
		loadExitModes();
		addEventListener(Event.ENTER_FRAME, onFrame);
		// TODO: subscribe to the game's gold event here and call addGold()
	}

	function label(fmt:TextFormat, x:Float, y:Float, w:Float):TextField {
		var t = new TextField();
		t.defaultTextFormat = fmt;
		t.selectable = false;
		t.mouseEnabled = false;
		t.width = w;
		t.height = 20;
		t.x = x;
		t.y = y;
		addChild(t);
		return t;
	}

	public function addGold(amount:Int):Void {
		if (amount <= 0) return;
		goldEarned += amount;
		goldLabel.text = "Gold : " + goldEarned;
	}

	// ----------------------------------------------------------------- game data

	/** The floor the local hero is on (same path as the original AS3 code). */
	function currentFloor():DistributedDungeonFloor {
		var h = refs.localHero;
		return h == null ? null : h.distributedDungeonFloor;
	}

	/** Tile corners of the floor, without filler tiles. */
	function getTilePositions():Array<Vector3D> {
		var floor = ctx.state.floor;
		if (floor == null) return null;
		var out:Array<Vector3D> = [];
		for (t in floor.tiles)
			if (t.category != "FILLER_TILE") out.push(new Vector3D(t.x, t.y));
		return out;
	}

	inline function posKey(x:Float, y:Float):String
		return Std.int(x) + "," + Std.int(y);

	/** Rebuilds exitKeys and exitModeByKey from the api's tile categories and the generated modes. */
	function refreshExitKeys():Void {
		exitKeys = new Map();
		exitModeByKey = new Map();
		var floor = ctx.state.floor;
		if (floor == null) return;
		for (t in floor.tiles) {
			if (t.category != "EXIT_TILE") continue;
			var key = posKey(t.x, t.y);
			exitKeys.set(key, true);
			var mode = exitModes.get(Std.string(t.id));
			exitModeByKey.set(key, mode == null ? "OTHER" : mode);
		}
	}

	function isExitTile(p:Vector3D):Bool
		return exitKeys.exists(posKey(p.x, p.y));

	function countExits():Int {
		var positions = getTilePositions();
		if (positions == null) return 0;
		var n = 0;
		for (p in positions)
			if (isExitTile(p)) n++;
		return n;
	}

    /** Last 4 digits of an NPC type in the 2xxxxxx range used by gate/plate props, -1 otherwise. */
    function typeSuffix(type:Dynamic):Int {
        var t = Std.parseInt(Std.string(type));
        if (t == null || t < 2000000 || t >= 3000000) return -1;
        return t % 10000;
    }

	/** True when the exit is blocked by a trap only (mode ends with _TRAP). */
	function isTrapOnly(mode:String):Bool
		return mode != null && StringTools.endsWith(mode, "_TRAP");

	/** The mode without its _TRAP marker. */
	function baseMode(mode:String):String
		return isTrapOnly(mode) ? mode.substr(0, mode.length - 5) : mode;

	/** State of the gates on this exit tile: GATE_UNKNOWN, GATE_CLOSED, GATE_BREAK or GATE_OPEN. */
	function gateState(p:Vector3D):Int {
		var floor = currentFloor();
		if (floor == null || floor.tileGrid == null) return GATE_UNKNOWN;
		var tile:Dynamic = floor.tileGrid.getTileAtPosition(p);
		if (tile == null) return GATE_UNKNOWN;
		var mode = exitModeByKey.get(posKey(p.x, p.y));
		if (mode == "NONE") return GATE_UNKNOWN; // nothing blocks this exit

		if (isTrapOnly(mode)) {
			// No door gate: the trap itself is not readable yet, but the pressure zone is
			// (its object flips to true when stepped on, which is what disarms plate-only traps)
			if (baseMode(mode) != "PLATE") return GATE_CLOSED;
			for (o in toArray(Reflect.getProperty(tile, "NPCGameObjects")))
				if (typeSuffix(Reflect.getProperty(o, "type")) == 301)
					return Reflect.getProperty(o, "triggerState") == true ? GATE_OPEN : GATE_CLOSED;
			return GATE_UNKNOWN;
		}
		var found = false;
		var anyClosed = false;
		var anyBreakable = false;
		for (o in toArray(Reflect.getProperty(tile, "NPCGameObjects"))) {
			if (!isGateSuffix(typeSuffix(Reflect.getProperty(o, "type")))) continue;
			found = true;
			if (Reflect.getProperty(o, "triggerState") == false) continue; // this one is open
			anyClosed = true;
			if (Reflect.getProperty(o, "isAttackable") == true) anyBreakable = true;
		}
		if (!found) return GATE_UNKNOWN;
		if (!anyClosed) return GATE_OPEN;
		return anyBreakable ? GATE_BREAK : GATE_CLOSED;
	}

	function gateColor(state:Int, mode:String):Int {
		mode = baseMode(mode);
		if (state == GATE_OPEN) return 0x3FB950; // green: already open
		if (state == GATE_BREAK) return 0x2EC4D6; // cyan: destroy the gate
		if (state == GATE_CLOSED) {
			if (mode == "PLATE") return 0xF0A030; // orange: step on a plate / rushable
			if (mode == "KILLS") return 0xE8D44D; // yellow: kill the monsters
			if (mode == "PLATE_KILLS") return 0x9B59D0; // purple: spawn monster, then kill
			return 0xD93636; // red: unknown way to open it
		}
		return 0x8A8F98; // grey: no gate object found
	}

	function loadExitModes():Void {
	try {
		var d:Dynamic = haxe.Json.parse(sys.io.File.getContent(ctx.resources + "/exit_modes.json"));
		for (id in Reflect.fields(d)) exitModes.set(id, Std.string(Reflect.field(d, id)));
		ctx.log("minimap: " + Lambda.count(exitModes) + " exit tile modes loaded");
	} catch (e:Dynamic) {
		ctx.log("minimap: could not read exit_modes.json: " + Std.string(e));
	}
	}

    /** One digit per exit tile (see GATE_* constants); changes when a gate or plate changes state. */
    function exitStateKey():String {
        var s = "";
        var positions = getTilePositions();
        if (positions == null) return s;
        for (p in positions)
            if (isExitTile(p)) s += gateState(p);
        return s;
    }

	function getLocalHeroPosition():Vector3D {
		for (h in ctx.state.heroes)
			if (h.local) return new Vector3D(h.x, h.y);
		return null;
	}

	function getHeroPosition(heroId:Int):Vector3D {
		for (h in ctx.state.heroes)
			if (h.id == heroId) return new Vector3D(h.x, h.y);
		return null;
	}

	var monsterLayer:Sprite = new Sprite(); // add it with addChild(monsterLayer) in the constructor

    // test mobs on map
	function updateMonsters():Void {
		monsterLayer.graphics.clear();
		monsterLayer.graphics.beginFill(0xFF5555, 0.9);
		var floor = ctx.state.floor;
		if (floor != null)
			for (m in floor.monsters)
				monsterLayer.graphics.drawCircle(PAD + offX + (m.x - minX) * scale, HEADER_H + PAD + offY + (m.y - minY) * scale, 1.8);
		monsterLayer.graphics.endFill();
	}

	// ------------------------------------------------------------------- per frame

	function onFrame(_):Void {
		if (!ctx.core.alive) return;
		updateTimer();

		var f = currentFloor();
		if (f != null) {
			var max = f.getMaxFloorNum();
			floorLabel.text = "Floor " + f.getCurrentFloorNum() + (max > 1 ? "/" + max : "");
		}

		// Redraw when the floor changes
		if (f != drawnFloor) ready = false;
		if (!ready) drawDungeonIfReady();

		if (ready) {
			updatePlayerMarker();
			updateAllyMarkers();
			updateMonsters();
		}

		// Every 30 frames, redraw if the grid grew or the exit count changed
		if (ready && ++checkFrames % 30 == 0) {
			refreshExitKeys();
			var tiles = getTilePositions();
            if ((tiles == null ? 0 : tiles.length) != tileCount || countExits() != exitCount || exitStateKey() != exitState)
                ready = false;
		}
	}

	function updateTimer():Void {
		var s = Std.int((Lib.getTimer() - startTime) / 1000);
		timerLabel.text = pad2(Std.int(s / 3600)) + ":" + pad2(Std.int(s % 3600 / 60)) + ":" + pad2(s % 60);
	}
	

	inline function pad2(n:Int):String
		return n < 10 ? "0" + n : "" + n;

	function drawDungeonIfReady():Void {
		var positions:Array<Vector3D> = getTilePositions();
		if (positions == null || positions.length == 0) return;

		refreshExitKeys();

		// World bounds of the tiles, then scale to fit the panel
		var maxX = positions[0].x, maxY = positions[0].y;
		minX = maxX; minY = maxY;
		for (p in positions) {
			minX = Math.min(minX, p.x); minY = Math.min(minY, p.y);
			maxX = Math.max(maxX, p.x); maxY = Math.max(maxY, p.y);
		}
		var worldW = maxX - minX + TILE_SIZE;
		var worldH = maxY - minY + TILE_SIZE;
		scale = Math.min(MAP_W / worldW, MAP_H / worldH);
		offX = (MAP_W - worldW * scale) * 0.5;
		offY = (MAP_H - worldH * scale) * 0.5;

		// Draw the tiles, exit tiles in red
		var tw = Math.max(2, TILE_SIZE * scale - 1);
		map.graphics.clear();
		for (p in positions) {
			if (isExitTile(p)) {
				map.graphics.beginFill(gateColor(gateState(p), exitModeByKey.get(posKey(p.x, p.y))), 0.95);
				map.graphics.lineStyle(1, 0xFFFFFF, 1);
			} else {
				map.graphics.beginFill(0x263746, 0.95);
				map.graphics.lineStyle(1, 0x91A6B7, 0.9);
			}
			map.graphics.drawRoundRect(offX + (p.x - minX) * scale, offY + (p.y - minY) * scale, tw, tw, 2, 2);
			map.graphics.endFill();
		}

		exitCount = countExits();
        exitState = exitStateKey();
		tileCount = positions.length;
		drawnFloor = currentFloor();
		ctx.log("minimap: tiles=" + positions.length + " exits=" + exitCount + " gates=" + exitState);
		ready = true;
	}

	function updatePlayerMarker():Void {
		var pos = getLocalHeroPosition();
		if (pos == null) return;
		playerMarker.x = PAD + offX + (pos.x - minX) * scale;
		playerMarker.y = HEADER_H + PAD + offY + (pos.y - minY) * scale;
	}

	function updateAllyMarkers():Void {
		for (m in markersByHero) m.visible = false;
		for (hero in ctx.state.heroes) {
			if (hero.local) continue;
			var pos = getHeroPosition(hero.id);
			if (pos == null) continue;
			var marker = markersByHero.get(hero.id);
			if (marker == null) {
				marker = new Sprite();
				marker.graphics.beginFill(0x55C7FF);
				marker.graphics.lineStyle(1, 0xFFFFFF, 1);
				marker.graphics.drawCircle(0, 0, 3);
				marker.graphics.endFill();
				if (hero.player != null) {
					var portrait = hero.player.createPortrait(18);
					portrait.x = -9; portrait.y = -9; // centered, may need adjusting
					marker.addChild(portrait);
				}
				markersByHero.set(hero.id, marker);
				addChild(marker);
			}
			marker.x = PAD + offX + (pos.x - minX) * scale;
			marker.y = HEADER_H + PAD + offY + (pos.y - minY) * scale;
			marker.visible = true;
		}
	}

	public function destroy():Void {
		removeEventListener(Event.ENTER_FRAME, onFrame);
		graphics.clear();
		map.graphics.clear();
		for (m in markersByHero) if (m.parent == this) removeChild(m);
		markersByHero.clear();
		monsterLayer.graphics.clear();
	}

    /** Snapshot taken by the first F6, compared by the second. */
    var snapshot:Map<String, Array<String>> = null;

	/** Debug (F6): 1st press lists the NPCs on exit tiles, 2nd press logs what changed or disappeared. */
	public function dumpExitObjects():Void {
		var floor = currentFloor();
		var positions = getTilePositions();
		if (floor == null || positions == null) return;

		// Only the exit tiles: "x,y#id" -> [type, trig, arch, layer, attackable, hp, state]
		var now = new Map<String, Array<String>>();
		for (p in positions) {
			if (!isExitTile(p)) continue;
			var tile:Dynamic = floor.tileGrid.getTileAtPosition(p);
			for (o in toArray(Reflect.getProperty(tile, "NPCGameObjects")))
				now.set(posKey(p.x, p.y) + "#" + g(o, "id"), [
					g(o, "type"), g(o, "triggerState"), g(o, "archwayAlpha"),
					g(o, "layer"), g(o, "isAttackable"), g(o, "hitPoints"), g(o, "mState")
				]);
		}

		var apiFloor = ctx.state.floor;
		var mapName = apiFloor != null ? Std.string(apiFloor.map) : "?";
		if (snapshot == null) {
			snapshot = now;
			ctx.log("snapshot taken on " + mapName + ", exit tile NPCs:");
			for (key in now.keys()) {
				var v = now.get(key);
				ctx.log("  " + key + " type=" + v[0] + " trig=" + v[1] + " arch=" + v[2] + " layer=" + v[3]
					+ " attackable=" + v[4] + " hp=" + v[5] + " state=" + v[6]);
			}
			dumpExitTriggers();
			return;
		}

		ctx.log("changes on " + mapName + ":");
		for (key in now.keys()) {
			var before = snapshot.get(key);
			var after = now.get(key);
			if (before == null) {
				ctx.log("  NEW " + key + " type=" + after[0]);
			} else if (before[1] != after[1] || before[5] != after[5] || before[6] != after[6]) {
				ctx.log("  " + key + " type=" + after[0] + " trig=" + before[1] + "->" + after[1]
					+ " hp=" + before[5] + "->" + after[5] + " state=" + before[6] + "->" + after[6]
					+ " attackable=" + after[4]);
			}
		}
		for (key in snapshot.keys())
			if (!now.exists(key)) ctx.log("  GONE " + key + " type=" + snapshot.get(key)[0]);
		snapshot = null;
	}

	/** Debug: lists the trigger objects built into each exit tile's library entry. */
	function dumpExitTriggers():Void {
		var apiFloor = ctx.state.floor;
		var floor = currentFloor();
		if (apiFloor == null || floor == null) return;
		var tileMap:Dynamic = @:privateAccess floor.dungeonFloorFactory.tileFactory.mTileMap;
		if (tileMap == null) return;
		for (t in apiFloor.tiles) {
			if (t.category != "EXIT_TILE") continue;
			var json:Dynamic = tileMap.itemFor(t.id);
			if (json == null) continue;
			var kinds:Array<String> = [];
			for (o in (json.LEObjects : Array<Dynamic>)) {
				var type = Std.string(o.type);
				if (type == "LETrigger" || type == "LETriggerGate" || type == "LETriggerable"
					|| type == "LENPCGeneratorWithAllSpawnsDeadTrigger")
					kinds.push(Std.string(o.constant));
			}
			ctx.log("exit(" + posKey(t.x, t.y) + ") library tile " + t.id + " triggers: " + kinds.join(", "));
		}
	}

    /** Reads a property as a string, "?" if it fails. */
    function g(o:Dynamic, name:String):String {
        try {
            return Std.string(Reflect.getProperty(o, name));
        } catch (_:Dynamic) {
            return "?";
        }
    }

        /** Turns an Array or any object with iterator() into an Array. */
    function toArray(coll:Dynamic):Array<Dynamic> {
        var out:Array<Dynamic> = [];
        if (coll == null) return out;
        try {
            if (Std.isOfType(coll, Array)) return coll;
            var it:Dynamic = Reflect.callMethod(coll, Reflect.field(coll, "iterator"), []);
            while (it.hasNext()) out.push(it.next());
        } catch (_:Dynamic) {}
        return out;
    }
}