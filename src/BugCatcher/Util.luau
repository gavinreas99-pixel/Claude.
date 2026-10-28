--[[
	Small helpers shared by the server and client scripts.
]]

local Util = {}

-- Makes an Instance and sets its properties in one go:
--   create("Part", { Name = "Rock", Size = Vector3.one, Parent = workspace })
-- Parent is always set last so the instance is fully set up before it replicates.
function Util.create(className, props)
	local instance = Instance.new(className)
	local parent = nil
	for key, value in props or {} do
		if key == "Parent" then
			parent = value
		else
			instance[key] = value
		end
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

-- An anchored part that never collides or blocks raycasts: for decoration.
function Util.decor(props)
	local part = Util.create("Part", {
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		TopSurface = Enum.SurfaceType.Smooth,
		BottomSurface = Enum.SurfaceType.Smooth,
	})
	for key, value in props do
		if key ~= "Parent" then
			part[key] = value
		end
	end
	part.Parent = props.Parent
	return part
end

-- Turns a part into an ellipsoid that fills its Size.
function Util.ellipsoid(part)
	Util.create("SpecialMesh", { MeshType = Enum.MeshType.Sphere, Parent = part })
	return part
end

-- A CFrame at `position` whose cylinder axis (a Part's X axis) points straight up.
function Util.upright(position)
	return CFrame.new(position) * CFrame.Angles(0, 0, math.pi / 2)
end

-- Frame-rate independent smoothing factor: lerp(a, b, Util.smooth(speed, dt)).
function Util.smooth(speed, dt)
	return 1 - math.exp(-speed * dt)
end

function Util.lerp(a, b, t)
	return a + (b - a) * t
end

-- Plays a one-shot sound at a part (or non-positional when parent is SoundService).
function Util.playSound(soundId, parent, volume, pitch)
	if not soundId or soundId == "" then
		return
	end
	local sound = Util.create("Sound", {
		SoundId = soundId,
		Volume = volume or 0.6,
		PlaybackSpeed = pitch or 1,
		RollOffMaxDistance = 80,
		Parent = parent,
	})
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	task.delay(8, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

return Util
