--[[
	Raptor modelini üretir: lune run src/build.luau   (raptor/ klasöründen)
	Çıktı: Raptor.rbxmx — Roblox Studio'ya sürükleyip bırakılabilir.

	Koordinatlar stud cinsindendir; model -Z yönüne bakar, zemin y = 0.
	Gövde tek bir eğri boyunca uzanır: kuyruk ucundan kalçaya, gövdeye ve S biçimli boyundan başa.
	Gövde, boyun, baş, kollar ve kuyruk kemiklere; bacak parçaları bacak bölümlerine bağlıdır.
	Bacak bölümlerinin çerçeveleri oyunda ters kinematikle hesaplanır; parçaların bu çerçevelere
	göre konumları "RaptorRig" ModuleScript'ine veri olarak yazılır.
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

-- Tekrarlanabilir rastgelelik (Park–Miller): her derlemede aynı desen çıkar.
local seed = 7070707
local function rand(): number
	seed = (seed * 16807) % 2147483647
	return seed / 2147483647
end

-- ─── Renkler (mavimsi gri pullar, sırtta mavi şerit, açık karın, kehribar gözler) ───
local RGB = Color3.fromRGB
local C = {
	skin = RGB(116, 130, 148),
	skinDark = RGB(86, 98, 116),
	belly = RGB(158, 168, 180),
	blue = RGB(58, 108, 180),
	claw = RGB(46, 48, 54),
	tooth = RGB(226, 222, 206),
	eye = RGB(222, 150, 34),
	pupil = RGB(14, 10, 8),
	mouth = RGB(118, 64, 74),
	nostril = RGB(40, 40, 48),
}
local M = Enum.Material
local SKIN = M.Slate

-- ─── Model ve klasörler ───
local model = Instance.new("Model")
model.Name = "Raptor"
model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
model:SetAttribute("OtomatikKukreme", true)
model:SetAttribute("KukremeAraligi", 12)
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
	p.CanQuery = opts.query ~= false
	p.CastShadow = opts.shadow ~= false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or SKIN
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if opts.transparency then
		p.Transparency = opts.transparency
	end
	if opts.reflectance then
		p.Reflectance = opts.reflectance
	end
	p.Parent = folder(group)
	if bone then
		table.insert(rigParts, { name = p.Name, bone = bone, cf = cf })
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
		up = if math.abs(look.Z) < 0.9 then V(0, 0, 1) else V(1, 0, 0)
	end
	local right = look:Cross(up).Unit
	return CFrame.fromMatrix(pos, right, right:Cross(look), -look)
end

--- a ile b arasına gerilmiş elips.
local function segment(prefix, group, bone, a, b, w, h, color, material, opts)
	opts = opts or {}
	local len = (b - a).Magnitude * (opts.extend or 1.2)
	return ellipsoid(prefix, group, bone, lookFrame((a + b) / 2, b - a, opts.up), V(w, h, len), color, material, opts)
end

--- Diş/pençe: tabanı `pos`, `out` yönüne uzanır, ucu `back` yönüne yatar.
local function spike(prefix, group, bone, pos, out, back, height, length, thickness, color, material, opts)
	out = out.Unit
	back = (back - out * back:Dot(out)).Unit
	local right = out:Cross(back).Unit
	local cf = CFrame.fromMatrix(pos + out * (height / 2), right, out, back)
	return basePart("WedgePart", prefix, group, bone, cf, V(thickness, height, length), color, material or M.SmoothPlastic, opts)
end

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function ctl(pos, w, h, bone)
	return { pos = pos, w = w, h = h, bone = bone }
end

--- Kontrol noktaları ({ pos, w, h, bone }) boyunca yay uzunluğuyla örnekleyici.
local function chainSampler(controls)
	local samples = {}
	for i = 1, #controls - 1 do
		local c0, c1 = controls[i], controls[i + 1]
		local seg = c1.pos - c0.pos
		local n = math.max(1, math.ceil(seg.Magnitude / 0.2))
		for k = 0, n - 1 do
			local t = k / n
			table.insert(samples, { pos = c0.pos + seg * t, w = lerp(c0.w, c1.w, t), h = lerp(c0.h, c1.h, t), bone = if t < 0.5 then c0.bone else c1.bone })
		end
	end
	local last = controls[#controls]
	table.insert(samples, { pos = last.pos, w = last.w, h = last.h, bone = last.bone })
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
	local function dir(s)
		return (at(s + 0.4).pos - at(s - 0.4).pos).Unit
	end
	return { at = at, dir = dir, total = total }
end

--- Zincir boyunca uzun ve çok üst üste binen elipslerden pürüzsüz bir boru.
local function smoothTube(prefix, group, controls, spacing, length, color, material, opts)
	local sampler = chainSampler(controls)
	local half = math.min(length, sampler.total) / 2
	local span = sampler.total - 2 * half
	local count = math.max(1, math.ceil(span / spacing) + 1)
	local made = {}
	for j = 0, count - 1 do
		local s = half + (if count > 1 then span * j / (count - 1) else span / 2)
		local c = sampler.at(s)
		local look = sampler.at(s + half * 0.5).pos - sampler.at(s - half * 0.5).pos
		table.insert(made, ellipsoid(prefix, group, c.bone, lookFrame(c.pos, look), V(c.w, c.h, half * 2), color, material, opts))
	end
	return made
end

--- `origin`dan `dir` yönünde giden ışının, `origin`ı içine alan elipslerden en dışta çıktığı mesafe.
local function surfaceDistance(parts, origin, dir)
	local best = 0
	for _, p in parts do
		local r = p.Size / 2
		local o = p.CFrame:PointToObjectSpace(origin) / r
		local d = p.CFrame:VectorToObjectSpace(dir) / r
		local a, b, c = d:Dot(d), 2 * o:Dot(d), o:Dot(o) - 1
		local disc = b * b - 4 * a * c
		if c < 0 and disc >= 0 then
			best = math.max(best, (-b + math.sqrt(disc)) / (2 * a))
		end
	end
	return best
end

--- Yüzeye yatık şerit: points = { pos, normal, width, bone }; ardışık noktalar arası yassı elipsler.
local function ribbon(prefix, group, points, thickness, color, material, overlap)
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local len = (b.pos - a.pos).Magnitude
		if len > 1e-3 then
			ellipsoid(prefix, group, a.bone, lookFrame((a.pos + b.pos) / 2, b.pos - a.pos, (a.normal + b.normal).Unit),
				V((a.width + b.width) / 2, thickness, len * (overlap or 2.2)), color, material, { shadow = false, query = false })
		end
	end
end

--- Catmull-Rom eğrisinde bir nokta.
local function catmull(p0, p1, p2, p3, t)
	local t2, t3 = t * t, t * t * t
	return (p1 * 2 + (p2 - p0) * t + (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2 + (p1 * 3 - p0 - p2 * 3 + p3) * t3) * 0.5
end

-- ═════════════════════════════ İSKELET ═════════════════════════════
-- Gövde eğrisinin kontrol noktaları kuyruk ucundan başa: { konum, genişlik, derinlik, kemik }
local CHAIN = {
	{ V(0, 10.2, 18.2), 0.22, 0.22, "kuyruk6" },
	{ V(0, 9.1, 15.8), 0.6, 0.62, "kuyruk6" },
	{ V(0, 8.2, 13.6), 0.95, 1.0, "kuyruk5" },
	{ V(0, 7.5, 11.2), 1.3, 1.4, "kuyruk4" },
	{ V(0, 7.1, 8.7), 1.7, 1.85, "kuyruk3" },
	{ V(0, 6.9, 6.2), 2.1, 2.4, "kuyruk2" },
	{ V(0, 6.8, 3.7), 2.6, 3.0, "kuyruk1" },
	{ V(0, 6.7, 1.2), 2.9, 3.4, "kalca" },
	{ V(0, 6.9, -1.2), 3.0, 3.7, "govde" },
	{ V(0, 7.4, -3.2), 2.6, 3.3, "gogus" },
	{ V(0, 8.4, -4.3), 2.0, 2.3, "boyun1" },
	{ V(0, 9.7, -4.75), 1.6, 1.75, "boyun2" },
	{ V(0, 10.9, -4.85), 1.42, 1.55, "boyun3" },
	{ V(0, 11.75, -5.45), 1.38, 1.5, "bas" },
}
local PELVIS = 8
addBone("kalca", nil, CHAIN[PELVIS][1])
for i = PELVIS - 1, 2, -1 do
	addBone(CHAIN[i][4], if i == PELVIS - 1 then "kalca" else CHAIN[i + 1][4], CHAIN[i][1])
end
for i = PELVIS + 1, #CHAIN do
	addBone(CHAIN[i][4], CHAIN[i - 1][4], CHAIN[i][1])
end
local headFrame = CFrame.new(pivotOf("bas")) * CFrame.Angles(rad(-14), 0, 0)
local function H(x, y, z)
	return headFrame * V(x, y, z)
end
local function HD(x, y, z)
	return headFrame:VectorToWorldSpace(V(x, y, z))
end
local function HCF(x, y, z)
	return headFrame * CFrame.new(x, y, z)
end
addBone("cene", "bas", H(0, -0.25, 0.6))

-- Kollar: omuz, dirsek, bilek
local ARMS = {}
for _, side in { "L", "R" } do
	local s = if side == "L" then 1 else -1
	ARMS[side] = { s = s, shoulder = V(s * 1.1, 7.3, -3.6), elbow = V(s * 1.55, 5.95, -3.05), wrist = V(s * 1.45, 6.05, -4.8) }
	addBone("kol" .. side, "gogus", ARMS[side].shoulder)
	addBone("onkol" .. side, "kol" .. side, ARMS[side].elbow)
	addBone("el" .. side, "onkol" .. side, ARMS[side].wrist)
end

-- ═════════════════════════════ GÖVDE ═════════════════════════════
-- Eğriyi Catmull-Rom ile yumuşat. Kalçanın kuyruk tarafında her bölgeyi kalçaya yakın kemik,
-- baş tarafında kalçaya yakın kemik taşır (bölgenin kökü).
local dense = {}
do
	local PER = 5
	for i = 1, #CHAIN - 1 do
		local p0, p1 = CHAIN[math.max(1, i - 1)][1], CHAIN[i][1]
		local p2, p3 = CHAIN[i + 1][1], CHAIN[math.min(#CHAIN, i + 2)][1]
		local bone = if i + 1 <= PELVIS then CHAIN[i + 1][4] else CHAIN[i][4]
		for k = 0, PER - 1 do
			local t = k / PER
			table.insert(dense, ctl(catmull(p0, p1, p2, p3, t), lerp(CHAIN[i][2], CHAIN[i + 1][2], t), lerp(CHAIN[i][3], CHAIN[i + 1][3], t), bone))
		end
	end
	local last = CHAIN[#CHAIN]
	table.insert(dense, ctl(last[1], last[2], last[3], "bas"))
	table.insert(dense, ctl(H(0, 0.35, -0.9), 1.45, 1.5, "bas"))
end
local bodyParts = smoothTube("Govde", "Govde", dense, 0.8, 3.6, C.skin, SKIN)
local body = chainSampler(dense)
--- Sırt yönü: zincire dik, yukarı ve geriye doğru (dik boyunda arkaya bakar).
local function dorsalAt(s)
	local d = body.dir(s)
	local hint = V(0, 1, 0.6)
	return (hint - d * hint:Dot(d)).Unit
end
local function surfaceAt(s, ray)
	local p = body.at(s).pos
	return p + ray * surfaceDistance(bodyParts, p, ray)
end

-- kalçanın iki yanındaki kalın uyluk kası (gövdeye kaynaşır)
for _, s in { 1, -1 } do
	ellipsoid("KalcaKasi", "Govde", "kalca", CFrame.new(s * 1.2, 6.1, 1.2) * CFrame.Angles(rad(-25), 0, 0), V(1.9, 3.0, 3.1), C.skin, SKIN)
end

-- Sırttaki mavi şerit: boynun tepesinden kuyruk ucuna
do
	local points = {}
	local s = 1.0
	while s < body.total - 1.0 do
		local c = body.at(s)
		local n = dorsalAt(s)
		table.insert(points, { pos = surfaceAt(s, n) - n * 0.12, normal = n, width = c.w * (if s < 15 then 0.6 else 0.5), bone = c.bone })
		s += 0.9
	end
	ribbon("MaviSerit", "Govde", points, 0.3, C.blue, M.SmoothPlastic, 2.3)
end
-- Boğazdan kalçaya açık renkli karın
do
	for _, range in { { 14.5, 21.6 }, { 23.4, body.total - 2.0 } } do
		local points = {}
		local s = range[1]
		while s <= range[2] do
			local c = body.at(s)
			local n = -dorsalAt(s)
			table.insert(points, { pos = surfaceAt(s, n) - n * 0.14, normal = n, width = c.w * 0.58, bone = c.bone })
			s += 0.5
		end
		ribbon("Karin", "Govde", points, 0.32, C.belly, SKIN, 1.9)
	end
end
-- Yanlarda koyu benekler
for _ = 1, 46 do
	local s = 2 + rand() * (body.total - 6)
	local c = body.at(s)
	local d, n = body.dir(s), dorsalAt(s)
	local side = d:Cross(n).Unit * (if rand() < 0.5 then 1 else -1)
	local a = 0.55 + rand() * 1.0
	local ray = (n * math.cos(a) + side * math.sin(a)).Unit
	local pos = surfaceAt(s, ray) - ray * 0.08
	local size = (0.35 + c.w * 0.18) * (0.7 + 0.6 * rand())
	ellipsoid("Benek", "Govde", c.bone, lookFrame(pos, d, ray), V(size * (0.6 + 0.4 * rand()), 0.2, size * (1.0 + 0.6 * rand())), C.skinDark, SKIN,
		{ shadow = false, query = false })
end

-- ═════════════════════════════ BAŞ ═════════════════════════════
local function hctl(x, y, z, w, h, bone)
	return ctl(H(x, y, z), w, h, bone or "bas")
end
local skull = smoothTube("Kafa", "Bas", {
	hctl(0, 0.35, 0.9, 1.45, 1.55),
	hctl(0, 0.45, -0.5, 1.7, 1.75),
	hctl(0, 0.35, -1.7, 1.45, 1.4),
	hctl(0, 0.22, -2.8, 1.15, 1.05),
	hctl(0, 0.12, -3.7, 0.9, 0.8),
	hctl(0, 0.05, -4.25, 0.6, 0.55),
}, 0.55, 1.9, C.skin, SKIN)
local jaw = smoothTube("Cene", "Bas", {
	hctl(0, -0.45, 0.5, 1.35, 0.85, "cene"),
	hctl(0, -0.62, -1.0, 1.2, 0.7, "cene"),
	hctl(0, -0.55, -2.6, 0.9, 0.52, "cene"),
	hctl(0, -0.45, -3.7, 0.62, 0.4, "cene"),
	hctl(0, -0.42, -4.1, 0.45, 0.3, "cene"),
}, 0.55, 1.8, C.skin, SKIN)
-- ağız içi
ellipsoid("Agiz", "Bas", "bas", HCF(0, -0.3, -2.2), V(0.72, 0.3, 3.8), C.mouth, M.SmoothPlastic, { shadow = false })
ellipsoid("AgizAlt", "Bas", "cene", HCF(0, -0.42, -2.0), V(0.66, 0.24, 3.4), C.mouth, M.SmoothPlastic, { shadow = false })
-- alt çenenin altında açık renkli boğaz
ellipsoid("Bogaz", "Bas", "cene", HCF(0, -0.78, -1.0), V(0.95, 0.4, 2.6), C.belly, SKIN, { shadow = false })

local lids = {}
for _, s in { 1, -1 } do
	-- kehribar göz, dikey göz bebeği, mavi göz çevresi ve kaş çıkıntısı
	local origin = H(0, 0.62, -0.6)
	local eyeDir = HD(s, 0.32, 0.08).Unit
	local eyePos = origin + eyeDir * (surfaceDistance(skull, origin, eyeDir) - 0.07)
	local eyeRot = headFrame.Rotation * CFrame.Angles(0, s * rad(8), s * rad(-12))
	ellipsoid("GozCevresi", "Bas", "bas", CFrame.new(eyePos - eyeDir * 0.05) * eyeRot, V(0.3, 0.6, 0.78), C.blue, M.SmoothPlastic, { shadow = false })
	ellipsoid("Goz", "Bas", "bas", CFrame.new(eyePos) * eyeRot, V(0.3, 0.42, 0.52), C.eye, M.Neon, { shadow = false })
	ellipsoid("GozBebegi", "Bas", "bas", CFrame.new(eyePos + eyeDir * 0.12) * eyeRot, V(0.08, 0.34, 0.1), C.pupil, M.SmoothPlastic, { shadow = false })
	local lid = ellipsoid("GozKapagi", "Bas", "bas", CFrame.new(eyePos + eyeDir * 0.02) * eyeRot, V(0.36, 0.5, 0.6), C.skin, SKIN,
		{ shadow = false, query = false, transparency = 1 })
	table.insert(lids, lid.Name)
	local browDir = HD(s * 0.9, 0.75, 0).Unit
	local browPos = origin + browDir * (surfaceDistance(skull, origin, browDir) - 0.14)
	ellipsoid("Kas", "Bas", "bas", CFrame.new(browPos) * headFrame.Rotation * CFrame.Angles(0, 0, -s * rad(40)), V(0.4, 0.26, 1.2), C.blue, M.SmoothPlastic)
	-- gözden başın arkasına uzanan mavi bant
	local points = {}
	for z = -1.6, 1.1, 0.3 do
		local o = H(0, 0.45, z)
		local d = HD(s * 0.75, 1, 0).Unit
		table.insert(points, { pos = o + d * (surfaceDistance(skull, o, d) - 0.07), normal = d, width = 0.5, bone = "bas" })
	end
	ribbon("MaviBant", "Bas", points, 0.17, C.blue, M.SmoothPlastic, 2.4)
	-- burun delikleri
	local noseOrigin = H(0, 0.1, -3.85)
	local noseDir = HD(s * 0.55, 1, -0.3).Unit
	ellipsoid("BurunDeligi", "Bas", "bas", CFrame.new(noseOrigin + noseDir * (surfaceDistance(skull, noseOrigin, noseDir) - 0.03)) * headFrame.Rotation,
		V(0.16, 0.12, 0.24), C.nostril, M.SmoothPlastic, { shadow = false })
	-- dişler
	for z = -1.2, -4.0, -0.4 do
		local o = H(0, 0.1, z)
		local d = HD(s * 0.6, -1, 0).Unit
		local big = z < -2.0 and z > -3.4
		spike("Dis", "Bas", "bas", o + d * surfaceDistance(skull, o, d) + HD(0, 0.06, 0), HD(0, -1, 0), HD(0, 0, -1),
			if big then 0.34 else 0.26, 0.14, 0.09, C.tooth, M.SmoothPlastic, { shadow = false })
	end
	for z = -1.4, -3.8, -0.42 do
		local o = H(0, -0.55, z)
		local d = HD(s * 0.6, 1, 0).Unit
		spike("AltDis", "Bas", "cene", o + d * surfaceDistance(jaw, o, d) - HD(0, 0.06, 0), HD(0, 1, 0), HD(0, 0, -1), 0.24, 0.13, 0.09, C.tooth, M.SmoothPlastic,
			{ shadow = false })
	end
end

-- ═════════════════════════════ KOLLAR ═════════════════════════════
for _, side in { "L", "R" } do
	local arm = ARMS[side]
	local s = arm.s
	local kol, onkol, el = "kol" .. side, "onkol" .. side, "el" .. side
	ellipsoid("Omuz", "Kollar", kol, CFrame.new(arm.shoulder + V(s * 0.05, -0.1, 0)), V(0.9, 1.1, 1.0), C.skin, SKIN)
	segment("Kol", "Kollar", kol, arm.shoulder, arm.elbow, 0.62, 0.7, C.skin, SKIN, { extend = 1.25 })
	segment("Onkol", "Kollar", onkol, arm.elbow, arm.wrist, 0.5, 0.55, C.skin, SKIN, { extend = 1.2 })
	ellipsoid("El", "Kollar", el, CFrame.new(arm.wrist + V(0, -0.05, -0.15)), V(0.5, 0.42, 0.6), C.skin, SKIN)
	-- üç uzun parmak ve kıvrık pençeler
	for i, dx in { -0.2, 0, 0.2 } do
		local base = arm.wrist + V(s * dx, -0.1, -0.25)
		local knuckle = base + V(s * dx * 0.6, -0.45, -0.55 - (if i == 2 then 0.15 else 0))
		local tip = knuckle + V(0, -0.6, -0.2)
		segment("Parmak", "Kollar", el, base, knuckle, 0.22, 0.22, C.skin, SKIN, { extend = 1.15 })
		segment("Parmak", "Kollar", el, knuckle, tip, 0.19, 0.19, C.skin, SKIN, { extend = 1.15 })
		spike("Pence", "Kollar", el, tip, V(0, -1, 0.35), V(0, 0, 1), 0.65, 0.26, 0.13, C.claw, M.SmoothPlastic)
	end
end

-- ═════════════════════════════ BACAKLAR ═════════════════════════════
-- Bacak bölümlerinin dinlenme çerçeveleri, oyundaki ters kinematikle aynı işlevlerle hesaplanır.
local rigSource = fs.readFile("src/rig.luau")
local RigCode = luau.load(rigSource, {
	debugName = "rig",
	environment = { CFrame = CFrame, Vector3 = Vector3, Rig = { bones = {}, parts = {}, legs = {}, lids = {} } },
})()

local legs = {}
for _, side in { "L", "R" } do
	local s = if side == "L" then 1 else -1
	local hip, knee, ankle, ball = V(s * 1.35, 6.3, 1.4), V(s * 1.6, 3.9, -0.3), V(s * 1.55, 2.35, 2.0), V(s * 1.5, 0.45, 0.75)
	local l1, l2 = (knee - hip).Magnitude, (ankle - knee).Magnitude
	local upperCF, lowerCF = RigCode.legFrames(hip, ankle, V(0, 0, -1) + V(s * 0.15, 0, 0), l1, l2)
	local metaCF = RigCode.frame(ankle, ball - ankle, V(0, 0, -1))
	local footCF = CFrame.new(ball)
	local sicklePivot = V(-s * 0.28, 0.05, -0.3)
	local sickleCF = footCF * CFrame.new(sicklePivot)
	local lm = (ball - ankle).Magnitude
	local group = "Bacak" .. side
	local leg = { side = s, hip = hip - pivotOf("kalca"), ball = ball, meta = ankle - ball, l1 = l1, l2 = l2, sickle = sicklePivot,
		groups = { upper = {}, lower = {}, meta = {}, foot = {}, sickle = {} } }
	local frames = { upper = upperCF, lower = lowerCF, meta = metaCF, foot = footCF, sickle = sickleCF }
	local function add(key, part)
		table.insert(leg.groups[key], { name = part.Name, offset = frames[key]:Inverse() * part.CFrame })
		return part
	end
	local function piece(key, prefix, localCF, size, color, material)
		return add(key, ellipsoid(prefix, group, nil, frames[key] * localCF, size, color, material or SKIN))
	end
	-- uyluk: kalçadan dize kalın, but kası; diz eklemi
	piece("upper", "Uyluk", CFrame.new(0, 0.15, -l1 * 0.38), V(1.75, 2.3, l1 * 1.4), C.skin)
	piece("upper", "Diz", CFrame.new(0, 0, -l1), V(0.8, 0.82, 0.82), C.skin)
	-- incik: dizden bileğe, üst kısmında baldır kası
	piece("lower", "Incik", CFrame.new(0, 0, -l2 * 0.5), V(0.78, 0.86, l2 * 1.12), C.skin)
	piece("lower", "Baldir", CFrame.new(0, -0.2, -l2 * 0.32), V(1.05, 1.15, l2 * 0.75), C.skin)
	-- bilekten ayağa uzanan ayak tarağı
	piece("meta", "Bilek", CFrame.new(0, 0, 0), V(0.62, 0.62, 0.62), C.skin)
	piece("meta", "Tarak", CFrame.new(0, 0, -lm * 0.5), V(0.5, 0.56, lm * 1.1), C.skin)
	-- ayak: taban, iki yere basan parmak ve pençeleri, arkada küçük bir pençe
	piece("foot", "Taban", CFrame.new(0, -0.1, -0.2), V(1.15, 0.55, 1.1), C.skin)
	for _, toe in { { 0.02, -1.9 }, { 0.62, -1.5 } } do
		local base = ball + V(s * toe[1] * 0.5, -0.05, -0.25)
		local tip = ball + V(s * toe[1], -0.27, toe[2])
		add("foot", segment("Parmak", group, nil, base, tip, 0.34, 0.3, C.skin, SKIN, { extend = 1.12 }))
		add("foot", spike("Pence", group, nil, tip + V(0, 0.05, -0.1), V(0, -0.45, -1), V(0, 1, 0), 0.5, 0.25, 0.18, C.claw))
	end
	add("foot", spike("Pence", group, nil, ball + V(-s * 0.3, -0.05, 0.3), V(-s * 0.3, -0.3, 1), V(0, 1, 0), 0.32, 0.16, 0.12, C.claw))
	-- orak pençe: ikinci parmak yerden kalkık durur, ucu öne ve aşağı kıvrılan büyük pençe
	local function sp(x, y, z)
		return sickleCF * V(0, y, z)
	end
	add("sickle", segment("OrakParmak", group, nil, sp(0, -0.05, 0.15), sp(0, 0.42, -0.45), 0.34, 0.34, C.skin, SKIN, { extend = 1.3 }))
	local hook = { sp(0, 0.42, -0.45), sp(0, 0.8, -0.72), sp(0, 0.88, -1.12), sp(0, 0.66, -1.42) }
	for i = 1, 3 do
		local w = 0.32 - i * 0.06
		add("sickle", segment("OrakPence", group, nil, hook[i], hook[i + 1], w * 0.7, w, C.claw, M.SmoothPlastic, { extend = 1.25, up = V(0, 0, -1) }))
	end
	add("sickle", spike("OrakUcu", group, nil, hook[4], hook[4] - hook[3], V(0, -1, 0), 0.3, 0.12, 0.1, C.claw))
	table.insert(legs, leg)
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
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local DUST = seq({ { 0, RGB(150, 138, 120) }, { 1, RGB(110, 102, 92) } })

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

-- Öne atılırken ayakların altından kalkan toz (animasyon script'i bir kez saçar)
local dustOut = Instance.new("Attachment")
dustOut.Name = "TozNoktasi"
dustOut.CFrame = CFrame.new(0, 0.2, 0.8)
dustOut.Parent = root
local dust = Instance.new("ParticleEmitter")
dust.Name = "Toz"
dust.Texture = SMOKE
dust.Color = DUST
dust.Size = nums({ { 0, 1.0 }, { 1, 4.5 } })
dust.Transparency = nums({ { 0, 0.45 }, { 1, 1 } })
dust.Lifetime = NumberRange.new(1.0, 1.8)
dust.Rate = 0
dust.Speed = NumberRange.new(5, 12)
dust.SpreadAngle = Vector2.new(80, 15)
dust.Rotation = NumberRange.new(0, 360)
dust.RotSpeed = NumberRange.new(-40, 40)
dust.Drag = 2.5
dust.Acceleration = V(0, 1, 0)
dust.EmissionDirection = Enum.NormalId.Top
dust:SetAttribute("HamleTozu", true)
dust:SetAttribute("Adet", 36)
dust.Parent = dustOut
-- Kaldırılan ayak yere basınca küçük toz
for _, leg in legs do
	local pad = folder("Bacak" .. (if leg.side > 0 then "L" else "R")):FindFirstChild(leg.groups.foot[1].name)
	local e = Instance.new("ParticleEmitter")
	e.Name = "AyakTozu"
	e.Texture = SMOKE
	e.Color = DUST
	e.Size = nums({ { 0, 0.5 }, { 1, 2 } })
	e.Transparency = nums({ { 0, 0.5 }, { 1, 1 } })
	e.Lifetime = NumberRange.new(0.6, 1.0)
	e.Rate = 0
	e.Speed = NumberRange.new(2, 4)
	e.SpreadAngle = Vector2.new(90, 10)
	e.Drag = 2
	e.EmissionDirection = Enum.NormalId.Top
	e:SetAttribute("AyakTozu", leg.side)
	e.Parent = pad
end

-- ═════════════════════════════ ÇARPIŞMA ═════════════════════════════
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
collider("GovdeCarpisma", CFrame.new(0, 7.3, -0.6), V(3.4, 4.0, 8.4))
collider("BacakCarpisma", CFrame.new(0, 2.6, 1.0), V(4.2, 5.2, 3.8))
collider("KuyrukCarpisma", CFrame.new(0, 7.8, 10.5) * CFrame.Angles(rad(-8), 0, 0), V(2.0, 2.0, 15))

-- ═════════════════════════════ RIG VERİSİ ═════════════════════════════
local function fmt(n: number): string
	local str = string.format("%.5f", n)
	str = str:gsub("0+$", ""):gsub("%.$", "")
	if str == "-0" then
		str = "0"
	end
	return str
end
local function v3(v)
	return string.format("Vector3.new(%s, %s, %s)", fmt(v.X), fmt(v.Y), fmt(v.Z))
end
local function cfLiteral(cf)
	local out = {}
	for _, n in { cf:GetComponents() } do
		table.insert(out, fmt(n))
	end
	return "CFrame.new(" .. table.concat(out, ", ") .. ")"
end
local function pieceList(list)
	local out = {}
	for _, p in list do
		table.insert(out, string.format("{ name = %q, offset = %s }", p.name, cfLiteral(p.offset)))
	end
	return table.concat(out, ", ")
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
	table.insert(lines, string.format("\t{ name = %q, bone = %d, offset = %s },", rp.name, boneIndex[rp.bone], cfLiteral(CFrame.new(-pivot.X, -pivot.Y, -pivot.Z) * rp.cf)))
end
table.insert(lines, "}")
table.insert(lines, "")
-- Bacaklar: kalça kalça kemiğine göre, ayak ve bilek model uzayında; parçalar bacak bölümlerine göre.
table.insert(lines, "Rig.legs = {")
for _, leg in legs do
	table.insert(lines, string.format("\t{ side = %d, bone = %d, hip = %s, ball = %s, meta = %s, l1 = %s, l2 = %s, sickle = %s, groups = {",
		leg.side, boneIndex.kalca, v3(leg.hip), v3(leg.ball), v3(leg.meta), fmt(leg.l1), fmt(leg.l2), v3(leg.sickle)))
	for _, key in { "upper", "lower", "meta", "foot", "sickle" } do
		table.insert(lines, string.format("\t\t%s = { %s },", key, pieceList(leg.groups[key])))
	end
	table.insert(lines, "\t} },")
end
table.insert(lines, "}")
local quoted = {}
for _, n in lids do
	table.insert(quoted, string.format("%q", n))
end
table.insert(lines, "Rig.lids = { " .. table.concat(quoted, ", ") .. " }")
table.insert(lines, "")

local rigModule = Instance.new("ModuleScript")
rigModule.Name = "RaptorRig"
rigModule.Source = table.concat(lines, "\n") .. "\n" .. rigSource
rigModule.Parent = model

local animator = Instance.new("Script")
animator.Name = "Animasyon"
animator.RunContext = Enum.RunContext.Client
animator.Source = fs.readFile("src/animator.client.luau")
animator.Parent = model

fs.writeFile("Raptor.rbxmx", roblox.serializeModel({ model }, true))
local count = 0
for _, d in model:GetDescendants() do
	if d:IsA("BasePart") then
		count += 1
	end
end
print(string.format("Raptor.rbxmx yazıldı: %d parça, %d kemik, gövde eğrisi %.1f stud", count, #bones, body.total))
for name, f in folders do
	print(string.format("  %-10s %d", name, #f:GetChildren()))
end
