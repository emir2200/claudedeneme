--[[
	Lav Golemi — animasyon (istemci)

	Bu Script'in RunContext'i "Client"tır: model Workspace'teyken her oyuncunun
	bilgisayarında çalışır, animasyonu orada akıcı biçimde oynatır. Roblox'a
	animasyon yüklemek gerekmez. Sunucu tarafında golem dinlenme pozunda kalır.

	Modelin öznitelikleri (Properties > Attributes) ile kontrol:
	  OtomatikKukreme  (bool)   true ise belirli aralıklarla kendiliğinden yere vurur.
	  KukremeAraligi   (number) otomatik saldırılar arasındaki saniye (varsayılan 14).
	  KukremeZamani    (number) bir sunucu script'inden saldırtmak için:
	                            golem:SetAttribute("KukremeZamani", workspace:GetServerTimeNow())
	  AnimasyonHizi    (number) 1 = normal hız.
	  KameraSarsintisi (bool)   true ise yere vurunca yakındaki oyuncunun kamerası sarsılır.

	Golemi taşımak için sunucuda golem:PivotTo(...) kullanın; animasyon "Kok"
	parçasını takip eder. Boyutu Studio'daki Scale aracıyla değiştirebilirsiniz.
]]

local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local model = script.Parent
local Rig = require(model:WaitForChild("GolemRig"))
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
local function scaled(offset: CFrame): CFrame
	return CFrame.new(offset.Position * scale) * offset.Rotation
end

-- Kemiklere bağlı parçalar.
local parts: { BasePart } = {}
local bones: { number } = {}
local offsets: { CFrame } = {}
for _, def in Rig.parts do
	local part = findPart(def.name)
	if part then
		table.insert(parts, part)
		table.insert(bones, def.bone)
		table.insert(offsets, scaled(def.offset))
	end
end
local boneCount = #parts

