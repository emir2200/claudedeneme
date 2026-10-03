--[[
	Zırhlı Gergedan — animasyon (istemci)

	Bu Script'in RunContext'i "Client"tır: model Workspace'teyken her oyuncunun
	bilgisayarında çalışır, animasyonu orada akıcı biçimde oynatır. Roblox'a
	animasyon yüklemek gerekmez. Sunucu tarafında gergedan dinlenme pozunda kalır.

	Modelin öznitelikleri (Properties > Attributes) ile kontrol:
	  OtomatikKukreme (bool)   true ise belirli aralıklarla kendiliğinden hücum eder.
	  KukremeAraligi  (number) otomatik hücumlar arasındaki saniye (varsayılan 14).
	  KukremeZamani   (number) bir sunucu script'inden hücum ettirmek için:
	                           gergedan:SetAttribute("KukremeZamani", workspace:GetServerTimeNow())
	  AnimasyonHizi   (number) 1 = normal hız.

	Gergedanı taşımak için sunucuda gergedan:PivotTo(...) kullanın; animasyon "Kok"
	parçasını takip eder. Boyutu Studio'daki Scale aracıyla değiştirebilirsiniz.
]]

local RunService = game:GetService("RunService")

local model = script.Parent
local Rig = require(model:WaitForChild("GergedanRig"))
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

-- Parlayan parçalar: aynı nabız gecikmesindekiler birlikte renk değiştirir.
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

-- Sırttan savrulan kıymıklar.
local floaters = {}
for _, f in Rig.floaters do
	local part = findPart(f.name)
	if part then
		table.insert(floaters, { def = f, part = part, shown = -1 })
	end
end

local tossEffects, snortEffects, chargeDust = {}, {}, {}
local scrapeDust: { ParticleEmitter } = {}
for _, d in model:GetDescendants() do
	if d:IsA("ParticleEmitter") then
		local count = d:GetAttribute("Adet") or 10
		if d:GetAttribute("SavurmaEfekti") then
			table.insert(tossEffects, { emitter = d, count = count })
		elseif d:GetAttribute("Soluk") then
			table.insert(snortEffects, { emitter = d, count = count })
		elseif d:GetAttribute("HucumTozu") then
			table.insert(chargeDust, { emitter = d, count = count })
		elseif d:GetAttribute("EseleTozu") then
			table.insert(scrapeDust, d)
		end
	end
end
local hornLight = model:FindFirstChild("BoynuzIsigi", true) :: PointLight?

local GLOW_DIM = Color3.fromRGB(255, 110, 20)
local GLOW_BRIGHT = Color3.fromRGB(255, 220, 130)
local GLOW_STEP = 0.02
local FAR_DISTANCE = 700
local FAR_UPDATE_INTERVAL = 0.25

local cframes = table.create(#parts)
local sinceUpdate = math.huge
local lastRt: number? = nil
local lastSnort = -1
local scraping = false

local function emitAll(list)
	for _, e in list do
		e.emitter:Emit(e.count)
	end
end

RunService.RenderStepped:Connect(function(dt: number)
	if not root.Parent then
		return
	end
	local rootCF = root.CFrame

	-- Uzaktaki gergedanı daha seyrek güncelle.
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
	for i = 1, boneCount do
		cframes[i] = rootCF * boneCFs[bones[i]] * offsets[i]
	end
	for _, leg in legs do
		local frames = Rig.solveLeg(leg.def, boneCFs, t, rt, scale)
		for key, list in leg.groups do
			local frame = rootCF * frames[key]
			for _, piece in list do
				cframes[piece.index] = frame * piece.offset
			end
		end
	end
	workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)

	-- parıltı
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
	if hornLight then
		hornLight.Brightness = 1.2 + 4 * Rig.toss(rt)
	end

	-- savrulan kıymıklar
	for _, f in floaters do
		local pos, rot, fade = Rig.floater(f.def, t)
		f.part.CFrame = rootCF * boneCFs[f.def.bone] * CFrame.new(pos * scale) * rot
		local shown = math.floor(fade * 10 + 0.5) / 10
		if shown ~= f.shown then
			f.shown = shown
			f.part.Transparency = shown
		end
	end

	-- olaylar: burundan soluk (boşta ara sıra, hazırlıkta iki kez), boynuz savurma, hücum tozu
	local snort = math.floor(t / Rig.SNORT_PERIOD)
	if snort ~= lastSnort then
		if lastSnort >= 0 and rt == nil then
			emitAll(snortEffects)
		end
		lastSnort = snort
	end
	if rt then
		local prev = lastRt or -1
		for _, mark in { 0.35, 1.2 } do
			if prev < mark and rt >= mark then
				emitAll(snortEffects)
			end
		end
		if prev < 1.4 and rt >= 1.4 then
			emitAll(chargeDust)
		end
		if prev < 1.7 and rt >= 1.7 then
			emitAll(tossEffects)
		end
	end
	lastRt = rt

	-- yer eşeleme tozu: ayak yere basıp geriye sürtülürken
	local _, _, dusting = Rig.scrapeFoot(Rig.scrape(t, rt))
	if dusting ~= scraping then
		scraping = dusting
		for _, e in scrapeDust do
			e.Enabled = dusting
		end
	end
end)
