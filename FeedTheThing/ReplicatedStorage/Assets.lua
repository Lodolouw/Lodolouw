--[[
	Assets  (ModuleScript, parent: ReplicatedStorage, name: "Assets")

	Props made in Blender (FeedTheThing/Blender/build_props.py), ready to use.

	upload.bat uploads FeedTheThing/Blender/Export/FeedTheThing_Props.fbx and
	the server loads it into ReplicatedStorage as "Props" (or import it by
	hand, name it "Props" and put it in ReplicatedStorage). Inside are parts
	named <Prop>_<Part> (Truck_Body, Truck_WheelFL, Package_Box...) plus two
	marker blocks per prop, <Prop>_Origin and <Prop>_MarkX, 10 studs apart.
	Assets.get("Truck") puts a prop together from those: the right size, the
	right way round (facing -Z), its base at its pivot. Parts named
	<Prop>_<Role>_<RRGGBB> (the Thinglets) get that colour and a "Role"
	attribute (Body, Eye, Accent); Role Glow glows in that colour.

	Not there at all? Assets.get returns nil and the game
	uses a simple stand-in built from blocks (see Looks).
]]

local Assets = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local templates = {} -- [prop name] = Model
local lastTry = {} -- [prop name] = when we last looked and didn't find it

local function source()
	local folder = ReplicatedStorage:FindFirstChild("Props")
	if folder then
		return folder
	end
	-- still named after the file (or an old import named "Assets")?
	for _, child in ipairs(ReplicatedStorage:GetChildren()) do
		if not child:IsA("ModuleScript") and child:FindFirstChild("Truck_Origin", true) then
			return child
		end
	end
	return nil
end

local function build(name)
	local folder = source()
	if not folder then
		return nil
	end
	local origin = folder:FindFirstChild(name .. "_Origin", true)
	local markX = folder:FindFirstChild(name .. "_MarkX", true)
	if not (origin and markX and origin:IsA("BasePart") and markX:IsA("BasePart")) then
		return nil
	end
	-- how the import placed it: the markers are 10 studs apart along the prop's +X
	local along = markX.Position - origin.Position
	local distance = along.Magnitude
	if distance < 0.0001 then
		return nil
	end
	local scale = 10 / distance
	local frame = CFrame.fromMatrix(origin.Position, along.Unit, Vector3.yAxis)

	local model = Instance.new("Model")
	model.Name = name
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(0.2, 0.2, 0.2)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CFrame = CFrame.new()
	root.Parent = model
	model.PrimaryPart = root

	local prefix = name .. "_"
	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("BasePart") and string.sub(d.Name, 1, #prefix) == prefix and d ~= origin and d ~= markX then
			local part = d:Clone()
			local relative = frame:ToObjectSpace(d.CFrame)
			part.Size = d.Size * scale
			part.CFrame = CFrame.new(relative.Position * scale) * relative.Rotation
			part.Name = string.sub(d.Name, #prefix + 1)
			part.Anchored = true
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
			-- <Role>_<RRGGBB>: one flat colour (creatures). Role Glow = glowing Neon.
			local role, hex = string.match(part.Name, "^(%a+)_(%x%x%x%x%x%x)")
			if role then
				part.Color = Color3.fromHex(hex)
				part.Material = Enum.Material.SmoothPlastic
				if role == "Glow" then
					part.Material = Enum.Material.Neon
					part.CastShadow = false
					role = "Accent"
				end
				part:SetAttribute("Role", role)
				part.Name = role
			end
			part.Parent = model
		end
	end
	return model
end

-- A fresh copy of prop `name`, or nil if it hasn't been imported
function Assets.get(name)
	if not templates[name] and os.clock() - (lastTry[name] or -100) > 5 then
		lastTry[name] = os.clock()
		local ok, result = pcall(build, name)
		if not ok then
			warn("[Assets] Couldn't put together '" .. name .. "': " .. tostring(result))
		elseif result then
			templates[name] = result
		end
	end
	local template = templates[name]
	return template and template:Clone() or nil
end

return Assets
