--[[
	Ateş Ejderhası — animasyon (istemci)

	Bu Script'in RunContext'i "Client"tır: model Workspace'teyken her oyuncunun
	bilgisayarında çalışır, animasyonu orada akıcı biçimde oynatır. Roblox'a
	animasyon yüklemek gerekmez. Sunucu tarafında ejderha dinlenme pozunda kalır.

	Modelin öznitelikleri (Properties > Attributes) ile kontrol:
	  OtomatikKukreme (bool)   true ise belirli aralıklarla kendiliğinden kükrer.
	  KukremeAraligi  (number) otomatik kükremeler arasındaki saniye (varsayılan 14).
	  KukremeZamani   (number) bir sunucu script'inden kükretmek için:
	                           ejderha:SetAttribute("KukremeZamani", workspace:GetServerTimeNow())
	  AnimasyonHizi   (number) 1 = normal hız.

	Ejderhayı taşımak için sunucuda ejderha:PivotTo(...) kullanın; animasyon "Kok"
	parçasını takip eder. Boyutu Studio'daki Scale aracıyla değiştirebilirsiniz.
]]

local RunService = game:GetService("RunService")

local model = script.Parent
local Rig = require(model:WaitForChild("EjderhaRig"))
local root = model:WaitForChild("Kok") :: BasePart
local scale = model:GetScale()

local function findPart(name: string): BasePart?
	local deadline = os.clock() + 10
	local found = model:FindFirstChild(name, true)
	while not found and os.clock() < deadline do
		task.wait(0.2)
		found = model:FindFirstChild(name, true)
	end
	return found :: BasePart?
end

-- Kemiklere bağlı parçalar ve kemiğe göre konumları (ölçeğe uyarlanmış).
local parts: { BasePart } = {}
local bones: { number } = {}
local offsets: { CFrame } = {}
for _, def in Rig.parts do
	local part = findPart(def.name)
	if part then
		table.insert(parts, part)
		table.insert(bones, def.bone)
		table.insert(offsets, CFrame.new(def.offset.Position * scale) * def.offset.Rotation)
	end
end

-- Kanat zarları: her üçgen iki WedgePart ile her karede yeniden çizilir.
local membranes = {}
for _, m in Rig.membranes do
	local w0, w1 = findPart(m.a), findPart(m.b)
	if w0 and w1 then
		table.insert(membranes, { w0 = w0, w1 = w1, points = m.points, thickness = m.thickness * scale })
	end
end

local glowParts: { BasePart } = {}
for _, name in Rig.glowParts do
	local part = findPart(name)
	if part then
		table.insert(glowParts, part)
	end
end

local fireEmitters: { ParticleEmitter } = {}
for _, d in model:GetDescendants() do
	if d:IsA("ParticleEmitter") and d:GetAttribute("AlevNefesi") then
		table.insert(fireEmitters, d)
	end
end
local mouthLight = model:FindFirstChild("AgizIsigi", true) :: PointLight?
local chestLight = model:FindFirstChild("GogusIsigi", true) :: PointLight?

local GLOW_DIM = Color3.fromRGB(255, 78, 14)
local GLOW_BRIGHT = Color3.fromRGB(255, 200, 90)
local FAR_DISTANCE = 700
local FAR_UPDATE_INTERVAL = 0.25

local cframes = table.create(#parts)
local sinceUpdate = math.huge
local fireOn = false

local function point(boneCFs: { CFrame }, rootCF: CFrame, p): Vector3
	return rootCF * (boneCFs[p.bone] * (p.pos * scale))
end

RunService.RenderStepped:Connect(function(dt: number)
	if not root.Parent then
		return
	end
	local rootCF = root.CFrame

	-- Uzaktaki ejderhayı daha seyrek güncelle.
	sinceUpdate += dt
	local camera = workspace.CurrentCamera
	if camera and (camera.CFrame.Position - rootCF.Position).Magnitude > FAR_DISTANCE * scale then
		if sinceUpdate < FAR_UPDATE_INTERVAL then
			return
		end
	end
	sinceUpdate = 0

	local now = workspace:GetServerTimeNow()
	local rt = Rig.roarTime(
		now,
		model:GetAttribute("OtomatikKukreme") ~= false,
		model:GetAttribute("KukremeAraligi") or Rig.ROAR_INTERVAL,
		model:GetAttribute("KukremeZamani")
	)
	local t = now * (model:GetAttribute("AnimasyonHizi") or 1)

	local boneCFs = Rig.solve(Rig.pose(t, rt), scale)
	for i, part in parts do
		cframes[i] = rootCF * boneCFs[bones[i]] * offsets[i]
	end
	workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)

	for _, m in membranes do
		local cf0, s0, cf1, s1 = Rig.triangle(
			point(boneCFs, rootCF, m.points[1]),
			point(boneCFs, rootCF, m.points[2]),
			point(boneCFs, rootCF, m.points[3])
		)
		if cf0 and s0 and cf1 and s1 then
			m.w0.Size = Vector3.new(m.thickness, s0.Y, s0.Z)
			m.w0.CFrame = cf0
			m.w1.Size = Vector3.new(m.thickness, s1.Y, s1.Z)
			m.w1.CFrame = cf1
		end
	end

	local glow = Rig.glow(t, rt)
	local color = GLOW_DIM:Lerp(GLOW_BRIGHT, glow)
	for _, part in glowParts do
		part.Color = color
	end

	local _, roar = Rig.roarEnvelope(rt)
	local wantFire = roar > 0.45
	if wantFire ~= fireOn then
		fireOn = wantFire
		for _, emitter in fireEmitters do
			emitter.Enabled = wantFire
		end
	end
	if mouthLight then
		mouthLight.Brightness = 0.5 + 7 * roar
	end
	if chestLight then
		chestLight.Brightness = 0.8 + 2.4 * glow
	end
end)
