--[[
	Üç Başlı Ejderha — animasyon (istemci)

	Bu Script'in RunContext'i "Client"tır: model Workspace'teyken her oyuncunun
	bilgisayarında çalışır, animasyonu orada akıcı biçimde oynatır. Roblox'a
	animasyon yüklemek gerekmez. Sunucu tarafında ejderha dinlenme pozunda kalır.

	Modelin öznitelikleri (Properties > Attributes) ile kontrol:
	  OtomatikKukreme (bool)   true ise belirli aralıklarla kendiliğinden kükrer.
	  KukremeAraligi  (number) otomatik kükremeler arasındaki saniye (varsayılan 15).
	  KukremeZamani   (number) bir sunucu script'inden kükretmek için:
	                           ejderha:SetAttribute("KukremeZamani", workspace:GetServerTimeNow())
	  AnimasyonHizi   (number) 1 = normal hız.

	Ejderhayı taşımak için sunucuda ejderha:PivotTo(...) kullanın; animasyon "Kok"
	parçasını takip eder. Boyutu Studio'daki Scale aracıyla değiştirebilirsiniz.
]]

local RunService = game:GetService("RunService")

local model = script.Parent
local Rig = require(model:WaitForChild("UcBasliRig"))
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

-- Altın şimşekler: her ağız için zikzak çizen neon parçalar.
local bolts = {}
for _, b in Rig.bolts do
	local list = {}
	for _, name in b.parts do
		local part = findPart(name)
		if part then
			table.insert(list, part)
		end
	end
	table.insert(bolts, { bone = b.bone, origin = b.origin * scale, forward = b.forward, parts = list, kinks = {} })
end

local boltEffects: { ParticleEmitter } = {}
local mouthLights: { PointLight } = {}
for _, d in model:GetDescendants() do
	if d:IsA("ParticleEmitter") and d:GetAttribute("SimsekEfekti") then
		table.insert(boltEffects, d)
	elseif d:IsA("PointLight") and d.Name == "AgizIsigi" then
		table.insert(mouthLights, d)
	end
end

local BOLT_LENGTH = 46
local BOLT_ZIGZAG = 2.2
local BOLT_REFRESH = 0.06
local FAR_DISTANCE = 700
local FAR_UPDATE_INTERVAL = 0.25

local cframes = table.create(#parts)
local sinceUpdate = math.huge
local boltsOn = false
local nextKinks = 0
local random = Random.new()

local function point(boneCFs: { CFrame }, rootCF: CFrame, p): Vector3
	return rootCF * (boneCFs[p.bone] * (p.pos * scale))
end

local function hideBolts()
	for _, b in bolts do
		for _, part in b.parts do
			part.Transparency = 1
		end
	end
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

	-- Kükreme: ağızlardan ileri doğru uzayan, sürekli titreyen altın şimşekler.
	local reach = Rig.boltReach(rt)
	local _, roar = Rig.roarEnvelope(rt)
	if reach > 0.02 then
		local clock = os.clock()
		local refresh = clock >= nextKinks
		if refresh then
			nextKinks = clock + BOLT_REFRESH
		end
		for _, b in bolts do
			local headCF = rootCF * boneCFs[b.bone]
			local origin = headCF * b.origin
			local dir = headCF:VectorToWorldSpace(b.forward)
			local right = dir:Cross(Vector3.yAxis)
			right = if right.Magnitude > 1e-3 then right.Unit else Vector3.xAxis
			local up = right:Cross(dir)
			local n = #b.parts
			if refresh then
				for k = 1, n - 1 do
					b.kinks[k] = Vector2.new(random:NextNumber(-1, 1), random:NextNumber(-1, 1))
				end
			end
			local length = BOLT_LENGTH * scale * reach
			local prev = origin
			for k = 1, n do
				local frac = k / n
				local nextPoint = origin + dir * (length * frac)
				local kink = b.kinks[k]
				if kink and k < n then
					nextPoint += (right * kink.X + up * kink.Y) * (BOLT_ZIGZAG * scale * reach)
				end
				local part = b.parts[k]
				local width = (0.35 + 0.25 * random:NextNumber()) * scale
				part.Size = Vector3.new(width, width, (nextPoint - prev).Magnitude + width)
				part.CFrame = CFrame.lookAt((prev + nextPoint) / 2, nextPoint)
				part.Transparency = 0
				prev = nextPoint
			end
		end
		boltsOn = true
	elseif boltsOn then
		hideBolts()
		boltsOn = false
	end

	local sparks = roar > 0.4
	for _, e in boltEffects do
		if e.Enabled ~= sparks then
			e.Enabled = sparks
		end
	end
	for _, l in mouthLights do
		l.Brightness = 6 * reach
	end
end)
