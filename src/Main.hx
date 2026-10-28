package mods.minimap;

import mods.api.Mod;
import mods.api.Context;
import mods.api.dungeon.Floor;
import openfl.ui.Keyboard;

class Main extends Mod {
	var ctx:Context;
	var minimap:Minimap;
	var dungeonStart:Int = -1;

	override public function init(context:Context):Void {
		ctx = context;
		context.onFloorEnter(onFloorEnter);
		context.onFloorExit(onFloorExit);
		context.onKeyDown(onKeyDown);
	}

	function onFloorEnter(floor:Floor):Void {
		if (floor.number == 1 || dungeonStart < 0)
			dungeonStart = openfl.Lib.getTimer();
		minimap = new Minimap(ctx, dungeonStart);
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