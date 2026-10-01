--[[
	Raptor — animasyon (istemci)

	Bu Script'in RunContext'i "Client"tır: model Workspace'teyken her oyuncunun
	bilgisayarında çalışır, animasyonu orada akıcı biçimde oynatır. Roblox'a
	animasyon yüklemek gerekmez. Sunucu tarafında raptor dinlenme pozunda kalır.

	Modelin öznitelikleri (Properties > Attributes) ile kontrol:
	  OtomatikKukreme (bool)   true ise belirli aralıklarla kendiliğinden öne atılıp çığlık atar.
	  KukremeAraligi  (number) otomatik saldırılar arasındaki saniye (varsayılan 12).
	  KukremeZamani   (number) bir sunucu script'inden saldırtmak için:
	                           raptor:SetAttribute("KukremeZamani", workspace:GetServerTimeNow())
	  AnimasyonHizi   (number) 1 = normal hız.

	Raptoru taşımak için sunucuda raptor:PivotTo(...) kullanın; animasyon "Kok"
	parçasını takip eder. Boyutu Studio'daki Scale aracıyla değiştirebilirsiniz.
]]

local RunService = game:GetService("RunService")

local model = script.Parent
local Rig = require(model:WaitForChild("RaptorRig"))
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
	local entry = { def = leg, groups = {}, lifted = false }
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

local lids: { BasePart } = {}
for _, name in Rig.lids do
	local part = findPart(name)
	if part then
		table.insert(lids, part)
	end
end

local lungeDust: { { emitter: ParticleEmitter, count: number } } = {}
local footDust: { [number]: ParticleEmitter } = {}
for _, d in model:GetDescendants() do
	if d:IsA("ParticleEmitter") then
		if d:GetAttribute("HamleTozu") then
			table.insert(lungeDust, { emitter = d, count = d:GetAttribute("Adet") or 30 })
		elseif d:GetAttribute("AyakTozu") then
			footDust[d:GetAttribute("AyakTozu")] = d
		end
	end
end

local FAR_DISTANCE = 700
local FAR_UPDATE_INTERVAL = 0.25

local cframes = table.create(#parts)
local sinceUpdate = math.huge
local lunging = false
local blinking = false

RunService.RenderStepped:Connect(function(dt: number)
	if not root.Parent then
		return
	end
	local rootCF = root.CFrame

	-- Uzaktaki raptoru daha seyrek güncelle.
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
		-- kaldırılan ayak yere basınca küçük toz
		local lift = Rig.footLift(leg.def.side, t, rt)
		if lift > 0.3 then
			leg.lifted = true
		elseif leg.lifted and lift < 0.02 then
			leg.lifted = false
			local e = footDust[leg.def.side]
			if e then
				e:Emit(8)
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

	-- öne atılma başlarken ayakların altından toz kalkar
	local _, roar = Rig.roarEnvelope(rt)
	local wantLunge = roar > 0.5
	if wantLunge ~= lunging then
		lunging = wantLunge
		if wantLunge then
			for _, d in lungeDust do
				d.emitter:Emit(d.count)
			end
		end
	end
end)
