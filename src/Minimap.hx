package mods.minimap;

import mods.api.Context;
import openfl.display.Sprite;
import openfl.events.Event;
import openfl.geom.Vector3D;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFieldAutoSize;
import openfl.Lib;

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
	var startTime:Int;
	var map:Sprite = new Sprite();
	var playerMarker:Sprite = new Sprite();
	var markersByHero:Map<Int, Sprite> = new Map();
	var timerLabel:TextField;
	var floorLabel:TextField;
	var goldLabel:TextField;
	var ready = false;
	var minX = 0.;
	var minY = 0.;
	var scale = 1.;
	var offX = 0.;
	var offY = 0.;
	var goldEarned = 0;

	public function new(ctx:Context, startTime:Int) {
		super();
		this.ctx = ctx;
		this.startTime = startTime;
		mouseEnabled = false;
		mouseChildren = false;

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

		playerMarker.graphics.beginFill(0xFFDF4D);
		playerMarker.graphics.lineStyle(1, 0xFFFFFF, 1);
		playerMarker.graphics.drawCircle(0, 0, 3.5);
		playerMarker.graphics.endFill();
		addChild(playerMarker);

		timerLabel = label(new TextFormat("Arial", 11, 0xFFFFFF, true), PAD, 6);
		floorLabel = label(new TextFormat("Arial", 11, 0xFFFFFF, true), PANEL_W - PAD - 75, 6);
		goldLabel = label(new TextFormat("Arial", 12, 0xFFD700, true), PAD, HEADER_H + MAP_H + PAD);
		goldLabel.text = "Gold : --";

		addEventListener(Event.ENTER_FRAME, onFrame);
		// CORE : s'abonner ici à l'événement d'or gagné pour appeler addGold()
	}

	function label(fmt:TextFormat, x:Float, y:Float):TextField {
		var t = new TextField();
		t.defaultTextFormat = fmt;
		t.autoSize = TextFieldAutoSize.LEFT;
		t.selectable = false;
		t.mouseEnabled = false;
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

	function onFrame(_):Void {
		updateTimer();
		var floor = ctx.state.floor;
		if (floor != null)
			floorLabel.text = "Floor " + floor.number; // + "/" + max via CORE
		if (!ready) drawDungeonIfReady();
		if (ready) {
			updatePlayerMarker();
			updateAllyMarkers();
		}
	}

	function updateTimer():Void {
		var s = Std.int((Lib.getTimer() - startTime) / 1000);
		timerLabel.text = pad2(Std.int(s / 3600)) + ":" + pad2(Std.int(s % 3600 / 60)) + ":" + pad2(s % 60);
	}

	inline function pad2(n:Int):String
		return n < 10 ? "0" + n : "" + n;

	function drawDungeonIfReady():Void {
		// CORE : récupérer la grille du sol courant (ancien mHero.distributedDungeonFloor.tileGrid)
		var positions:Array<Vector3D> = getTilePositions();
		if (positions == null || positions.length == 0) return;

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

		var tw = Math.max(2, TILE_SIZE * scale - 1);
		map.graphics.clear();
		for (p in positions) {
			if (isExitTile(p)) {
				map.graphics.beginFill(0xD93636, 0.95);
				map.graphics.lineStyle(1, 0xFFFFFF, 1);
			} else {
				map.graphics.beginFill(0x263746, 0.95);
				map.graphics.lineStyle(1, 0x91A6B7, 0.9);
			}
			map.graphics.drawRoundRect(offX + (p.x - minX) * scale, offY + (p.y - minY) * scale, tw, tw, 2, 2);
			map.graphics.endFill();
		}
		ready = true;
	}

	function updatePlayerMarker():Void {
		var pos = getLocalHeroPosition(); // CORE
		if (pos == null) return;
		playerMarker.x = PAD + offX + (pos.x - minX) * scale;
		playerMarker.y = HEADER_H + PAD + offY + (pos.y - minY) * scale;
		// icône : ctx.state.heroes → hero.local → hero.player.createPortrait(18), à poser une fois
	}

	function updateAllyMarkers():Void {
		for (m in markersByHero) m.visible = false;
		for (hero in ctx.state.heroes) {
			if (hero.local) continue;
			var pos = getHeroPosition(hero.id); // CORE
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
					portrait.x = -9; portrait.y = -9; // centré (à ajuster)
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

	// ---- Accès au cœur du jeu : à remplir avec ctx.core ----
	function getTilePositions():Array<Vector3D> return null;
	function isExitTile(p:Vector3D):Bool return false;
	function getLocalHeroPosition():Vector3D return null;
	function getHeroPosition(heroId:Int):Vector3D return null;

	public function destroy():Void {
		removeEventListener(Event.ENTER_FRAME, onFrame);
		graphics.clear();
		map.graphics.clear();
		for (m in markersByHero) if (m.parent == this) removeChild(m);
		markersByHero.clear();
	}
}