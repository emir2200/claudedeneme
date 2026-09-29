--[[
	Ateş Ejderhası modelini üretir: lune run src/build.luau   (ejderha/ klasöründen)
	Çıktı: AtesEjderhasi.rbxmx — Roblox Studio'ya sürükleyip bırakılabilir.

	Koordinatlar stud cinsindendir; model -Z yönüne bakar, zemin y = 0.
	Her parça bir kemiğe bağlanır; parçaların kemiğe göre konumları ve kanat zarı
	üçgenleri "EjderhaRig" ModuleScript'ine veri olarak yazılır.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local Instance = roblox.Instance
local CFrame = roblox.CFrame
local Vector3 = roblox.Vector3
local Vector2 = roblox.Vector2
local Color3 = roblox.Color3
local Enum = roblox.Enum
local ColorSequence, ColorSequenceKeypoint = roblox.ColorSequence, roblox.ColorSequenceKeypoint
local NumberSequence, NumberSequenceKeypoint = roblox.NumberSequence, roblox.NumberSequenceKeypoint
local NumberRange = roblox.NumberRange

local function V(x: number, y: number, z: number)
	return Vector3.new(x, y, z)
end
local rad = math.rad

-- ─── Renkler (görseldeki kızıl-turuncu pullar, koyu plakalar, lav parıltısı) ───
local RGB = Color3.fromRGB
local C = {
	scale = RGB(176, 58, 28),
	scaleLight = RGB(206, 88, 42),
	scaleDark = RGB(118, 34, 20),
	belly = RGB(84, 50, 40),
	glow = RGB(255, 110, 30),
	horn = RGB(50, 44, 46),
	hornTip = RGB(112, 100, 94),
	membrane = RGB(196, 74, 40),
	wingBone = RGB(138, 44, 24),
	claw = RGB(38, 32, 32),
	tooth = RGB(236, 222, 196),
	eye = RGB(255, 196, 70),
	spike = RGB(66, 30, 24),
	nostril = RGB(28, 18, 16),
}
local M = Enum.Material

-- ─── Model ve klasörler ───
local model = Instance.new("Model")
model.Name = "AtesEjderhasi"
model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
model:SetAttribute("OtomatikKukreme", true)
model:SetAttribute("KukremeAraligi", 14)
model:SetAttribute("AnimasyonHizi", 1)

local folders = {}
local function folder(name: string)
	if not folders[name] then
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = model
		folders[name] = f
	end
	return folders[name]
end

-- ─── İskelet ───
type Bone = { name: string, parent: number, pivot: any }
local bones: { Bone } = {}
local boneIndex: { [string]: number } = {}
local function addBone(name: string, parent: string?, pivot)
	table.insert(bones, { name = name, parent = if parent then boneIndex[parent] else 0, pivot = pivot })
	boneIndex[name] = #bones
end
local function pivotOf(name: string)
	return bones[boneIndex[name]].pivot
end

-- ─── Parça yardımcıları ───
local rigParts = {} -- { name, bone, cf }
local glowParts = {}
local counters = {}
local function uniqueName(prefix: string): string
	counters[prefix] = (counters[prefix] or 0) + 1
	return prefix .. counters[prefix]
end

local function basePart(class: string, prefix: string, group: string, bone: string?, cf, size, color, material, opts)
	opts = opts or {}
	local p = Instance.new(class)
	p.Name = uniqueName(prefix)
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CastShadow = opts.shadow ~= false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or M.Slate
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if opts.transparency then
		p.Transparency = opts.transparency
	end
	p.Parent = folder(group)
	if bone then
		table.insert(rigParts, { name = p.Name, bone = bone, cf = cf })
	end
	if opts.glow then
		table.insert(glowParts, p.Name)
	end
	return p
end

local function ellipsoid(prefix, group, bone, cf, size, color, material, opts)
	local p = basePart("Part", prefix, group, bone, cf, size, color, material, opts)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

--- `pos` konumunda, -Z'si (LookVector) `look` yönüne bakan çerçeve. Lune 0.10'daki CFrame.lookAt
--- eğik yönlerde yanlış sonuç verdiği için fromMatrix ile kuruyoruz.
local function lookFrame(pos, look, upHint)
	look = look.Unit
	local up = upHint or V(0, 1, 0)
	if math.abs(look:Dot(up.Unit)) > 0.92 then
		up = V(0, 0, 1)
	end
	local right = look:Cross(up).Unit
	return CFrame.fromMatrix(pos, right, right:Cross(look), -look)
end

--- a'dan b'ye uzanan çerçeve: -Z (LookVector) b'ye bakar.
local function along(a, b, upHint)
	return lookFrame((a + b) / 2, b - a, upHint)
end

--- a ile b arasına gerilmiş elips (uzuvlar, boyun, kuyruk, boynuz parçaları).
local function segment(prefix, group, bone, a, b, w, h, color, material, opts)
	opts = opts or {}
	local len = (b - a).Magnitude * (opts.extend or 1.25)
	return ellipsoid(prefix, group, bone, along(a, b, opts.up), V(w, h, len), color, material, opts)
end

--- Diken/pençe/diş: tabanı `pos`, `out` yönüne uzanır, ucu `back` yönüne yatar.
local function spike(prefix, group, bone, pos, out, back, height, length, thickness, color, material, opts)
	out = out.Unit
	back = (back - out * back:Dot(out)).Unit
	local right = out:Cross(back).Unit
	local cf = CFrame.fromMatrix(pos + out * (height / 2), right, out, back)
	return basePart("WedgePart", prefix, group, bone, cf, V(thickness, height, length), color, material or M.Basalt, opts)
end

-- Sagital düzlemde (YZ) bir doğrultunun ön (ventral) normali: d × X.
local function frontNormal(d)
	return d:Cross(V(1, 0, 0)).Unit
end

local function lerp(a, b, t)
	return a + (b - a) * t
end

--- Kontrol noktaları ({ pos, w, h, bone }) boyunca `step` aralıklı örnekler.
local function sampleChain(controls, step)
	local samples = {}
	for i = 1, #controls - 1 do
		local c0, c1 = controls[i], controls[i + 1]
		local seg = c1.pos - c0.pos
		local n = math.max(1, math.ceil(seg.Magnitude / step))
		for k = 0, n - 1 do
			local t = k / n
			table.insert(samples, {
				pos = c0.pos + seg * t,
				w = lerp(c0.w, c1.w, t),
				h = lerp(c0.h, c1.h, t),
				bone = if t < 0.5 then c0.bone else c1.bone,
				dir = seg.Unit,
			})
		end
	end
	local last, prev = controls[#controls], controls[#controls - 1]
	table.insert(samples, { pos = last.pos, w = last.w, h = last.h, bone = last.bone, dir = (last.pos - prev.pos).Unit })
	return samples
end

--- Catmull-Rom ile yumuşatılmış eğri noktaları (boynuzlar gibi kıvrımlı şekiller için).
local function smoothCurve(points, perSegment)
	local out = {}
	local n = #points
	for i = 1, n - 1 do
		local p0 = points[math.max(1, i - 1)]
		local p1, p2 = points[i], points[i + 1]
		local p3 = points[math.min(n, i + 2)]
		for k = 0, perSegment - 1 do
			local t = k / perSegment
			local t2, t3 = t * t, t * t * t
			table.insert(out, (p1 * 2 + (p2 - p0) * t + (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2 + (p1 * 3 - p0 - p2 * 3 + p3) * t3) * 0.5)
		end
	end
	table.insert(out, points[n])
	return out
end

--- Kontrol noktaları boyunca, üst üste binen elipslerden sürekli bir boru (boyun, gövde, kuyruk, boynuz).
local function tube(prefix, group, controls, step, color, material, opts)
	opts = opts or {}
	local samples = sampleChain(controls, step)
	local made = {}
	for i = 1, #samples - 1 do
		local a, b = samples[i], samples[i + 1]
		local len = (b.pos - a.pos).Magnitude
		local p = ellipsoid(prefix, group, a.bone, along(a.pos, b.pos, opts.up), V((a.w + b.w) / 2, (a.h + b.h) / 2, len * (opts.overlap or 2.4)), color, material, opts)
		table.insert(made, { part = p, sample = a })
	end
	return made
end

--- Zincir boyunca uzun ve çok üst üste binen elipslerden pürüzsüz bir boru (gövde, kuyruk, kanat
--- kemikleri). `spacing` elips merkezleri arası, `length` her elipsin boyu; length/spacing ≥ 3 iken
--- halka izi kalmaz. Uçtaki elipsler zincirin dışına taşmaz, uçlar doğal biçimde incelir.
local function smoothTube(prefix, group, controls, spacing, length, color, material, opts)
	opts = opts or {}
	local samples = sampleChain(controls, 0.25)
	local arcs = { 0 }
	for i = 2, #samples do
		arcs[i] = arcs[i - 1] + (samples[i].pos - samples[i - 1].pos).Magnitude
	end
	local total = arcs[#arcs]
	local function at(s)
		s = math.clamp(s, 0, total)
		local i = 1
		while i < #samples - 1 and arcs[i + 1] < s do
			i += 1
		end
		local a, b = samples[i], samples[i + 1]
		local t = if arcs[i + 1] > arcs[i] then (s - arcs[i]) / (arcs[i + 1] - arcs[i]) else 0
		return { pos = lerp(a.pos, b.pos, t), w = lerp(a.w, b.w, t), h = lerp(a.h, b.h, t), bone = if t < 0.5 then a.bone else b.bone }
	end
	local half = math.min(length, total) / 2
	local span = total - 2 * half
	local count = math.max(1, math.ceil(span / spacing) + 1)
	local made = {}
	for j = 0, count - 1 do
		local s = half + (if count > 1 then span * j / (count - 1) else span / 2)
		local c = at(s)
		local look = at(s + half * 0.5).pos - at(s - half * 0.5).pos
		local p = ellipsoid(prefix, group, c.bone, lookFrame(c.pos, look, opts.up), V(c.w, c.h, half * 2), color, material, opts)
		table.insert(made, { part = p, sample = c })
	end
	return made
end

--- `origin`dan `dir` yönünde giden ışının elips parçalardan en dışta çıktığı mesafe.
local function surfaceDistance(tubeParts, origin, dir)
	local best = 0
	for _, entry in tubeParts do
		local p = entry.part
		local r = p.Size / 2
		local o = p.CFrame:PointToObjectSpace(origin) / r
		local d = p.CFrame:VectorToObjectSpace(dir) / r
		local a, b, c = d:Dot(d), 2 * o:Dot(d), o:Dot(o) - 1
		local disc = b * b - 4 * a * c
		if disc >= 0 then
			best = math.max(best, (-b + math.sqrt(disc)) / (2 * a))
		end
	end
	return best
end

--- Omurga zincirinin karnı: koyu karın plakası şeridi ve plakaların arasından parlayan ince lav çizgileri.
--- Şerit gövdenin gerçek yüzeyine (bodyParts elipslerine) oturtulur.
local function bellyPlates(group, controls, bodyParts, fromArc, toArc, seamSpacing)
	local strip, seams = {}, {}
	local arc, nextSeam = 0, fromArc + seamSpacing * 0.5
	local samples = sampleChain(controls, 0.25)
	for i, smp in samples do
		if i > 1 then
			arc += (smp.pos - samples[i - 1].pos).Magnitude
		end
		if arc >= fromArc and arc <= toArc then
			local nf = frontNormal(smp.dir)
			local center = smp.pos + nf * (surfaceDistance(bodyParts, smp.pos, nf) - 1.0)
			if #strip == 0 or (center - strip[#strip].pos).Magnitude >= 0.8 then
				table.insert(strip, { pos = center, w = smp.w * 0.62, h = 2.3, bone = smp.bone })
			end
			if arc >= nextSeam then
				nextSeam += seamSpacing
				local right = smp.dir:Cross(nf).Unit
				local seam = ellipsoid("LavCizgisi", group, smp.bone, CFrame.fromMatrix(center, right, smp.dir, nf),
					V(smp.w * 0.64, 0.3, 2.6), C.glow, M.Neon, { glow = true, shadow = false })
				table.insert(seams, { part = seam, sample = smp })
			end
		end
	end
	smoothTube("Plaka", group, strip, 1.4, 4.6, C.belly, M.Basalt)
	return seams
end

--- Zincirin sırtı boyunca dikenler. dorsalSign: sırt normali = dorsalSign × ön normal.
local function dorsalSpikes(group, controls, surfaceParts, spacing, fromArc, toArc, heightAt, dorsalSign, towardTailSign)
	local arc = 0
	local samples = sampleChain(controls, spacing)
	for i, smp in samples do
		if i > 1 then
			arc += (smp.pos - samples[i - 1].pos).Magnitude
		end
		if arc >= fromArc and arc <= toArc then
			local nd = frontNormal(smp.dir) * dorsalSign
			local height = heightAt(arc)
			spike("Diken", group, smp.bone, smp.pos + nd * (surfaceDistance(surfaceParts, smp.pos, nd) - 0.35), nd, smp.dir * towardTailSign, height, height * 0.8, 0.45, C.spike)
		end
	end
end

-- ═════════════════════════════ İSKELET ═════════════════════════════
addBone("pelvis", nil, V(0, 9.5, 3.2))
addBone("spine1", "pelvis", V(0, 13.5, 1.6))
addBone("chest", "spine1", V(0, 17.5, -0.3))
addBone("neck1", "chest", V(0, 21.0, -1.8))
addBone("neck2", "neck1", V(0, 24.5, -2.6))
addBone("neck3", "neck2", V(0, 27.6, -3.1))
addBone("head", "neck3", V(0, 30.6, -3.4))

local HEAD_PITCH = rad(30)
local headFrame = CFrame.new(pivotOf("head")) * CFrame.Angles(HEAD_PITCH, 0, 0)
local function H(x, y, z) -- baş koordinatlarından dünyaya
	return headFrame * V(x, y, z)
end
local function HD(x, y, z) -- baş koordinatlarındaki bir yön
	return headFrame:VectorToWorldSpace(V(x, y, z))
end
local function HCF(x, y, z, rx, ry, rz)
	return headFrame * CFrame.new(x, y, z) * CFrame.Angles(rx or 0, ry or 0, rz or 0)
end
addBone("jaw", "head", H(0, -0.35, -1.2))

local tailPivots = { V(0, 8.6, 6.0), V(0, 6.6, 9.4), V(0, 4.6, 12.8), V(0, 3.0, 16.4), V(0, 2.0, 20.0), V(0, 1.6, 23.6) }
for i, p in tailPivots do
	addBone("tail" .. i, if i == 1 then "pelvis" else "tail" .. (i - 1), p)
end
local TAIL_END = V(0, 1.4, 27.4)

for side, s in { L = 1, R = -1 } do
	addBone("thigh" .. side, "pelvis", V(s * 3.6, 9.4, 3.4))
	addBone("shin" .. side, "thigh" .. side, V(s * 4.6, 5.8, -0.4))
	addBone("foot" .. side, "shin" .. side, V(s * 4.5, 2.3, 3.0))
	addBone("arm" .. side, "chest", V(s * 3.9, 19.4, -1.2))
	addBone("forearm" .. side, "arm" .. side, V(s * 5.8, 15.8, -3.4))
	addBone("hand" .. side, "forearm" .. side, V(s * 5.6, 15.2, -7.0))
	addBone("wingRoot" .. side, "chest", V(s * 3.0, 20.6, 1.4))
	addBone("wingElbow" .. side, "wingRoot" .. side, V(s * 11.5, 26.5, 5.0))
	addBone("wingWrist" .. side, "wingElbow" .. side, V(s * 19.0, 31.0, 3.0))
	for f = 1, 4 do
		addBone("finger" .. side .. f, "wingWrist" .. side, V(s * 19.0, 31.0, 3.0))
	end
end

-- ═════════════════════════════ GÖVDE ═════════════════════════════
-- Kalçadan başa uzanan omurga zinciri: { konum, genişlik, derinlik, kemik }
local function ctl(x, y, z, w, h, bone)
	return { pos = V(x, y, z), w = w, h = h, bone = bone }
end
local spineChain = {
	ctl(0, 6.6, 5.0, 6.6, 5.8, "pelvis"),
	ctl(0, 8.2, 4.3, 8.0, 6.8, "pelvis"),
	ctl(0, 10.6, 3.2, 8.8, 7.6, "pelvis"),
	ctl(0, 13.2, 1.9, 9.2, 8.0, "spine1"),
	ctl(0, 15.8, 0.8, 9.6, 8.4, "spine1"),
	ctl(0, 18.4, -0.4, 9.7, 8.5, "chest"),
	ctl(0, 20.8, -1.5, 7.4, 6.6, "chest"),
	ctl(0, 22.6, -2.1, 5.4, 5.0, "neck1"),
	ctl(0, 24.8, -2.6, 4.9, 4.6, "neck2"),
	ctl(0, 27.0, -3.0, 4.4, 4.1, "neck2"),
	ctl(0, 29.2, -3.3, 4.0, 3.8, "neck3"),
	ctl(0, 30.9, -3.5, 3.8, 3.6, "neck3"),
	ctl(0, 32.2, -3.2, 3.2, 3.0, "neck3"), -- kafatasının içinde biter
}
-- Zincirin ilk kontrol noktası kasık altındadır; yay uzunlukları buna göre kaydırılır.
local SPINE_START = (spineChain[2].pos - spineChain[1].pos).Magnitude
local bodyParts = smoothTube("Govde", "Govde", spineChain, 1.4, 7.0, C.scale, M.Slate)
local bellyGlow = bellyPlates("Govde", spineChain, bodyParts, SPINE_START + 1.0, SPINE_START + 23.4, 1.9)
dorsalSpikes("Govde", spineChain, bodyParts, 1.7, SPINE_START + 0.5, SPINE_START + 23.5, function(arc)
	arc -= SPINE_START
	return if arc < 14 then 2.4 - arc * 0.03 else 1.9 - (arc - 14) * 0.08
end, -1, -1)

ellipsoid("Omuz", "Govde", "chest", CFrame.new(3.7, 19.6, -0.6), V(4.2, 4.8, 4.8), C.scale, M.Slate)
ellipsoid("Omuz", "Govde", "chest", CFrame.new(-3.7, 19.6, -0.6), V(4.2, 4.8, 4.8), C.scale, M.Slate)
ellipsoid("Sirt", "Govde", "chest", CFrame.new(0, 20.2, 1.4) * CFrame.Angles(rad(-20), 0, 0), V(7.2, 5.4, 5.2), C.scaleDark, M.Slate)
-- göğüs yanlarındaki lav çatlakları
for _, s in { 1, -1 } do
	for i, y in { 13.2, 15.4, 17.6, 19.6 } do
		local z = 2.2 - (y - 13) * 0.42 - 3.4
		ellipsoid("Catlak", "Govde", if y < 15 then "spine1" else "chest",
			CFrame.new(s * (4.05 - i * 0.05), y, z) * CFrame.Angles(rad(22), 0, s * rad(12)),
			V(0.35, 1.9, 0.35), C.glow, M.Neon, { glow = true, shadow = false })
	end
end

-- ═════════════════════════════ BAŞ ═════════════════════════════
ellipsoid("Kafatasi", "Kafa", "head", HCF(0, 0.9, -1.8), V(4.4, 3.6, 5.6), C.scale, M.Slate)
ellipsoid("Tepe", "Kafa", "head", HCF(0, 2.1, -1.4), V(2.4, 1.3, 4.2), C.scaleDark, M.Slate)
for _, s in { 1, -1 } do
	ellipsoid("Kas", "Kafa", "head", HCF(s * 1.45, 1.95, -3.4, 0, s * rad(14), 0), V(1.5, 1.0, 2.6), C.scaleDark, M.Slate)
	ellipsoid("Goz", "Kafa", "head", HCF(s * 1.8, 1.35, -3.5, 0, s * rad(18), 0), V(0.45, 0.7, 1.1), C.eye, M.Neon, { shadow = false })
	ellipsoid("Yanak", "Kafa", "head", HCF(s * 1.6, 0.2, -2.2), V(1.6, 2.0, 3.0), C.scale, M.Slate)
end
ellipsoid("Burun", "Kafa", "head", HCF(0, 0.55, -5.3), V(3.1, 2.1, 5.4), C.scale, M.Slate)
ellipsoid("BurunSirti", "Kafa", "head", HCF(0, 1.35, -5.0), V(1.6, 0.8, 4.4), C.scaleDark, M.Slate)
ellipsoid("BurunUcu", "Kafa", "head", HCF(0, 0.75, -7.7), V(2.3, 1.6, 1.8), C.scale, M.Slate)
for _, s in { 1, -1 } do
	ellipsoid("BurunDeligi", "Kafa", "head", HCF(s * 0.62, 1.25, -8.2), V(0.5, 0.35, 0.5), C.nostril, M.SmoothPlastic, { shadow = false })
end
spike("BurunBoynuzu", "Kafa", "head", H(0, 1.45, -7.0), HD(0, 1, 0.35), HD(0, 0, 1), 1.0, 0.9, 0.35, C.horn)

-- Ağız içi (parlayan boğaz) — alev buradan çıkar
local mouth = ellipsoid("Agiz", "Kafa", "head", HCF(0, -0.5, -4.4), V(2.3, 1.1, 5.6), C.glow, M.Neon, { glow = true, shadow = false })

-- Üst dişler
for _, s in { 1, -1 } do
	for i = 0, 5 do
		local z = -3.6 - i * 0.72
		local big = i == 5
		spike("Dis", "Kafa", "head", H(s * 1.12, -0.35, z), HD(0, -1, 0), HD(0, 0, -1), if big then 1.1 else 0.7, 0.35, 0.22, C.tooth, M.SmoothPlastic, { shadow = false })
	end
end

-- Boynuzlar (ana çift ve küçük çift)
for _, s in { 1, -1 } do
	-- ana boynuz: kafatasının arkasından geriye ve aşağı kıvrılır, uca doğru incelir
	local hornPts = smoothCurve({ H(s * 1.15, 1.8, -0.2), H(s * 1.8, 2.9, 1.3), H(s * 2.4, 3.2, 3.1), H(s * 2.8, 2.5, 4.8), H(s * 2.7, 1.1, 5.8) }, 3)
	local hornControls = {}
	for i, pt in hornPts do
		local t = (i - 1) / (#hornPts - 1)
		local w = lerp(1.35, 0.3, t)
		table.insert(hornControls, { pos = pt, w = w, h = w, bone = "head" })
	end
	tube("Boynuz", "Kafa", hornControls, 0.45, C.horn, M.Basalt, { overlap = 2.6 })
	local tipDir = hornPts[#hornPts] - hornPts[#hornPts - 1]
	spike("BoynuzUcu", "Kafa", "head", hornPts[#hornPts], tipDir, HD(0, 0, 1), 0.9, 0.35, 0.3, C.hornTip)
	-- küçük boynuz çifti
	local smallPts = smoothCurve({ H(s * 1.8, 0.9, 0.2), H(s * 2.8, 1.2, 1.6), H(s * 3.4, 0.8, 2.9) }, 3)
	local smallControls = {}
	for i, pt in smallPts do
		local w = lerp(0.85, 0.25, (i - 1) / (#smallPts - 1))
		table.insert(smallControls, { pos = pt, w = w, h = w, bone = "head" })
	end
	tube("Boynuz", "Kafa", smallControls, 0.4, C.horn, M.Basalt, { overlap = 2.6 })
	-- yanak/çene dikenleri (görseldeki tırtıklı yaka)
	for i, p in { { -2.4, -1.0 }, { -1.3, -0.7 }, { -0.2, -0.3 } } do
		spike("Yaka", "Kafa", "head", H(s * 1.6, p[2], p[1]), HD(s * 0.75, -0.45, 0.5), HD(0, 0, 1), 1.6 - i * 0.15, 1.4, 0.32, C.scaleDark, M.Slate)
	end
end
for i, x in { 0, 0.85, -0.85 } do
	spike("Ense", "Kafa", "head", H(x, 2.5, 0.6 + math.abs(x) * 0.3), HD(0, 0.6, 1), HD(0, -1, 0.3), 1.3 - (if i == 1 then 0 else 0.3), 0.8, 0.35, C.spike)
end

-- Alt çene (açılıp kapanır)
ellipsoid("Cene", "Kafa", "jaw", HCF(0, -1.25, -4.4), V(2.7, 1.2, 5.8), C.scale, M.Slate)
ellipsoid("Cene", "Kafa", "jaw", HCF(0, -1.3, -7.0), V(1.8, 1.0, 1.4), C.scale, M.Slate)
ellipsoid("CenePlaka", "Kafa", "jaw", HCF(0, -1.75, -3.8), V(1.8, 0.5, 4.4), C.belly, M.Basalt)
for _, s in { 1, -1 } do
	for i = 0, 4 do
		spike("AltDis", "Kafa", "jaw", H(s * 1.02, -0.72, -4.0 - i * 0.78), HD(0, 1, 0), HD(0, 0, -1), 0.6, 0.32, 0.2, C.tooth, M.SmoothPlastic, { shadow = false })
	end
end

-- ═════════════════════════════ KUYRUK ═════════════════════════════
local tailChain = {
	ctl(0, 10.2, 2.4, 6.8, 6.4, "pelvis"), -- gövdenin içinden başlar
	ctl(0, 9.2, 4.6, 6.8, 6.2, "pelvis"),
	ctl(tailPivots[1].X, tailPivots[1].Y, tailPivots[1].Z, 5.8, 5.2, "tail1"),
	ctl(tailPivots[2].X, tailPivots[2].Y, tailPivots[2].Z, 4.9, 4.4, "tail2"),
	ctl(tailPivots[3].X, tailPivots[3].Y, tailPivots[3].Z, 4.0, 3.6, "tail3"),
	ctl(tailPivots[4].X, tailPivots[4].Y, tailPivots[4].Z, 3.2, 2.9, "tail4"),
	ctl(tailPivots[5].X, tailPivots[5].Y, tailPivots[5].Z, 2.4, 2.2, "tail5"),
	ctl(tailPivots[6].X, tailPivots[6].Y, tailPivots[6].Z, 1.7, 1.6, "tail6"),
	ctl(TAIL_END.X, TAIL_END.Y, TAIL_END.Z, 1.0, 1.0, "tail6"),
}
local TAIL_START = (tailChain[2].pos - tailChain[1].pos).Magnitude
local tailParts = smoothTube("Kuyruk", "Kuyruk", tailChain, 1.5, 6.0, C.scale, M.Slate)
dorsalSpikes("Kuyruk", tailChain, tailParts, 1.8, TAIL_START + 1.5, TAIL_START + 22.5, function(arc)
	return 2.0 - (arc - TAIL_START) * 0.055
end, 1, 1)
ellipsoid("KuyrukUcu", "Kuyruk", "tail6", CFrame.new(0, 1.4, 28.2) * CFrame.Angles(0, 0, 0), V(3.4, 0.55, 3.2), C.scaleDark, M.Slate)
for _, s in { 1, -1 } do
	spike("KuyrukUcu", "Kuyruk", "tail6", V(s * 1.2, 1.4, 28.6), V(s, 0, 0.6), V(0, 0, 1), 1.4, 0.8, 0.4, C.spike)
end
spike("KuyrukUcu", "Kuyruk", "tail6", V(0, 1.4, 29.5), V(0, 0, 1), V(0, 1, 0), 1.6, 0.8, 0.45, C.spike)

-- ═════════════════════════════ BACAKLAR VE KOLLAR ═════════════════════════════
for side, s in { L = 1, R = -1 } do
	local hip, knee, ankle = pivotOf("thigh" .. side), pivotOf("shin" .. side), pivotOf("foot" .. side)
	-- arka bacak
	ellipsoid("Uyluk", "Bacaklar", "thigh" .. side, CFrame.new(s * 4.2, 8.2, 2.6) * CFrame.Angles(rad(-25), 0, 0), V(4.2, 5.6, 5.4), C.scale, M.Slate)
	segment("Uyluk", "Bacaklar", "thigh" .. side, hip, knee, 4.0, 4.4, C.scale, M.Slate)
	segment("Incik", "Bacaklar", "shin" .. side, knee, ankle, 2.5, 2.8, C.scale, M.Slate)
	spike("DizDikeni", "Bacaklar", "shin" .. side, V(s * 4.6, 6.2, -1.2), V(0, 0.35, -1), V(0, 1, 0), 1.2, 0.8, 0.4, C.spike)
	segment("Ayak", "Bacaklar", "foot" .. side, ankle, V(s * 4.5, 0.8, 1.5), 1.9, 2.0, C.scale, M.Slate)
	ellipsoid("Taban", "Bacaklar", "foot" .. side, CFrame.new(s * 4.5, 0.6, 0.8), V(3.0, 1.1, 3.4), C.scaleDark, M.Slate)
	for _, dx in { -0.95, 0, 0.95 } do
		local base = V(s * 4.5 + dx, 0.6, 0.1)
		local tip = V(s * 4.5 + dx * 1.3, 0.45, -1.7)
		segment("Parmak", "Bacaklar", "foot" .. side, base, tip, 0.85, 0.75, C.scale, M.Slate)
		spike("Pence", "Bacaklar", "foot" .. side, tip + V(0, 0, -0.2), V(0, -0.3, -1), V(0, 1, 0), 1.1, 0.55, 0.4, C.claw)
	end
	spike("Pence", "Bacaklar", "foot" .. side, V(s * 4.5, 0.7, 2.6), V(0, -0.2, 1), V(0, 1, 0), 0.8, 0.45, 0.35, C.claw)

	-- ön kol
	local shoulder, elbow, wrist = pivotOf("arm" .. side), pivotOf("forearm" .. side), pivotOf("hand" .. side)
	segment("Kol", "Kollar", "arm" .. side, shoulder, elbow, 2.6, 2.9, C.scale, M.Slate)
	segment("Onkol", "Kollar", "forearm" .. side, elbow, wrist, 2.0, 2.2, C.scale, M.Slate)
	spike("DirsekDikeni", "Kollar", "forearm" .. side, elbow + V(0, 0, 0.8), V(0, -0.2, 1), V(0, -1, 0), 0.9, 0.6, 0.35, C.spike)
	ellipsoid("Avuc", "Kollar", "hand" .. side, CFrame.new(s * 5.6, 14.9, -7.8), V(2.2, 1.3, 2.2), C.scale, M.Slate)
	for _, dx in { -0.72, 0, 0.72 } do
		local base = V(s * 5.6 + dx, 14.8, -8.4)
		local tip = V(s * 5.6 + dx * 1.2, 13.6, -9.4)
		segment("ElParmak", "Kollar", "hand" .. side, base, tip, 0.6, 0.6, C.scale, M.Slate)
		spike("Pence", "Kollar", "hand" .. side, tip, V(0, -0.8, -0.6), V(0, 0.2, 1), 0.9, 0.45, 0.32, C.claw)
	end
end

-- ═════════════════════════════ KANATLAR ═════════════════════════════
local membranes = {}
for side, s in { L = 1, R = -1 } do
	local R, E, W = pivotOf("wingRoot" .. side), pivotOf("wingElbow" .. side), pivotOf("wingWrist" .. side)
	local F = { V(s * 31, 37, 5.5), V(s * 34, 27, 9.0), V(s * 30, 17.5, 10.5), V(s * 22, 11.5, 9.0) }
	local B = V(s * 3.4, 12.2, 4.6)
	local group = "Kanat" .. side

	ellipsoid("KanatOmuz", group, "wingRoot" .. side, CFrame.new(R), V(2.6, 2.6, 2.6), C.scale, M.Slate)
	smoothTube("KanatKemik", group, { ctl(R.X, R.Y, R.Z, 2.1, 2.1, "wingRoot" .. side), ctl(E.X, E.Y, E.Z, 1.6, 1.6, "wingRoot" .. side) }, 2.2, 6.5, C.wingBone, M.Slate)
	ellipsoid("KanatDirsek", group, "wingElbow" .. side, CFrame.new(E), V(1.9, 1.9, 1.9), C.wingBone, M.Slate)
	smoothTube("KanatKemik", group, { ctl(E.X, E.Y, E.Z, 1.6, 1.6, "wingElbow" .. side), ctl(W.X, W.Y, W.Z, 1.25, 1.25, "wingElbow" .. side) }, 2.2, 5.5, C.wingBone, M.Slate)
	ellipsoid("KanatBilek", group, "wingWrist" .. side, CFrame.new(W), V(1.5, 1.5, 1.5), C.wingBone, M.Slate)
	spike("KanatPencesi", group, "wingWrist" .. side, W + V(0, 0.4, -0.3), V(0, 0.5, -1), V(s, 0.5, 0), 1.5, 0.7, 0.4, C.claw)
	for f = 1, 4 do
		local bone = "finger" .. side .. f
		smoothTube("KanatParmak", group, { ctl(W.X, W.Y, W.Z, 0.95, 0.95, bone), ctl(F[f].X, F[f].Y, F[f].Z, 0.35, 0.35, bone) }, 2.4, 6.0, C.wingBone, M.Slate)
		spike("KanatUcu", group, bone, F[f], F[f] - W, V(0, -1, 0), 0.9, 0.4, 0.3, C.claw)
	end

	-- Zar üçgenleri: her köşe bir kemiğe bağlıdır; oyun sırasında her karede yeniden çizilir.
	local function P(bone, point)
		return { bone = bone, point = point }
	end
	local tris = {
		{ P("wingRoot" .. side, R), P("wingElbow" .. side, E), P("pelvis", B) },
		{ P("wingElbow" .. side, E), P("wingWrist" .. side, W), P("pelvis", B) },
		{ P("wingWrist" .. side, W), P("finger" .. side .. "4", F[4]), P("pelvis", B) },
		{ P("wingWrist" .. side, W), P("finger" .. side .. "3", F[3]), P("finger" .. side .. "4", F[4]) },
		{ P("wingWrist" .. side, W), P("finger" .. side .. "2", F[2]), P("finger" .. side .. "3", F[3]) },
		{ P("wingWrist" .. side, W), P("finger" .. side .. "1", F[1]), P("finger" .. side .. "2", F[2]) },
	}
	for _, tri in tris do
		table.insert(membranes, { group = group, side = side, points = tri })
	end
end

-- ═════════════════════════════ EFEKTLER ═════════════════════════════
local function seq(points)
	local kps = {}
	for _, p in points do
		table.insert(kps, ColorSequenceKeypoint.new(p[1], p[2]))
	end
	return ColorSequence.new(kps)
end
local function nums(points)
	local kps = {}
	for _, p in points do
		table.insert(kps, NumberSequenceKeypoint.new(p[1], p[2]))
	end
	return NumberSequence.new(kps)
end

local fireOut = Instance.new("Attachment")
fireOut.Name = "AlevCikisi"
fireOut.CFrame = CFrame.new(0, 0, -2.9)
fireOut.Parent = mouth

local flame = Instance.new("ParticleEmitter")
flame.Name = "Alev"
flame.Texture = "rbxasset://textures/particles/fire_main.dds"
flame.Color = seq({ { 0, RGB(255, 246, 190) }, { 0.2, RGB(255, 190, 60) }, { 0.55, RGB(255, 90, 20) }, { 1, RGB(110, 20, 6) } })
flame.Size = nums({ { 0, 1.2 }, { 0.4, 4.2 }, { 1, 7.5 } })
flame.Transparency = nums({ { 0, 0.25 }, { 0.7, 0.45 }, { 1, 1 } })
flame.Lifetime = NumberRange.new(0.7, 1.1)
flame.Rate = 180
flame.Speed = NumberRange.new(38, 52)
flame.SpreadAngle = Vector2.new(9, 9)
flame.Rotation = NumberRange.new(0, 360)
flame.RotSpeed = NumberRange.new(-120, 120)
flame.LightEmission = 1
flame.LightInfluence = 0
flame.Drag = 1.2
flame.Acceleration = V(0, 6, 0)
flame.EmissionDirection = Enum.NormalId.Front
flame.ZOffset = 1
flame.Enabled = false
flame:SetAttribute("AlevNefesi", true)
flame.Parent = fireOut

local core = Instance.new("ParticleEmitter")
core.Name = "AlevCekirdegi"
core.Texture = "rbxasset://textures/particles/fire_main.dds"
core.Color = seq({ { 0, RGB(255, 255, 230) }, { 0.5, RGB(255, 220, 110) }, { 1, RGB(255, 120, 30) } })
core.Size = nums({ { 0, 0.6 }, { 0.5, 2.2 }, { 1, 3.2 } })
core.Transparency = nums({ { 0, 0.1 }, { 0.8, 0.5 }, { 1, 1 } })
core.Lifetime = NumberRange.new(0.35, 0.55)
core.Rate = 120
core.Speed = NumberRange.new(48, 62)
core.SpreadAngle = Vector2.new(5, 5)
core.Rotation = NumberRange.new(0, 360)
core.LightEmission = 1
core.LightInfluence = 0
core.EmissionDirection = Enum.NormalId.Front
core.ZOffset = 1.5
core.Enabled = false
core:SetAttribute("AlevNefesi", true)
core.Parent = fireOut

local smoke = Instance.new("ParticleEmitter")
smoke.Name = "AlevDumani"
smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
smoke.Color = seq({ { 0, RGB(90, 70, 60) }, { 1, RGB(40, 36, 34) } })
smoke.Size = nums({ { 0, 2 }, { 1, 9 } })
smoke.Transparency = nums({ { 0, 0.55 }, { 1, 1 } })
smoke.Lifetime = NumberRange.new(1.4, 2.2)
smoke.Rate = 22
smoke.Speed = NumberRange.new(20, 30)
smoke.SpreadAngle = Vector2.new(14, 14)
smoke.Rotation = NumberRange.new(0, 360)
smoke.RotSpeed = NumberRange.new(-30, 30)
smoke.Drag = 1.5
smoke.Acceleration = V(0, 4, 0)
smoke.EmissionDirection = Enum.NormalId.Front
smoke.Enabled = false
smoke:SetAttribute("AlevNefesi", true)
smoke.Parent = fireOut

local mouthLight = Instance.new("PointLight")
mouthLight.Name = "AgizIsigi"
mouthLight.Color = RGB(255, 140, 40)
mouthLight.Range = 28
mouthLight.Brightness = 0.5
mouthLight.Shadows = false
mouthLight.Parent = mouth

-- Göğüsteki lav çekirdeği: ışık ve sürekli uçuşan kıvılcımlar
-- göğüs kemiğine bağlı ilk lav parçası
local chestGlow
for _, g in bellyGlow do
	if g.sample.bone == "chest" then
		chestGlow = g.part
		break
	end
end
local chestLight = Instance.new("PointLight")
chestLight.Name = "GogusIsigi"
chestLight.Color = RGB(255, 110, 30)
chestLight.Range = 16
chestLight.Brightness = 1.5
chestLight.Shadows = false
chestLight.Parent = chestGlow

local emberOut = Instance.new("Attachment")
emberOut.Name = "Kivilcimlar"
emberOut.Parent = chestGlow
local embers = Instance.new("ParticleEmitter")
embers.Name = "Kivilcim"
embers.Texture = "rbxasset://textures/particles/sparkles_main.dds"
embers.Color = seq({ { 0, RGB(255, 210, 90) }, { 1, RGB(255, 80, 20) } })
embers.Size = nums({ { 0, 0.35 }, { 1, 0 } })
embers.Lifetime = NumberRange.new(1.5, 2.6)
embers.Rate = 7
embers.Speed = NumberRange.new(1, 3)
embers.SpreadAngle = Vector2.new(180, 180)
embers.Acceleration = V(0, 3, 0)
embers.LightEmission = 1
embers.LightInfluence = 0
embers.Parent = emberOut

-- Burun deliklerinden hafif duman
local nose = folders["Kafa"]:FindFirstChild("BurunUcu1")
local noseOut = Instance.new("Attachment")
noseOut.Name = "BurunDumani"
noseOut.CFrame = CFrame.new(0, 0.5, -0.6) * CFrame.Angles(rad(35), 0, 0)
noseOut.Parent = nose
local puff = Instance.new("ParticleEmitter")
puff.Name = "Duman"
puff.Texture = "rbxasset://textures/particles/smoke_main.dds"
puff.Color = seq({ { 0, RGB(120, 100, 90) }, { 1, RGB(60, 56, 54) } })
puff.Size = nums({ { 0, 0.5 }, { 1, 2.5 } })
puff.Transparency = nums({ { 0, 0.6 }, { 1, 1 } })
puff.Lifetime = NumberRange.new(1.2, 1.8)
puff.Rate = 4
puff.Speed = NumberRange.new(2, 4)
puff.SpreadAngle = Vector2.new(15, 15)
puff.Acceleration = V(0, 2, 0)
puff.EmissionDirection = Enum.NormalId.Front
puff.Parent = noseOut

-- ═════════════════════════════ KÖK VE ÇARPIŞMA ═════════════════════════════
local root = Instance.new("Part")
root.Name = "Kok"
root.Anchored = true
root.CanCollide = false
root.CanTouch = false
root.CanQuery = false
root.Transparency = 1
root.Size = V(6, 0.2, 6)
root.CFrame = CFrame.new(0, 0, 0)
root.Parent = model
model.PrimaryPart = root

local function collider(name, cf, size)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = true
	p.CanTouch = false
	p.Transparency = 1
	p.CastShadow = false
	p.Size = size
	p.CFrame = cf
	p.Parent = folder("Carpisma")
end
collider("GovdeCarpisma", CFrame.new(0, 15, 1) * CFrame.Angles(rad(-22), 0, 0), V(8.5, 16, 7.5))
collider("BacakCarpisma", CFrame.new(0, 4.5, 1.5), V(11, 9, 7))
collider("KuyrukCarpisma", CFrame.new(0, 3, 16) * CFrame.Angles(rad(12), 0, 0), V(4, 3, 20))

-- ═════════════════════════════ RIG VERİSİ ═════════════════════════════
local function fmt(n: number): string
	local s = string.format("%.5f", n)
	s = s:gsub("0+$", ""):gsub("%.$", "")
	if s == "-0" then
		s = "0"
	end
	return s
end
local function v3(v)
	return string.format("Vector3.new(%s, %s, %s)", fmt(v.X), fmt(v.Y), fmt(v.Z))
end
local function cfLiteral(cf)
	local c = { cf:GetComponents() }
	local out = {}
	for _, n in c do
		table.insert(out, fmt(n))
	end
	return "CFrame.new(" .. table.concat(out, ", ") .. ")"
end

local lines = { "-- Bu tablo build.luau tarafından üretildi; elle düzenlemeyin.", "local Rig = {}", "", "Rig.bones = {" }
for _, b in bones do
	local parentPivot = if b.parent > 0 then bones[b.parent].pivot else V(0, 0, 0)
	table.insert(lines, string.format("\t{ name = %q, parent = %d, rel = %s },", b.name, b.parent, v3(b.pivot - parentPivot)))
end
table.insert(lines, "}")
table.insert(lines, "")
table.insert(lines, "Rig.parts = {")
for _, rp in rigParts do
	local pivot = pivotOf(rp.bone)
	local offset = CFrame.new(-pivot.X, -pivot.Y, -pivot.Z) * rp.cf
	table.insert(lines, string.format("\t{ name = %q, bone = %d, offset = %s },", rp.name, boneIndex[rp.bone], cfLiteral(offset)))
end
table.insert(lines, "}")
table.insert(lines, "")

-- Zar parçaları: dinlenme pozunda çizilir; veriye köşe noktaları kemiğe göre yazılır.
local rigSource = fs.readFile("src/rig.luau")
local MEMBRANE_THICKNESS = 0.22
table.insert(lines, "Rig.membranes = {")
local triangle -- Rig.triangle'ı aşağıda rig.luau'dan alacağız
do
	local env = { CFrame = CFrame, Vector3 = Vector3, Rig = { bones = {}, parts = {}, membranes = {}, glowParts = {} } }
	local chunk = luau.load(rigSource, { debugName = "rig", environment = env })
	triangle = chunk().triangle
end
for i, m in membranes do
	local world = {}
	local pts = {}
	for k, pt in m.points do
		world[k] = pt.point
		table.insert(pts, string.format("{ bone = %d, pos = %s }", boneIndex[pt.bone], v3(pt.point - pivotOf(pt.bone))))
	end
	local cf0, s0, cf1, s1 = triangle(world[1], world[2], world[3])
	assert(cf0, "dejenere zar üçgeni")
	local nameA = "Zar" .. m.side .. i .. "a"
	local nameB = "Zar" .. m.side .. i .. "b"
	for _, pair in { { nameA, cf0, s0 }, { nameB, cf1, s1 } } do
		local w = Instance.new("WedgePart")
		w.Name = pair[1]
		w.Anchored = true
		w.CanCollide = false
		w.CanTouch = false
		w.Size = V(MEMBRANE_THICKNESS, pair[3].Y, pair[3].Z)
		w.CFrame = pair[2]
		w.Color = C.membrane
		w.Material = M.SmoothPlastic
		w.TopSurface = Enum.SurfaceType.Smooth
		w.BottomSurface = Enum.SurfaceType.Smooth
		w.Parent = folder(m.group)
	end
	table.insert(lines, string.format("\t{ a = %q, b = %q, thickness = %s, points = { %s } },", nameA, nameB, fmt(MEMBRANE_THICKNESS), table.concat(pts, ", ")))
end
table.insert(lines, "}")
table.insert(lines, "")
local glowQuoted = {}
for _, n in glowParts do
	table.insert(glowQuoted, string.format("%q", n))
end
table.insert(lines, "Rig.glowParts = { " .. table.concat(glowQuoted, ", ") .. " }")
table.insert(lines, "")

local rigModule = Instance.new("ModuleScript")
rigModule.Name = "EjderhaRig"
rigModule.Source = table.concat(lines, "\n") .. "\n" .. rigSource
rigModule.Parent = model

local animator = Instance.new("Script")
animator.Name = "Animasyon"
animator.RunContext = Enum.RunContext.Client
animator.Source = fs.readFile("src/animator.client.luau")
animator.Parent = model

fs.writeFile("AtesEjderhasi.rbxmx", roblox.serializeModel({ model }, true))
local count = 0
for _, d in model:GetDescendants() do
	if d:IsA("BasePart") then
		count += 1
	end
end
print(string.format("AtesEjderhasi.rbxmx yazıldı: %d parça, %d kemik, %d zar üçgeni", count, #bones, #membranes))
for name, f in folders do
	print(string.format("  %-10s %d", name, #f:GetChildren()))
end
