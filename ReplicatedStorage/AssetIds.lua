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
	  * Icons: each weapon's icon (Tools/Weapons/make_icons.py, from its real
	    picture), uploaded as a decal, by the weapon's key. The Arcade and the
	    Weapons panel show them (as "rbxthumb://type=Asset&id=...").
	Missing ones are fine: a weapon without its model is the blocky one made in
	code, an ability without its animation still does everything else, and one
	without its icon shows a gem in its rarity's colour.
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
	Sounds = {
		Acid_Burst = 139867042768158,
		Acid_Fling = 136152037849230,
		Acid_Hiss = 83892065831641,
		Acid_Swish = 109823321740053,
		Blade_Draw = 89386237683322,
		Dagger_Swing = 71533132223691,
		Eye_Pop = 121016302548274,
		Goo_Clap = 108877685865753,
		Goo_Hit = 131758780577831,
		Goo_Slam = 127471564402598,
		Goo_Splat = 125420332324063,
		Goo_Swish = 140588956075616,
		Hammer_Hit = 88536812599390,
		Hammer_Swing = 118498328188457,
		Jaw_Chomp = 129828757729615,
		Jaw_Open = 107952849825555,
		Jelly_Swing = 75655173218068,
		Jelly_Wave = 131842255063214,
		Jelly_Wobble = 87603903466040,
		Katana_Swing = 113604788077166,
		Scythe_Swing = 106812830416148,
		Slime_Dash = 113921521598499,
		Sword_Hit = 101039186289015,
		Sword_Swing = 108223416687483,
		Whirlwind = 139816322041910,
	},
	Icons = {
		AcidScythe = 92186964822893,
		AnchorFists = 90475736731880,
		BarrelDaggers = 123391948922966,
		BarrelHammer = 106806283849311,
		ChestPoundFists = 71164046592839,
		CopyPasteScythe = 116918761890085,
		DeleteKey = 135189615516880,
		DoodleKatana = 123915264829968,
		EraserHammer = 71395536181403,
		GelatinHammer = 121494823065548,
		GelatinousEdge = 122197652877536,
		GooGloves = 89562644011077,
		HonourBlade = 121873465389193,
		InkFists = 79106520620756,
		Jellyblade = 71398958720929,
		JungleFang = 73093391986288,
		KongsCrown = 115856675263661,
		NitroKatana = 91343085190407,
		NoQuarter = 90688568511869,
		OozeDaggers = 77817232870619,
		PencilSword = 79904152359905,
		PistonPunchers = 97885973037612,
		PitStopSabre = 82972348410690,
		RelicDaggers = 105912214719168,
		ShovelHammer = 83618426645114,
		SpadeScythe = 128055335598226,
		TyreScythe = 116832452543623,
		VictoryLap = 123643157684459,
		VineScythe = 76595267349253,
		WheelieWrecker = 75868539990526,
	},
}
