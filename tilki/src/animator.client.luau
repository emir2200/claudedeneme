--[[
	Dokuz Kuyruklu Tilki — animasyon (istemci)

	Bu Script'in RunContext'i "Client"tır: model Workspace'teyken her oyuncunun
	bilgisayarında çalışır, animasyonu orada akıcı biçimde oynatır. Roblox'a
	animasyon yüklemek gerekmez. Sunucu tarafında tilki dinlenme pozunda kalır.

	Modelin öznitelikleri (Properties > Attributes) ile kontrol:
	  OtomatikKukreme (bool)   true ise belirli aralıklarla kendiliğinden ulur ve tilki ateşleri çağırır.
	  KukremeAraligi  (number) otomatik ulumalar arasındaki saniye (varsayılan 15).
	  KukremeZamani   (number) bir sunucu script'inden ulutmak için:
	                           tilki:SetAttribute("KukremeZamani", workspace:GetServerTimeNow())
	  AnimasyonHizi   (number) 1 = normal hız.

	Tilkiyi taşımak için sunucuda tilki:PivotTo(...) kullanın; animasyon "Kok"
	parçasını takip eder. Boyutu Studio'daki Scale aracıyla değiştirebilirsiniz.
]]

local RunService = game:GetService("RunService")

local model = script.Parent
local Rig = require(model:WaitForChild("TilkiRig"))
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
local function findAll(names: { string }): { BasePart }
	local list = {}
	for _, name in names do
		local part = findPart(name)
		if part then
			table.insert(list, part)
		end
	end
	return list
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

local lids = findAll(Rig.lids)
local marks = findAll(Rig.marks)
local halo = findAll(Rig.halo)
local haloLight = model:FindFirstChild("HaleIsigi", true) :: PointLight?

-- Tilki ateşleri: her biri bir kuyruğun ucundan çıkar.
local orbs = {}
for k, name in Rig.orbs do
	local part = findPart(name)
	if part then
		table.insert(orbs, {
			part = part,
			tail = Rig.tails[k],
			flame = part:FindFirstChildOfClass("ParticleEmitter"),
			light = part:FindFirstChildOfClass("PointLight"),
			size = part.Size * scale,
		})
	end
end

local MARK_DIM = Color3.fromRGB(70, 165, 255)
local MARK_BRIGHT = Color3.fromRGB(215, 245, 255)
local HALO_DIM = Color3.fromRGB(255, 222, 150)
local HALO_BRIGHT = Color3.fromRGB(255, 250, 225)
local ORBIT_CENTER = Vector3.new(0, 8.5, 0.6)
local ORBIT_RADIUS = 6.5
local FAR_DISTANCE = 700
local FAR_UPDATE_INTERVAL = 0.25

local cframes = table.create(#parts)
local sinceUpdate = math.huge
local blinking = false
local orbsOn = false
local glowLevel = -1

RunService.RenderStepped:Connect(function(dt: number)
	if not root.Parent then
		return
	end
	local rootCF = root.CFrame

	-- Uzaktaki tilkiyi daha seyrek güncelle.
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

	-- göz kırpma
	local blink = Rig.blink(t)
	if blink ~= blinking then
		blinking = blink
		for _, lid in lids do
			lid.Transparency = if blink then 0 else 1
		end
	end

	-- ulurken alındaki işaret ve hale parlar
	local _, roar = Rig.roarEnvelope(rt)
	local level = math.floor(roar * 20 + 0.5) / 20
	if level ~= glowLevel then
		glowLevel = level
		local markColor = MARK_DIM:Lerp(MARK_BRIGHT, level)
		for _, p in marks do
			p.Color = markColor
		end
		local haloColor = HALO_DIM:Lerp(HALO_BRIGHT, level)
		for _, p in halo do
			p.Color = haloColor
		end
	end
	if haloLight then
		haloLight.Brightness = 1 + 4 * roar
	end

	-- tilki ateşleri: kuyruk uçlarından çıkıp tilkinin çevresinde döner
	local fire = Rig.foxfire(rt)
	if fire > 0.02 then
		local center = rootCF * (ORBIT_CENTER * scale)
		for k, orb in orbs do
			local tip = rootCF * (boneCFs[orb.tail.bones[4]] * (orb.tail.tip * scale))
			local angle = (k - 1) / #orbs * math.pi * 2 + t * 1.4
			local ring = rootCF:VectorToWorldSpace(Vector3.new(math.cos(angle), 0.18 * math.sin(t * 2 + k), math.sin(angle)))
			local target = center + ring * (ORBIT_RADIUS * scale)
			orb.part.CFrame = CFrame.new(tip:Lerp(target, fire))
			orb.part.Size = orb.size * (0.4 + 0.6 * fire)
			if orb.light then
				orb.light.Brightness = 3 * fire
			end
		end
		if not orbsOn then
			orbsOn = true
			for _, orb in orbs do
				orb.part.Transparency = 0
				if orb.flame then
					orb.flame.Enabled = true
				end
			end
		end
	elseif orbsOn then
		orbsOn = false
		for _, orb in orbs do
			orb.part.Transparency = 1
			if orb.flame then
				orb.flame.Enabled = false
			end
			if orb.light then
				orb.light.Brightness = 0
			end
		end
	end
end)
