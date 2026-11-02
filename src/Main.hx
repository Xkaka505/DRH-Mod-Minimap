package mods.minimap;

import mods.api.Mod;
import mods.api.Context;
import mods.api.dungeon.Floor;
import openfl.ui.Keyboard;
import distributedObjects.HeroGameObjectOwner;
import distributedObjects.PlayerGameObjectOwner;

class Main extends Mod {
	static inline final F6 = 117;
	static inline final F7 = 118;

	// Debug probe (F7): counts the game's events between two presses
	var probeSubs:Array<Dynamic> = null;
	var probeCounts:Map<String, Int> = new Map();

	var ctx:Context;
	var minimap:Minimap;
	var refs:Refs = new Refs();
	var dungeonStart:Int = -1;
	// Gold: the game reports the account balance (basicCurrency), the minimap shows the gain of the run
	var gold = 0; // gained since the dungeon started, kept across floors
	var goldBase:Null<Int> = null; // balance when the dungeon started
	var lastTotal:Null<Int> = null; // last balance the game reported, in town included
	var playerOwner:Dynamic = null; // the local PlayerGameObjectOwner

	// UI choices kept here because each floor creates a new Minimap
	var minimapVisible = true;
	var minimapOffX = 0.;
	var minimapOffY = 0.;

	override public function init(context:Context):Void {
		ctx = context;
		context.onFloorEnter(onFloorEnter);
		context.onFloorExit(onFloorExit);
		context.onKeyDown(onKeyDown);

		var core = context.core;
		core.onFieldReceived(function(obj, id, name) {
			if (StringTools.endsWith(name, ".basicCurrency")) onGoldField(obj);
		});
		core.onObjectReady(function(object) {
			if (Std.isOfType(object, HeroGameObjectOwner)) {
				refs.localHero = cast object;
			} else if (Std.isOfType(object, PlayerGameObjectOwner)) {
				playerOwner = object;
			}
		});
		core.onObjectGone(function(object) {
			if (object == playerOwner) playerOwner = null;
			if (object == refs.localHero) refs.localHero = null;
		});
	}

	function onFloorEnter(floor:Floor):Void {
		if (floor.number == 1 || dungeonStart < 0) {
			dungeonStart = openfl.Lib.getTimer();
			gold = 0;
			goldBase = currentTotal();
		}
		minimap = new Minimap(ctx, refs, dungeonStart);
		minimap.setGold(gold); // a new floor creates a new minimap: give it the current total
		minimap.visible = minimapVisible; // apply the saved choice to the new minimap
		minimap.setOffset(minimapOffX, minimapOffY); // and the dragged position
		ctx.overlay.addChild(minimap);
	}

	/** The account balance read on the player object (PlayerGameObjectOwner.basicCurrency), null if unreadable. */
	function readBalance(obj:Dynamic):Null<Int> {
		if (obj == null) return null;
		for (n in ["basicCurrency", "mBasicCurrency", "_basicCurrency"]) {
			var value:Null<Int> = null;
			try {
				value = Std.parseInt(Std.string(Reflect.getProperty(obj, n)));
			} catch (_:Dynamic) {}
			if (value != null) return value;
		}
		return null;
	}

	/** Best known balance right now: the live field, else the last one reported, else the account's. */
	function currentTotal():Null<Int> {
		var live = readBalance(playerOwner);
		if (live != null) return live;
		if (lastTotal != null) return lastTotal;
		var acc = ctx.state.account;
		return acc == null ? null : acc.coins;
	}

	/** The server sent PlayerGameObjectOwner.basicCurrency: show what was gained since the dungeon started. */
	function onGoldField(obj:Dynamic):Void {
		var value = readBalance(obj);
		if (value == null) return;
		lastTotal = value;
		// Baseline unknown (the balance was not readable at dungeon start): start counting from here
		if (goldBase == null) goldBase = value;
		gold = value - goldBase;
		ctx.log("gold: balance=" + value + " base=" + goldBase + " gained=" + gold);
		if (minimap != null) minimap.setGold(gold);
	}

	function onFloorExit(floor:Floor):Void {
		removeMinimap();
	}

	function onKeyDown(key:UInt):Bool {
		if (key == Keyboard.M) {
			minimapVisible = !minimapVisible;
			if (minimap != null) minimap.visible = minimapVisible;
			return true;
		}
		if (key == F6 && minimap != null) {
			minimap.dumpExitObjects();
			return true;
		}
		if (key == F7) {
			toggleProbe();
			return true;
		}
		return false;
	}

	/** Debug (F7): 1st press starts counting the game's events, 2nd press logs them, rarest first. */
	function toggleProbe():Void {
		if (probeSubs == null) {
			probeCounts = new Map();
			var core = ctx.core;
			probeSubs = [
				core.onFieldReceived(function(obj, id, name) probe("field " + className(obj) + "." + name)),
				core.onObjectReady(function(obj) probe("ready " + className(obj))),
				core.onObjectGone(function(obj) probe("gone " + className(obj)))
			];
			ctx.log("probe: recording, pick up some gold then press F7 again");
			return;
		}
		for (s in probeSubs) s.cancel();
		probeSubs = null;

		// A gold pickup is a discrete event, unlike positions or animations, so rare ones come first
		var keys = [for (k in probeCounts.keys()) k];
		keys.sort(function(a, b) return probeCounts.get(a) - probeCounts.get(b));
		ctx.log("probe: " + keys.length + " distinct events, rarest first:");
		for (k in keys.slice(0, 60)) ctx.log("  " + probeCounts.get(k) + "x " + k);
	}

	function probe(key:String):Void {
		var n = probeCounts.get(key);
		probeCounts.set(key, n == null ? 1 : n + 1);
	}

	function className(o:Dynamic):String {
		var c = Type.getClass(o);
		return c == null ? "?" : Type.getClassName(c);
	}

	function removeMinimap():Void {
		if (minimap != null) {
			// Save the dragged position before the minimap is destroyed
			minimapOffX = minimap.getOffsetX();
			minimapOffY = minimap.getOffsetY();
			minimap.destroy();
			ctx.overlay.removeChild(minimap);
			minimap = null;
		}
	}

	override public function dispose():Void {
		removeMinimap();
	}
}
