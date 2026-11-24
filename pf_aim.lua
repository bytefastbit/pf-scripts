--[[
	Phantom Forces — Humanized Aimbot
	Executor: Solara (or anything with HttpGet)
	Place ID: 292439477

	Load:
		loadstring(game:HttpGet("https://raw.githubusercontent.com/<you>/<repo>/main/pf_aim.lua"))()

	Tune live in the console:  getgenv().PFAim.FOV = 100
	Unload:                    getgenv().PFAimUnload()
--]]

if game.PlaceId ~= 292439477 then
	warn("[PF Aim] Join Phantom Forces first.")
	return
end

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace  = game:GetService("Workspace")
local UIS        = game:GetService("UserInputService")
local SG         = game:GetService("StarterGui")

local LP = Players.LocalPlayer

--=========================== CONFIG ===========================
local CONFIG = {
	FOV           = 140,                      -- screen-pixel radius
	MaxDistance   = 450,                      -- studs
	Smoothness    = 7,                        -- higher = slower, more human snap
	MissChance    = 0.18,                     -- chance of a deliberate drift per roll
	Jitter        = 0.5,                      -- degrees of constant micro-shake
	HeadBias      = 0.7,                      -- 0.7 = 70% head, 30% torso
	Prediction    = 0.6,                      -- lead on moving targets
	VisibleOnly   = true,
	TeamCheck     = true,
	ReactionMin   = 0.09,                     -- human reaction delay (s)
	ReactionMax   = 0.22,
	HoldKey       = Enum.UserInputType.MouseButton2,
	ToggleMode    = false,                    -- true = press to toggle
}
getgenv().PFAim = CONFIG
--==============================================================

local state = {
	enabled     = true,
	holding     = false,
	model       = nil,
	reactUntil  = 0,
	wantHead    = true,
	smooth      = CONFIG.Smoothness,
	missUntil   = 0,
	missOffset  = Vector2.new(),
	nextMissRoll = 0,
}

local function rnd(a, b) return a + math.random() * (b - a) end
local function now() return os.clock() end

local function isAlive(model)
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum then return hum.Health > 0 end
	return model:FindFirstChild("Head") ~= nil
end

local function sameTeam(model)
	if not CONFIG.TeamCheck then return false end
	local plr = Players:FindFirstChild(model.Name)
	if not plr or not plr.Team then return false end
	return plr.Team == LP.Team
end

local PRIORITY = {
	head = { "Head", "UpperTorso", "Torso", "LowerTorso" },
	body = { "UpperTorso", "Torso", "LowerTorso", "Head" },
}

local function pickHitbox(model, wantHead)
	for _, name in ipairs(wantHead and PRIORITY.head or PRIORITY.body) do
		local p = model:FindFirstChild(name, true)
		if p and p:IsA("BasePart") then return p end
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then return d end
	end
	return nil
end

local rparams = RaycastParams.new()
rparams.FilterType = Enum.RaycastFilterType.Exclude
local IGNORE = { "FX", "Effects", "Debris" }

local function buildFilter(model, cam)
	local list = { model }
	if LP.Character then table.insert(list, LP.Character) end
	table.insert(list, cam)
	for _, n in ipairs(IGNORE) do
		local f = Workspace:FindFirstChild(n)
		if f then table.insert(list, f) end
	end
	return list
end

local function canSee(part, model, cam)
	rparams.FilterDescendantsInstances = buildFilter(model, cam)
	local res = Workspace:Raycast(cam.CFrame.Position, part.Position - cam.CFrame.Position, rparams)
	return res == nil or res.Instance:IsDescendantOf(model)
end

local function getFolder()
	return Workspace:FindFirstChild("Players") or Workspace:FindFirstChild("Characters")
end

local function findBest()
	local cam = Workspace.CurrentCamera
	local folder = getFolder()
	if not cam or not folder then return nil end

	local center = Vector2.new(cam.ViewportSize.X * 0.5, cam.ViewportSize.Y * 0.5)
	local best, bestScore = nil, math.huge

	for _, model in ipairs(folder:GetChildren()) do
		if model:IsA("Model") and model.Name ~= LP.Name and isAlive(model) and not sameTeam(model) then
			local part = pickHitbox(model, state.wantHead)
			if part then
				local origin = cam.CFrame.Position
				local dist = (part.Position - origin).Magnitude
				if dist <= CONFIG.MaxDistance then
					local sp, onScreen = cam:WorldToViewportPoint(part.Position)
					if onScreen and sp.Z > 0 then
						local sdist = (Vector2.new(sp.X, sp.Y) - center).Magnitude
						if sdist <= CONFIG.FOV then
							if not CONFIG.VisibleOnly or canSee(part, model, cam) then
								local score = sdist + dist * 0.06
								if score < bestScore then
									best, bestScore = model, score
								end
							end
						end
					end
				end
			end
		end
	end
	return best
