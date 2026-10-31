package mods.minimap;

import distributedObjects.DistributedDungeonFloor; // chemin à vérifier
import distributedObjects.HeroGameObject;
import distributedObjects.HeroGameObjectOwner;

/** Ce que le mod a vu passer dans le jeu. */
class Refs {
	public var floor:Null<DistributedDungeonFloor>;
	public var localHero:Null<HeroGameObjectOwner>;
	public var heroes:Map<Int, HeroGameObject> = new Map();

	public function new() {}
}