-- Bacak parçaları: her bacağın bölümlerine bağlı; bölüm çerçeveleri her karede IK ile çözülür.
local legs = {}
for _, leg in Rig.legs do
	local entry = { def = leg, groups = {} }
	for key, list in leg.groups do
		entry.groups[key] = {}
		for _, piece in list do
			local part = findPart(piece.name)
			if part then
				table.insert(parts, part)
				table.insert(entry.groups[key], { index = #parts, offset = scaled(piece.offset) })
			end
		end
	end
	table.insert(legs, entry)
end

-- Lav çekirdekleri: aynı nabız gecikmesindeki parçalar birlikte renk değiştirir.
local glowGroups = {}
for _, g in Rig.glowGroups do
	local list = {}
	for _, name in g.parts do
		local part = findPart(name)
		if part then
			table.insert(list, part)
		end
	end
	table.insert(glowGroups, { phase = g.phase, parts = list, value = -1 })
end
local eyes: { BasePart } = {}
for _, name in Rig.eyes do
	local part = findPart(name)
	if part then
		table.insert(eyes, part)
	end
end

local impactEffects = {}
for _, d in model:GetDescendants() do
	if d:IsA("ParticleEmitter") and d:GetAttribute("VurusEfekti") then
		table.insert(impactEffects, { emitter = d, count = d:GetAttribute("Adet") or 30 })
	end
end
local ring = model:FindFirstChild("SokDalgasi1", true) :: BasePart?
local chestLight = model:FindFirstChild("GogusIsigi", true) :: PointLight?

local GLOW_DIM = Color3.fromRGB(255, 70, 8)
local GLOW_BRIGHT = Color3.fromRGB(255, 205, 90)
local EYE_DIM = Color3.fromRGB(255, 150, 30)
local EYE_BRIGHT = Color3.fromRGB(255, 245, 170)
local GLOW_STEP = 0.02
local RING_OFFSET = CFrame.new(0, 0.12, -4.8) * CFrame.Angles(0, 0, math.pi / 2)
local SHAKE_DISTANCE = 90
local SHAKE_DURATION = 0.6
local FAR_DISTANCE = 700
local FAR_UPDATE_INTERVAL = 0.25

local cframes = table.create(#parts)
local sinceUpdate = math.huge
local lastRt: number? = nil
local shakeUntil = 0
local shakeStrength = 0
local random = Random.new()

-- Kamera sarsıntısı: kamera betiğinden hemen sonra çalışır, kamerayı küçük ve sönen açılarla sarsar.
RunService:BindToRenderStep("GolemSarsinti" .. HttpService:GenerateGUID(false), Enum.RenderPriority.Camera.Value + 1, function()
	local left = shakeUntil - os.clock()
	local camera = workspace.CurrentCamera
	if left > 0 and camera then
		local k = shakeStrength * (left / SHAKE_DURATION)
		camera.CFrame *= CFrame.Angles(random:NextNumber(-1, 1) * 0.012 * k, random:NextNumber(-1, 1) * 0.012 * k, random:NextNumber(-1, 1) * 0.008 * k)
	end
end)

RunService.RenderStepped:Connect(function(dt: number)
	if not root.Parent then
		return
	end
	local rootCF = root.CFrame

	-- Uzaktaki golemi daha seyrek güncelle.
	sinceUpdate += dt
	local camera = workspace.CurrentCamera
	local distance = if camera then (camera.CFrame.Position - rootCF.Position).Magnitude else 0
	if distance > FAR_DISTANCE * scale and sinceUpdate < FAR_UPDATE_INTERVAL then
		return
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
	for i = 1, boneCount do
		cframes[i] = rootCF * boneCFs[bones[i]] * offsets[i]
	end
	for _, leg in legs do
		local frames = Rig.solveLeg(leg.def, boneCFs, scale)
		for key, list in leg.groups do
			local frame = rootCF * frames[key]
			for _, piece in list do
				cframes[piece.index] = frame * piece.offset
			end
		end
	end
	workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)

	-- lav çatlakları ve gözler
	for _, g in glowGroups do
		local value = Rig.glow(t, rt, g.phase)
		if math.abs(value - g.value) >= GLOW_STEP then
			g.value = value
			local color = GLOW_DIM:Lerp(GLOW_BRIGHT, value)
			for _, part in g.parts do
				part.Color = color
			end
		end
	end
	local raise, slam = Rig.roarEnvelope(rt)
	local eyeColor = EYE_DIM:Lerp(EYE_BRIGHT, math.max(raise, slam))
	for _, eye in eyes do
		if eye.Color ~= eyeColor then
			eye.Color = eyeColor
		end
	end
	if chestLight then
		chestLight.Brightness = 1 + 1.5 * Rig.glow(t, rt, 0) + 3 * slam
	end

	-- yere vurma anı: toz, lav, kaya parçaları ve kamera sarsıntısı
	if rt and rt >= Rig.SLAM_TIME and (lastRt == nil or lastRt < Rig.SLAM_TIME) then
		for _, e in impactEffects do
			e.emitter:Emit(e.count)
		end
		if model:GetAttribute("KameraSarsintisi") ~= false and distance < SHAKE_DISTANCE * scale then
			shakeStrength = 1 - distance / (SHAKE_DISTANCE * scale)
			shakeUntil = os.clock() + SHAKE_DURATION
		end
	end
	lastRt = rt

	-- şok dalgası halkası
	if ring then
		local k = Rig.shockwave(rt)
		if k then
			local d = (4 + 40 * k) * scale
			ring.Size = Vector3.new(0.15 * scale, d, d)
			ring.CFrame = rootCF * CFrame.new(RING_OFFSET.Position * scale) * RING_OFFSET.Rotation
			ring.Transparency = 0.15 + 0.85 * k
		elseif ring.Transparency < 1 then
			ring.Transparency = 1
		end
	end
end)
