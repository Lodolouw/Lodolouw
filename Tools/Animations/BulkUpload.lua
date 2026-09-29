--[[
	Uploads every animation in a folder at once and prints their IDs - no
	publishing them one by one.

	It has to run as a LOCAL PLUGIN (Roblox only lets plugins upload), so, once:
	  1. In Studio, put a Script anywhere (e.g. ServerStorage), paste all of this in.
	  2. Right-click the Script > "Save as Local Plugin...". Then delete the Script.
	  3. A "Bulk Upload" button shows up in the Plugins tab.

	Then: select the WeaponAnimations folder (the one full of KeyframeSequences,
	e.g. in ServerStorage or RBX_ANIMSAVES) and press the button. Each one is
	uploaded to whoever owns this game (you, or your group - animations only
	play in games their owner owns), and the Output gets a list of
	"Name = rbxassetid://..." lines. Paste those back to Claude and it fills in
	Config.

	(It uses AssetService:CreateAssetAsync. If Roblox refuses, the Output says why.)
]]

local AssetService = game:GetService("AssetService")
local Selection = game:GetService("Selection")

local toolbar = plugin:CreateToolbar("Animations")
local button = toolbar:CreateButton("Bulk Upload", "Upload every KeyframeSequence in the selected folder", "rbxassetid://4458901886")
button.ClickableWhenViewportHidden = true

local busy = false

local function upload(seq, creatorType, creatorId)
	local ok, result, id = pcall(function()
		return AssetService:CreateAssetAsync(seq, Enum.AssetType.Animation, {
			Name = seq.Name,
			Description = "",
			CreatorType = creatorType,
			CreatorId = creatorId,
		})
	end)
	if not ok then
		return nil, tostring(result)
	end
	if result ~= Enum.CreateAssetResult.Success then
		return nil, tostring(result)
	end
	return id
end

button.Click:Connect(function()
	if busy then
		return
	end
	local folder = Selection:Get()[1]
	if not folder then
		warn("[Bulk Upload] Select the folder of animations first.")
		return
	end
	local seqs = {}
	for _, d in folder:GetDescendants() do
		if d:IsA("KeyframeSequence") then
			table.insert(seqs, d)
		end
	end
	if folder:IsA("KeyframeSequence") then
		table.insert(seqs, folder)
	end
	if #seqs == 0 then
		warn("[Bulk Upload] No KeyframeSequences in " .. folder:GetFullName())
		return
	end
	table.sort(seqs, function(a, b)
		return a.Name < b.Name
	end)

	local creatorType, creatorId = Enum.AssetCreatorType.User, game:GetService("StudioService"):GetUserId()
	if game.CreatorType == Enum.CreatorType.Group then
		creatorType, creatorId = Enum.AssetCreatorType.Group, game.CreatorId
	end

	busy = true
	print(("[Bulk Upload] Uploading %d animations..."):format(#seqs))
	local lines, failed = {}, 0
	for i, seq in seqs do
		local id, err = upload(seq, creatorType, creatorId)
		if id then
			table.insert(lines, ("%s = rbxassetid://%d"):format(seq.Name, id))
			print(("[Bulk Upload] %d/%d %s -> %d"):format(i, #seqs, seq.Name, id))
		else
			failed += 1
			warn(("[Bulk Upload] %d/%d %s FAILED: %s"):format(i, #seqs, seq.Name, err))
		end
		task.wait(0.5) -- (gentle on Roblox's upload limit)
	end
	busy = false
	print("[Bulk Upload] Done. " .. (failed > 0 and (failed .. " failed. ") or "") .. "Copy everything below:\n" .. table.concat(lines, "\n"))
end)
