--[[
	Lav Dinozoru — animasyon (istemci)

	Bu Script'in RunContext'i "Client"tır: model Workspace'teyken her oyuncunun
	bilgisayarında çalışır, animasyonu orada akıcı biçimde oynatır. Roblox'a
	animasyon yüklemek gerekmez. Sunucu tarafında dinozor dinlenme pozunda kalır.

	Modelin öznitelikleri (Properties > Attributes) ile kontrol:
	  OtomatikKukreme (bool)   true ise belirli aralıklarla kendiliğinden kükrer.
	  KukremeAraligi  (number) otomatik kükremeler arasındaki saniye (varsayılan 12).
	  KukremeZamani   (number) bir sunucu script'inden kükretmek için:
	                           dinozor:SetAttribute("KukremeZamani", workspace:GetServerTimeNow())
	  AnimasyonHizi   (number) 1 = normal hız.

	Dinozoru taşımak için sunucuda dinozor:PivotTo(...) kullanın; animasyon "Kok"
	parçasını takip eder. Boyutu Studio'daki Scale aracıyla değiştirebilirsiniz.
]]

local RunService = game:GetService("RunService")

local model = script.Parent
local Rig = require(model:WaitForChild("DinozorRig"))
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

-- Lav çatlakları: aynı nabız gecikmesindeki parçalar birlikte renk değiştirir.
local glowGroups = {}
for _, g in Rig.glowGroups do
	local list = {}
	for _, name in g.parts do
		local part = findPart(name)
		if part then
			table.insert(list, part)
		end
	end
	table.insert(glowGroups, { phase = g.phase, parts = list, value = -1, updated = 0 })
end

-- Damlayan lav: her karede asılı olduğu yerden aşağı sarkıtılır, koptuğunda bir damla düşer.
local drips = {}
for _, d in Rig.drips do
	local part = findPart(d.name)
	if part then
		local tip = part:FindFirstChild("DamlaUcu") :: Attachment?
		table.insert(drips, {
			part = part,
			tip = tip,
			emitter = tip and tip:FindFirstChildOfClass("ParticleEmitter"),
			bone = d.bone,
			anchor = d.anchor * scale,
			length = d.length * scale,
			width = d.width * scale,
			period = d.period,
			phase = d.phase,
			count = nil :: number?,
		})
	end
end

local breathEmitters: { ParticleEmitter } = {}
local backEmitters = {}
for _, d in model:GetDescendants() do
	if d:IsA("ParticleEmitter") then
		if d:GetAttribute("AlevNefesi") then
			table.insert(breathEmitters, d)
		elseif d:GetAttribute("SirtAlevi") then
			table.insert(backEmitters, { emitter = d, base = d:GetAttribute("TemelHiz") or d.Rate })
		end
	end
end
local mouthLight = model:FindFirstChild("AgizIsigi", true) :: PointLight?
local bellyLight = model:FindFirstChild("GovdeIsigi", true) :: PointLight?
local backLight = model:FindFirstChild("SirtIsigi", true) :: PointLight?

local GLOW_DIM = Color3.fromRGB(255, 70, 8)
local GLOW_BRIGHT = Color3.fromRGB(255, 190, 70)
local GLOW_STEP = 0.02 -- bundan küçük parlaklık değişimlerinde renkleri yeniden yazma
local GLOW_MIN_INTERVAL = 0.05
local FAR_DISTANCE = 700
local FAR_UPDATE_INTERVAL = 0.25

local cframes = table.create(#parts)
local sinceUpdate = math.huge
local fireOn = false
local backBoost = -1

RunService.RenderStepped:Connect(function(dt: number)
	if not root.Parent then
		return
	end
	local rootCF = root.CFrame

	-- Uzaktaki dinozoru daha seyrek güncelle.
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

	local clock = os.clock()
	for _, g in glowGroups do
		local value = Rig.glow(t, rt, g.phase)
		if math.abs(value - g.value) >= GLOW_STEP and clock - g.updated >= GLOW_MIN_INTERVAL then
			g.value = value
			g.updated = clock
			local color = GLOW_DIM:Lerp(GLOW_BRIGHT, value)
			for _, part in g.parts do
				part.Color = color
			end
		end
	end

	local down = -rootCF.UpVector
	local rotation = rootCF.Rotation
	for _, d in drips do
		local top = rootCF * (boneCFs[d.bone] * d.anchor)
		local amount, count = Rig.dripCycle(t, d.period, d.phase)
		local len = d.length * amount
		d.part.Size = Vector3.new(d.width, len, d.width)
		d.part.CFrame = rotation + (top + down * (len * 0.45))
		if d.tip then
			d.tip.Position = Vector3.new(0, -len * 0.5, 0)
		end
		if count ~= d.count then
			if d.count and d.emitter then
				d.emitter:Emit(1)
			end
			d.count = count
		end
	end

	local windup, roar = Rig.roarEnvelope(rt)
	local wantFire = roar > 0.4
	if wantFire ~= fireOn then
		fireOn = wantFire
		for _, emitter in breathEmitters do
			emitter.Enabled = wantFire
		end
	end
	local boost = math.floor((1 + 2.5 * math.max(roar, windup * 0.5)) * 10 + 0.5) / 10
	if boost ~= backBoost then
		backBoost = boost
		for _, e in backEmitters do
			e.emitter.Rate = e.base * boost
		end
	end
	if mouthLight then
		mouthLight.Brightness = 1 + 6 * roar
	end
	if bellyLight then
		bellyLight.Brightness = 0.6 + 1.6 * Rig.glow(t, rt, 0)
	end
	if backLight then
		backLight.Brightness = 1.4 + 0.4 * math.sin(t * 11) * math.sin(t * 6.7) + 2.5 * roar
	end
end)
