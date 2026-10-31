package mods.minimap;

import mods.api.Mod;
import mods.api.Context;
import mods.api.dungeon.Floor;
import openfl.ui.Keyboard;
import distributedObjects.DistributedDungeonFloor;
import distributedObjects.HeroGameObject;
import distributedObjects.HeroGameObjectOwner;

class Main extends Mod {
	var ctx:Context;
	var minimap:Minimap;
	var refs:Refs = new Refs();
	var dungeonStart:Int = -1;
	static inline final F6 = 117;

	override public function init(context:Context):Void {
		ctx = context;
		context.onFloorEnter(onFloorEnter);
		context.onFloorExit(onFloorExit);
		context.onKeyDown(onKeyDown);
		var core = context.core;
	core.onObjectReady(function(object) {
	if (Std.isOfType(object, DistributedDungeonFloor)) {
		refs.floor = cast object;
	} else if (Std.isOfType(object, HeroGameObjectOwner)) {
		refs.localHero = cast object;
		refs.heroes.set(object.id, cast object);
	} else if (Std.isOfType(object, HeroGameObject)) {
		refs.heroes.set(object.id, cast object);
	}
	});
	core.onObjectGone(function(object) {
		if (object == refs.floor) refs.floor = null;
		if (object == refs.localHero) refs.localHero = null;
		refs.heroes.remove(object.id);
	});
	}

	function onFloorEnter(floor:Floor):Void {
		if (floor.number == 1 || dungeonStart < 0)
			dungeonStart = openfl.Lib.getTimer();
		minimap = new Minimap(ctx, refs, dungeonStart);
		ctx.overlay.addChild(minimap);
	}

	function onFloorExit(floor:Floor):Void {
		removeMinimap();
	}

	function onKeyDown(key:UInt):Bool {
		if (key == Keyboard.M && minimap != null) {
			minimap.visible = !minimap.visible;
			return true;
		}
		if (key == F6 && minimap != null) {
		minimap.dumpExitObjects();
		return true;
	}
		return false;
	}

	function removeMinimap():Void {
		if (minimap != null) {
			minimap.destroy();
			ctx.overlay.removeChild(minimap);
			minimap = null;
		}
	}

	override public function dispose():Void {
		removeMinimap();
	}
}