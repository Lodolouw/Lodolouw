--[[
	AssetIds  (ModuleScript, parent: ReplicatedStorage, name: "AssetIds")

	The ids of things uploaded to Roblox by Tools/Upload/upload_assets.bat (it
	prints them when it's done - they go here):
	  * Models: each voxel weapon's 3D model (Tools/Weapons/out/models/<key>.fbx).
	    The server loads them into ReplicatedStorage > WeaponModels when the game
	    starts (ServerScriptService/WeaponModelLoader); WeaponFX holds them.
	  * Animations: each weapon ability's animation (Tools/Animations, the
	    abilities), by the ability's key.
	  * Sounds: the weapons' sound effects (Tools/Sounds/weapon_sfx.py), by
	    name with _ for spaces. ServerScriptService/SoundLoader puts each in
	    SoundService under its name ("Goo_Splat" -> "Goo Splat").
	Missing ones are fine: a weapon without its model is the blocky one made in
	code, an ability without its animation still does everything else.
]]
return {
	Models = {
		AcidScythe = 104140984967278,
		GelatinHammer = 131062277349121,
		GelatinousEdge = 110987894693619,
		GooGloves = 82980152557659,
		Jellyblade = 96243509826192,
		OozeDaggers = 124118509862140,
	},
	Animations = {
		AcidScythe = 124092425504751,
		GelatinHammer = 112687185619293,
		GelatinousEdge = 95554663647047,
		GooGloves = 108600089777652,
		Jellyblade = 95397064572099,
		OozeDaggers = 128814812173522,
	},
	Sounds = {},
}
