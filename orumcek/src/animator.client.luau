--[[
	Orman Örümceği — animasyon (istemci)

	Bu Script'in RunContext'i "Client"tır: model Workspace'teyken her oyuncunun
	bilgisayarında çalışır, animasyonu orada akıcı biçimde oynatır. Roblox'a
	animasyon yüklemek gerekmez. Sunucu tarafında örümcek dinlenme pozunda kalır.

	Modelin öznitelikleri (Properties > Attributes) ile kontrol:
	  OtomatikKukreme (bool)   true ise belirli aralıklarla kendiliğinden saldırıp zehir püskürtür.
	  KukremeAraligi  (number) otomatik saldırılar arasındaki saniye (varsayılan 13).
	  KukremeZamani   (number) bir sunucu script'inden saldırtmak için:
	                           orumcek:SetAttribute("KukremeZamani", workspace:GetServerTimeNow())
	  AnimasyonHizi   (number) 1 = normal hız.

	Örümceği taşımak için sunucuda orumcek:PivotTo(...) kullanın; animasyon "Kok"
	parçasını takip eder. Boyutu Studio'daki Scale aracıyla değiştirebilirsiniz.
]]

local RunService = game:GetService("RunService")

local model = script.Parent
local Rig = require(model:WaitForChild("OrumcekRig"))
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

-- Kemiklere bağlı gövde parçaları.
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

-- Bacak parçaları: her bacağın üst ve alt bölümüne bağlı; bölüm çerçeveleri her karede IK ile çözülür.
local legs = {}
for _, leg in Rig.legs do
	local entry = { def = leg, upper = {}, lower = {} }
	for _, key in { "upper", "lower" } do
		for _, piece in leg[key] do
			local part = findPart(piece.name)
			if part then
				table.insert(parts, part)
				table.insert(entry[key], { index = #parts, offset = scaled(piece.offset) })
			end
		end
	end
	table.insert(legs, entry)
end

local venomEmitters: { ParticleEmitter } = {}
for _, d in model:GetDescendants() do
	if d:IsA("ParticleEmitter") and d:GetAttribute("Zehir") then
		table.insert(venomEmitters, d)
	end
end
local eyeLight = model:FindFirstChild("GozIsigi", true) :: PointLight?

local FAR_DISTANCE = 700
local FAR_UPDATE_INTERVAL = 0.25

local cframes = table.create(#parts)
local sinceUpdate = math.huge
local venomOn = false

RunService.RenderStepped:Connect(function(dt: number)
	if not root.Parent then
		return
	end
	local rootCF = root.CFrame

	-- Uzaktaki örümceği daha seyrek güncelle.
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
		local upperCF, lowerCF = Rig.solveLeg(leg.def, boneCFs, t, rt, scale)
		upperCF, lowerCF = rootCF * upperCF, rootCF * lowerCF
		for _, piece in leg.upper do
			cframes[piece.index] = upperCF * piece.offset
		end
		for _, piece in leg.lower do
			cframes[piece.index] = lowerCF * piece.offset
		end
	end
	workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)

	local windup, roar = Rig.roarEnvelope(rt)
	local wantVenom = roar > 0.4
	if wantVenom ~= venomOn then
		venomOn = wantVenom
		for _, e in venomEmitters do
			e.Enabled = wantVenom
		end
	end
	if eyeLight then
		eyeLight.Brightness = 1.2 + 0.3 * math.sin(t * 2.3) + 3 * math.max(windup, roar)
	end
end)
