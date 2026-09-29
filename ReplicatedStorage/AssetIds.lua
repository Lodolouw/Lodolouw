--[[
	AssetIds  (ModuleScript, parent: ReplicatedStorage, name: "AssetIds")

	The ids of things uploaded to Roblox by Tools/Upload/upload_assets.bat (it
	prints them when it's done - they go here):
	  * Models: each voxel weapon's 3D model (Tools/Weapons/out/models/<key>.fbx).
	    The server loads them into ReplicatedStorage > WeaponModels when the game
	    starts (ServerScriptService/WeaponModelLoader); WeaponFX holds them.
	  * Animations: each weapon ability's animation (Tools/Animations, the
	    abilities), by the ability's key.
	Missing ones are fine: a weapon without its model is the blocky one made in
	code, an ability without its animation still does everything else.
]]
return {
	Models = {},
	Animations = {},
}