end

local circle
pcall(function()
	circle = Drawing.new("Circle")
	circle.Thickness, circle.Color = 1, Color3.fromRGB(120, 200, 255)
	circle.Filled, circle.Transparency = false, 0.7
	circle.NumSides, circle.Visible = 64, false
end)

local function onRender(dt)
	dt = math.min(dt, 1 / 20)
	local cam = Workspace.CurrentCamera
	if not cam then return end

	local center = Vector2.new(cam.ViewportSize.X * 0.5, cam.ViewportSize.Y * 0.5)
	if circle then
		circle.Position, circle.Radius = center, CONFIG.FOV
		circle.Visible = state.enabled
	end

	if not (state.enabled and state.holding) then
		state.model = nil
		return
	end

	local t = now()
	local model = state.model
	if model and (not model.Parent or not isAlive(model) or sameTeam(model)) then
		model = nil
	end

	if not model then
		model = findBest()
		if not model then
			state.model = nil
			return
		end
		state.model = model
		state.reactUntil  = t + rnd(CONFIG.ReactionMin, CONFIG.ReactionMax)
		state.wantHead    = math.random() < CONFIG.HeadBias
		state.smooth      = CONFIG.Smoothness * rnd(0.85, 1.15)
		state.nextMissRoll = t + rnd(0.1, 0.35)
		state.missUntil   = 0
	end

	if t < state.reactUntil then return end

	local part = pickHitbox(model, state.wantHead)
	if not part then return end

	local origin = cam.CFrame.Position
	local dist = (part.Position - origin).Magnitude
	if dist > CONFIG.MaxDistance then
		state.model = nil
		return
	end

	-- deliberate miss roll
	if t >= state.nextMissRoll then
		state.nextMissRoll = t + rnd(0.12, 0.5)
		if math.random() < CONFIG.MissChance then
			state.missUntil = t + rnd(0.08, 0.4)
			local mag = rnd(0.9, 4.2)
			local a = math.random() * math.pi * 2
			state.missOffset = Vector2.new(math.cos(a), math.sin(a)) * mag
		end
	end

	local yaw, pitch = 0, 0
	if t < state.missUntil then
		yaw   = yaw   + state.missOffset.X
		pitch = pitch + state.missOffset.Y
	end
	yaw   = yaw   + rnd(-1, 1) * CONFIG.Jitter
	pitch = pitch + rnd(-1, 1) * CONFIG.Jitter

	local aimPos = part.Position + part.AssemblyLinearVelocity * (dist / 800) * CONFIG.Prediction
	local dir    = (aimPos - origin).Unit
	local goal   = CFrame.new(origin, origin + dir) * CFrame.Angles(math.rad(pitch), math.rad(yaw), 0)
	local alpha  = 1 - math.exp(-(60 / math.max(state.smooth, 0.5)) * dt)

	cam.CFrame = cam.CFrame:Lerp(goal, alpha)
end

local lastErr
RunService:BindToRenderStep("PFAim", Enum.RenderPriority.Camera.Value + 1, function(dt)
	local ok, err = pcall(onRender, dt)
	if not ok and err ~= lastErr then
		lastErr = err
		warn("[PF Aim] " .. tostring(err))
	end
end)

UIS.InputBegan:Connect(function(input, gp)
	if gp and input.UserInputType == Enum.UserInputType.Keyboard then return end
	if input.UserInputType == CONFIG.HoldKey or input.KeyCode == CONFIG.HoldKey then
		if CONFIG.ToggleMode then
			state.enabled = not state.enabled
			state.holding = state.enabled
		else
			state.holding = true
		end
	end
end)

UIS.InputEnded:Connect(function(input)
	if CONFIG.ToggleMode then return end
	if input.UserInputType == CONFIG.HoldKey or input.KeyCode == CONFIG.HoldKey then
		state.holding = false
		state.model = nil
	end
end)

getgenv().PFAimUnload = function()
	RunService:UnbindFromRenderStep("PFAim")
	if circle then circle:Remove() end
end

pcall(function()
	SG:SetCore("SendNotification", {
		Title = "PF Humanized Aim",
		Text = "Hold RMB to aim — getgenv().PFAim to tune",
		Duration = 5,
	})
end)
print("[PF Aim] loaded")