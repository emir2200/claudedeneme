--[[
	Buz Yılanı — animasyon (istemci)

	Bu Script'in RunContext'i "Client"tır: model Workspace'teyken her oyuncunun
	bilgisayarında çalışır, animasyonu orada akıcı biçimde oynatır. Roblox'a
	animasyon yüklemek gerekmez. Sunucu tarafında yılan dinlenme pozunda kalır.

	Modelin öznitelikleri (Properties > Attributes) ile kontrol:
	  OtomatikKukreme (bool)   true ise belirli aralıklarla kendiliğinden saldırıp buz püskürtür.
	  KukremeAraligi  (number) otomatik saldırılar arasındaki saniye (varsayılan 14).
	  KukremeZamani   (number) bir sunucu script'inden saldırtmak için:
	                           yilan:SetAttribute("KukremeZamani", workspace:GetServerTimeNow())
	  AnimasyonHizi   (number) 1 = normal hız.

	Yılanı taşımak için sunucuda yilan:PivotTo(...) kullanın; animasyon "Kok"
	parçasını takip eder. Boyutu Studio'daki Scale aracıyla değiştirebilirsiniz.
]]

local RunService = game:GetService("RunService")

local model = script.Parent
local Rig = require(model:WaitForChild("YilanRig"))
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

local breathEmitters: { ParticleEmitter } = {}
local noseEmitters = {}
for _, d in model:GetDescendants() do
	if d:IsA("ParticleEmitter") then
		if d:GetAttribute("AyazNefesi") then
			table.insert(breathEmitters, d)
		elseif d:GetAttribute("BurunBuhari") then
			table.insert(noseEmitters, { emitter = d, base = d:GetAttribute("TemelHiz") or 10 })
		end
	end
end
local mouthLight = model:FindFirstChild("AgizIsigi", true) :: PointLight?

local FAR_DISTANCE = 700
local FAR_UPDATE_INTERVAL = 0.25

local cframes = table.create(#parts)
local sinceUpdate = math.huge
local breathOn = false

RunService.RenderStepped:Connect(function(dt: number)
	if not root.Parent then
		return
	end
	local rootCF = root.CFrame

	-- Uzaktaki yılanı daha seyrek güncelle.
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

	local _, roar = Rig.roarEnvelope(rt)
	local wantBreath = roar > 0.35
	if wantBreath ~= breathOn then
		breathOn = wantBreath
		for _, e in breathEmitters do
			e.Enabled = wantBreath
		end
	end
	local exhale = if roar > 0 then 0 else Rig.exhale(t)
	for _, n in noseEmitters do
		n.emitter.Rate = n.base * exhale
	end
	if mouthLight then
		mouthLight.Brightness = 5 * roar
	end
end)
