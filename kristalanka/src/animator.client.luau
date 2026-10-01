--[[
	Kristal Anka — animasyon (istemci)

	Bu Script'in RunContext'i "Client"tır: model Workspace'teyken her oyuncunun
	bilgisayarında çalışır, animasyonu orada akıcı biçimde oynatır. Roblox'a
	animasyon yüklemek gerekmez. Sunucu tarafında kuş dinlenme pozunda kalır.

	Modelin öznitelikleri (Properties > Attributes) ile kontrol:
	  OtomatikKukreme (bool)   true ise belirli aralıklarla kendiliğinden çığlık atar.
	  KukremeAraligi  (number) otomatik çığlıklar arasındaki saniye (varsayılan 16).
	  KukremeZamani   (number) bir sunucu script'inden çığlık attırmak için:
	                           anka:SetAttribute("KukremeZamani", workspace:GetServerTimeNow())
	  AnimasyonHizi   (number) 1 = normal hız.

	Kuşu taşımak için sunucuda anka:PivotTo(...) kullanın; animasyon "Kok" parçasını
	takip eder (kuş Kok'un yaklaşık 14 stud üstünde süzülür). Boyutu Studio'daki Scale
	aracıyla değiştirebilirsiniz.
]]

local RunService = game:GetService("RunService")

local model = script.Parent
local Rig = require(model:WaitForChild("AnkaRig"))
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

local screechEffects: { ParticleEmitter } = {}
local bursts = {}
for _, d in model:GetDescendants() do
	if d:IsA("ParticleEmitter") then
		if d:GetAttribute("CiglikEfekti") then
			table.insert(screechEffects, d)
		elseif d:GetAttribute("CiglikPatlamasi") then
			table.insert(bursts, { emitter = d, count = d:GetAttribute("Adet") or 60 })
		end
	end
end
local headLight = model:FindFirstChild("BasIsigi", true) :: PointLight?
local core = model:FindFirstChild("IsikCekirdegi", true) :: BasePart?
local coreSize = if core then core.Size else Vector3.one

local FAR_DISTANCE = 700
local FAR_UPDATE_INTERVAL = 0.25

local cframes = table.create(#parts)
local sinceUpdate = math.huge
local screeching = false

RunService.RenderStepped:Connect(function(dt: number)
	if not root.Parent then
		return
	end
	local rootCF = root.CFrame

	-- Uzaktaki kuşu daha seyrek güncelle.
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

	-- Çığlık: başlarken ışık patlaması bir kez saçılır; sürdükçe gagadan kristal kırıntıları fışkırır.
	local _, roar = Rig.roarEnvelope(rt)
	local wantScreech = roar > 0.5
	if wantScreech ~= screeching then
		screeching = wantScreech
		for _, e in screechEffects do
			e.Enabled = wantScreech
		end
		if wantScreech then
			for _, b in bursts do
				b.emitter:Emit(b.count)
			end
		end
	end
	local flicker = 0.5 + 0.5 * math.sin(t * 17) * math.sin(t * 7.3)
	if headLight then
		headLight.Brightness = 2 + 0.6 * flicker + 7 * roar
	end
	if core then
		core.Size = coreSize * (1 + 0.15 * flicker + 1.2 * roar)
	end
end)
